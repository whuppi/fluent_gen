// Tests for the FTL inspection layer.
//
// Verifies the inspector wraps the syntax parser correctly and
// surfaces the metadata the inference + emission stages rely on.

import 'package:fluent_gen/src/inspection/ftl_inspector.dart';
import 'package:test/test.dart';

InspectedFile inspect(String content) =>
    inspectFtl(path: 'test/fixture.ftl', locale: 'en', content: content);

void main() {
  group('inspectFtl — basic shape', () {
    test('returns one InspectedMessage per Message in source', () {
      final file = inspect('''
hello = Hi
welcome = Hello, { \$name }!
''');
      expect(file.messages, hasLength(2));
      expect(file.messages.map((m) => m.id), ['hello', 'welcome']);
    });

    test('terms collected separately', () {
      final file = inspect('''
-brand = Acme
welcome = Welcome to { -brand }!
''');
      expect(file.messages, hasLength(1));
      expect(file.terms, hasLength(1));
      expect(file.terms.single.id.name, 'brand');
    });

    test('messages without value or attributes are skipped', () {
      // `empty =` (no value, no attributes) is parsed as Junk by
      // fluent-rs spec — it never reaches the messages list at all.
      // Verify the inspector doesn't surface it as an InspectedMessage.
      final file = inspect('''
hello = Hi
empty =
''');
      expect(file.messages.map((m) => m.id), ['hello']);
    });

    test('attributes captured', () {
      final file = inspect('''
login = Log in
    .title = Sign-in screen
    .helper = Tap to continue
''');
      expect(file.messages, hasLength(1));
      final inspected = file.messages.single;
      expect(inspected.id, 'login');
      expect(inspected.attributeNames, ['title', 'helper']);
      expect(inspected.hasValue, isTrue);
    });

    test('value-less message with attributes accepted', () {
      // A message with attributes but no value is valid FTL — used
      // for "namespace" entries like `shortcut = .key = Ctrl+S`.
      // The inspector keeps it; emission generates accessors for
      // each attribute but no top-level method.
      final file = inspect('''
shortcut =
    .key = Ctrl+S
''');
      expect(file.messages, hasLength(1));
      final inspected = file.messages.single;
      expect(inspected.hasValue, isFalse);
      expect(inspected.attributeNames, ['key']);
    });
  });

  group('inspectFtl — junk handling', () {
    test('parse errors surface as junk, not as exceptions', () {
      final file = inspect('''
valid = ok
broken =
''');
      // The "broken =" with nothing after is junk per Fluent spec.
      expect(file.messages.map((m) => m.id), ['valid']);
      expect(file.junk, isNotEmpty);
    });

    test('completely malformed input does not throw', () {
      final file = inspect('### invalid\nthis is not fluent at all\n');
      expect(file.junk, isNotEmpty);
      // Nothing crashed. The build can continue and surface the
      // junk as a warning.
    });
  });

  group('inspectFtl — markup detection', () {
    test('hasMarkup is true when body contains <tag>', () {
      final file = inspect('''
welcome = Hello, <bold>{ \$name }</bold>!
''');
      expect(file.messages.single.hasMarkup, isTrue);
    });

    test('hasMarkup is true for self-closing <icon/>', () {
      final file = inspect('''
tip = Save with the <icon name="floppy"/> button.
''');
      expect(file.messages.single.hasMarkup, isTrue);
    });

    test('hasMarkup is false for plain messages', () {
      final file = inspect('''
hello = Hi, { \$name }
''');
      expect(file.messages.single.hasMarkup, isFalse);
    });

    test('hasMarkup ignores < that is not followed by alpha', () {
      // `1 < 2` should not be detected as markup.
      final file = inspect('''
math = 1 < 2 is true
''');
      expect(file.messages.single.hasMarkup, isFalse);
    });
  });

  group('inspectFtl — source text capture', () {
    test('sourceText preserves the original formatting', () {
      final file = inspect('''
welcome = Hello, { \$name }!
''');
      // Doc comments need the source verbatim so consumers reading
      // generated code can match it back to their .ftl.
      expect(file.messages.single.sourceText, 'welcome = Hello, { \$name }!');
    });

    test('multi-line message captures everything in the span', () {
      final file = inspect('''
items = { \$count ->
    [one] one item
   *[other] { \$count } items
}
''');
      final source = file.messages.single.sourceText;
      // The source must contain the selector and at least one of
      // the variant arms.
      expect(source, contains('count'));
      expect(source, contains('[one]'));
      expect(source, contains('*[other]'));
    });
  });
}
