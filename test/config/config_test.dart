// Tests for Config.fromMap — the BuilderOptions parsing layer.
//
// Required-key, type-mismatch, and validation paths are all
// exercised. These tests double as the documentation for what
// shapes the consumer's build.yaml may legally take.

import 'package:fluent_gen/src/config/config.dart';
import 'package:test/test.dart';

void main() {
  group('Config.fromMap — happy path', () {
    test('reads every supplied key', () {
      final config = Config.fromMap({
        'base_locale': 'en',
        'ftl_dir': 'lib/strings',
        'output_path': 'lib/gen/messages.g.dart',
        'class_name': 'AppMessages',
        'warn_on_missing_messages': false,
        'warn_on_orphan_messages': false,
      });

      expect(config.baseLocale, 'en');
      expect(config.ftlDir, 'lib/strings');
      expect(config.outputPath, 'lib/gen/messages.g.dart');
      expect(config.className, 'AppMessages');
      expect(config.warnOnMissingMessages, isFalse);
      expect(config.warnOnOrphanMessages, isFalse);
    });

    test('applies every documented default when only base_locale is set', () {
      final config = Config.fromMap({'base_locale': 'fr'});

      expect(config.baseLocale, 'fr');
      expect(config.ftlDir, 'lib/i18n');
      expect(config.outputPath, 'lib/i18n/translations.g.dart');
      expect(config.className, 'Translations');
      expect(config.warnOnMissingMessages, isTrue);
      expect(config.warnOnOrphanMessages, isTrue);
    });

    test('output_path defaults derive from ftl_dir', () {
      final config = Config.fromMap({
        'base_locale': 'en',
        'ftl_dir': 'lib/locale',
      });
      // When the consumer overrides ftl_dir but not output_path, the
      // generated file lives next to the FTL files by default. Less
      // surprising than a hardcoded `lib/i18n/`.
      expect(config.outputPath, 'lib/locale/translations.g.dart');
    });
  });

  group('Config.fromMap — required keys', () {
    test('missing base_locale throws with named-key error', () {
      expect(
        () => Config.fromMap({}),
        throwsA(
          isA<ConfigError>().having(
            (e) => e.message,
            'message',
            contains('base_locale'),
          ),
        ),
      );
    });

    test('empty base_locale rejected', () {
      expect(
        () => Config.fromMap({'base_locale': ''}),
        throwsA(isA<ConfigError>()),
      );
    });
  });

  group('Config.fromMap — type validation', () {
    test('non-string base_locale throws', () {
      expect(
        () => Config.fromMap({'base_locale': 42}),
        throwsA(
          isA<ConfigError>().having(
            (e) => e.message,
            'message',
            contains('must be a string'),
          ),
        ),
      );
    });

    test('non-bool warn_on_missing_messages throws', () {
      expect(
        () => Config.fromMap({
          'base_locale': 'en',
          'warn_on_missing_messages': 'yes',
        }),
        throwsA(
          isA<ConfigError>().having(
            (e) => e.message,
            'message',
            contains('must be a bool'),
          ),
        ),
      );
    });
  });

  group('Config.fromMap — locale enum + bundling options', () {
    test('defaults: AppLocale, bundling off', () {
      final config = Config.fromMap({'base_locale': 'en'});
      expect(config.localeEnumName, 'AppLocale');
      expect(config.bundleFtl, isFalse);
    });

    test('overrides parse', () {
      final config = Config.fromMap({
        'base_locale': 'en',
        'locale_enum_name': 'Lingo',
        'bundle_ftl': true,
      });
      expect(config.localeEnumName, 'Lingo');
      expect(config.bundleFtl, isTrue);
    });

    test('lowercase locale_enum_name rejected, key named', () {
      expect(
        () => Config.fromMap({
          'base_locale': 'en',
          'locale_enum_name': 'appLocale',
        }),
        throwsA(
          isA<ConfigError>().having(
            (e) => e.message,
            'message',
            contains('locale_enum_name'),
          ),
        ),
      );
    });

    test('enum name colliding with class_name rejected', () {
      expect(
        () => Config.fromMap({
          'base_locale': 'en',
          'class_name': 'Messages',
          'locale_enum_name': 'Messages',
        }),
        throwsA(isA<ConfigError>()),
      );
    });
  });

  group('Config.fromMap — class_name validation', () {
    test('lowercase class_name rejected', () {
      expect(
        () =>
            Config.fromMap({'base_locale': 'en', 'class_name': 'translations'}),
        throwsA(
          isA<ConfigError>().having(
            (e) => e.message,
            'message',
            contains('class_name'),
          ),
        ),
      );
    });

    test('class_name with spaces rejected', () {
      expect(
        () => Config.fromMap({
          'base_locale': 'en',
          'class_name': 'My Translations',
        }),
        throwsA(isA<ConfigError>()),
      );
    });

    test('class_name with underscores accepted', () {
      // PascalCase with underscores is unusual but a valid Dart
      // identifier. Don't enforce style beyond Dart's grammar.
      final config = Config.fromMap({
        'base_locale': 'en',
        'class_name': 'My_Translations',
      });
      expect(config.className, 'My_Translations');
    });
  });

  group('Config.fromMap — base_locale validation', () {
    test('locale with hyphen accepted (BCP47 style)', () {
      final config = Config.fromMap({'base_locale': 'en-US'});
      expect(config.baseLocale, 'en-US');
    });

    test('locale with extension accepted', () {
      final config = Config.fromMap({'base_locale': 'zh-Hans-CN'});
      expect(config.baseLocale, 'zh-Hans-CN');
    });

    test('locale with leading digit rejected', () {
      expect(
        () => Config.fromMap({'base_locale': '1en'}),
        throwsA(isA<ConfigError>()),
      );
    });

    test('locale with whitespace rejected', () {
      expect(
        () => Config.fromMap({'base_locale': 'en US'}),
        throwsA(isA<ConfigError>()),
      );
    });
  });
}
