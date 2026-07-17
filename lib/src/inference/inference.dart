// Public entry point for the inference stage.
//
// `inferMessage(message, context)` computes, in one pass:
//
//   - the body method's parameters (the VALUE pattern's variables,
//     transitively through message references),
//   - each attribute method's parameters (that ATTRIBUTE's pattern),
//   - the whole-message union (what the locale validator compares
//     across locales),
//   - comment type pins applied on top of usage-based inference,
//   - every advisory note the walk + pin passes produced.
//
// Per-pattern parameter lists exist because the runtime formats only
// the requested pattern: `formatMessage(id)` renders the value,
// `formatMessage(id, attribute: a)` renders that attribute. A method
// must demand exactly the variables its pattern (transitively)
// resolves — no more, no less.

import 'package:fluent_bundle/syntax.dart';
import 'package:fluent_gen/src/inference/ast_walker.dart';
import 'package:fluent_gen/src/inference/comment_pins.dart';
import 'package:fluent_gen/src/inference/inference_note.dart';
import 'package:fluent_gen/src/inference/type_resolver.dart';
import 'package:fluent_gen/src/inference/usage_kinds.dart';

export 'package:fluent_gen/src/inference/inference_note.dart';
export 'package:fluent_gen/src/inference/type_resolver.dart'
    show InferredDartType, InferredVariable;
export 'package:fluent_gen/src/inference/usage_kinds.dart'
    show UsageKind, VariableUsage;

/// What inference needs beyond the message itself: the id → Message
/// map of the SAME locale, so message references resolve transitively.
///
/// Build one per locale from every file of that locale (message
/// references cross files within a locale).
class InferenceContext {
  /// Wraps the locale's [messagesById] map.
  const InferenceContext({required this.messagesById});

  /// Every message of the locale, keyed by FTL id.
  final Map<String, Message> messagesById;
}

/// The complete inference result for one message.
class MessageInference {
  /// Bundles every per-message inference product.
  const MessageInference({
    required this.messageVariables,
    required this.valueVariables,
    required this.attributeVariables,
    required this.notes,
  });

  /// Union across the value pattern and every attribute — the
  /// "what args does this message take" set the locale validator
  /// compares across locales.
  final List<InferredVariable> messageVariables;

  /// The body method's parameters (empty when the message has no
  /// value pattern).
  final List<InferredVariable> valueVariables;

  /// Each attribute method's parameters, keyed by attribute name.
  final Map<String, List<InferredVariable>> attributeVariables;

  /// Advisories for the build log (positional term args, pin typos,
  /// pin/usage conflicts).
  final List<InferenceNote> notes;
}

/// Run inference on a single [Message] under [context].
MessageInference inferMessage(Message message, InferenceContext context) {
  final messageId = message.id.name;
  final notes = <InferenceNote>[];

  final pins = parseCommentPins(
    messageId: messageId,
    commentContent: message.comment?.content,
  );
  notes.addAll(pins.notes);

  WalkResult walk(Pattern pattern) => walkPattern(
    pattern,
    messageId: messageId,
    messagesById: context.messagesById,
  );

  final valueWalk = message.value == null ? null : walk(message.value!);
  if (valueWalk != null) notes.addAll(valueWalk.notes);

  final attrWalks = <String, WalkResult>{};
  for (final attribute in message.attributes) {
    final result = walk(attribute.value);
    attrWalks[attribute.id.name] = result;
    notes.addAll(result.notes);
  }

  // The union resolves from ALL usages so a variable typed by one
  // pattern (NUMBER($x) in an attribute) carries that constraint in
  // the cross-locale comparison. Pin notes (conflict / unknown
  // variable) are emitted from the union pass ONLY — the per-pattern
  // passes reuse the same pin decisions silently so each note appears
  // once.
  final unionUsages = <VariableUsage>[
    ...?valueWalk?.usages,
    for (final result in attrWalks.values) ...result.usages,
  ];
  final union = _applyPins(
    messageId: messageId,
    variables: resolveVariableTypes(unionUsages),
    pins: pins.pins,
    notes: notes,
  );

  for (final pinned in pins.pins.keys) {
    if (!union.any((v) => v.name == pinned)) {
      notes.add(PinUnknownVariableNote(messageId: messageId, variable: pinned));
    }
  }

  List<InferredVariable> resolvePattern(WalkResult result) => _applyPins(
    messageId: messageId,
    variables: resolveVariableTypes(result.usages),
    pins: pins.pins,
    notes: null,
  );

  return MessageInference(
    messageVariables: union,
    valueVariables: valueWalk == null ? const [] : resolvePattern(valueWalk),
    attributeVariables: {
      for (final entry in attrWalks.entries)
        entry.key: resolvePattern(entry.value),
    },
    notes: notes,
  );
}

/// Apply comment pins on top of usage-based inference. Usage is
/// ground truth: a pin only narrows a variable inference left at
/// `Object?` without a hard conflict. Disagreements surface on
/// [notes] when a sink is given (the union pass); per-pattern passes
/// pass null so each note appears once.
List<InferredVariable> _applyPins({
  required String messageId,
  required List<InferredVariable> variables,
  required Map<String, InferredDartType> pins,
  required List<InferenceNote>? notes,
}) {
  if (pins.isEmpty) return variables;

  return [
    for (final v in variables) _applyPin(messageId, v, pins[v.name], notes),
  ];
}

InferredVariable _applyPin(
  String messageId,
  InferredVariable variable,
  InferredDartType? pin,
  List<InferenceNote>? notes,
) {
  if (pin == null || variable.type == pin) return variable;

  if (variable.type == InferredDartType.objectType && !variable.hadConflict) {
    return InferredVariable(name: variable.name, type: pin, hadConflict: false);
  }

  notes?.add(
    PinConflictNote(
      messageId: messageId,
      variable: variable.name,
      pinnedType: _keywordOf(pin),
      inferredType:
          variable.hadConflict
              ? 'Object? (conflicting usages)'
              : _dartNameOf(variable.type),
    ),
  );
  return variable;
}

String _keywordOf(InferredDartType type) => switch (type) {
  InferredDartType.stringType => 'String',
  InferredDartType.numType => 'Number',
  InferredDartType.dateTimeType => 'DateTime',
  InferredDartType.objectType => 'Object',
};

String _dartNameOf(InferredDartType type) => switch (type) {
  InferredDartType.stringType => 'String',
  InferredDartType.numType => 'num',
  InferredDartType.dateTimeType => 'DateTime',
  InferredDartType.objectType => 'Object?',
};
