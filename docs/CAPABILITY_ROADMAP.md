# fluent_gen — Capabilities

What's shipped, what's deliberately out of scope. For how it's wired see [`ARCHITECTURE.md`](ARCHITECTURE.md); for maintenance recipes see [`UPDATING.md`](UPDATING.md).

---

## Builder pipeline

Two-builder split (primary `Builder` → JSON cache; `PostProcessBuilder`
→ source files) forced by `build_runner`'s static `buildExtensions`.

| Feature | Status |
|---|:---:|
| Primary builder discovers all `.ftl` under `ftl_dir` | DONE |
| Fan-out writes one file per `outputs` entry to source | DONE |
| `auto_apply: root_package` — only the consumer triggers it | DONE |
| `testBuilder`-driven unit suite (ok / placeholder / junk paths) | DONE |
| Watch mode: mid-watch FTL edits, brand-NEW locale files, and deletions all rebuild correctly | DONE — live-verified 2026-07-17 (edit landed in the generated file; a new `de.ftl` added `AppLocale.de` mid-watch; removing it took the value away) |

## Locale discovery

| Pattern | Shape | Status |
|---|---|:---:|
| Per-file | `lib/i18n/en.ftl`, `lib/i18n/zh-Hans-CN.ftl` | DONE |
| Per-directory | `lib/i18n/en/auth.ftl` | DONE |
| Mixed layouts | hard `LocaleDiscoveryError` | DONE |
| BCP47 tags, multiple files per locale (per-directory) | | DONE |

## Type inference

Types come from USAGE — transitively through message references, per
pattern (body vs attribute), with the priority cascade DateTime > num >
String > Object?.

| Usage in FTL | Inferred type | Status |
|---|---|:---:|
| Plain `{ $x }` | `Object?` | DONE |
| `{ NUMBER($x) }` | `num` | DONE |
| `{ DATETIME($x) }` | `DateTime` | DONE |
| Numeric selector (number / plural-category keys) | `num` | DONE |
| String selector (any non-plural key; `*[other]` default alone gives no signal) | `String` | DONE |
| `{ FN($x) }` custom function | `Object?` | DONE |
| `{ msg }` / `{ msg.attr }` reference | unions the referenced pattern's variables | DONE |
| `{ -term($x) }` positional term arg | no parameter (no runtime effect) + a build warning | DONE |
| Conflict (num AND DateTime on one var) | `Object?` + doc note | DONE |
| Comment type pin `# $x (String/Number/DateTime)` | narrows a Object?-inferred var; usage wins on conflict | DONE |
| Per-pattern split (body demands value vars, attribute demands its own) | | DONE |

## Code emission

| Feature | Status |
|---|:---:|
| One method per body / attribute / `*AsSpans` sibling | DONE |
| Collision detection over the COMPLETE name set (bodies + attributes + siblings) with source-descriptor errors | DONE |
| FTL `$errors` variable escaped so the file always compiles | DONE |
| Markup detection on the VALUE pattern only (no attribute false-siblings) | DONE |
| Doc comments: attached FTL comment + fenced source + `Source: path:line` | DONE |
| Conflict-widened parameters carry an explanatory note | DONE |
| Generated file analyzes clean under `package:lints/recommended` — no blanket suppression | DONE |
| Output formatted by `package:dart_style` | DONE |

## Identifier sanitization

| FTL id | Dart name | Status |
|---|---|:---:|
| `shopping-cart` / `user_name` | `shoppingCart` / `userName` | DONE |
| `launchedAt` (clean single segment) | preserved verbatim | DONE |
| `if` / `class` / reserved word | `$if` / `$class` | DONE |
| `123-foo` (leading digit) | `$123Foo` | DONE |
| A variable named `when` (Dart contextual keyword) | param `$when`, key `'when'` | DONE |
| Two ids that sanitize to the same name | `CollisionError` naming both | DONE |

## Multi-locale validation

Warnings only — localization is incremental, never build-blocking.

| Validation | Status |
|---|:---:|
| Missing message (in base, absent in non-base) | DONE |
| Orphan message (in non-base, absent from base) | DONE |
| Mismatched args (transitively computed per locale) | DONE |
| Configurable suppression flags | DONE |

## Errors and warnings

