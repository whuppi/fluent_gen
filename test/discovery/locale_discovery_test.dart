// Tests for the per-file vs per-directory locale-discovery walker.
//
// The walker takes (path, content) tuples — never touches the
// filesystem — so these tests are pure unit tests with no fixture
// directory required.

import 'package:fluent_gen/src/discovery/locale_discovery.dart';
import 'package:test/test.dart';

({String path, String content}) asset(String path, [String content = '']) => (
  path: path,
  content: content,
);

void main() {
  group('discoverLocales — per-file pattern', () {
    test('extracts locale from filename stem', () {
      final result = discoverLocales(
        ftlDir: 'lib/i18n',
        assets: [asset('lib/i18n/en.ftl'), asset('lib/i18n/fr.ftl')],
      );
      expect(result.pattern, LocaleNamingPattern.perFile);
      expect(result.locales, {'en', 'fr'});
      expect(result.filesFor('en'), hasLength(1));
      expect(result.filesFor('en').single.path, 'lib/i18n/en.ftl');
    });

    test('handles BCP47-style locale tags', () {
      final result = discoverLocales(
        ftlDir: 'lib/i18n',
        assets: [asset('lib/i18n/en-US.ftl'), asset('lib/i18n/zh-Hans-CN.ftl')],
      );
      expect(result.pattern, LocaleNamingPattern.perFile);
      expect(result.locales, {'en-US', 'zh-Hans-CN'});
    });
  });

  group('discoverLocales — per-directory pattern', () {
    test('extracts locale from parent directory', () {
      final result = discoverLocales(
        ftlDir: 'lib/i18n',
        assets: [
          asset('lib/i18n/en/messages.ftl'),
          asset('lib/i18n/fr/messages.ftl'),
        ],
      );
      expect(result.pattern, LocaleNamingPattern.perDirectory);
      expect(result.locales, {'en', 'fr'});
    });

    test('multiple files per locale', () {
      // A consumer can split their messages across files within a
      // per-directory layout (`en/auth.ftl`, `en/profile.ftl`). All
      // those files contribute to the `en` locale.
      final result = discoverLocales(
        ftlDir: 'lib/i18n',
        assets: [
          asset('lib/i18n/en/auth.ftl'),
          asset('lib/i18n/en/profile.ftl'),
          asset('lib/i18n/fr/auth.ftl'),
        ],
      );
      expect(result.locales, {'en', 'fr'});
      expect(result.filesFor('en'), hasLength(2));
    });
  });

  group('discoverLocales — empty input', () {
    test('returns empty result, not error', () {
      final result = discoverLocales(ftlDir: 'lib/i18n', assets: const []);
      expect(result.pattern, LocaleNamingPattern.empty);
      expect(result.files, isEmpty);
    });
  });

  group('discoverLocales — error paths', () {
    test('mixing per-file + per-directory patterns errors', () {
      expect(
        () => discoverLocales(
          ftlDir: 'lib/i18n',
          assets: [asset('lib/i18n/en.ftl'), asset('lib/i18n/fr/messages.ftl')],
        ),
        throwsA(
          isA<LocaleDiscoveryError>().having(
            (e) => e.message,
            'message',
            contains('Mixed locale-file patterns'),
          ),
        ),
      );
    });

    test('non-locale filename rejected', () {
      // `messages.ftl` (no locale) at the top level isn't valid for
      // either pattern. Surface the path so the consumer can fix it.
      expect(
        () => discoverLocales(
          ftlDir: 'lib/i18n',
          assets: [asset('lib/i18n/messages.ftl')],
        ),
        throwsA(
          isA<LocaleDiscoveryError>().having(
            (e) => e.message,
            'message',
            contains('Could not extract a locale'),
          ),
        ),
      );
    });

    test('three-deep directory structure rejected', () {
      // Only `<ftlDir>/<locale>.ftl` and
      // `<ftlDir>/<locale>/<file>.ftl` are supported. Deeper paths
      // are ambiguous about which directory holds the locale.
      expect(
        () => discoverLocales(
          ftlDir: 'lib/i18n',
          assets: [asset('lib/i18n/en/auth/login.ftl')],
        ),
        throwsA(isA<LocaleDiscoveryError>()),
      );
    });
  });

  group('discoverLocales — content pass-through', () {
    test('content is preserved on every discovered file', () {
      final result = discoverLocales(
        ftlDir: 'lib/i18n',
        assets: [
          asset('lib/i18n/en.ftl', 'hello = Hi\n'),
          asset('lib/i18n/fr.ftl', 'hello = Salut\n'),
        ],
      );
      expect(result.filesFor('en').single.content, 'hello = Hi\n');
      expect(result.filesFor('fr').single.content, 'hello = Salut\n');
    });
  });
}
