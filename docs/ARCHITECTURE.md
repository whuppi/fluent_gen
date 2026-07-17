# fluent_gen — Architecture

How the generator is wired. For usage examples see [`../README.md`](../README.md). For capability status see [`CAPABILITY_ROADMAP.md`](CAPABILITY_ROADMAP.md); for maintenance recipes see [`UPDATING.md`](UPDATING.md).

fluent_gen is a build-time code generator: it reads `.ftl` through
`fluent_bundle`'s public parser and emits one typed accessor class so
misspelled message ids and wrong argument types become compile errors
instead of runtime placeholders.

---

## 1. The contract

Five guarantees the generator earns:

- **Reads only the public surface of `fluent_bundle`.** Imports go
  through `package:fluent_bundle/syntax.dart` only — the generator can
  re-publish independently.
- **The base locale drives codegen; other locales never change
  signatures.** Translators ship coverage in pieces. Drift between
  locales surfaces as build warnings, never errors — a partial
  translation never blocks a build.
- **Types are inferred from usage, transitively and per pattern.**
  Fluent has no type grammar. Every parameter type is inferred from how
  the `$variable` is used — `NUMBER($x)` → `num`, plural selector →
  `num`, a message reference pulls the referenced pattern's variables.
  A body method demands exactly the value pattern's variables; each
  attribute method demands its own. The one annotation channel is the
  Mozilla comment convention (`# $name (String)`), and even there usage
  wins on conflict.
- **The generated file always compiles and analyzes clean.** Collision
  detection spans the complete emitted name set (bodies, attributes,
  `*AsSpans` siblings); an FTL `$errors` variable is escaped so it can't
  clash with the `errors` parameter; the output carries no blanket lint
  suppression and passes `package:lints/recommended`.
- **Base-locale parse errors fail the build; everything else warns.** A
  junked base message would silently vanish from the class — that's an
  error. Non-base junk, missing translations, orphan messages, and
  no-effect term args are warnings.

---

## 2. Source tree

One folder per pipeline stage; tests mirror `lib/src` file-for-file.

```
lib/
  builder.dart                       — public entry: the two build_runner factories
  testing.dart                       — public entry: consumer-test helpers (unusedFluentAccessors)
  src/
    builders/
      gen_builder.dart               — FluentGenBuilder (orchestrates the pipeline)
      fan_out_builder.dart           — FluentFanOutBuilder (JSON payload → source files)
    config/
      config.dart                    — Config.fromMap(BuilderOptions.config) + validation
    discovery/
      asset_glob.dart                — ftlAssetGlob(ftlDir) — the discovery glob, testable alone
      locale_discovery.dart          — (path, content) tuples → grouped by locale; layout detection
    inspection/
      ftl_inspector.dart             — wraps FluentParser; surfaces messages, comments, spans, junk
    inference/
      inference.dart                 — inferMessage(message, context): per-pattern + union + notes
      ast_walker.dart                — collects usages; transitive message refs; selector rule
      type_resolver.dart             — usage aggregation → InferredVariable (priority cascade)
      comment_pins.dart              — Mozilla-convention type annotations from the comment
      usage_kinds.dart               — UsageKind enum + VariableUsage record
      inference_note.dart            — build advisories (term args, pin typos, pin conflicts)
    emission/
      emitter.dart                   — emitFile → EmitResult (source + notes); collision detection
      locale_enum_emitter.dart       — the locale enum (+ embedded FTL when bundle_ftl)
      method_emitter.dart            — one method per body / attribute / AsSpans sibling
      identifier.dart                — sanitizeIdentifier + findCollisions + dartReservedWords
    testing/
      unused_accessors.dart          — the dead-translation scan (lib/testing.dart entrypoint)
    validation/
      locale_validator.dart          — missing / orphan / arg-mismatch warnings

test/                                — mirrors lib/src file-for-file
  builders/  config/  discovery/  inspection/  inference/  validation/
  emission/                          — emission_test, identifier_test, battery_test, golden_test,
                                       _generate_goldens.dart, golden/ (*.ftl + *.expected.dart)

example/                             — a consumer package; the real build_runner integration
  lib/i18n/{en,fr}.ftl               — base + partial non-base fixtures
  lib/main.dart                      — the showcase: every generated surface in one file
  analysis_options.yaml              — package:lints/recommended (the analyzes-clean bar)
  test/                              — generated smoke / locale enum / unused-message
                                       guard / analyzes-clean / showcase (pinned output)

Makefile                             — the gate: `make check` = analyze (package +
                                       example) + floor + VM suite + example fixture
```

---

## 3. The two-builder pipeline

