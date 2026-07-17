// Regenerate the .expected.dart files for golden_test.dart.
//
// Run after intentionally changing the emitter's output:
//
//   dart run test/emission/_generate_goldens.dart
//
// Then `git diff` the .expected.dart files and review the changes
// before committing. NEVER blindly accept — every change is a
// behavior change for every consumer of the generator.
//
// This file is a tool, not a test. It's not in test/.../*_test.dart
// so the test runner skips it.

import 'dart:io';

import 'package:fluent_gen/src/emission/emitter.dart';
import 'package:fluent_gen/src/inspection/ftl_inspector.dart';
import 'package:path/path.dart' as p;

void main() {
  final goldenDir = Directory(
    p.join(Directory.current.path, 'test/emission/golden'),
  );
  if (!goldenDir.existsSync()) {
    stderr.writeln('Golden directory not found: ${goldenDir.path}');
    exit(1);
  }

  for (final ftlFile in goldenDir.listSync().whereType<File>().where(
    (f) => f.path.endsWith('.ftl'),
  )) {
    final stem = p.basenameWithoutExtension(ftlFile.path);
    final inspected = inspectFtl(
      path: 'lib/i18n/en.ftl',
      locale: 'en',
      content: ftlFile.readAsStringSync(),
    );
    final dart =
        emitFile(
          baseLocaleFiles: [inspected],
          className: 'Translations',
        ).source;

    final expectedFile = File(p.join(goldenDir.path, '$stem.expected.dart'));
    expectedFile.writeAsStringSync(dart);
    stdout.writeln('wrote ${expectedFile.path} (${dart.length} bytes)');
  }
}
