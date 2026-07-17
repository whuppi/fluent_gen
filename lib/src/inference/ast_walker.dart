// Walk patterns and collect every $variable usage with its UsageKind,
// following message references transitively.
//
// Message references resolve in the SAME scope as the referring
// message at runtime — the referenced pattern's variables are the
// caller's to supply. The walker therefore unions a referenced
// message's usages into the referrer: `{ msg }` walks msg's value
// pattern, `{ msg.attr }` walks that attribute's pattern, recursively,
// with a visited-set guard so reference cycles terminate (the runtime
// separately reports cycles as FluentCyclicReferenceError).
//
// Term references contribute NO parameters. A term's body resolves
// against its own named call args only — caller args never leak in —
// and the resolver never evaluates positional term args, so a bare
// `{ -term($x) }` has no runtime effect. It surfaces as a
// [PositionalTermArgNote] instead of a parameter. Named term-call
// args are restricted to literals by the Fluent EBNF; the walker
// skips them.
//
// Custom functions (`{ FN($x) }`) call into FluentFunction
// implementations registered on the bundle. The function's expected
// signature is unknown to the generator, so usages route to
// UsageKind.customFunctionArg, which collapses to `Object?` in the
// resolver.
//
// Pure function of the AST + message map: same input → same output,
// no caching, no side effects.

import 'package:fluent_bundle/syntax.dart';
import 'package:fluent_gen/src/inference/inference_note.dart';
import 'package:fluent_gen/src/inference/usage_kinds.dart';

/// Everything one pattern walk observed: variable usages (duplicates
/// preserved — the resolver aggregates) and advisory notes.
class WalkResult {
  /// Bundles the walk's [usages] and [notes].
  const WalkResult({required this.usages, required this.notes});

  /// Every variable usage observed, duplicates preserved.
  final List<VariableUsage> usages;

  /// Advisory notes (positional term args).
  final List<InferenceNote> notes;
}

/// Walk one [Pattern] and return every variable usage observed,
/// following message references through [messagesById] (the base
/// locale's id → Message map).
///
/// [messageId] attributes notes to the message whose method the walk
/// serves — for a transitive walk, notes still name the OUTER message
/// (its generated method is where the consumer looks).
WalkResult walkPattern(
  Pattern pattern, {
  required String messageId,
  required Map<String, Message> messagesById,
}) {
  final walker = _Walker(messageId: messageId, messagesById: messagesById);
  walker._walkPattern(pattern);
  return WalkResult(usages: walker.usages, notes: walker.notes);
}

class _Walker {
  _Walker({required this.messageId, required this.messagesById});

  final String messageId;
  final Map<String, Message> messagesById;
  final usages = <VariableUsage>[];
  final notes = <InferenceNote>[];

  /// Reference targets already entered on the current walk —
  /// `msg` for value references, `msg.attr` for attribute references.
  /// Guards against reference cycles.
  final _visited = <String>{};

  void _walkPattern(Pattern pattern) {
    for (final element in pattern.elements) {
      if (element is TextElement) continue;
      if (element is Placeable) {
        _walkExpression(element.expression);
      }
    }
  }

  void _walkExpression(Expression expression) {
    if (expression is VariableReference) {
      usages.add(
        VariableUsage(
          variable: expression.id.name,
          kind: UsageKind.plainInterp,
        ),
      );
      return;
    }

    if (expression is FunctionReference) {
      _walkFunctionCall(expression);
      return;
    }

    if (expression is TermReference) {
      _walkTermCall(expression);
      return;
    }

    if (expression is MessageReference) {
      _walkMessageRef(expression);
      return;
    }

    if (expression is SelectExpression) {
      _walkSelect(expression);
      return;
    }

    // Literal expressions (StringLiteral, NumberLiteral) and
    // Placeable wrappers around them have nothing to contribute.
  }

