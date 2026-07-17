// Verify the asset-discovery glob matches every path shape the
// Builder promises to support, and rejects shapes outside that
// support.
//
// Specifically guards against the silent-fail mode where a glob
// like `**/<dir>/**/*.ftl` skips paths that have no segments
// preceding `<dir>`. The unit suite catches that class of glob
// regression here, before it reaches build_runner.

import 'package:fluent_gen/src/discovery/asset_glob.dart';
import 'package:test/test.dart';

void main() {
  group('ftlAssetGlob — matches the supported shapes', () {
    final glob = ftlAssetGlob('lib/i18n');

    test('per-file: lib/i18n/en.ftl', () {
      expect(glob.matches('lib/i18n/en.ftl'), isTrue);
    });

    test('per-file with hyphenated locale: lib/i18n/zh-Hans-CN.ftl', () {
      expect(glob.matches('lib/i18n/zh-Hans-CN.ftl'), isTrue);
    });

    test('per-directory: lib/i18n/en/messages.ftl', () {
      expect(glob.matches('lib/i18n/en/messages.ftl'), isTrue);
    });

    test('per-directory multi-file: lib/i18n/en/auth.ftl', () {
      expect(glob.matches('lib/i18n/en/auth.ftl'), isTrue);
    });

    test('deeply nested still matches: lib/i18n/en/auth/login.ftl', () {
      // The glob doesn't reject extra depth — locale_discovery's
      // pattern detector does that with a clear error. The glob
      // stays liberal so the discovery stage owns the cardinality
      // rule.
      expect(glob.matches('lib/i18n/en/auth/login.ftl'), isTrue);
    });
  });

  group('ftlAssetGlob — rejects shapes outside the configured dir', () {
    final glob = ftlAssetGlob('lib/i18n');

    test('outside the ftlDir entirely', () {
      expect(glob.matches('lib/other.ftl'), isFalse);
      expect(glob.matches('test/fixture.ftl'), isFalse);
    });

    test('different extension', () {
      expect(glob.matches('lib/i18n/en.json'), isFalse);
      expect(glob.matches('lib/i18n/en.txt'), isFalse);
    });

    test('similarly-named directory', () {
      // `lib/i18n_old/en.ftl` does NOT match `lib/i18n/...` because
      // the glob anchors on the literal `lib/i18n/` prefix.
      expect(glob.matches('lib/i18n_old/en.ftl'), isFalse);
    });
  });

  group('ftlAssetGlob — custom ftlDir', () {
    test('configurable directory still works', () {
      final glob = ftlAssetGlob('lib/strings');
      expect(glob.matches('lib/strings/en.ftl'), isTrue);
      expect(glob.matches('lib/strings/en/messages.ftl'), isTrue);
      expect(glob.matches('lib/i18n/en.ftl'), isFalse);
    });

    test('top-level directory works', () {
      final glob = ftlAssetGlob('translations');
      expect(glob.matches('translations/en.ftl'), isTrue);
      expect(glob.matches('translations/en/messages.ftl'), isTrue);
    });
  });
}
