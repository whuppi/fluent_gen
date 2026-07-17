// Full-surface battery: one FTL fixture exercising every inference
// rule, every emission shape, and their interactions, asserted against
// the generated Dart. This is the drift-catcher — if a future change to
// inference or emission alters a signature, doc shape, or degrade, a
// row here goes red.
//
// Complements the golden tests (byte-for-byte on small fixtures) by
// asserting SEMANTIC properties on a dense, realistic source.

import 'package:fluent_gen/src/emission/emitter.dart';
import 'package:fluent_gen/src/inspection/ftl_inspector.dart';
import 'package:test/test.dart';

const _ftl = r'''
# A plain greeting.
# $name (String) - the user's display name.
welcome = Welcome, { $name }!

## This group comment is standalone and must not attach anywhere.

items = { $count ->
    [one] one item
   *[other] { $count } items
}

platform = { $os ->
    [windows] Windows
    [macos] macOS
   *[other] your system
}

price = Total: { NUMBER($amount, style: "currency", currency: "EUR") }

meeting = Starts { DATETIME($when) }

# tagline references the -brand term.
tagline = { -brand } — { $slogan }
-brand = { $brandName }

# Positional term arg has no runtime effect: NO parameter, a warning.
legal = Read { -brand($ignored) } terms

banner = Hello, <bold>{ $who }</bold>!
    .tooltip = Click to greet { $who }

login = Sign in
    .placeholder = Enter your { $field }

shopping-cart = Your cart

oops = Problem: { $errors }

# Conflicting usages widen to Object?.
weird = { NUMBER($x) } and { DATETIME($x) }
''';

String get _out {
  final file = inspectFtl(path: 'lib/i18n/en.ftl', locale: 'en', content: _ftl);
  return emitFile(baseLocaleFiles: [file], className: 'Messages').source;
}

EmitResult get _result {
  final file = inspectFtl(path: 'lib/i18n/en.ftl', locale: 'en', content: _ftl);
  return emitFile(baseLocaleFiles: [file], className: 'Messages');
}

void main() {
  group('battery — type inference in signatures', () {
    test('comment (String) pin narrows a plain interp', () {
      expect(_out, contains('String welcome({required String name'));
    });

    test('plural selector → num', () {
      expect(_out, contains('String items({required num count'));
    });

    test('string selector with *[other] default → String', () {
      expect(_out, contains('String platform({required String os'));
    });

    test('NUMBER builtin arg → num', () {
      expect(_out, contains('String price({required num amount'));
    });

    test('DATETIME builtin arg → DateTime', () {
      expect(_out, contains(r'String meeting({required DateTime $when'));
    });

    test('conflicting usages → Object? with a doc note', () {
      expect(_out, contains(r'String weird({required Object? x'));
      expect(_out, contains('could not be narrowed'));
    });
  });

  group('battery — transitive references', () {
    test('{ -brand } pulls no term params (term scope is its own)', () {
      // tagline references -brand, whose body uses $brandName. A TERM
      // reference resolves in its own scope — $brandName is the term's
      // internal arg, never the caller's. Only $slogan is a parameter.
      expect(_out, contains(r'String tagline({required Object? slogan'));
      // The term's internal $brandName never becomes a caller parameter.
      expect(_out, isNot(contains('required Object? brandName')));
    });
  });

  group('battery — term arg + errors-name safety', () {
    test('positional term arg is not a parameter, and warns', () {
      expect(_out, contains('String legal({List<FluentError>? errors})'));
      expect(
        _result.notes.map((n) => n.formatted()),
        anyElement(contains('positional argument to term `-brand`')),
      );
    });

    test(r'an FTL $errors variable escapes the errors parameter', () {
      expect(_out, contains(r'required Object? $errors'));
      expect(_out, contains(r"'errors': $errors"));
      expect(_out, contains('List<FluentError>? errors'));
    });
  });

  group('battery — emission shapes', () {
    test('markup message gets both String and AsSpans siblings', () {
      expect(_out, contains('String banner({required Object? who'));
      expect(_out, contains('List<FluentSpan> bannerAsSpans('));
    });

    test('attribute methods carry only their own pattern vars', () {
      // banner.tooltip uses $who; login.placeholder uses $field.
      expect(_out, contains(r'String banner$tooltip({required Object? who'));
      expect(_out, contains(r'String login$placeholder('));
      expect(_out, contains('required Object? field'));
      // login body has no vars.
      expect(_out, contains('String login({List<FluentError>? errors})'));
    });

    test('attributes never get AsSpans siblings', () {
      expect(_out, isNot(contains(r'banner$tooltipAsSpans')));
    });

    test('kebab-case id sanitized to camelCase', () {
      expect(_out, contains('String shoppingCart('));
    });
  });

  group('battery — doc comments', () {
    test('attached FTL comment leads the doc block', () {
      expect(_out, contains("/// A plain greeting."));
    });

    test('the FTL source is fenced', () {
      expect(_out, contains('/// ```ftl'));
    });

    test('source path + line are present', () {
      expect(_out, contains('/// Source: `lib/i18n/en.ftl:'));
    });
  });

  group('battery — locale enum + manifest', () {
    test('the enum, base constant, and negotiation are present', () {
      expect(_out, contains('enum AppLocale {'));
      expect(_out, contains('static const AppLocale base = AppLocale.en;'));
      expect(_out, contains('static AppLocale negotiate('));
    });

    test('the manifest lists every accessor', () {
      expect(_out, contains('static const List<String> accessorNames'));
      expect(_out, contains("r'welcome'"));
      expect(_out, contains(r"r'banner$tooltip'"));
      expect(_out, contains("r'bannerAsSpans'"));
    });
  });

  group('battery — file integrity', () {
    test('imports markup.dart because a markup message exists', () {
      expect(_out, contains("import 'package:fluent_bundle/markup.dart';"));
    });

    test('no blanket lint suppression header', () {
      expect(_out, isNot(contains('ignore_for_file: type=lint')));
    });

    test('every method returns through the bundle', () {
      // No placeholder bodies, no TODOs.
      expect(_out, isNot(contains('TODO')));
      expect(_out, isNot(contains('throw Unimple')));
    });
  });
}
