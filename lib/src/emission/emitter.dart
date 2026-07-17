// Top-level emitter — assembles the full `.g.dart` file content
// from a list of inspected messages.
//
// Pipeline:
//   inspect → infer → emit-per-method → assemble file → format

import 'package:dart_style/dart_style.dart';
import 'package:fluent_gen/src/emission/identifier.dart';
import 'package:fluent_gen/src/emission/locale_enum_emitter.dart';
import 'package:fluent_gen/src/emission/method_emitter.dart';
import 'package:fluent_gen/src/inspection/ftl_inspector.dart';
import 'package:fluent_gen/src/inference/inference.dart';

/// A finished emission: the generated Dart source plus every
/// inference advisory the pass produced. The Builder layer logs the
/// notes; emission itself stays pure.
class EmitResult {
  /// Bundles the [source] and its [notes].
  const EmitResult({required this.source, required this.notes});

  /// The complete generated `.g.dart` content, dart_style-formatted.
  final String source;

  /// Inference advisories, in emission order.
  final List<InferenceNote> notes;
}

/// Render a complete generated `.g.dart` file.
///
/// [baseLocaleFiles] drive codegen (non-base locales are validated
/// separately and never change signatures). [className] names the
/// accessor class; [localeEnumName] names the locale enum, whose
/// values come from [allLocaleFiles]' keys (falling back to
/// [baseLocale] alone when no map is given — the single-locale case).
/// With [bundleFtl] every locale's raw FTL is embedded and the enum
/// gains `ftlSources` + `load()`. `headerPreamble` is added between
/// the banner and the imports — for project-level suppressions the
/// consumer wants (e.g. an `ignore_for_file` line for a project lint).
EmitResult emitFile({
  required Iterable<InspectedFile> baseLocaleFiles,
  required String className,
  String baseLocale = 'en',
  Map<String, List<InspectedFile>>? allLocaleFiles,
  bool bundleFtl = false,
  String localeEnumName = 'AppLocale',
  String? headerPreamble,
}) {
  // Collect every (message, source-path) pair, then run inference
  // + collision detection in one pass.
  final allMessages = <(InspectedFile, InspectedMessage)>[];
  for (final file in baseLocaleFiles) {
    for (final msg in file.messages) {
      allMessages.add((file, msg));
    }
  }

  // Message references resolve transitively within the locale —
  // across files too — so the inference context spans every
  // base-locale message.
  final context = InferenceContext(
    messagesById: {for (final (_, msg) in allMessages) msg.id: msg.message},
  );

  // The COMPLETE emitted name set — body methods, attribute methods
  // (`$` separator, added OUTSIDE `sanitizeIdentifier` because the
  // sanitizer strips `$`), AND the `*AsSpans` siblings, which share
  // the same Dart namespace (a message `foo-as-spans` collides with a
  // markup message `foo`'s sibling). Each entry carries its FTL
  // source descriptor so a collision error names the real culprits.
  final localeFilesByTag =
      allLocaleFiles ?? {baseLocale: baseLocaleFiles.toList()};
  // Sorted so enum-value order (and therefore the generated file) is
  // deterministic regardless of filesystem discovery order.
  final localeEntries = [
    for (final tag in localeFilesByTag.keys.toList()..sort())
      LocaleEnumEntry(tag: tag, files: localeFilesByTag[tag]!),
  ];

  final emittedNames = <EmittedName>[
    // The accessor-name manifest is a class member like any generated
    // method — an FTL id sanitizing to `accessorNames` must collide
    // loudly instead of shadowing it.
    (dartName: 'accessorNames', sourceId: '(the accessorNames manifest)'),
    // Enum values share the enum's namespace with each other.
    for (final entry in localeEntries)
      (
        dartName: '$localeEnumName.${localeEnumValueName(entry.tag)}',
        sourceId: 'locale ${entry.tag}',
      ),
  ];
  for (final (_, msg) in allMessages) {
    final base = sanitizeIdentifier(msg.id);
    if (msg.hasValue) {
      emittedNames.add((dartName: base, sourceId: msg.id));
      if (msg.hasMarkup) {
        emittedNames.add((
          dartName: '${base}AsSpans',
          sourceId: '${msg.id} (its *AsSpans sibling)',
        ));
      }
    }
    for (final attr in msg.attributeNames) {
      emittedNames.add((
        dartName: '$base\$${sanitizeIdentifier(attr)}',
        sourceId: '${msg.id}.$attr',
      ));
    }
  }
  for (final entry in findCollisions(emittedNames).entries) {
    throw CollisionError(entry.key, entry.value);
  }

  // The `*AsSpans` methods call the formatMessageAsSpans extension, which
  // lives in package:fluent_bundle/markup.dart — import it only when the
  // generated class actually has a markup message.
  final hasAnyMarkup = allMessages.any((m) => m.$2.hasValue && m.$2.hasMarkup);

  final notes = <InferenceNote>[];
  final buf = StringBuffer();
  _writeFileHeader(
    buf,
    headerPreamble: headerPreamble,
    hasMarkup: hasAnyMarkup,
  );
  _writeClassOpen(buf, className);
  for (final (file, msg) in allMessages) {
    _writeMessageMethods(
      buf,
      file: file,
      message: msg,
      context: context,
      notes: notes,
    );
  }
  _writeAccessorManifest(buf, emittedNames);
  _writeClassClose(buf);
  buf.writeln();
  buf.writeln(
    emitLocaleEnum(
      enumName: localeEnumName,
      entries: localeEntries,
      baseTag: baseLocale,
      bundleFtl: bundleFtl,
    ),
  );

  return EmitResult(source: _format(buf.toString()), notes: notes);
}

