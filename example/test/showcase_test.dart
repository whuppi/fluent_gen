// Runs the showcase (lib/main.dart) and pins its output — every claim in
// the tour stays proven. The \u2068/\u2069 escapes are the FSI/PDI
// bidi-isolation marks the bundle wraps substituted values in by default.

import 'package:fluent_gen_example/main.dart';
import 'package:test/test.dart';

void main() {
  late Map<String, String> lines;

  setUpAll(() {
    lines = {
      for (final line in runShowcase())
        line.substring(0, line.indexOf(': ')): line.substring(
          line.indexOf(': ') + 2,
        ),
    };
  });

  test('showcase covers every section with unique labels', () {
    expect(
      lines.keys,
      hasLength(runShowcase().length),
      reason: 'duplicate showcase labels would hide a pinned line',
    );
  });

  test('AppLocale — values, base, tryParse, negotiate, manifest', () {
    expect(lines['locale.values'], 'en,fr');
    expect(lines['locale.base'], 'en');
    expect(lines['locale.tryParse'], 'fr / null');
    expect(lines['locale.negotiate'], 'fr-CA→fr ja-JP→en');
    expect(lines['locale.manifest'], '13 accessors');
  });

  test('typed accessors — every inference shape renders', () {
    expect(lines['msg.plain'], 'Hi');
    expect(lines['msg.fr'], 'Salut');
    expect(lines['msg.pinned'], 'Hello, \u2068Aria\u2069!');
    expect(
      lines['msg.plural'],
      'You have \u2068one new message\u2069. / '
      'You have \u2068\u20685\u2069 new messages\u2069.',
    );
    expect(lines['msg.select'], 'Open the \u2068store\u2069.');
    expect(lines['msg.number'], 'Total: \u2068\$42.00\u2069');
    expect(lines['msg.datetime'], 'Launched at \u2068Jan 15, 2026\u2069');
    expect(lines['msg.unpinned'], 'Hi again, \u2068Aria\u2069');
    expect(
      lines['msg.reserved'],
      'Hi again, \u2068Aria\u2069 — last seen \u20681/15/2026\u2069',
    );
  });

  test('attributes and markup — per-attribute methods, span siblings', () {
    expect(lines['attr.value'], 'Sign in');
    expect(lines['attr.title'], 'Welcome back');
    expect(lines['attr.helper'], 'Tap to continue, \u2068Aria\u2069');
    expect(
      lines['markup.flat'],
      'Read <bold>\u2068Pro\u2069</bold> on our blog.',
    );
    expect(
      lines['markup.spans'],
      'text(Read) | bold(text(\u2068Pro\u2069)) | text(on our blog.)',
    );
  });

  test('errors — clean formatting records nothing', () {
    expect(lines['errors.clean'], 'Hello, \u2068Aria\u2069! (0 errors)');
  });

  test('missing message in a partial locale reports loud', () {
    expect(lines['fallback.missing'], 'device (1 error)');
  });
}
