// Tests for identifier sanitization + collision detection.

import 'package:fluent_gen/src/emission/identifier.dart';
import 'package:test/test.dart';

void main() {
  group('sanitizeIdentifier — happy path', () {
    test('plain lowercase passes through', () {
      expect(sanitizeIdentifier('welcome'), 'welcome');
      expect(sanitizeIdentifier('hello'), 'hello');
    });

    test('kebab-case becomes camelCase', () {
      expect(sanitizeIdentifier('shopping-cart'), 'shoppingCart');
      expect(sanitizeIdentifier('a-b-c-d'), 'aBCD');
      expect(sanitizeIdentifier('long-multi-word-id'), 'longMultiWordId');
    });

    test('snake_case becomes camelCase', () {
      expect(sanitizeIdentifier('user_name'), 'userName');
      expect(sanitizeIdentifier('first_last_third'), 'firstLastThird');
    });

    test('mixed kebab + snake handled', () {
      expect(sanitizeIdentifier('user-name_email'), 'userNameEmail');
    });

    test('multi-segment uppercase normalized to lowerCamelCase', () {
      // Multi-segment inputs always go through the rebuild path,
      // even when individual segments are uppercase.
      expect(sanitizeIdentifier('UPPER-CASE'), 'upperCase');
      expect(sanitizeIdentifier('SCREAMING_SNAKE'), 'screamingSnake');
    });

    test('single-segment Dart identifier preserved verbatim', () {
      // The translator's casing wins for any single-segment input
      // that's already a valid Dart identifier — both lowerCamel
      // and PascalCase shapes pass through unchanged.
      expect(sanitizeIdentifier('launchedAt'), 'launchedAt');
      expect(sanitizeIdentifier('XmlHttpRequest'), 'XmlHttpRequest');
      expect(sanitizeIdentifier('myField'), 'myField');
      expect(sanitizeIdentifier('IOError'), 'IOError');
    });
  });

  group('sanitizeIdentifier — reserved-word handling', () {
    test('Dart keyword `if` becomes `\$if`', () {
      expect(sanitizeIdentifier('if'), r'$if');
    });

    test('Dart keyword `class` becomes `\$class`', () {
      expect(sanitizeIdentifier('class'), r'$class');
    });

    test('Dart keyword `void` becomes `\$void`', () {
      expect(sanitizeIdentifier('void'), r'$void');
    });

    test('built-in `dynamic` reserved', () {
      expect(sanitizeIdentifier('dynamic'), r'$dynamic');
    });

    test('compound id not affected when its parts are reserved', () {
      // Only the FULL sanitized result is checked against the
      // reserved-word set. `if-then` → `ifThen`, which isn't a
      // reserved word.
      expect(sanitizeIdentifier('if-then'), 'ifThen');
    });
  });

  group('sanitizeIdentifier — leading digit', () {
    test('leading digit gets \$ prefix', () {
      expect(sanitizeIdentifier('123-foo'), r'$123Foo');
      expect(sanitizeIdentifier('1message'), r'$1message');
    });
  });

  group('sanitizeIdentifier — edge cases', () {
    test('empty input throws ArgumentError', () {
      expect(() => sanitizeIdentifier(''), throwsArgumentError);
    });

    test('only separators throws ArgumentError', () {
      expect(() => sanitizeIdentifier('---'), throwsArgumentError);
      expect(() => sanitizeIdentifier('___'), throwsArgumentError);
    });

    test('leading/trailing separators stripped', () {
      expect(sanitizeIdentifier('-leading'), 'leading');
      expect(sanitizeIdentifier('trailing-'), 'trailing');
      expect(sanitizeIdentifier('-both-'), 'both');
    });

    test('repeated separators collapsed', () {
      expect(sanitizeIdentifier('a---b'), 'aB');
      expect(sanitizeIdentifier('a___b'), 'aB');
    });

    test('non-ASCII chars stripped', () {
      // FTL allows unicode in identifiers; Dart doesn't always.
      // The sanitizer strips non-Dart-identifier chars; what
      // remains is camelCased.
      expect(sanitizeIdentifier('hello-世界-foo'), 'helloFoo');
    });

    test('all-stripped input throws', () {
      expect(() => sanitizeIdentifier('🎉🎉'), throwsArgumentError);
    });
  });

  group('findCollisions', () {
    /// Sanitize-and-pair helper matching the emitter's shape: the
    /// dart name derives from the FTL id; the source descriptor IS
    /// the FTL id.
    EmittedName emitted(String ftlId) => (
      dartName: sanitizeIdentifier(ftlId),
      sourceId: ftlId,
    );

    test('no collision → empty result', () {
      final collisions = findCollisions(
        ['welcome', 'goodbye', 'help'].map(emitted),
      );
      expect(collisions, isEmpty);
    });

    test('two FTL ids that collide are reported together', () {
      // `foo-bar` and `foo_bar` both → `fooBar`.
      final collisions = findCollisions(['foo-bar', 'foo_bar'].map(emitted));
      expect(collisions, hasLength(1));
      expect(collisions['fooBar'], containsAll(['foo-bar', 'foo_bar']));
    });

    test('three-way collision reports all three source ids', () {
      // `Foo-Bar`, `foo-bar`, and `foo_bar` all sanitize to the same
      // camelCase. `fooBar` (no separator) would be a different
      // entry — it's a single segment that lowercases to `foobar`.
      final collisions = findCollisions(
        ['Foo-Bar', 'foo-bar', 'foo_bar'].map(emitted),
      );
      expect(collisions, hasLength(1));
      expect(
        collisions['fooBar'],
        containsAll(['Foo-Bar', 'foo-bar', 'foo_bar']),
      );
    });

    test('multiple independent collisions are all reported', () {
      final collisions = findCollisions(
        [
          'foo-bar',
          'foo_bar', // collides with foo-bar → fooBar
          'baz-qux',
          'baz_qux', // collides with baz-qux → bazQux
          'unique',
        ].map(emitted),
      );
      expect(collisions.keys.toSet(), {'fooBar', 'bazQux'});
    });

    test('an AsSpans sibling collides with a message named *-as-spans', () {
      // The emitter registers sibling names in the same namespace.
      final collisions = findCollisions([
        (dartName: 'fooAsSpans', sourceId: 'foo (its *AsSpans sibling)'),
        emitted('foo-as-spans'),
      ]);
      expect(collisions, hasLength(1));
      expect(
        collisions['fooAsSpans'],
        containsAll(['foo (its *AsSpans sibling)', 'foo-as-spans']),
      );
    });
  });
}