/// The manifest of every generated accessor name — consumed by the
/// unused-message helper in `package:fluent_gen/testing.dart`.
void _writeAccessorManifest(StringBuffer buf, List<EmittedName> names) {
  buf.writeln('  /// Every generated accessor name, for tooling (the');
  buf.writeln('  /// unused-message helper in');
  buf.writeln('  /// `package:fluent_gen/testing.dart`).');
  buf.writeln('  static const List<String> accessorNames = [');
  for (final name in names) {
    // Manifest + enum entries registered for collisions aren't
    // accessors themselves.
    if (name.dartName == 'accessorNames') continue;
    if (name.dartName.contains('.')) continue;
    buf.writeln("    r'${name.dartName}',");
  }
  buf.writeln('  ];');
  buf.writeln();
}

void _writeFileHeader(
  StringBuffer buf, {
  String? headerPreamble,
  bool hasMarkup = false,
}) {
  buf.writeln('// GENERATED CODE — DO NOT MODIFY BY HAND.');
  buf.writeln(
    '// This file is regenerated by `fluent_gen` whenever the '
    'source FTL files change.',
  );
  buf.writeln('//');
  buf.writeln('// Run `dart run build_runner build` to refresh after edits.');
  // No blanket lint suppression — the emitted shape analyzes clean
  // under package:lints recommended (the example's analyzes-clean
  // test proves it, and would prove nothing under a blanket ignore).
  // Consumers with stricter custom lint sets exclude generated files
  // (the ecosystem convention) or pass suppressions via
  // `header_preamble`.
  if (headerPreamble != null && headerPreamble.isNotEmpty) {
    buf.writeln();
    buf.writeln(headerPreamble);
  }
  buf.writeln();
  buf.writeln("import 'package:fluent_bundle/fluent_bundle.dart';");
  if (hasMarkup) {
    buf.writeln("import 'package:fluent_bundle/markup.dart';");
  }
  buf.writeln();
}

void _writeClassOpen(StringBuffer buf, String className) {
  buf.writeln(
    '/// Typed accessor for fluent_bundle messages. Wraps a '
    '[FluentBundle] and exposes one method per message + per '
    'attribute, with parameter types inferred from how each '
    'variable is used in the FTL source.',
  );
  buf.writeln('///');
  buf.writeln(
    '/// Construct with the bundle the consumer prepared (loaded '
    'with the active locale\'s FTL):',
  );
  buf.writeln('///');
  buf.writeln('/// ```dart');
  buf.writeln("/// final bundle = FluentBundle('en')..addResource(ftl);");
  buf.writeln('/// final t = $className(bundle);');
  buf.writeln('/// final hi = t.welcome(name: "Aria");');
  buf.writeln('/// ```');
  buf.writeln('class $className {');
  buf.writeln('  /// Wraps the prepared [FluentBundle].');
  buf.writeln('  $className(this._bundle);');
  buf.writeln();
  buf.writeln('  final FluentBundle _bundle;');
  buf.writeln();
}

void _writeMessageMethods(
  StringBuffer buf, {
  required InspectedFile file,
  required InspectedMessage message,
  required InferenceContext context,
  required List<InferenceNote> notes,
}) {
  final inference = inferMessage(message.message, context);
  notes.addAll(inference.notes);

  if (message.hasValue) {
    final dartName = sanitizeIdentifier(message.id);
    final input = EmissionInput(
      dartName: dartName,
      messageId: message.id,
      attributeName: null,
      parameters: inference.valueVariables,
      sourceText: message.sourceText,
      sourcePath: file.path,
      sourceLine: message.sourceLine,
      commentText: message.commentText,
      hasMarkup: message.hasMarkup,
    );
    buf.writeln(emitMethod(input));
    buf.writeln();
    if (message.hasMarkup) {
      buf.writeln(emitMethod(input, asSpans: true));
      buf.writeln();
    }
  }

  for (final attrName in message.attributeNames) {
    final dartName =
        '${sanitizeIdentifier(message.id)}\$${sanitizeIdentifier(attrName)}';
    final input = EmissionInput(
      dartName: dartName,
      messageId: message.id,
      attributeName: attrName,
      // Each attribute method demands exactly ITS pattern's
      // variables — the runtime renders only the requested pattern.
      parameters: inference.attributeVariables[attrName] ?? const [],
      // The message's source already contains its attribute lines —
      // the full block is the context a reader wants on hover.
      sourceText: message.sourceText,
      sourcePath: file.path,
      sourceLine: message.attributeLines[attrName] ?? message.sourceLine,
      commentText: message.commentText,
      // Attribute methods deliberately do NOT emit AsSpans variants.
      // Per Fluent + the inline-markup design, attributes feed
      // machine-consumed values (href, src, …); spans don't apply.
      hasMarkup: false,
    );
    buf.writeln(emitMethod(input));
    buf.writeln();
  }
}

void _writeClassClose(StringBuffer buf) {
  buf.writeln('}');
}

String _format(String source) {
  // DartFormatter normalizes whitespace, ensures lines fit within
  // the analyzer's default page width, and applies Dart's canonical
  // bracket / argument indentation.
  //
  // Modern (tall) style. The family's SDK floor is >=3.7, so every
  // consumer's own `dart format` runs the same style — emitted files
  // never fight a consumer's format gate. Lowering the floor below
  // 3.7 would reintroduce that fight; don't.
  final formatter = DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  );
  return formatter.format(source);
}
