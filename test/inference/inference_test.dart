// Tests for the inference stage.
//
// Covers every row of the usage-kind → Dart-type table, the
// conflict-resolution priority cascade, the selector-classification
// rule, transitive message references, comment type pins, and the
// per-pattern (value vs attribute) parameter split. Uses the FTL
// parser via the inspector so the tests exercise the same path the
// Builder runs at build time.

import 'package:fluent_gen/src/inspection/ftl_inspector.dart';
import 'package:fluent_gen/src/inference/inference.dart';
import 'package:test/test.dart';

/// Parse an FTL source and run inference for the message named [id]
/// (the first message when omitted), resolving references against
/// every message in the source.
MessageInference inferIn(String ftl, {String? id}) {
  final file = inspectFtl(path: 'test/fixture.ftl', locale: 'en', content: ftl);
  final context = InferenceContext(
    messagesById: {for (final m in file.messages) m.id: m.message},
  );
  final msg =
      id == null
          ? file.messages.first
          : file.messages.firstWhere((m) => m.id == id);
  return inferMessage(msg.message, context);
}

/// The whole-message union — what most single-message tests assert.
List<InferredVariable> infer(String ftl, {String? id}) =>
    inferIn(ftl, id: id).messageVariables;

/// Find the inferred variable by name. Throws if absent so tests
/// fail loudly instead of silently passing `null`.
InferredVariable byName(List<InferredVariable> vars, String name) =>
    vars.firstWhere(
      (v) => v.name == name,
      orElse: () => throw StateError('no variable named $name in $vars'),
    );

