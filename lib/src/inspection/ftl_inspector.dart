// FTL inspection layer.
//
// Wraps the existing `package:fluent_bundle/syntax.dart` parser and
// pulls out the metadata the inference + emission stages need:
//
//   - the message id and (optional) attribute names
//   - whether the value-pattern contains inline markup
//   - the FTL source text for each message (for doc comments)
//   - junk / parse errors collected per file
//
// Stays pure-data — no Dart-emission logic. The inference stage
// owns the AST walk; this layer just parses and surfaces the
// results in a generator-friendly shape.

import 'package:fluent_bundle/syntax.dart';

/// A `.ftl` file's contents inspected for codegen.
class InspectedFile {
  /// Bundles one parsed file's codegen-relevant metadata.
  const InspectedFile({
    required this.path,
    required this.locale,
    required this.content,
    required this.resource,
    required this.messages,
    required this.terms,
    required this.junk,
  });

  /// Source path the file came from (for diagnostics + doc comments).
  final String path;

  /// Locale the file belongs to.
  final String locale;

  /// The raw FTL source, exactly as read. Embedded into the generated
  /// file when `bundle_ftl` is on.
  final String content;

  /// The full parsed `Resource` AST. Inference walks this directly.
  final Resource resource;

  /// Every `Message` with at least one of: a value-pattern, an
  /// attribute, or both. Junk messages and value-less / attribute-
  /// less messages are filtered out.
  final List<InspectedMessage> messages;

  /// Every `Term` parsed from the file. Terms never generate public
  /// methods (they're invisible to the consumer per the Fluent spec)
  /// and never contribute parameters (a term's scope is its own named
  /// call args) — exposed for diagnostics and future tooling.
  final List<Term> terms;

  /// Every `Junk` entry the parser couldn't make sense of. Surfaced
  /// to the caller so it can decide whether to emit a build warning
  /// or fail the build.
  final List<Junk> junk;
}

/// A `Message` extracted from a Resource, paired with metadata the
/// emission stage needs.
class InspectedMessage {
  /// Bundles one message's codegen-relevant metadata.
  const InspectedMessage({
    required this.id,
    required this.message,
    required this.sourceText,
    required this.sourceLine,
    required this.attributeLines,
  });

  /// The message id as it appears in the FTL (`welcome`,
  /// `shopping-cart`, etc.). Always identical to `message.id.name`,
  /// stored separately so callers don't have to dereference the AST.
  final String id;

  /// The raw `Message` AST node.
  final Message message;

  /// The exact source text of the message, used to render
  /// doc-comments on generated methods.
  ///
  /// Example for `welcome = Hello, { $name }!\n`:
  /// `'welcome = Hello, { \$name }!'` (newline trimmed).
  final String sourceText;

  /// 1-based line the message starts on (1 when spans are absent).
  final int sourceLine;

  /// 1-based start line per attribute name (message line when spans
  /// are absent).
  final Map<String, int> attributeLines;

  /// The attached comment's content (`# …` directly above the
  /// message), without the `#` markers. Null when absent.
  String? get commentText => message.comment?.content;

  /// True when the message's VALUE pattern contains inline markup —
  /// `<` or `</` followed by a letter in its literal text (or in a
  /// string-literal placeable, which resolves into the same text the
  /// markup parser sees).
  ///
  /// Only the value pattern counts: the `*AsSpans` sibling formats
  /// the value, never attributes, so markup-shaped text in an
  /// attribute must not trigger a sibling.
  bool get hasMarkup {
    final value = message.value;
    if (value == null) return false;
    final pattern = RegExp(r'</?[A-Za-z]');
    for (final element in value.elements) {
      if (element is TextElement && pattern.hasMatch(element.value)) {
        return true;
      }
      if (element is Placeable) {
        final expr = element.expression;
        if (expr is StringLiteralExpression &&
            pattern.hasMatch(expr.literal.value)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Names of every attribute defined on this message (in source
  /// order).
  List<String> get attributeNames =>
      message.attributes.map((a) => a.id.name).toList(growable: false);

  /// True when the message defines a value pattern (`= Hello, ...`).
  /// False for value-less attribute-only messages (`= \n .key = ...`).
  bool get hasValue => message.value != null;
}

/// Parse and inspect a single `.ftl` file.
///
/// Returns an [InspectedFile] even when the source has parse errors;
/// the errors live in `junk`. Inspection never throws on bad FTL —
/// the build can continue with the parts that did parse, surfacing
/// junk as build warnings.
InspectedFile inspectFtl({
  required String path,
  required String locale,
  required String content,
}) {
  final parser = FluentParser(
    options: const FluentParserOptions(withSpans: true),
  );
  final resource = parser.parse(content);

  final messages = <InspectedMessage>[];
  final terms = <Term>[];
  final junk = <Junk>[];

  for (final entry in resource.body) {
    if (entry is Message) {
      // Skip messages with neither a value nor attributes — those
      // are syntactically valid but generate nothing useful.
      if (entry.value == null && entry.attributes.isEmpty) continue;

      final source = _sourceFor(entry, content);
      messages.add(
        InspectedMessage(
          id: entry.id.name,
          message: entry,
          sourceText: source,
          sourceLine: _lineOf(entry.span, content),
          attributeLines: {
            for (final attribute in entry.attributes)
              attribute.id.name: _lineOf(attribute.span ?? entry.span, content),
          },
        ),
      );
    } else if (entry is Term) {
      terms.add(entry);
    } else if (entry is Junk) {
      junk.add(entry);
    }
    // Standalone comments and group comments are dropped. A comment
    // directly above a message rides on `Message.comment` and renders
    // into the generated method's doc comment (and may carry type
    // annotations — see comment_pins.dart).
  }

  return InspectedFile(
    path: path,
    locale: locale,
    content: content,
    resource: resource,
    messages: messages,
    terms: terms,
    junk: junk,
  );
}

/// 1-based line number a span starts on. 1 when spans are absent —
/// the inspector always parses with spans, so the fallback is for
/// safety only.
int _lineOf(Span? span, String content) {
  if (span == null) return 1;
  final start = span.start.clamp(0, content.length);
  var line = 1;
  for (var i = 0; i < start; i++) {
    if (content.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

/// Extract the original source text covered by an entry's span.
///
/// Falls back to a synthetic `id = ...` rendering when the parser
/// was configured without spans. The inspector always requests
/// spans via [FluentParserOptions.withSpans], so the fallback is
/// for safety only — never reached in normal use.
String _sourceFor(Entry entry, String content) {
  final span = entry.span;
  if (span == null) {
    if (entry is Message) return '${entry.id.name} = …';
    if (entry is Term) return '-${entry.id.name} = …';
    return '';
  }
  final start = span.start;
  final end = span.end.clamp(start, content.length);
  return content.substring(start, end).trimRight();
}
