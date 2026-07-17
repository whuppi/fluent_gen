// The generated AppLocale enum: parsing, negotiation, and (because
// this example builds with `bundle_ftl: true`) the embedded-source
// load() path end to end — a bundle that formats real messages with
// zero asset plumbing.

import 'package:fluent_gen_example/i18n/app_messages.g.dart';
import 'package:fluent_intl/fluent_intl.dart';
import 'package:test/test.dart';

void main() {
  group('AppLocale — parse + negotiate', () {
    test('one value per discovered locale, base marked', () {
      expect(AppLocale.values.map((l) => l.languageTag), ['en', 'fr']);
      expect(AppLocale.base, AppLocale.en);
    });

    test('tryParse is case-insensitive and null on unknown', () {
      expect(AppLocale.tryParse('FR'), AppLocale.fr);
      expect(AppLocale.tryParse('de'), isNull);
    });

    test('negotiate truncates subtags to a match', () {
      expect(AppLocale.negotiate('fr-CA'), AppLocale.fr);
      expect(AppLocale.negotiate('en-US-posix'), AppLocale.en);
    });

    test('negotiate falls back to base (or the override)', () {
      expect(AppLocale.negotiate('de'), AppLocale.en);
      expect(AppLocale.negotiate('de', fallback: AppLocale.fr), AppLocale.fr);
    });
  });

  group('AppLocale — bundled load()', () {
    test('load() yields a working bundle from embedded FTL', () {
      final t = AppMessages(AppLocale.fr.load(backend: IntlBackend()));
      expect(t.hello(), 'Salut');
    });

    test('placeables survived the embedding (no interpolation)', () {
      final t = AppMessages(AppLocale.en.load(backend: IntlBackend()));
      expect(t.welcome(name: 'Aria'), contains('Aria'));
      expect(t.items(count: 3), contains('3'));
    });

    test('negotiate + load composes into locale selection', () {
      final locale = AppLocale.negotiate('fr-CA');
      final t = AppMessages(locale.load(backend: IntlBackend()));
      expect(t.hello(), 'Salut');
    });
  });
}