  /// Function calls. Argument positions get usage kinds based on the
  /// callee's identity:
  ///
  ///   NUMBER(...)   → numberBuiltinArg
  ///   DATETIME(...) → dateTimeBuiltinArg
  ///   anything else → customFunctionArg
  void _walkFunctionCall(FunctionReference call) {
    final fnName = call.id.name;
    final UsageKind argKind;
    if (fnName == 'NUMBER') {
      argKind = UsageKind.numberBuiltinArg;
    } else if (fnName == 'DATETIME') {
      argKind = UsageKind.dateTimeBuiltinArg;
    } else {
      argKind = UsageKind.customFunctionArg;
    }

    for (final positional in call.arguments.positional) {
      if (positional is VariableReference) {
        usages.add(VariableUsage(variable: positional.id.name, kind: argKind));
      } else {
        // The arg is itself a complex expression (rare but valid).
        // Keep walking — any nested $var references will be picked
        // up with their own usage kind.
        _walkExpression(positional);
      }
    }

    // Named arg values are typed as `Literal` per the AST — they
    // can never be VariableReference. No $variable usage can hide
    // there, so the walker skips them.
  }

  /// Term calls contribute no parameters (see the file header). A
  /// bare variable in a positional slot notes the no-effect usage;
  /// complex positional expressions are still walked so any nested
  /// variables surface with their own kinds.
  void _walkTermCall(TermReference term) {
    final args = term.arguments;
    if (args == null) return;

    for (final positional in args.positional) {
      if (positional is VariableReference) {
        notes.add(
          PositionalTermArgNote(messageId: messageId, termName: term.id.name),
        );
      } else {
        _walkExpression(positional);
      }
    }

    // Named term-call args are Literal-only per the EBNF — skipped.
  }

  /// Message references resolve the referenced pattern in the SAME
  /// scope at runtime — union its usages into this walk. Unknown
  /// targets contribute nothing (the runtime records a FluentError;
  /// the locale validator's territory).
  void _walkMessageRef(MessageReference ref) {
    final target = messagesById[ref.id.name];
    if (target == null) return;

    final attr = ref.attribute?.name;
    final visitKey = attr == null ? ref.id.name : '${ref.id.name}.$attr';
    if (!_visited.add(visitKey)) return;

    if (attr == null) {
      if (target.value != null) _walkPattern(target.value!);
      return;
    }
    for (final attribute in target.attributes) {
      if (attribute.id.name == attr) {
        _walkPattern(attribute.value);
        return;
      }
    }
  }

  /// Select expressions. Two contributions:
  ///
  ///   1. The selector itself: `{ $count -> ... }` — classified by
  ///      the variant keys.
  ///   2. Variables inside variant patterns are walked recursively
  ///      with their own usage kinds.
  void _walkSelect(SelectExpression select) {
    final selector = select.selector;
    if (selector is VariableReference) {
      final kind = _selectorKindFromVariants(select.variants);
      if (kind != null) {
        usages.add(VariableUsage(variable: selector.id.name, kind: kind));
      } else {
        // Keys give no signal (only `*[other]`) — record the bare
        // usage so the variable still becomes a parameter.
        usages.add(
          VariableUsage(
            variable: selector.id.name,
            kind: UsageKind.plainInterp,
          ),
        );
      }
    } else {
      // Selector is not a bare variable — the resolver evaluates it
      // first (e.g. `{ NUMBER($x) -> ... }`). Walk the expression so
      // any nested variables surface with their own usage.
      _walkExpression(selector);
    }

    for (final variant in select.variants) {
      _walkPattern(variant.value);
    }
  }
}

/// Classify a select's bare-variable selector from its variant keys.
///
///   - numeric — EVERY key is a number literal or a CLDR plural
///     category, AND at least one key is a number or a non-`other`
///     plural category. The resolver routes a numeric selector
///     through plural rules, which require a `num`.
///   - string — any key is a non-plural identifier (`[windows]`,
///     `[happy]`). The resolver matches those as string literals.
///   - null (no signal) — the only key is `*[other]`. `other` is both
///     a plural category AND the natural default key for string
///     selectors (`{ PLATFORM() -> [windows] … *[other] … }`), so
///     alone it cannot decide either way.
UsageKind? _selectorKindFromVariants(List<Variant> variants) {
  const pluralCategories = {'zero', 'one', 'two', 'few', 'many', 'other'};

  var sawNumericSignal = false;
  for (final variant in variants) {
    final key = variant.key;
    if (key is NumberLiteralKey) {
      sawNumericSignal = true;
      continue;
    }
    if (key is IdentifierKey) {
      final name = key.id.name;
      if (!pluralCategories.contains(name)) {
        return UsageKind.stringSelector;
      }
      if (name != 'other') sawNumericSignal = true;
    }
  }

  return sawNumericSignal ? UsageKind.numericSelector : null;
}
