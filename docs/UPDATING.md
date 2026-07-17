# Updating fluent_gen

Maintenance recipes for the generator. For how it's wired see
[`ARCHITECTURE.md`](ARCHITECTURE.md); for capability status see
[`CAPABILITY_ROADMAP.md`](CAPABILITY_ROADMAP.md).

fluent_gen reads `.ftl` through `fluent_bundle`'s public parser and
emits Dart. It tracks two upstreams:

| Source | Why |
|---|---|
| `fluent_bundle` (`syntax.dart`) | The parser + AST the generator walks. An AST change is the main reason to touch inference/emission. |
| Dart's reserved-word list + `package:lints` | The sanitizer escapes reserved words; the emitted code must pass the recommended lints. |

---

## When to update

| Trigger | Recipe |
|---|---|
| `fluent_bundle` parser / AST changes | §1 — Sync with the parser |
| A new inference rule (usage kind, type pin, selector shape) | §2 — Add an inference rule |
| Emitter output changes for any reason | §3 — Regenerate the goldens |
| A new Dart version reserves a keyword | §4 — Refresh the reserved words |
| `build`, `build_test`, or `dart_style` bumps | §5 — Standard pub upgrade |

---

## §1 — Sync with the fluent_bundle parser

The generator never re-implements parsing — it imports
`package:fluent_bundle/syntax.dart` and walks the AST. When
`fluent_bundle` changes the AST:

1. Bump the path/hosted dep, `fvm dart pub get`, run the suite.
2. A new AST node type surfaces as a non-exhaustive `switch` or a
   missing case in `lib/src/inference/ast_walker.dart` — handle it
   there (the walker is the single place that reads expression
   shapes).
3. If the node carries a new variable position, decide its
   `UsageKind` (`lib/src/inference/usage_kinds.dart`) and its type
   contribution (`lib/src/inference/type_resolver.dart`).
4. `inspectFtl` (`lib/src/inspection/ftl_inspector.dart`) reads
   `Message.comment`, spans, and value/attribute patterns — if the
   AST moved any of those, update it.
5. Regenerate goldens (§3) and review the diff.

---

## §2 — Add an inference rule

Type inference reads USAGE, never annotations the Fluent grammar
doesn't have (the one exception is the Mozilla comment convention —
see the pins below). One rule touches these files in order:

| Step | Where | What |
|---|---|---|
| 1 | `lib/src/inference/usage_kinds.dart` | Add a `UsageKind` if the usage is genuinely new. |
| 2 | `lib/src/inference/ast_walker.dart` | Emit that usage when the walk hits the construct. Selector classification lives in `_selectorKindFromVariants`. |
| 3 | `lib/src/inference/type_resolver.dart` | Map the usage to its type constraint in the priority cascade (DateTime > num > String > Object?). |
| 4 | `test/inference/inference_test.dart` | A row per new shape, including the conflict and no-signal cases. |
| 5 | `test/emission/battery_test.dart` | If the rule changes a generated signature, add it to the dense fixture. |

**Comment type pins** (`lib/src/inference/comment_pins.dart`) parse
`# $var (String|Number|DateTime)` from the base-locale comment. To add
a keyword: extend `_keywordToType`, add a test in
`inference_test.dart`. Usage always wins over a disagreeing pin — keep
that invariant.

**Transitive references**: `_walkMessageRef` unions a referenced
message's usages into the referrer (same-scope runtime semantics),
cycle-guarded. Term references contribute nothing — the resolver never
evaluates positional term args. Don't "fix" that into parameters; it's
correct.

---

## §3 — Regenerate the golden files

The golden tests assert byte-for-byte emitter output on small
fixtures. After ANY intentional emitter change:

```sh
fvm dart run test/emission/_generate_goldens.dart
git diff test/emission/golden/
```

Read every line of the diff — a single unintended change is a bug for
every consumer. Commit the regenerated `*.expected.dart` in the same
commit as the emitter change so the diff is auditable. The
`test/emission/battery_test.dart` suite asserts SEMANTIC properties on
a dense fixture and catches drift the small goldens miss.

---

## §4 — Refresh the reserved words

The sanitizer (`lib/src/emission/identifier.dart`, `dartReservedWords`)
escapes message ids and parameter names that collide with Dart
keywords. The same set guards parameter names in
`lib/src/emission/method_emitter.dart` (single-sourced — imported, not
re-listed). When a new Dart version reserves a keyword:

1. Add it to `dartReservedWords` — never remove an entry (removal
   breaks consumer FTL that relied on the escape).
2. `test/emission/identifier_test.dart` gets a row.

The `errors` parameter is not a Dart keyword but is escaped anyway
(`$errors`) because every generated method already declares a
`List<FluentError>? errors` — an FTL `$errors` variable must not
collide with it.

---

## §5 — Refresh build / dart_style deps

```sh
fvm dart pub upgrade build build_test dart_style
fvm dart analyze . && fvm dart test
cd example && fvm dart run build_runner build --delete-conflicting-outputs && fvm dart test
```

`dart_style` formats every emitted file; a major bump can reflow
signatures — regenerate goldens (§3) if so. The emitter formats at
`latestLanguageVersion` (the modern tall style); the family's >=3.7 SDK
floor guarantees every consumer's own `dart format` agrees with the
emitted shape. Don't lower the floor below 3.7 — that reintroduces a
style fight between the generator and consumer format gates. `build_test` drives the
`FluentGenBuilder` unit suite (`test/builders/gen_builder_test.dart`).

---

## Reading the failure modes

| Failure | First check |
|---|---|
| Generated file doesn't compile | An emission bug — collision over the full name set, or an unescaped reserved word. Run the example's `generated_analyzes_clean_test`. |
| A parameter has the wrong type | Inference — is the usage classified right in `ast_walker.dart`? Does a comment pin conflict (check the build warnings)? |
| A method demands a variable its pattern doesn't use | Per-pattern inference regressed — `inferMessage` returns `valueVariables` / `attributeVariables` separately; the emitter must use the right one. |
| Base-locale junk didn't fail the build | `gen_builder.dart` gates base junk to `log.severe` + throw; non-base stays a warning. |
| Golden test red after an unrelated change | Emitter output shifted — regenerate (§3), read the diff, confirm intentional. |
| `dart analyze` finds undocumented members | `public_member_api_docs` is on (family standard) — every public member needs a one-line doc. |

---

## The canonical-doc contract

Three living docs, no fourth: this file, `ARCHITECTURE.md`,
`CAPABILITY_ROADMAP.md`. Design history lives in git; per-file notes
live in code comments.
