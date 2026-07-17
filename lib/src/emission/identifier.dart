// Sanitize FTL identifiers into valid Dart identifiers.
//
// FTL allows `kebab-case` and underscores. Dart wants `lowerCamelCase`
// for methods, and Dart reserved words can't be used as identifiers
// at all. The sanitizer:
//
//   1. Strips/replaces every character not in `[a-zA-Z0-9_]`.
//   2. Converts kebab-case to lowerCamelCase
//      (`shopping-cart` → `shoppingCart`).
//   3. Prepends `$` if the result starts with a digit OR collides
//      with a Dart reserved word.
//   4. Detects collisions across a batch of FTL ids and surfaces
//      duplicates as hard errors (not silent renames).

/// Dart reserved words that cannot be used as identifiers.
///
/// Includes both unconditional reserved words AND built-in
/// identifiers that are reserved only in some positions. The set
/// is conservative — every entry gets a `$` prefix on collision so
/// generated code is safe regardless of where the identifier lands.
/// Add new entries when a future Dart version reserves more
/// keywords; never remove entries (would break consumer FTL files
/// that depend on the prefix).
/// Shared by the method-name sanitizer here and the parameter-name
/// guard in method_emitter.dart — one list, one source of truth.
const Set<String> dartReservedWords = {
  // Reserved words
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue',
  'default', 'do', 'else', 'enum', 'extends', 'false', 'final',
  'finally', 'for', 'if', 'in', 'is', 'new', 'null', 'rethrow',
  'return', 'super', 'switch', 'this', 'throw', 'true', 'try',
  'var', 'void', 'while', 'with',
  // Built-in identifiers (reserved in some positions)
  'abstract', 'as', 'covariant', 'deferred', 'dynamic', 'export',
  'extension', 'external', 'factory', 'function', 'get', 'implements',
  'import', 'interface', 'late', 'library', 'mixin', 'operator',
  'part', 'required', 'set', 'static', 'typedef',
  // Async-related
  'async', 'await', 'sync', 'yield',
  // Pattern-matching (Dart 3.0+)
  'when', 'inout', 'out',
};

/// Convert one FTL identifier to a Dart-safe lowerCamelCase form.
///
/// Examples:
///   `welcome`         → `welcome`
///   `shopping-cart`   → `shoppingCart`
///   `user_name`       → `userName`
///   `if`              → `$if`
///   `123-foo`         → `$123Foo`        (leading digit → $-prefix)
///   `--double-dash`   → `doubleDash`     (leading separators stripped)
///   ``                → throws ArgumentError
String sanitizeIdentifier(String ftlId) {
  if (ftlId.isEmpty) {
    throw ArgumentError('Cannot sanitize empty identifier');
  }

  // Split on `-` or `_`, drop empty pieces. Handles `--foo`,
  // `foo--bar`, leading/trailing separators.
  final parts =
      ftlId.split(RegExp(r'[-_]+')).where((p) => p.isNotEmpty).toList();

  if (parts.isEmpty) {
    throw ArgumentError('Identifier `$ftlId` produces no segments');
  }

  // Single-segment Dart-identifier-shaped inputs (alpha or `_`
  // start, alphanumeric/`_` rest) pass through verbatim. The
  // translator's casing is the answer for `launchedAt`,
  // `XmlHttpRequest`, etc. Multi-segment inputs (`launched-at`,
  // `LAUNCHED_AT`) get the canonical lowerCamelCase rebuild.
  final isCleanSingleSegment =
      parts.length == 1 &&
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(parts.first);
  var result =
      isCleanSingleSegment
          ? parts.first
          : _toLowerCase(parts.first) + parts.skip(1).map(_capitalize).join();

  // Defensive strip of any chars outside `[a-zA-Z0-9_]`. Spec FTL
  // identifiers cannot contain anything else, but stripping keeps
  // the output a valid Dart identifier even if the parser ever
  // loosens its rule.
  result = result.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');

  if (result.isEmpty) {
    // Input was all non-Dart-identifier chars (e.g. emoji-only).
    // Surface as a hard error rather than emit a synthetic name.
    throw ArgumentError(
      'Cannot sanitize identifier `$ftlId`: no valid Dart-identifier '
      'characters remain after stripping.',
    );
  }

  // Prefix with `$` when the result starts with a digit or
  // collides with a Dart keyword.
  if (RegExp(r'^[0-9]').hasMatch(result)) {
    result = '\$$result';
  } else if (dartReservedWords.contains(result)) {
    result = '\$$result';
  }

  return result;
}

String _toLowerCase(String segment) =>
    segment.isEmpty ? segment : segment.toLowerCase();

String _capitalize(String segment) {
  if (segment.isEmpty) return segment;
  return segment[0].toUpperCase() + segment.substring(1).toLowerCase();
}

/// One emitted Dart name paired with the FTL source construct it came
/// from (`welcome`, `login.title`, `foo [AsSpans sibling]`) — the
/// descriptor is what a collision error shows the consumer.
typedef EmittedName = ({String dartName, String sourceId});

/// Detect collisions in the COMPLETE emitted name set — body methods,
/// attribute methods, and `*AsSpans` siblings all share one Dart
/// namespace, so all of them enter the check.
///
/// Returns `dart-identifier → the FTL source descriptors that map to
/// it` for every entry with more than one source. The emitter rejects
/// the build with [CollisionError] rather than pick a winner silently.
Map<String, List<String>> findCollisions(Iterable<EmittedName> names) {
  final byDart = <String, List<String>>{};
  for (final name in names) {
    byDart.putIfAbsent(name.dartName, () => []).add(name.sourceId);
  }
  return Map.fromEntries(byDart.entries.where((e) => e.value.length > 1));
}

/// Thrown by emission when sanitization produces colliding Dart
/// identifiers. The consumer fixes it by renaming one of the
/// offending FTL ids. The emitter never picks a winner silently
/// because the renamed identifier would be invisible to translators.
class CollisionError implements Exception {
  /// Creates the error for one [dartIdentifier] and its [colliding]
  /// sources.
  CollisionError(this.dartIdentifier, this.colliding);

  /// The Dart name every source mapped to.
  final String dartIdentifier;

  /// The FTL source descriptors that collided.
  final List<String> colliding;

  @override
  String toString() =>
      'CollisionError: FTL ids '
      '${colliding.map((s) => '`$s`').join(', ')} all sanitize to '
      'the Dart identifier `$dartIdentifier`. Rename one of the '
      'offending messages so each maps to a unique Dart name.';
}