`build_runner`'s `Builder.buildExtensions` is a static
extension-to-extension map; the consumer-configurable `output_path`
can't be expressed there. Two stages translate that into a configurable
path.

```
.ftl assets ──▶ FluentGenBuilder (Builder, build_to: cache)
                  buildExtensions: { $lib$ → [_fluent_gen_temp.json] }
                  writes {outputs: {<output_path>: <source>}}
                ──▶ FluentFanOutBuilder (PostProcessBuilder, build_to: source)
                      inputExtensions: [_fluent_gen_temp.json]
                    writes each {path: source} to the real source tree
```

`auto_apply: root_package` runs the pipeline for consumers that add
`fluent_gen` to `dev_dependencies`; `applies_builders` ties the
fan-out to the main builder. Config shape and `build.yaml` details are
unchanged from the original design.

---

## 4. The pipeline stages

`FluentGenBuilder.build` runs these in order:

```
1. Discover        findAssets(ftlAssetGlob(config.ftlDir))
2. Group by locale discoverLocales(...) → per-file vs per-directory layout
3. Inspect         inspectFtl(path, locale, content) per file
                   ├─ parse with spans; filter Junk
                   ├─ BASE-locale junk → log.severe + throw (build fails)
                   └─ non-base junk → warning
4. Validate        validateNonBaseLocales(...) → missing / orphan / arg-mismatch warnings
5. Emit            emitFile(baseFiles, className) → EmitResult(source, notes)
                   ├─ inference notes logged as warnings
                   └─ payload {outputs: {output_path: source}} → temp JSON
```

The fan-out post-process builder writes the payload to the real tree.

---

## 5. Type inference

`inferMessage(message, context)` returns a `MessageInference` with three
products plus advisory notes:

- **`valueVariables`** — the body method's parameters (the value
  pattern's variables, transitively).
- **`attributeVariables`** — per attribute, that attribute's pattern's
  variables. The runtime renders only the requested pattern, so each
  method must demand exactly its own.
- **`messageVariables`** — the union, for the cross-locale validator.

### The walk

`ast_walker.dart` classifies each `$variable` occurrence into a
`UsageKind` and follows message references:

| Construct | Contribution |
|---|---|
| `{ $x }` plain | unconstrained (→ Object? unless narrowed elsewhere) |
| `{ NUMBER($x) }` | num |
| `{ DATETIME($x) }` | DateTime |
| `{ FN($x) }` custom | unconstrained |
| `{ $x -> … }` selector | num or String or no-signal (see below) |
| `{ msg }` / `{ msg.attr }` | UNION the referenced pattern's usages (same-scope runtime semantics), cycle-guarded, cross-file within the locale |
| `{ -term($x) }` | nothing — the resolver never evaluates positional term args; emits a `PositionalTermArgNote` |

### Selector classification

A bare-variable selector is:

- **numeric** — every variant key is a number literal or a CLDR plural
  category (`zero`/`one`/`two`/`few`/`many`/`other`) AND at least one
  key is a number or a non-`other` category. Routed through plural
  rules → `num`.
- **string** — any key is a non-plural identifier (`[windows]`,
  `[happy]`). Matched as string literals → `String`.
- **no signal** — the only key is `*[other]`. `other` is both a plural
  category and the natural default for string selectors, so alone it
  decides nothing; the variable stays unconstrained.

### Resolution + pins

`type_resolver.dart` aggregates a variable's usages through the
cascade: **DateTime > num > String > Object?**. Incompatible hard
requirements (num AND DateTime) widen to `Object?` with a conflict flag
the emitter surfaces in a doc note.

`comment_pins.dart` parses `# $name (String|Number|DateTime)` from the
base-locale comment. A pin narrows a variable inference left at
`Object?`; it never overrides a proven type (usage wins, with a
`PinConflictNote`). Unknown keywords and annotations of absent variables
produce notes too.

---

## 6. Code emission

`emitFile` returns an `EmitResult` (source + inference notes). The class
shape is fixed: a doc-commented `Translations` (or configured name)
wrapping a `FluentBundle`, one method per body / attribute /
`*AsSpans` sibling.

### Collision detection

