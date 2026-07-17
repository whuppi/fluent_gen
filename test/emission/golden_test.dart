// Golden-file tests on the emitter.
//
// For every `.ftl` fixture in test/emission/golden/, compare the
// emitter's output byte-for-byte against the matching
// `.expected.dart`. Catches:
//
//   * formatter drift (dart_style upgrades that change spacing)
//   * doc-comment drift (emitter assembly that changes whitespace)
//   * order drift (method emission order changes)
//   * any silent change in the generated shape
//
// On failure AFTER an intentional emitter change:
//
//   1. Run `dart run test/emission/_generate_goldens.dart`.
//   2. `git diff` the .expected.dart files.
//   3. Read EVERY change. A single unintended diff is a bug.
//   4. Commit the regenerated goldens together with the emitter
//      change so the diff is auditable in a single PR.

import 'dart:io';

import 'package:fluent_gen/src/emission/emitter.dart';
import 'package:fluent_gen/src/inspection/ftl_inspector.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // The test runner sets cwd to the package root; build paths
  // relative to that so the test can run from any IDE / CI shell.
  final goldenDir = Directory(
    p.join(Directory.current.path, 'test/emission/golden'),
  );

  if (!goldenDir.existsSync()) {
    fail(
      'Golden directory not found at ${goldenDir.path}. '
      'The `test/emission/golden/` directory ships with the package '
      '— if it is missing, the working copy is corrupt.',
    );
  }

  final ftlFiles =
      goldenDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.ftl'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (ftlFiles.isEmpty) {
    fail(
      'No .ftl fixtures found in ${goldenDir.path}. Add at least '
      'one input + matching .expected.dart pair.',
    );
  }

  for (final ftlFile in ftlFiles) {
    final stem = p.basenameWithoutExtension(ftlFile.path);
    final expectedFile = File(p.join(goldenDir.path, '$stem.expected.dart'));

    test('golden: $stem', () {
      if (!expectedFile.existsSync()) {
        fail(
          'No expected file at ${expectedFile.path}. Run '
          '`dart run test/emission/_generate_goldens.dart` to '
          'create it, then audit the result before committing.',
        );
      }

      final inspected = inspectFtl(
        path: 'lib/i18n/en.ftl',
        locale: 'en',
        content: ftlFile.readAsStringSync(),
      );
      final actual =
          emitFile(
            baseLocaleFiles: [inspected],
            className: 'Translations',
          ).source;
      final expected = expectedFile.readAsStringSync();

      // Use `equals` against the literal string so the failure
      // message shows the diff in test output. `expect` truncates
      // long strings — that's fine for a quick diff; for a full
      // diff, run `git diff` after regenerating.
      expect(
        actual,
        expected,
        reason:
            'Emitter output for $stem differs from the golden. '
            'If the change was intentional, regenerate the golden '
            'and audit the diff. If unintentional, investigate '
            'before re-running.',
      );
    });
  }
}
