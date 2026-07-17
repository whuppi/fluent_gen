// Aggregate per-variable [VariableUsage]s into a single Dart type.
//
// Priority cascade:
//
//   1. Any usage requires DateTime → DateTime.
//   2. Else if any usage requires num → num.
//   3. Else if all usages accept String → String.
//   4. Else → Object? (the safety net for incompatible usages).
//
// Conflicting hard requirements (e.g. one usage demands DateTime,
// another demands num) collapse to Object? AND set hadConflict=true
// so the emitter can annotate the generated parameter.

import 'package:fluent_gen/src/inference/usage_kinds.dart';

/// The Dart-level shape inferred for a $variable. Used by emission.
enum InferredDartType {
  /// `String` — at least one usage is a string selector or term
  /// arg, and no usage requires a number / datetime.
  stringType,

  /// `num` — at least one usage is a numeric selector or NUMBER
  /// builtin arg, and no usage requires a DateTime.
  numType,

  /// `DateTime` — at least one usage is a DATETIME builtin arg.
  dateTimeType,

  /// `Object?` — usages conflict, or the only usage was a custom
  /// function arg or a plain interp without other constraints.
  objectType,
}

/// Inferred type for one variable, plus a flag indicating whether
/// the inference was a hard conflict (in which case the emitter
/// should annotate the generated parameter with a comment pointing
/// at the conflict for the consumer to read).
class InferredVariable {
  /// Bundles one variable's resolved type.
  const InferredVariable({
    required this.name,
    required this.type,
    required this.hadConflict,
  });

  /// Variable name (without the leading `$`).
  final String name;

  /// Resolved Dart type.
  final InferredDartType type;

  /// True when the inference rule fired its widen-on-conflict
  /// path. The emitter uses this to add a `// inferred Object? due
  /// to conflicting usage` comment so the consumer notices.
  final bool hadConflict;

  @override
  String toString() =>
      'InferredVariable($name: ${type.name}'
      '${hadConflict ? ', conflict' : ''})';
}

/// Aggregate a list of [VariableUsage]s into one [InferredVariable]
/// per distinct variable name.
///
/// Order of variables in the result matches the order of FIRST
/// occurrence in [usages] — gives stable, source-order parameter
/// lists in the generated method signatures.
List<InferredVariable> resolveVariableTypes(List<VariableUsage> usages) {
  // Group usages by variable name, preserving first-seen order.
  final orderedNames = <String>[];
  final byName = <String, List<UsageKind>>{};
  for (final u in usages) {
    if (!byName.containsKey(u.variable)) {
      orderedNames.add(u.variable);
      byName[u.variable] = [];
    }
    byName[u.variable]!.add(u.kind);
  }

  return [for (final name in orderedNames) _resolve(name, byName[name]!)];
}

InferredVariable _resolve(String name, List<UsageKind> kinds) {
  // Build sets of "what the variable MUST be" and "what it MUST
  // NOT be" across every usage. The conflict matrix is small enough
  // that explicit boolean accumulation is simpler than a constraint
  // solver — and it's stable: the priority order is in the
  // outermost cascade below.

  var needsDateTime = false;
  var needsNum = false;
  var needsString = false;

  for (final kind in kinds) {
    switch (kind) {
      case UsageKind.dateTimeBuiltinArg:
        needsDateTime = true;
      case UsageKind.numberBuiltinArg:
      case UsageKind.numericSelector:
        needsNum = true;
      case UsageKind.stringSelector:
        needsString = true;
      case UsageKind.plainInterp:
      case UsageKind.customFunctionArg:
        break; // structurally unconstrained
    }
  }

  // Priority cascade per plan §4.
  //
  // Conflicts: a variable that needs to be BOTH DateTime AND num,
  // or DateTime AND String, or num AND String, can't be narrowed.
  // Fall through to Object? and flag the conflict so the emitter
  // surfaces it.
  final hardestNeedsCount =
      (needsDateTime ? 1 : 0) + (needsNum ? 1 : 0) + (needsString ? 1 : 0);

  if (hardestNeedsCount > 1) {
    return InferredVariable(
      name: name,
      type: InferredDartType.objectType,
      hadConflict: true,
    );
  }

  if (needsDateTime) {
    return InferredVariable(
      name: name,
      type: InferredDartType.dateTimeType,
      hadConflict: false,
    );
  }

  if (needsNum) {
    return InferredVariable(
      name: name,
      type: InferredDartType.numType,
      hadConflict: false,
    );
  }

  if (needsString) {
    return InferredVariable(
      name: name,
      type: InferredDartType.stringType,
      hadConflict: false,
    );
  }

  // All usages were plain-interp or custom-function-arg. The
  // variable is structurally unconstrained — fall back to Object?.
  // Not a "conflict" per se; the consumer can pass anything that
  // toString-coerces (or a comment pin narrows it — see
  // comment_pins.dart).
  return InferredVariable(
    name: name,
    type: InferredDartType.objectType,
    hadConflict: false,
  );
}