void main() {
  group('inference — plain interpolation', () {
    test('plain { \$name } infers Object?', () {
      final vars = infer(r'hello = Hi, { $name }');
      expect(vars, hasLength(1));
      expect(vars.single.name, 'name');
      expect(vars.single.type, InferredDartType.objectType);
      expect(vars.single.hadConflict, isFalse);
    });

    test('multiple plain interps for same variable still Object?', () {
      final vars = infer(r'msg = { $x } and { $x } and { $x }');
      expect(vars, hasLength(1));
      expect(vars.single.type, InferredDartType.objectType);
    });
  });

  group('inference — NUMBER builtin arg', () {
    test('NUMBER(\$amount) infers num', () {
      final vars = infer(r'price = { NUMBER($amount) }');
      expect(vars, hasLength(1));
      expect(vars.single.name, 'amount');
      expect(vars.single.type, InferredDartType.numType);
    });

    test('NUMBER with options still infers num', () {
      final vars = infer(
        r'price = { NUMBER($amount, style: "currency", currency: "EUR") }',
      );
      expect(vars.single.type, InferredDartType.numType);
    });
  });

  group('inference — DATETIME builtin arg', () {
    test('DATETIME(\$d) infers DateTime', () {
      final vars = infer(r'at = { DATETIME($d) }');
      expect(vars.single.name, 'd');
      expect(vars.single.type, InferredDartType.dateTimeType);
    });
  });

  group('inference — selector classification', () {
    test('plural-category selector infers num', () {
      final vars = infer(r'''
items = { $count ->
    [one] one item
   *[other] { $count } items
}
''');
      expect(byName(vars, 'count').type, InferredDartType.numType);
    });

    test('numeric-literal-key selector infers num', () {
      final vars = infer(r'''
rank = { $place ->
    [1] first
    [2] second
   *[other] { $place }th
}
''');
      expect(byName(vars, 'place').type, InferredDartType.numType);
    });

    test('non-plural string keys infer String', () {
      final vars = infer(r'''
mood = { $tone ->
    [happy] cheerful
    [sad] glum
   *[neutral] fine
}
''');
      expect(byName(vars, 'tone').type, InferredDartType.stringType);
    });

    test('the PLATFORM pattern — string keys with *[other] default '
        'infer String, not num', () {
      // `other` is the natural default key for STRING selectors too
      // (Mozilla's canonical `{ PLATFORM() -> [windows] … *[other] … }`
      // shape). Its presence alone must not force `num`.
      final vars = infer(r'''
menu = { $platform ->
    [windows] Options
   *[other] Preferences
}
''');
      expect(byName(vars, 'platform').type, InferredDartType.stringType);
    });

    test('an only-*[other] selector gives no signal — Object?', () {
      final vars = infer(r'''
fallbacky = { $thing ->
   *[other] whatever
}
''');
      expect(byName(vars, 'thing').type, InferredDartType.objectType);
      expect(byName(vars, 'thing').hadConflict, isFalse);
    });

    test('mixed number + plural keys still infer num', () {
      final vars = infer(r'''
rank = { $place ->
    [1] gold
    [one] { $place }st
   *[other] { $place }th
}
''');
      expect(byName(vars, 'place').type, InferredDartType.numType);
    });

    test('a non-plural identifier key wins over plural keys — String', () {
      // `[vip]` can never match a plural category; the runtime CAN
      // literal-match it (and `one`) for a string selector. String is
      // the only typing under which every variant is reachable.
      final vars = infer(r'''
tier = { $level ->
    [vip] gold lounge
    [one] single pass
   *[other] standard
}
''');
      expect(byName(vars, 'level').type, InferredDartType.stringType);
    });
  });

  group('inference — term references', () {
    test('positional term-call \$var contributes NO parameter + notes', () {
      // The resolver builds a term's scope from NAMED args only and
      // never evaluates positional term args — `{ -brand($x) }` has
      // no runtime effect. No parameter; an advisory note instead.
      final result = inferIn(r'greet = Hello, { -brand($userCase) }!');
      expect(result.messageVariables, isEmpty);
      expect(result.notes, hasLength(1));
      final note = result.notes.single as PositionalTermArgNote;
      expect(note.messageId, 'greet');
      expect(note.termName, 'brand');
      expect(note.formatted(), contains('-brand'));
    });

    test('term reference without args contributes nothing', () {
      final result = inferIn(r'about = About { -brand }.');
      expect(result.messageVariables, isEmpty);
      expect(result.notes, isEmpty);
    });

    test('named term args are literal-only — nothing to walk', () {
      final result = inferIn(r'about = About { -brand(case: "genitive") }.');
      expect(result.messageVariables, isEmpty);
      expect(result.notes, isEmpty);
    });
  });

  group('inference — custom function args', () {
    test('custom FN(\$x) infers Object?', () {
      final vars = infer(r'msg = { SHOUT($word) }');
      expect(byName(vars, 'word').type, InferredDartType.objectType);
    });
  });

  group('inference — transitive message references', () {
    test('{ msg } pulls the referenced message\'s variables', () {
      // The runtime resolves a referenced message's pattern in the
      // SAME scope — its variables are the caller's to supply.
      final vars = infer(r'''
greeting = Hello { $title }
welcome = { greeting }, { $name }!
''', id: 'welcome');
      expect(vars.map((v) => v.name), ['title', 'name']);
    });

    test('typed usages carry through the reference', () {
      final vars = infer(r'''
price-line = Total { NUMBER($total) }
receipt = { price-line } for { $buyer }
''', id: 'receipt');
      expect(byName(vars, 'total').type, InferredDartType.numType);
    });

    test('{ msg.attr } pulls that attribute\'s variables only', () {
      final vars = infer(r'''
login = Sign in
    .tooltip = Hi { $user }
prompt = { login.tooltip } now { $when }
''', id: 'prompt');
      expect(vars.map((v) => v.name), ['user', 'when']);
    });

    test('references chase through multiple hops', () {
      final vars = infer(r'''
a = { $deep }
b = { a }
c = { b }
''', id: 'c');
      expect(vars.map((v) => v.name), ['deep']);
    });

    test('reference cycles terminate', () {
      final vars = infer(r'''
ping = { pong } { $p }
pong = { ping } { $q }
''', id: 'ping');
      expect(vars.map((v) => v.name).toSet(), {'q', 'p'});
    });

    test('self-reference terminates', () {
      final vars = infer(r'ouro = { ouro } { $tail }');
      expect(vars.map((v) => v.name), ['tail']);
    });

    test('unknown reference target contributes nothing', () {
      final vars = infer(r'msg = { nonexistent } and { $x }');
      expect(vars.map((v) => v.name), ['x']);
    });
  });

  group('inference — conflict resolution', () {
    test('num + DateTime usage on same var → Object? + conflict flag', () {
      final vars = infer(r'''
weird = { NUMBER($x) } and also { DATETIME($x) }
''');
      expect(byName(vars, 'x').type, InferredDartType.objectType);
      expect(byName(vars, 'x').hadConflict, isTrue);
    });

    test('num + String usage → Object? + conflict flag', () {
      final vars = infer(r'''
weird = { NUMBER($x) } in { $x ->
    [happy] a
   *[sad] b
}
''');
      expect(byName(vars, 'x').type, InferredDartType.objectType);
      expect(byName(vars, 'x').hadConflict, isTrue);
    });

    test('DateTime + String usage → Object? + conflict flag', () {
      final vars = infer(r'''
weird = { DATETIME($x) } in { $x ->
    [happy] a
   *[sad] b
}
''');
      expect(byName(vars, 'x').type, InferredDartType.objectType);
      expect(byName(vars, 'x').hadConflict, isTrue);
    });

    test('plain interp does NOT conflict with num', () {
      final vars = infer(r'msg = { $x } costs { NUMBER($x) }');
      expect(byName(vars, 'x').type, InferredDartType.numType);
      expect(byName(vars, 'x').hadConflict, isFalse);
    });

    test('multiple usages of same constraint kind do not conflict', () {
      final vars = infer(r'''
msg = { $count ->
    [one] one
   *[other] { $count } items
}
''');
      expect(byName(vars, 'count').type, InferredDartType.numType);
      expect(byName(vars, 'count').hadConflict, isFalse);
    });
  });

  group('inference — multiple variables', () {
    test('source-order preserved', () {
      final vars = infer(r'msg = { $a } then { $b } finally { $c }');
      expect(vars.map((v) => v.name), ['a', 'b', 'c']);
    });

    test('first occurrence determines order', () {
      final vars = infer(r'msg = { $b } and { $a } and { $b }');
      expect(vars.map((v) => v.name), ['b', 'a']);
    });
  });

  group('inference — per-pattern parameter split', () {
    test('body params come from the value pattern only', () {
      // The runtime renders only the requested pattern — the body
      // method must not demand attribute-only variables.
      final result = inferIn(r'''
login = Sign in { $user }
    .title = Welcome back
    .helper = Last seen { DATETIME($lastSeen) }
''');
      expect(result.valueVariables.map((v) => v.name), ['user']);
      expect(result.attributeVariables['title'], isEmpty);
      expect(result.attributeVariables['helper']!.map((v) => v.name), [
        'lastSeen',
      ]);
    });

    test('the union still aggregates across value + attributes', () {
      final result = inferIn(r'''
login = Sign in { $user }
    .helper = Last seen { DATETIME($lastSeen) }
''');
      expect(result.messageVariables.map((v) => v.name).toSet(), {
        'user',
        'lastSeen',
      });
    });

    test('same variable can type differently per pattern', () {
      // In the body `$x` is only interpolated (Object?); the
      // attribute proves num. The union carries num; the body method
      // keeps the honest per-pattern Object?.
      final result = inferIn(r'''
m = { $x }
    .title = { NUMBER($x) }
''');
      expect(
        byName(result.valueVariables, 'x').type,
        InferredDartType.objectType,
      );
      expect(
        byName(result.attributeVariables['title']!, 'x').type,
        InferredDartType.numType,
      );
      expect(
        byName(result.messageVariables, 'x').type,
        InferredDartType.numType,
      );
    });

    test('cross-attr conflict triggers widen + flag on the union', () {
      final result = inferIn(r'''
m = { NUMBER($x) }
    .title = { DATETIME($x) }
''');
      expect(
        byName(result.messageVariables, 'x').type,
        InferredDartType.objectType,
      );
      expect(byName(result.messageVariables, 'x').hadConflict, isTrue);
    });
  });

  group('inference — comment type pins', () {
    test('a (String) pin narrows a plain interp', () {
      final result = inferIn(r'''
# $name (String) - the user's name
hello = Hi { $name }
''');
      expect(
        byName(result.messageVariables, 'name').type,
        InferredDartType.stringType,
      );
      expect(result.notes, isEmpty);
    });

    test('(Number) and (DateTime) pins map to num and DateTime', () {
      final result = inferIn(r'''
# $count (Number) - how many
# $when (DateTime) - the moment
msg = { $count } at { $when }
''');
      expect(
        byName(result.messageVariables, 'count').type,
        InferredDartType.numType,
      );
      expect(
        byName(result.messageVariables, 'when').type,
        InferredDartType.dateTimeType,
      );
    });

    test('pins apply to per-pattern lists too', () {
      final result = inferIn(r'''
# $name (String) - the user's name
hello = Hi { $name }
    .short = { $name }
''');
      expect(
        byName(result.valueVariables, 'name').type,
        InferredDartType.stringType,
      );
      expect(
        byName(result.attributeVariables['short']!, 'name').type,
        InferredDartType.stringType,
      );
    });

    test('usage beats a disagreeing pin, with a note', () {
      final result = inferIn(r'''
# $count (String) - misannotated
msg = { NUMBER($count) }
''');
      expect(
        byName(result.messageVariables, 'count').type,
        InferredDartType.numType,
      );
      final note = result.notes.whereType<PinConflictNote>().single;
      expect(note.variable, 'count');
      expect(note.pinnedType, 'String');
      expect(note.inferredType, 'num');
    });

    test('a pin cannot fix a hard conflict', () {
      final result = inferIn(r'''
# $x (Number) - hopeful
weird = { NUMBER($x) } and { DATETIME($x) }
''');
      expect(
        byName(result.messageVariables, 'x').type,
        InferredDartType.objectType,
      );
      expect(byName(result.messageVariables, 'x').hadConflict, isTrue);
      expect(result.notes.whereType<PinConflictNote>(), hasLength(1));
    });

    test('unknown type keyword produces a note and no pin', () {
      final result = inferIn(r'''
# $count (Numbr) - typo
msg = { $count }
''');
      expect(
        byName(result.messageVariables, 'count').type,
        InferredDartType.objectType,
      );
      final note = result.notes.whereType<UnknownPinTypeNote>().single;
      expect(note.keyword, 'Numbr');
    });

    test('annotating a variable the message never uses produces a note', () {
      final result = inferIn(r'''
# $nme (String) - typo'd variable
hello = Hi { $name }
''');
      final note = result.notes.whereType<PinUnknownVariableNote>().single;
      expect(note.variable, 'nme');
    });

    test('prose parentheticals are not annotation attempts', () {
      final result = inferIn(r'''
# Shows $name (the user's display name) prominently.
hello = Hi { $name }
''');
      expect(result.notes, isEmpty);
      expect(
        byName(result.messageVariables, 'name').type,
        InferredDartType.objectType,
      );
    });

    test('a redundant pin matching the inference is silent', () {
      final result = inferIn(r'''
# $count (Number) - how many
msg = { NUMBER($count) }
''');
      expect(
        byName(result.messageVariables, 'count').type,
        InferredDartType.numType,
      );
      expect(result.notes, isEmpty);
    });
  });
}
