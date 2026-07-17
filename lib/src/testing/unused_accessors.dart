// Source-scan detection of generated accessors nothing references —
// the "dead translation" check, run inside the CONSUMER's own test
// suite (no CLI; `dart run build_runner watch` stays the only dev
// loop).
//
// The scan is a heuristic, the same one slang's analyze uses: an
// accessor counts as used when `.name` appears anywhere in the scanned
// Dart source outside the generated file itself. Dynamic dispatch or
// same-named members on unrelated classes can fool it in both
// directions — that's the documented trade for having the check at
// all (Dart has no unused-public-method diagnostic).

import 'dart:io';

/// Names from `accessorNames` (the generated manifest) that no Dart
/// file under [sourceRoot] references.
///
/// [generatedFilePath] is excluded from the scan — it DEFINES every
/// name. `*AsSpans` siblings are folded into their base accessor: a
/// message counts as used when either variant is referenced.
/// [excludePaths] skips additional trees (other generated output,
/// fixtures).
///
/// Typical consumer test:
///
/// ```dart
/// test('no dead translations', () {
///   expect(
///     unusedFluentAccessors(
///       accessorNames: Translations.accessorNames,
///       generatedFilePath: 'lib/i18n/translations.g.dart',
///     ),
///     isEmpty,
///   );
/// });
/// ```
Set<String> unusedFluentAccessors({
  required List<String> accessorNames,
  required String generatedFilePath,
  String sourceRoot = 'lib',
  List<String> excludePaths = const [],
}) {
  final generated = File(generatedFilePath).absolute.path;
  final excluded = [
    generated,
    for (final path in excludePaths)
      FileSystemEntity.isDirectorySync(path)
          ? Directory(path).absolute.path
          : File(path).absolute.path,
  ];

  final sources = StringBuffer();
  final root = Directory(sourceRoot);
  if (root.existsSync()) {
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final absolute = entity.absolute.path;
      if (excluded.any(absolute.startsWith)) continue;
      sources
        ..write(entity.readAsStringSync())
        ..write('\n');
    }
  }
  final haystack = sources.toString();

  final unused = <String>{};
  for (final name in accessorNames) {
    // Fold the AsSpans sibling into its base accessor.
    final base =
        name.endsWith('AsSpans')
            ? name.substring(0, name.length - 'AsSpans'.length)
            : name;
    if (unused.contains(base)) continue;

    final used =
        RegExp('\\.${RegExp.escape(base)}\\b').hasMatch(haystack) ||
        RegExp('\\.${RegExp.escape(base)}AsSpans\\b').hasMatch(haystack);
    if (!used) unused.add(base);
  }
  return unused;
}