Runs over the COMPLETE emitted name set — body methods, attribute
methods (`$` separator), and `*AsSpans` siblings all share one Dart
namespace. Each candidate carries its FTL source descriptor, so a
`CollisionError` names the real culprits (e.g. a message `foo-as-spans`
colliding with markup message `foo`'s sibling).

### The `errors` guard

Every method declares a `List<FluentError>? errors` parameter. An FTL
`$errors` variable is escaped to `$errors` (the args-map key stays
`'errors'`) so the generated file always compiles.

### Doc comments

Per method: the attached FTL comment first (verbatim — the Fluent
convention, and where type pins live), then the FTL source fenced in a
```ftl block (so select brackets don't read as Dart doc references),
then `Source: path:line`. Markup messages get a pointer to their
`*AsSpans` sibling; conflict-widened parameters get an explanatory note.

### Markup detection

`hasMarkup` walks the VALUE pattern's text elements (and string-literal
placeables) only — attribute markup never triggers a sibling, because
the `*AsSpans` method formats the value, not attributes.

### The locale enum + manifest

After the class, the emitter renders the locale enum
(`locale_enum_emitter.dart`): one value per discovered locale (tags
sorted for deterministic output), `languageTag`, the `base` constant,
`tryParse`, and `negotiate`. With `bundle_ftl: true` each value also
carries `ftlSources` (the raw FTL embedded as escaped triple-quoted
literals — backslashes, dollars, and quote-triples neutralized) and
`load({backend})`. The class itself gains a `static const
accessorNames` manifest feeding the unused-message check; the manifest
name and every enum value join the collision set.

### Identifier sanitization

`sanitizeIdentifier` turns FTL ids into Dart names: kebab/snake →
lowerCamelCase, clean single segments preserved verbatim, reserved
words and leading digits `$`-prefixed. The reserved-word set is
single-sourced in `identifier.dart` and reused by the parameter guard.

---

## 7. Multi-locale validation

The base locale drives codegen; non-base locales are parsed and
validated against it, contributing only warnings:
`MissingMessageWarning`, `OrphanMessageWarning`, `ArgMismatchWarning`.
Each locale resolves its own message references (arg sets are computed
transitively, matching what the generator emits). Suppression flags on
the config silence categories a consumer isn't ready to act on.

---

## 8. Errors and warnings

| Severity | When |
|---|---|
| ERROR (build fails) | parse error in the BASE locale; `LocaleDiscoveryError` (mixed layout / non-locale filename); `CollisionError`; `base_locale` has no `.ftl`; `ConfigError` |
| WARNING (build continues) | non-base junk; the locale validator's three kinds; inference notes (positional term arg, pin typo, pin/usage conflict, annotation of an absent variable) |

The generated Dart never has a `TODO`, a placeholder body, or a
silently-swallowed error. Every method calls a real bundle method with a
real argument map.

---

## 9. Test architecture

| Suite | Proves |
|---|---|
| `test/inference/inference_test.dart` | Every usage kind, the selector rule (incl. the PLATFORM pattern), transitive refs + cycles, comment pins, the per-pattern split. |
| `test/emission/emission_test.dart` | Method shapes, `errors` escape, doc comments, collisions. |
| `test/emission/battery_test.dart` | Semantic properties on one dense fixture — the drift-catcher. |
| `test/emission/golden_test.dart` | Byte-for-byte output on small fixtures. |
| `test/emission/identifier_test.dart` | Sanitization table + full-name-set collisions. |
| `test/builders/gen_builder_test.dart` | `testBuilder`-driven: ok path, note surfacing, placeholder paths, junk-severity branches. |
| `test/{config,discovery,inspection,validation}/…` | Each stage in isolation. |
| `test/testing/unused_accessors_test.dart` | The dead-translation scan against a synthetic package (usage, exclusion, AsSpans folding, prefix safety). |
| `example/test/…` | The real build_runner integration + `dart analyze .` on generated output under `package:lints/recommended`. |

---

## 10. Compliance with the Fluent spec

The generator READS Fluent; it never invents syntax. Two non-obvious
constraints it respects: named function/term arguments are literal-only
(variables can only be positional), and plural-category keys drive
numeric selectors. Both are reflected in the walker.

---

## 11. Non-goals

- Replacing `FluentBundle` — the generated class is a thin typed shell
  over a bundle the consumer owns.
- Bundling FTL into the generated Dart — translations load at runtime;
  hot reload via `addResource(source, allowOverrides: true)` needs no
  regeneration.
- A CLI mode — `build_runner watch` covers the dev loop (the
  dead-translation check runs in the consumer's tests instead).
- REACTIVE locale switching (context plumbing, widget rebuild) — the
  `fluent_flutter` satellite's job (its `TypedFluentDelegate` serves
  the generated class). The pure-Dart half (the locale enum, parsing,
  negotiation, and — opt-in — bundle loading) ships here.

---

## 12. The one-line summary

> **Reads `.ftl` via `fluent_bundle/syntax`, infers Dart types from
> usage — transitively through message references, per pattern, with
> Mozilla-convention comment pins where usage leaves a gap — and emits a
> typed accessor class through a two-builder `build_runner` pipeline.
> The generated file always compiles and analyzes clean. Base-locale
> parse errors fail the build; every other drift is a warning.**
