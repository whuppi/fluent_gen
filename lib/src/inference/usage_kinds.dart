// The atomic unit of variable-usage inference.
//
// When the AST walker visits a $variable it records exactly one
// of these kinds for that occurrence. The type resolver then
// aggregates every kind a single variable has across the message
// and collapses them to a single Dart type. See `type_resolver.dart`
// for the priority cascade (DateTime > num > String > Object?).

/// How a `$variable` is used at one point in a message.
///
/// Order doesn't matter at the per-occurrence level — collapsing
/// happens in the resolver's aggregation.
enum UsageKind {
  /// Plain text interpolation: `Hello, { $name }!`.
  ///
  /// The variable's value is rendered via the bundle's number /
  /// datetime / string formatters. Anything coerces — collapse to
  /// the broadest accepted type unless another usage narrows it.
  plainInterp,

  /// Numeric / plural selector: `{ $count -> [one] ... [other] ... }`
  /// where any variant key is a number-literal or a CLDR plural
  /// category name.
  ///
  /// Forces `num` because the resolver invokes plural rules.
  numericSelector,

  /// String selector: `{ $tone -> [happy] ... [sad] ... }` with
  /// only string-keyed variants and no plural-category keys.
  ///
  /// Forces `String` (the resolver matches against literal strings).
  stringSelector,

  /// Argument to the `NUMBER` builtin: `{ NUMBER($amount) }`.
  ///
  /// Forces `num`.
  numberBuiltinArg,

  /// Argument to the `DATETIME` builtin: `{ DATETIME($d) }`.
  ///
  /// Forces `DateTime`.
  dateTimeBuiltinArg,

  /// Argument to a custom function: `{ FN($x) }`.
  ///
  /// The function's expected signature is unknown (user-defined
  /// FluentFunction registered on the bundle). Falls through to
  /// `Object?` in the resolver.
  customFunctionArg,

  // There is deliberately NO kind for term-call args. The resolver
  // never evaluates positional term args (a term's scope is built
  // from its named args only), so `{ -term($x) }` has no runtime
  // effect — the walker surfaces a PositionalTermArgNote instead of
  // a parameter.
}

/// One observed usage of a single variable. Aggregating these per-
/// variable produces the inferred Dart type.
class VariableUsage {
  /// Records one observation of [variable] used as [kind].
  const VariableUsage({required this.variable, required this.kind});

  /// The variable name (without the leading `$`).
  final String variable;

  /// What kind of usage was observed.
  final UsageKind kind;

  @override
  String toString() => 'VariableUsage(\$$variable as ${kind.name})';

  @override
  bool operator ==(Object other) =>
      other is VariableUsage &&
      other.variable == variable &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(variable, kind);
}
