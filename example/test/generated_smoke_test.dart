// End-to-end test that exercises the generated AppMessages.
//
// This test only passes when build_runner has produced
// `lib/i18n/app_messages.g.dart`. The CI invocation in the
// definition-of-done runs build_runner first, then this test.
//
// What it proves:
//   - The generated file compiles (the import below would fail
//     otherwise).
//   - Method names match what we expect from sanitization rules.
//   - Required-named-arg signatures match what inference picked.
//   - Round-trip behavior matches the underlying bundle's
//     formatMessage output for plain + plural messages.
//   - The AsSpans sibling returns a non-empty span tree.

import 'package:fluent_bundle/markup.dart';
import 'package:fluent_intl/fluent_intl.dart';
import 'package:fluent_gen_example/i18n/app_messages.g.dart';
import 'package:test/test.dart';

FluentBundle _bundle() {
  // Use `en-US` (not bare `en`) so package:intl's currency formatter
  // knows to render the `$` prefix. NUMBER / DATETIME builtins are
  // registered automatically; IntlBackend supplies the CLDR data.
  return FluentBundle('en-US', backend: IntlBackend())..addResource(r'''
hello = Hi
# $name (String) - the person to greet.
welcome = Hello, { $name }!
items = You have { $count ->
    [one] one new message
   *[other] { $count } new messages
}.
device = Open the { $platform ->
    [ios] App Store
    [android] Play Store
   *[other] store
}.
price = Total: { NUMBER($amount, style: "currency", currency: "USD") }
launchedAt = Launched at { DATETIME($d, dateStyle: "medium") }
banner = Read <bold>{ $title }</bold> on our blog.
greeting = Hi again, { $name }
welcomeBack = { greeting } — last seen { DATETIME($when, dateStyle: "short") }
login = Sign in
    .title = Welcome back
    .helper = Tap to continue, { $name }

''');
}

void main() {
  late AppMessages t;
  setUp(() {
    t = AppMessages(_bundle());
  });

  group('generated AppMessages — basic shape', () {
    test('hello returns the expected string', () {
      expect(t.hello(), 'Hi');
    });

    test('welcome accepts a required String name (via a comment pin)', () {
      // The `# $name (String)` annotation narrowed the parameter from
      // Object? to String — this call only compiles because of it.
      final String name = 'Aria';
      expect(
        t.welcome(name: name),
        // Bidi marks (FSI/PDI) wrap the interpolated value.
        'Hello, \u{2068}Aria\u{2069}!',
      );
    });

    test('device string-selector takes a String (not num)', () {
      expect(t.device(platform: 'ios'), contains('App Store'));
      expect(t.device(platform: 'android'), contains('Play Store'));
      expect(t.device(platform: 'web'), contains('store'));
    });

    test('items applies plural rules via the typed num arg', () {
      // The bidi-isolation marks (FSI/PDI) wrap the variant arm
      // because the surrounding pattern has multiple elements.
      // The visible text is what matters for these assertions.
      expect(t.items(count: 1), contains('one new message'));
      expect(t.items(count: 5), contains('5'));
      expect(t.items(count: 5), contains('new messages'));
    });

    test('price runs NUMBER with the supplied currency style', () {
      // The exact currency-symbol output depends on package:intl
      // locale data being initialized. Just verify the number was
      // interpolated and the surrounding text is present.
      final out = t.price(amount: 9.99);
      expect(out, contains('Total:'));
      expect(out, contains('9.99'));
    });

    test('launchedAt runs DATETIME', () {
      final d = DateTime(2026, 4, 29);
      final out = t.launchedAt(d: d);
      expect(out, contains('2026'));
    });
  });

  group('generated AppMessages — transitive references', () {
    test('greeting stands alone too', () {
      expect(t.greeting(name: 'Aria'), contains('Aria'));
    });

    test('welcomeBack demands both its own AND the referenced vars', () {
      // welcomeBack references `greeting` (which uses $name) and adds
      // $when — so the generated method takes both. It only compiles
      // if the transitive inference pulled $name through the ref.
      // `when` is a Dart reserved word — the generated parameter is
      // escaped to `$when`, the args-map key stays `'when'`.
      final out = t.welcomeBack(name: 'Aria', $when: DateTime(2026, 4, 29));
      expect(out, contains('Aria'));
      expect(out, contains('2026'));
    });
  });

  group('generated AppMessages — markup', () {
    test('banner returns the resolved string with literal tags', () {
      // The plain-string variant returns the raw resolved text,
      // markup tags and all. Consumers who want to render markup
      // call the AsSpans sibling instead.
      final out = t.banner(title: 'Spec Compliance');
      expect(out, contains('<bold>'));
      expect(out, contains('</bold>'));
      expect(out, contains('Spec Compliance'));
    });

    test('bannerAsSpans returns a span tree', () {
      final spans = t.bannerAsSpans(title: 'Spec Compliance');
      expect(spans, isNotEmpty);
      // The tree contains at least one markup span tagged "bold".
      final hasBold = spans.any(
        (s) => s is FluentMarkupSpan && s.tag == 'bold',
      );
      expect(hasBold, isTrue);
    });
  });

  group('generated AppMessages — attributes', () {
    test('login returns the body value', () {
      expect(t.login(), 'Sign in');
    });

    test(r'login$title returns the title attribute', () {
      expect(t.login$title(), 'Welcome back');
    });

    test(r'login$helper demands only its own pattern var', () {
      // The helper attribute uses $name; the body does not. The body
      // method takes no args, the helper method takes name.
      expect(t.login$helper(name: 'Aria'), contains('Tap to continue'));
      expect(t.login$helper(name: 'Aria'), contains('Aria'));
    });
  });

  group('generated AppMessages — error handling', () {
    test('errors out-list passes through to the underlying bundle', () {
      // Type-checked accessor → no way to call with the wrong shape
      // by accident. Verify the optional `errors` parameter does
      // reach the bundle. With well-formed args + a known message,
      // the list stays empty.
      final errs = <FluentError>[];
      final result = AppMessages(_bundle()).welcome(name: 'Aria', errors: errs);
      expect(result, contains('Hello'));
      expect(errs, isEmpty);
    });
  });
}
