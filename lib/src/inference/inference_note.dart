// Advisories the inference stage produces alongside the inferred
// variables. Inference stays a pure function — notes are returned,
// never logged; the Builder layer decides how to surface them
// (build warnings today).

/// One advisory about a message's FTL source, produced during
/// inference. Never fatal — the generated code is still valid; the
/// note tells the FTL author about something they probably didn't
/// intend.
sealed class InferenceNote {
  const InferenceNote({required this.messageId});

  /// The FTL message id the note concerns.
  final String messageId;

  /// Human-readable formatted message for the build log.
  String formatted();
}

/// `{ -term($x) }` — a positional argument in a term call. The
/// resolver builds a term's scope from NAMED arguments only;
/// positional term args are never evaluated, so the expression has no
/// runtime effect and contributes no method parameter.
class PositionalTermArgNote extends InferenceNote {
  /// Notes a positional argument to [termName] in [messageId].
  const PositionalTermArgNote({
    required super.messageId,
    required this.termName,
  });

  /// The referenced term (without the leading `-`).
  final String termName;

  @override
  String formatted() =>
      'fluent_gen: message `$messageId` passes a '
      'positional argument to term `-$termName`. Fluent terms take '
      'named arguments only — the positional argument has no runtime '
      'effect and is not a method parameter.';
}

/// A comment annotation used a type keyword the generator doesn't
/// know: `# $count (Numbr)`. Recognized keywords: `String`, `Number`,
/// `DateTime`.
class UnknownPinTypeNote extends InferenceNote {
  /// Notes an unrecognized [keyword] annotating [variable].
  const UnknownPinTypeNote({
    required super.messageId,
    required this.variable,
    required this.keyword,
  });

  /// The annotated variable name (without the leading `$`).
  final String variable;

  /// The unrecognized keyword as written.
  final String keyword;

  @override
  String formatted() =>
      'fluent_gen: message `$messageId` annotates '
      '`\$$variable` with unknown type `($keyword)`. Recognized '
      'annotations: (String), (Number), (DateTime). The annotation '
      'was ignored.';
}

/// A comment annotation names a variable the message (including
/// everything it references transitively) never uses:
/// `# $nme (String)` above a message that only uses `$name`.
class PinUnknownVariableNote extends InferenceNote {
  /// Notes an annotation for a [variable] the message never uses.
  const PinUnknownVariableNote({
    required super.messageId,
    required this.variable,
  });

  /// The annotated variable name (without the leading `$`).
  final String variable;

  @override
  String formatted() =>
      'fluent_gen: message `$messageId` has a type '
      'annotation for `\$$variable`, but no such variable is used by '
      'the message. Probably a typo in the comment.';
}

/// A comment annotation disagrees with what usage-based inference
/// proved: `# $count (String)` on a variable used as `NUMBER($count)`.
/// Usage wins — the annotation was ignored.
class PinConflictNote extends InferenceNote {
  /// Notes a pin the usage-based inference overruled.
  const PinConflictNote({
    required super.messageId,
    required this.variable,
    required this.pinnedType,
    required this.inferredType,
  });

  /// The annotated variable name (without the leading `$`).
  final String variable;

  /// The type the comment asked for, as written (`String`, `Number`,
  /// `DateTime`).
  final String pinnedType;

  /// The Dart type usage-based inference resolved (`num`,
  /// `DateTime`, `String`, `Object?`).
  final String inferredType;

  @override
  String formatted() =>
      'fluent_gen: message `$messageId` annotates '
      '`\$$variable` as ($pinnedType) but its usage in the FTL '
      'requires `$inferredType`. Usage wins — the annotation was '
      'ignored.';
}
