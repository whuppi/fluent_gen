// Shape-level tests on the top-level emitter.
//
// Each test parses a small FTL fixture, runs `emitFile`, and
// asserts the emitted Dart contains the expected method
// signatures, doc-comment fragments, and structural elements.
//
// For byte-for-byte coverage of complete emitter output across
// fixtures, see `test/emission/golden_test.dart`.

import 'package:fluent_gen/src/emission/emitter.dart';
import 'package:fluent_gen/src/emission/identifier.dart';
import 'package:fluent_gen/src/inspection/ftl_inspector.dart';
import 'package:test/test.dart';

String generate(
  String ftl, {
  String className = 'Translations',
  Map<String, String> otherLocales = const {},
  bool bundleFtl = false,
  String localeEnumName = 'AppLocale',
}) {
  final base = inspectFtl(path: 'lib/i18n/en.ftl', locale: 'en', content: ftl);
  return emitFile(
    baseLocaleFiles: [base],
    className: className,
    allLocaleFiles: {
      'en': [base],
      for (final entry in otherLocales.entries)
        entry.key: [
          inspectFtl(
            path: 'lib/i18n/${entry.key}.ftl',
            locale: entry.key,
            content: entry.value,
          ),
        ],
    },
    bundleFtl: bundleFtl,
    localeEnumName: localeEnumName,
  ).source;
}

