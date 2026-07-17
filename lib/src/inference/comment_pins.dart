// Parse type annotations from a message's attached FTL comment.
//
// The syntax is Mozilla's documented comment convention (used across
// Firefox's own FTL and adopted by fluent-typed in the Rust
// ecosystem) — no invented fluent_gen syntax:
//
//     # $name (String) - the user's name
//     # $count (Number) - how many items
//     # $when (DateTime) - when it happened
//     welcome = Hello { $name }
//
// Recognized keywords: String, Number, DateTime. Number maps to Dart
// `num`. Annotations are read from the BASE locale only (the
// generator never reads non-base comments — only the base drives
// codegen), so translators never maintain type metadata.
//
// Pins fill the gap usage-based inference can't close: a variable
// whose only usages are plain interpolation or custom-function args
// resolves to `Object?`; a pin narrows it. When usage PROVED a type
// (NUMBER($x) → num) a disagreeing pin is ignored with a
// [PinConflictNote] — usage is ground truth.

import 'package:fluent_gen/src/inference/inference_note.dart';
import 'package:fluent_gen/src/inference/type_resolver.dart';

/// The parsed annotations of one message comment.
class CommentPins {
  /// Bundles the parsed [pins] and [notes].
  const CommentPins({required this.pins, required this.notes});

  /// The no-comment / no-annotation result.
  static const empty = CommentPins(pins: {}, notes: []);

  /// variable name (without `$`) → pinned type.
  final Map<String, InferredDartType> pins;

  /// Advisories: unknown type keywords.
  final List<InferenceNote> notes;
}

/// An annotation attempt: `$name (Word)` where Word is one
/// PascalCase-ish token. Prose like `$name (the user's name)` has a
/// space inside the parens and never matches; only single-token
/// parentheticals are treated as annotation attempts.
final _pinPattern = RegExp(
  r'\$([A-Za-z][A-Za-z0-9_-]*)\s*\(([A-Za-z][A-Za-z0-9]*)\)',
);

const _keywordToType = <String, InferredDartType>{
  'String': InferredDartType.stringType,
  'Number': InferredDartType.numType,
  'DateTime': InferredDartType.dateTimeType,
};

/// Parse every `$var (Type)` annotation out of [commentContent]
/// (a message's attached comment; pass null for none).
CommentPins parseCommentPins({
  required String messageId,
  required String? commentContent,
}) {
  if (commentContent == null || commentContent.isEmpty) {
    return CommentPins.empty;
  }

  final pins = <String, InferredDartType>{};
  final notes = <InferenceNote>[];

  for (final match in _pinPattern.allMatches(commentContent)) {
    final variable = match.group(1)!;
    final keyword = match.group(2)!;
    final type = _keywordToType[keyword];
    if (type == null) {
      // A single capitalized token that isn't a known keyword reads
      // as a typo'd annotation (`(Numbr)`); lowercase tokens read as
      // prose and stay silent.
      if (keyword[0].toUpperCase() == keyword[0]) {
        notes.add(
          UnknownPinTypeNote(
            messageId: messageId,
            variable: variable,
            keyword: keyword,
          ),
        );
      }
      continue;
    }
    pins[variable] = type;
  }

  return CommentPins(pins: pins, notes: notes);
}
