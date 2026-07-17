/// Test-time helpers for packages that consume fluent_gen's output.
///
/// One check today: `unusedFluentAccessors` — feed it the generated
/// class's `accessorNames` manifest and it reports every accessor the
/// scanned source never references, so dead translations fail a test
/// instead of quietly accumulating:
///
/// ```dart
/// import 'package:fluent_gen/testing.dart';
///
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
///
/// The scan is a source-text heuristic (dynamic dispatch escapes it) —
/// see `unusedFluentAccessors` for the exact rules.
library;

export 'package:fluent_gen/src/testing/unused_accessors.dart'
    show unusedFluentAccessors;