void main() {
  group('emitFile — header', () {
    test('always emits the auto-generated banner', () {
      final out = generate('hello = Hi\n');
      expect(out, contains('GENERATED CODE'));
      expect(out, contains('DO NOT MODIFY'));
      expect(out, contains('build_runner build'));
    });

    test('imports fluent_bundle (for FluentBundle + FluentSpan)', () {
      final out = generate('hello = Hi\n');
      expect(
        out,
        contains("import 'package:fluent_bundle/fluent_bundle.dart';"),
      );
    });

    test('class name is configurable', () {
      final out = generate('hello = Hi\n', className: 'AppMessages');
      expect(out, contains('class AppMessages {'));
    });
  });

  group('emitFile — basic message', () {
    test('plain no-arg message emits a no-param method', () {
      final out = generate('hello = Hi\n');
      // Method signature has no required params (just the optional
      // errors list).
      expect(out, contains('String hello({List<FluentError>? errors})'));
      expect(out, contains("'hello'"));
      expect(out, contains('args: <String, Object?>{}'));
    });

    test('message with one variable infers + emits required param', () {
      final out = generate(
        r'greet = Hi, { $name }!'
        '\n',
      );
      expect(out, contains('String greet({required Object? name'));
      expect(out, contains("'name': name"));
    });

    test('NUMBER builtin emits num parameter', () {
      final out = generate(
        r'price = { NUMBER($amount) }'
        '\n',
      );
      expect(out, contains('required num amount'));
    });

    test('DATETIME builtin emits DateTime parameter', () {
      final out = generate(
        r'at = { DATETIME($d) }'
        '\n',
      );
      expect(out, contains('required DateTime d'));
    });

    test('plural selector emits num parameter', () {
      final out = generate(r'''
items = { $count ->
    [one] one item
   *[other] { $count } items
}
''');
      expect(out, contains('required num count'));
    });
  });

  group('emitFile — attributes', () {
    test(r'each attribute emits a separate method with $-suffix', () {
      final out = generate('''
login = Sign in
    .title = Welcome
    .helper = Tap to continue
''');
      expect(out, contains('String login('));
      expect(out, contains(r'String login$title('));
      expect(out, contains(r'String login$helper('));
      expect(out, contains("attribute: 'title'"));
      expect(out, contains("attribute: 'helper'"));
    });

    test('value-less message emits attribute methods only', () {
      final out = generate('''
shortcut =
    .key = Ctrl+S
''');
      // No body method — message has no value.
      expect(out, isNot(contains(' shortcut(')));
      expect(out, contains(r'String shortcut$key('));
    });
  });

  group('emitFile — inline markup', () {
    test('message with <tag> emits both String and AsSpans variants', () {
      final out = generate(r'''
welcome = Hello, <bold>{ $name }</bold>!
''');
      expect(out, contains('String welcome('));
      expect(out, contains('List<FluentSpan> welcomeAsSpans('));
      expect(out, contains('formatMessageAsSpans'));
    });

    test('plain message does not emit AsSpans sibling', () {
      final out = generate(
        r'plain = Hi { $name }!'
        '\n',
      );
      expect(out, contains('String plain('));
      expect(out, isNot(contains('AsSpans')));
    });

    test('attribute methods never get AsSpans siblings', () {
      // Spec: attributes feed machine-consumed values (href, src),
      // spans don't apply. Verify even when the message body has
      // markup, the attribute methods stay String-only.
      final out = generate(r'''
welcome = Hello, <bold>{ $name }</bold>!
    .title = Welcome <bold>{ $name }</bold>
''');
      expect(out, contains('welcomeAsSpans'));
      expect(out, isNot(contains(r'welcome$titleAsSpans')));
    });
  });

  group('emitFile — identifier sanitization', () {
    test('kebab-case message id sanitized to camelCase', () {
      final out = generate('shopping-cart = Your cart\n');
      expect(out, contains('String shoppingCart('));
    });

    test('reserved-word message id gets \$-prefix', () {
      final out = generate('class = A class\n');
      expect(out, contains(r'String $class('));
    });
  });

  group('emitFile — collisions', () {
    test('two FTL ids that sanitize to the same Dart name throw', () {
      // `foo-bar` and `foo_bar` both → `fooBar`.
      expect(
        () => generate('''
foo-bar = One
foo_bar = Two
'''),
        throwsA(isA<CollisionError>()),
      );
    });
  });

  group('emitFile — doc comments', () {
    test('source FTL appears in the doc comment', () {
      final out = generate(
        r'greet = Hi, { $name }!'
        '\n',
      );
      expect(out, contains(r'/// greet = Hi, { $name }!'));
    });

    test('source path + line appear in the doc comment', () {
      final out = generate('hello = Hi\n');
      expect(out, contains('/// Source: `lib/i18n/en.ftl:1`.'));
    });

    test('line numbers track the message position in the file', () {
      final out = generate('first = One\n\nsecond = Two\n');
      expect(out, contains('/// Source: `lib/i18n/en.ftl:3`.'));
    });

    test('the FTL source is fenced as a code block', () {
      final out = generate('hello = Hi\n');
      expect(out, contains('/// ```ftl'));
    });

    test('the attached FTL comment leads the doc comment', () {
      final out = generate('# The tiny greeting.\nhello = Hi\n');
      expect(out, contains('/// The tiny greeting.'));
      // The comment renders BEFORE the fenced source.
      expect(
        out.indexOf('/// The tiny greeting.'),
        lessThan(out.indexOf('/// ```ftl')),
      );
    });

    test('an FTL \$errors variable cannot collide with the errors '
        'parameter', () {
      final out = generate(r'oops = Problem: { $errors }');
      expect(out, contains(r'required Object? $errors'));
      expect(out, contains(r"'errors': $errors"));
      expect(out, contains('List<FluentError>? errors'));
    });

    test('markup messages get the AsSpans pointer', () {
      final out = generate(r'''
welcome = Hello, <bold>{ $name }</bold>!
''');
      expect(out, contains('Has inline markup'));
      expect(out, contains('[welcomeAsSpans]'));
    });

    test('conflict-flagged params get an explanatory note', () {
      final out = generate(r'''
weird = { NUMBER($x) } and { DATETIME($x) }
''');
      expect(out, contains('could not be narrowed'));
      expect(out, contains(r'`$x`'));
    });
  });

  group('emitFile — locale enum', () {
    test('one value per discovered locale, tags sorted', () {
      final out = generate(
        'hello = Hi\n',
        otherLocales: {'fr': 'hello = Salut\n', 'zh-Hans-CN': 'hello = Ni\n'},
      );
      expect(out, contains('enum AppLocale {'));
      expect(out, contains("en('en')"));
      expect(out, contains("fr('fr')"));
      expect(out, contains("zhHansCn('zh-Hans-CN')"));
      // sorted: en < fr < zh-Hans-CN
      expect(out.indexOf("en('en')"), lessThan(out.indexOf("fr('fr')")));
    });

    test('the base constant points at base_locale', () {
      final out = generate('hello = Hi\n', otherLocales: {'fr': 'x = y\n'});
      expect(out, contains('static const AppLocale base = AppLocale.en;'));
    });

    test('tryParse and negotiate are emitted', () {
      final out = generate('hello = Hi\n');
      expect(out, contains('static AppLocale? tryParse(String tag)'));
      expect(out, contains('static AppLocale negotiate('));
    });

    test('the enum name is configurable', () {
      final out = generate('hello = Hi\n', localeEnumName: 'Lingo');
      expect(out, contains('enum Lingo {'));
      expect(out, isNot(contains('enum AppLocale')));
    });

    test('without bundling there is no ftlSources or load', () {
      final out = generate('hello = Hi\n');
      expect(out, isNot(contains('ftlSources')));
      expect(out, isNot(contains('FluentBundle load(')));
    });
  });

  group('emitFile — bundled FTL', () {
    test('every locale embeds its source and gains load()', () {
      final out = generate(
        'hello = Hi { \$name }\n',
        otherLocales: {'fr': 'hello = Salut { \$name }\n'},
        bundleFtl: true,
      );
      expect(out, contains('List<String> get ftlSources'));
      expect(out, contains('FluentBundle load('));
      // The FTL is embedded with its placeable dollar escaped.
      expect(out, contains(r'hello = Hi { \$name }'));
      expect(out, contains(r'hello = Salut { \$name }'));
    });

    test('a quote-run and a trailing quote survive embedding', () {
      // ''' inside the FTL and a content-final quote are the two ways
      // an embedded literal could terminate early — both must emit
      // valid Dart (proven by the formatter inside emitFile) and keep
      // the content.
      final out = generate("tricky = { \"x\" } it''' fine'\n", bundleFtl: true);
      expect(out, contains('ftlSources'));
      expect(out, contains('fine'));
    });

    test('embedded source escapes quotes and backslashes', () {
      final out = generate(
        'quoted = He said { "\'em all" }\n',
        bundleFtl: true,
      );
      // The generated file must still be valid Dart — proven by the
      // formatter-integrity group; here just confirm the content
      // survived (escaped quote present).
      expect(out, contains('ftlSources'));
      expect(out, contains('em all'));
    });
  });

  group('emitFile — accessor manifest', () {
    test('every accessor (bodies, attributes, siblings) is listed', () {
      final out = generate('''
welcome = Hello, <b>{ \$name }</b>
login = Sign in
    .title = Welcome
''');
      expect(out, contains('static const List<String> accessorNames'));
      expect(out, contains("r'welcome'"));
      expect(out, contains("r'welcomeAsSpans'"));
      expect(out, contains("r'login'"));
      expect(out, contains(r"r'login$title'"));
    });

    test('an FTL id sanitizing to accessorNames collides loudly', () {
      expect(
        () => generate('accessor-names = Boom\n'),
        throwsA(isA<CollisionError>()),
      );
    });
  });

  group('emitFile — formatter integrity', () {
    test('output is formatted dart (no extra blank-line runs)', () {
      final out = generate('a = One\nb = Two\nc = Three\n');
      // After DartFormatter, there's never a triple-newline.
      expect(out, isNot(contains('\n\n\n\n')));
    });

    test('output is valid Dart that DartFormatter accepts on round-trip', () {
      // If the emitter ever produced invalid Dart, DartFormatter
      // inside emitFile would throw — getting a string back at all
      // is a compile-time correctness check.
      expect(
        () => generate(r'''
hello = Hi
welcome = Hi, { $name }!
items = { $count ->
    [one] one item
   *[other] { $count } items
}
markup = <bold>{ $word }</bold>
'''),
        returnsNormally,
      );
    });
  });
}
