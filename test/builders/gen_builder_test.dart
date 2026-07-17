// Drive FluentGenBuilder end to end through build_test's testBuilder:
// the ok path, the two placeholder-only paths (no FTL, missing base
// locale), the base-junk build failure, and warning surfacing. The
// example package covers the REAL build_runner integration; this suite
// covers the builder's own decision points in isolation.

import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:fluent_gen/src/builders/gen_builder.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

FluentGenBuilder builder({String baseLocale = 'en', bool bundleFtl = false}) =>
    FluentGenBuilder.fromOptions(
      BuilderOptions({'base_locale': baseLocale, 'bundle_ftl': bundleFtl}),
    );

/// Run the builder over [assets] and return (payload, log records).
Future<(Map<String, Object?>, List<LogRecord>)> run(
  Map<String, String> assets, {
  String baseLocale = 'en',
  bool bundleFtl = false,
}) async {
  final logs = <LogRecord>[];
  final result = await testBuilder(
    builder(baseLocale: baseLocale, bundleFtl: bundleFtl),
    {for (final entry in assets.entries) 'pkg|${entry.key}': entry.value},
    rootPackage: 'pkg',
    onLog: logs.add,
  );
  // The temp payload is a build-cache output — it physically lands
  // under `.dart_tool/build/generated/…`. Read whichever asset ends
  // in the temp filename.
  final reader = result.readerWriter;
  final tempId = reader.testing.assets.firstWhere(
    (id) => id.path.endsWith('_fluent_gen_temp.json'),
    orElse: () => AssetId('pkg', '__none__'),
  );
  final payload =
      await reader.canRead(tempId)
          ? jsonDecode(utf8.decode(await reader.readAsBytes(tempId)))
              as Map<String, Object?>
          : <String, Object?>{};
  return (payload, logs);
}

void main() {
  group('FluentGenBuilder — ok path', () {
    test('emits the payload with the generated source', () async {
      final (payload, logs) = await run({
        'lib/i18n/en.ftl': 'hello = Hi { \$name }\n',
      });
      final meta = payload['fluent_gen']! as Map<String, Object?>;
      expect(meta['status'], 'ok');
      final outputs = payload['outputs']! as Map<String, Object?>;
      final source = outputs['lib/i18n/translations.g.dart']! as String;
      expect(source, contains('class Translations'));
      expect(source, contains('String hello({required Object? name'));
      expect(logs.where((l) => l.level >= Level.WARNING), isEmpty);
    });

    test('inference notes surface as build warnings', () async {
      final (_, logs) = await run({
        'lib/i18n/en.ftl': 'greet = Hi { -brand(\$x) }\n',
      });
      expect(
        logs.map((l) => l.message),
        anyElement(contains('positional argument to term `-brand`')),
      );
    });

    test('the locale enum spans every discovered locale', () async {
      final (payload, _) = await run({
        'lib/i18n/en.ftl': 'hello = Hi\n',
        'lib/i18n/fr.ftl': 'hello = Salut\n',
      });
      final outputs = payload['outputs']! as Map<String, Object?>;
      final source = outputs.values.single! as String;
      expect(source, contains("en('en')"));
      expect(source, contains("fr('fr')"));
    });

    test('bundle_ftl embeds sources and emits load()', () async {
      final (payload, _) = await run({
        'lib/i18n/en.ftl': 'hello = Hi\n',
      }, bundleFtl: true);
      final outputs = payload['outputs']! as Map<String, Object?>;
      final source = outputs.values.single! as String;
      expect(source, contains('List<String> get ftlSources'));
      expect(source, contains('hello = Hi'));
      expect(source, contains('FluentBundle load({'));
    });

    test('non-base locale drift surfaces as warnings', () async {
      final (payload, logs) = await run({
        'lib/i18n/en.ftl': 'hello = Hi\nbye = Bye\n',
        'lib/i18n/fr.ftl': 'hello = Salut\n',
      });
      final meta = payload['fluent_gen']! as Map<String, Object?>;
      expect(meta['status'], 'ok');
      expect(
        logs.map((l) => l.message),
        anyElement(contains('missing message `bye`')),
      );
    });
  });

  group('FluentGenBuilder — placeholder-only paths', () {
    test('no .ftl files → empty outputs, status recorded', () async {
      final (payload, _) = await run({});
      final meta = payload['fluent_gen']! as Map<String, Object?>;
      expect(meta['status'], 'no-ftl-files');
      expect(payload['outputs'], isEmpty);
    });

    test('base locale missing → empty outputs, severe log', () async {
      final (payload, logs) = await run({
        'lib/i18n/fr.ftl': 'hello = Salut\n',
      }, baseLocale: 'en');
      final meta = payload['fluent_gen']! as Map<String, Object?>;
      expect(meta['status'], 'base-locale-missing');
      expect(payload['outputs'], isEmpty);
      expect(
        logs.where((l) => l.level >= Level.SEVERE).map((l) => l.message),
        anyElement(contains('base_locale `en` has no matching')),
      );
    });
  });

  group('FluentGenBuilder — junk severity', () {
    test('junk in the BASE locale fails the build', () async {
      // build_runner catches a builder throw and surfaces it as a
      // SEVERE log with no output written — that IS a failed build.
      final (payload, logs) = await run({
        'lib/i18n/en.ftl': 'hello = Hi\n= broken junk line\n',
      });
      expect(payload, isEmpty);
      expect(
        logs.where((l) => l.level >= Level.SEVERE).map((l) => l.message),
        anyElement(contains('base locale `en`')),
      );
    });

    test('junk in a NON-base locale only warns', () async {
      final (payload, logs) = await run({
        'lib/i18n/en.ftl': 'hello = Hi\n',
        'lib/i18n/fr.ftl': 'hello = Salut\n= broken junk line\n',
      });
      final meta = payload['fluent_gen']! as Map<String, Object?>;
      expect(meta['status'], 'ok');
      expect(logs.map((l) => l.message), anyElement(contains('parse-junk')));
    });
  });
}