| Severity | Trigger | Status |
|---|---|:---:|
| ERROR | parse error in the BASE locale | DONE |
| ERROR | duplicate sanitized identifier (full name set) | DONE |
| ERROR | mixed locale-discovery layouts / missing base `.ftl` / bad config | DONE |
| WARNING | non-base junk; missing / orphan / arg-mismatch; inference notes | DONE |

## Configuration

| Option | Default | Status |
|---|---|:---:|
| `base_locale` | (required) | DONE |
| `ftl_dir` | `lib/i18n` | DONE |
| `output_path` | `lib/i18n/translations.g.dart` | DONE |
| `class_name` | `Translations` | DONE |
| `warn_on_missing_messages` / `warn_on_orphan_messages` | `true` | DONE |
| `locale_enum_name` | `AppLocale` | DONE |
| `bundle_ftl` | `false` | DONE |

## Locale enum + negotiation

Pure Dart — no UI framework. Locale SWITCHING (context plumbing,
widget rebuild) stays fluent_flutter territory; parsing and picking a
locale does not.

| Feature | Status |
|---|:---:|
| One enum value per discovered locale (`AppLocale.en`, `.zhHansCn`), tags sorted for deterministic output | DONE |
| `languageTag` + the `base` constant (the generator's `base_locale`) | DONE |
| `tryParse` (case-insensitive) | DONE |
| `negotiate` — exact → truncated subtags → language-prefix → fallback/base | DONE |
| `locale_enum_name` config (default `AppLocale`) | DONE |

## Bundled FTL (opt-in)

`bundle_ftl: true` embeds every locale's FTL source in the generated
file — no asset pipeline, no async load, and (unlike assets) hot
reload picks translation edits up through `build_runner watch`.
Default stays OFF: runtime asset loading keeps translations updatable
without an app rebuild (OTA).

| Feature | Status |
|---|:---:|
| `ftlSources` per enum value (escaped-safe for any FTL content) | DONE |
| `load({backend})` — a ready `FluentBundle` per locale | DONE |
| Off by default; zero output change when off | DONE |

## Unused-message check (test-time)

`package:fluent_gen/testing.dart` — the dead-translation check runs
inside the CONSUMER's own test suite (no CLI). Source-scan heuristic,
same trade slang's analyze makes; the generated `accessorNames`
manifest feeds it.

| Feature | Status |
|---|:---:|
| `accessorNames` manifest on the generated class (collision-guarded) | DONE |
| `unusedFluentAccessors` — scan, AsSpans folding, excludes | DONE |

---

## Won't do

| Capability | Reason |
|---|---|
| Dynamic-id dispatch | `bundle.formatMessage` is the right tool for runtime-only ids; the generator types by name. |
| Flutter-specific accessors | Stays pure Dart (CLI, server-side i18n). Mapping the `*AsSpans` tree to `InlineSpan`s is the `fluent_flutter` satellite's territory (its `TypedFluentDelegate` serves generated classes with chain fallback). |
| Locale SWITCHING (context plumbing, reactive rebuild) | The `fluent_flutter` satellite's job. The pure-Dart half — the locale enum + negotiation — shipped here (see above). |
| Custom-function ARG typing beyond `Object?` | A function's return type never touches signatures (everything renders to a string), and the argument's type is already pinnable with the comment convention (`# $x (String)`). Nothing left to build. |
| ICU MessageFormat / ARB / gettext migration | Wrong HOME, not a dead idea: Mozilla's own precedent is a separate tool (fluent-migrate), and an ARB→FTL one-shot converter is a real adoption funnel for Flutter apps. Belongs in a future standalone `fluent_migrate`, never inside this build_runner package (fluent_flutter's won't-do list rejects it too). |

---

## The one-line summary

> **A build-time generator that turns `.ftl` into one typed accessor
> class plus a locale enum with negotiation — and, opt-in, the FTL
> embedded so `AppLocale.load()` needs no asset pipeline. Types
> inferred from usage — transitive, per-pattern, with comment pins.
> Dead translations fail a consumer test via the `accessorNames`
> manifest + `fluent_gen/testing.dart`. The generated file always
> compiles and analyzes clean. Base-locale parse errors fail the
> build; every other drift is a warning. Reactive locale switching +
> Flutter wiring stay the future satellite's job.**
