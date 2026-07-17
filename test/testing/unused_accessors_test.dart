// The unused-accessor scan against a synthetic consumer package laid
// out in a temp directory: used names, unused names, AsSpans folding,
// generated-file exclusion, and extra excludes.

import 'dart:io';

import 'package:fluent_gen/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fluent_gen_unused_');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  File write(String relative, String content) =>
      File(p.join(tmp.path, relative))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);

  test('referenced accessors are not reported', () {
    write('lib/app.dart', '''
void main() {
  print(t.hello());
  print(t.welcome(name: 'x'));
}
''');
    final generated = write('lib/i18n/translations.g.dart', '''
class Translations {
  String hello() => '';
  String welcome() => '';
  String goodbye() => '';
}
''');

    final unused = unusedFluentAccessors(
      accessorNames: const ['hello', 'welcome', 'goodbye'],
      generatedFilePath: generated.path,
      sourceRoot: p.join(tmp.path, 'lib'),
    );
    expect(unused, {'goodbye'});
  });

  test('the generated file itself never counts as a usage', () {
    final generated = write('lib/i18n/translations.g.dart', '''
class Translations {
  // The definition mentions t.orphan in a comment and the body — must
  // not count.
  String orphan() => _bundle.formatMessage('orphan');
}
''');
    write('lib/app.dart', 'void main() {}');

    final unused = unusedFluentAccessors(
      accessorNames: const ['orphan'],
      generatedFilePath: generated.path,
      sourceRoot: p.join(tmp.path, 'lib'),
    );
    expect(unused, {'orphan'});
  });

  test('an AsSpans reference marks the base accessor used', () {
    write('lib/app.dart', '''
void main() {
  render(t.bannerAsSpans(title: 'x'));
}
''');
    final generated = write('lib/i18n/translations.g.dart', '');

    final unused = unusedFluentAccessors(
      accessorNames: const ['banner', 'bannerAsSpans'],
      generatedFilePath: generated.path,
      sourceRoot: p.join(tmp.path, 'lib'),
    );
    expect(unused, isEmpty);
  });

  test(r'attribute accessors ($-separated) are matched literally', () {
    write('lib/app.dart', r'''
void main() {
  print(t.login$title());
}
''');
    final generated = write('lib/i18n/translations.g.dart', '');

    final unused = unusedFluentAccessors(
      accessorNames: const [r'login$title', r'login$helper'],
      generatedFilePath: generated.path,
      sourceRoot: p.join(tmp.path, 'lib'),
    );
    expect(unused, {r'login$helper'});
  });

  test('excludePaths trees are skipped', () {
    write('lib/fixtures/sample.dart', 'final x = t.hello();');
    final generated = write('lib/i18n/translations.g.dart', '');

    final unused = unusedFluentAccessors(
      accessorNames: const ['hello'],
      generatedFilePath: generated.path,
      sourceRoot: p.join(tmp.path, 'lib'),
      excludePaths: [p.join(tmp.path, 'lib/fixtures')],
    );
    expect(unused, {'hello'});
  });

  test('a name that is a prefix of another does not false-match', () {
    write('lib/app.dart', 'final x = t.helloWorld();');
    final generated = write('lib/i18n/translations.g.dart', '');

    final unused = unusedFluentAccessors(
      accessorNames: const ['hello', 'helloWorld'],
      generatedFilePath: generated.path,
      sourceRoot: p.join(tmp.path, 'lib'),
    );
    expect(unused, {'hello'});
  });
}
