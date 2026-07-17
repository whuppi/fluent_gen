// Tests for non-base-locale validation warnings.

import 'package:fluent_gen/src/inspection/ftl_inspector.dart';
import 'package:fluent_gen/src/validation/locale_validator.dart';
import 'package:test/test.dart';

InspectedFile parse({
  required String locale,
  required String content,
  String? path,
}) => inspectFtl(
  path: path ?? 'lib/i18n/$locale.ftl',
  locale: locale,
  content: content,
);

List<LocaleWarning> validate({
  required InspectedFile base,
  required InspectedFile other,
}) => validateNonBaseLocales(
  baseFiles: [base],
  nonBaseFiles: [other],
  warnOnMissingMessages: true,
  warnOnOrphanMessages: true,
  warnOnArgMismatch: true,
);

void main() {
  group('validateNonBaseLocales — happy path', () {
    test('identical locales produce no warnings', () {
      final base = parse(
        locale: 'en',
        content: '''
hello = Hi
welcome = Hi, { \$name }!
''',
      );
      final fr = parse(
        locale: 'fr',
        content: '''
hello = Salut
welcome = Salut, { \$name } !
''',
      );
      final warnings = validate(base: base, other: fr);
      expect(warnings, isEmpty);
    });
  });

  group('validateNonBaseLocales — missing messages', () {
    test('reports message present in base but absent in other', () {
      final base = parse(
        locale: 'en',
        content: '''
hello = Hi
welcome = Welcome
''',
      );
      final fr = parse(locale: 'fr', content: 'hello = Salut\n');
      final warnings = validate(base: base, other: fr);

      final missing = warnings.whereType<MissingMessageWarning>().toList();
      expect(missing, hasLength(1));
      expect(missing.single.messageId, 'welcome');
      expect(missing.single.locale, 'fr');
    });

    test('warning is suppressed when flag is false', () {
      final base = parse(
        locale: 'en',
        content: '''
hello = Hi
welcome = Welcome
''',
      );
      final fr = parse(locale: 'fr', content: 'hello = Salut\n');
      final warnings = validateNonBaseLocales(
        baseFiles: [base],
        nonBaseFiles: [fr],
        warnOnMissingMessages: false,
        warnOnOrphanMessages: true,
        warnOnArgMismatch: true,
      );
      expect(warnings.whereType<MissingMessageWarning>(), isEmpty);
    });
  });

  group('validateNonBaseLocales — orphan messages', () {
    test('reports message present in other but absent in base', () {
      final base = parse(locale: 'en', content: 'hello = Hi\n');
      final fr = parse(
        locale: 'fr',
        content: '''
hello = Salut
bonjour = Bonjour
''',
      );
      final warnings = validate(base: base, other: fr);

      final orphans = warnings.whereType<OrphanMessageWarning>().toList();
      expect(orphans, hasLength(1));
      expect(orphans.single.messageId, 'bonjour');
    });

    test('warning is suppressed when flag is false', () {
      final base = parse(locale: 'en', content: 'hello = Hi\n');
      final fr = parse(
        locale: 'fr',
        content: '''
hello = Salut
bonjour = Bonjour
''',
      );
      final warnings = validateNonBaseLocales(
        baseFiles: [base],
        nonBaseFiles: [fr],
        warnOnMissingMessages: true,
        warnOnOrphanMessages: false,
        warnOnArgMismatch: true,
      );
      expect(warnings.whereType<OrphanMessageWarning>(), isEmpty);
    });
  });

  group('validateNonBaseLocales — argument mismatches', () {
    test('reports extra args in non-base', () {
      final base = parse(
        locale: 'en',
        content:
            r'greet = Hi, { $name }!'
            '\n',
      );
      final fr = parse(
        locale: 'fr',
        content:
            r'greet = Bonjour, { $prenom } { $nom }!'
            '\n',
      );
      final warnings = validate(base: base, other: fr);

      final mismatches = warnings.whereType<ArgMismatchWarning>().toList();
      expect(mismatches, hasLength(1));
      expect(mismatches.single.messageId, 'greet');
      expect(mismatches.single.extraInLocale, {'prenom', 'nom'});
      expect(mismatches.single.missingInLocale, {'name'});
    });

    test('reports missing arg even when extra args are absent', () {
      final base = parse(
        locale: 'en',
        content:
            r'greet = Hi, { $name }! at { DATETIME($d) }'
            '\n',
      );
      final fr = parse(
        locale: 'fr',
        content:
            r'greet = Bonjour, { $name } !'
            '\n',
      );
      final warnings = validate(base: base, other: fr);

      final mismatches = warnings.whereType<ArgMismatchWarning>().toList();
      expect(mismatches, hasLength(1));
      expect(mismatches.single.missingInLocale, {'d'});
      expect(mismatches.single.extraInLocale, isEmpty);
    });

    test('orphan-message warning excludes mismatch-warning for same id', () {
      // A message that's an orphan can't also be a mismatch — there's
      // nothing to compare against. Both checks see it but only the
      // orphan warning is emitted.
      final base = parse(locale: 'en', content: 'hello = Hi\n');
      final fr = parse(
        locale: 'fr',
        content:
            r'extra = Foo { $x }'
            '\n',
      );
      final warnings = validate(base: base, other: fr);
      expect(warnings.whereType<OrphanMessageWarning>(), hasLength(1));
      // The validator skips arg-mismatch when there's no base entry.
      expect(warnings.whereType<ArgMismatchWarning>(), isEmpty);
    });
  });

  group('validateNonBaseLocales — multi-file per locale', () {
    test('warnings span every file in a locale', () {
      final base = parse(
        locale: 'en',
        content: '''
hello = Hi
welcome = Welcome
goodbye = Bye
''',
      );
      final fr1 = parse(
        locale: 'fr',
        content: 'hello = Salut\n',
        path: 'lib/i18n/fr/auth.ftl',
      );
      final fr2 = parse(
        locale: 'fr',
        content: 'welcome = Bienvenue\n',
        path: 'lib/i18n/fr/profile.ftl',
      );
      final warnings = validateNonBaseLocales(
        baseFiles: [base],
        nonBaseFiles: [fr1, fr2],
        warnOnMissingMessages: true,
        warnOnOrphanMessages: true,
        warnOnArgMismatch: true,
      );

      // `goodbye` is missing from `fr` — reported once.
      expect(warnings.whereType<MissingMessageWarning>(), hasLength(1));
      expect(
        warnings.whereType<MissingMessageWarning>().single.messageId,
        'goodbye',
      );
    });
  });

  group('LocaleWarning.formatted', () {
    test('missing-message message is human-readable', () {
      const warn = MissingMessageWarning(
        locale: 'fr',
        path: 'lib/i18n/fr.ftl',
        messageId: 'welcome',
      );
      final out = warn.formatted();
      expect(out, contains('fluent_gen'));
      expect(out, contains('fr'));
      expect(out, contains('welcome'));
    });

    test('arg-mismatch message lists both extra and missing', () {
      final warn = ArgMismatchWarning(
        locale: 'fr',
        path: 'lib/i18n/fr.ftl',
        messageId: 'greet',
        baseArgs: {'name'},
        localeArgs: {'prenom', 'nom'},
      );
      final out = warn.formatted();
      expect(out, contains('extra args'));
      expect(out, contains('missing args'));
      expect(out, contains('prenom'));
      expect(out, contains('name'));
    });
  });
}
