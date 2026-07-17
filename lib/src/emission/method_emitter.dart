// Emit one Dart method per FTL message + per attribute + (when the
// message has inline markup) one *AsSpans sibling.
//
// Pure data → pure string. Takes a fully-resolved EmissionInput
// (id, attribute or null, sanitized Dart name, inferred parameters,
// source FTL for doc-comments, markup flag) and returns the Dart
// source for one method.
//
// Doc-style choices:
//   - Triple-slash doc comments before each method.
//   - The message's attached FTL comment first (verbatim) — that's
//     the Fluent convention for translator/developer context.
//   - The exact FTL source, fenced in a ```ftl block so brackets in
//     select variants never read as Dart doc references.
//   - `Source: path:line` for jump-to-source.
//   - (Only when applicable) the *AsSpans pointer + inference-conflict
//     notes.

import 'package:fluent_gen/src/emission/identifier.dart';
import 'package:fluent_gen/src/inference/inference.dart';

/// One unit the emitter produces — a method, with its source
/// metadata bundled so the doc comment can be assembled.
class EmissionInput {
  /// Bundles everything [emitMethod] needs for one method.
  const EmissionInput({
    required this.dartName,
    required this.messageId,
    required this.attributeName,
    required this.parameters,
    required this.sourceText,
    required this.sourcePath,
    required this.sourceLine,
    required this.commentText,
    required this.hasMarkup,
  });

  /// The sanitized lowerCamelCase name the method gets in Dart.
  final String dartName;

  /// The FTL message id (always `welcome` etc., never with the
  /// attribute suffix).
  final String messageId;

  /// The attribute name when this method targets a specific
  /// `.attr` rather than the message body. Null for body methods.
  final String? attributeName;

  /// Inferred parameters in source order.
  final List<InferredVariable> parameters;

  /// The exact FTL source for the message — used in the doc comment.
  final String sourceText;

  /// Path of the FTL file (relative or absolute) for the
  /// "Source: …" doc comment line.
  final String sourcePath;

  /// 1-based line the construct starts on in [sourcePath].
  final int sourceLine;

  /// The message's attached FTL comment (`# …` lines directly above
  /// it), without the `#` markers. Null when the message has none.
  final String? commentText;

  /// True when the *AsSpans sibling should also be emitted for this
  /// method. Pertains to the message body — attribute methods never
  /// emit AsSpans variants because attributes are by spec
  /// stringy-only (used as `href`, etc.).
  final bool hasMarkup;
}

/// Render one method.
///
/// When `asSpans` is true, the method returns `List<FluentSpan>` and
/// calls `formatMessageAsSpans` instead of `formatMessage`. This is
/// only valid for message-body methods (not attributes); the caller
/// guards via `EmissionInput.hasMarkup`.
String emitMethod(EmissionInput input, {bool asSpans = false}) {
  final buf = StringBuffer();
  buf.writeln(_methodDocComment(input, asSpans: asSpans));
  buf.writeln(_methodSignature(input, asSpans: asSpans));
  return buf.toString();
}

/// Doc comment block: source FTL + path + (optional) markup pointer.
String _methodDocComment(EmissionInput input, {required bool asSpans}) {
  final lines = <String>[];

  // The attached FTL comment leads — it's the author's own context
  // for the message (and, per the Mozilla convention, may carry the
  // type annotations the inference consumed).
  final comment = input.commentText;
  if (comment != null && comment.isNotEmpty) {
    for (final line in comment.split('\n')) {
      lines.add(line.isEmpty ? '///' : '/// $line');
    }
    lines.add('///');
  }

  // The exact source text, fenced as FTL so select-variant brackets
  // (`[one]`) never parse as Dart doc references and IDE hovers
  // render the block as code.
  lines.add('/// ```ftl');
  for (final line in input.sourceText.split('\n')) {
    lines.add(line.isEmpty ? '///' : '/// $line');
  }
  lines.add('/// ```');
  lines.add('///');
  lines.add('/// Source: `${input.sourcePath}:${input.sourceLine}`.');

  if (input.hasMarkup) {
    if (asSpans) {
      lines.add('///');
      lines.add(
        '/// Returns the span tree. For the resolved-string '
        'variant see [${input.dartName.replaceAll('AsSpans', '')}].',
      );
    } else {
      lines.add('///');
      lines.add(
        '/// Has inline markup — for a span-tree variant suitable '
        'for `RichText`, see [${input.dartName}AsSpans].',
      );
    }
  }

  if (input.parameters.any((p) => p.hadConflict)) {
    final conflicting = input.parameters
        .where((p) => p.hadConflict)
        .map((p) => p.name);
    lines.add('///');
    lines.add(
      '/// Note: parameter${conflicting.length == 1 ? '' : 's'} '
      "${conflicting.map((n) => '`\$$n`').join(', ')} could not "
      'be narrowed to a single concrete type because the FTL '
      'message uses ${conflicting.length == 1 ? 'it' : 'them'} in '
      'incompatible ways. Inferred as `Object?` — pass whatever '
      'type the resolver expects.',
    );
  }

  return lines.join('\n');
}

/// `String foo({required int n, ...})` or `List<FluentSpan> fooAsSpans(...)`.
String _methodSignature(EmissionInput input, {required bool asSpans}) {
  final returnType = asSpans ? 'List<FluentSpan>' : 'String';
  final methodName = asSpans ? '${input.dartName}AsSpans' : input.dartName;

  final paramFragments = <String>[
    for (final p in input.parameters)
      'required ${_dartTypeOf(p.type)} ${_safeParamName(p.name)}',
    'List<FluentError>? errors',
  ];
  final params = paramFragments.join(', ');

  final argMapEntries = input.parameters
      .map((p) => "'${p.name}': ${_safeParamName(p.name)}")
      .join(', ');
  final argMap =
      argMapEntries.isEmpty
          ? '<String, Object?>{}'
          : '<String, Object?>{$argMapEntries}';

  final attrArg =
      input.attributeName == null
          ? ''
          : "attribute: '${input.attributeName}', ";

  final formatCall =
      asSpans
          ? '_bundle.formatMessageAsSpans(\n'
              "        '${input.messageId}',\n"
              '        $attrArg'
              'args: $argMap,\n'
              '        errors: errors,\n'
              '      )'
          : '_bundle.formatMessage(\n'
              "        '${input.messageId}',\n"
              '        $attrArg'
              'args: $argMap,\n'
              '        errors: errors,\n'
              '      )';

  return '$returnType $methodName({$params}) =>\n'
      '      $formatCall;';
}

/// Map an [InferredDartType] to its Dart-source representation.
String _dartTypeOf(InferredDartType type) => switch (type) {
  InferredDartType.stringType => 'String',
  InferredDartType.numType => 'num',
  InferredDartType.dateTimeType => 'DateTime',
  InferredDartType.objectType => 'Object?',
};

/// Parameter names get the same Dart-keyword guard as method names,
/// in case a translator named a variable `if` or `class` (legal
/// FTL, illegal Dart parameter). `errors` gets the same escape —
/// every generated method already declares a `List<FluentError>? errors`
/// parameter, so an FTL `$errors` variable must not collide with it
/// (the args-map key stays `'errors'`).
String _safeParamName(String ftlName) {
  // Re-use the sanitizeIdentifier rules for the keyword guard,
  // but skip the kebab-case conversion (variables can't be
  // hyphenated in FTL — the parser would reject `\$foo-bar`).
  if (dartReservedWords.contains(ftlName) || ftlName == 'errors') {
    return '\$$ftlName';
  }
  return ftlName;
}
