<h1 align="center">fluent_gen</h1>

<p align="center">
  <a href="https://pub.dev/packages/fluent_gen"><img src="https://img.shields.io/pub/v/fluent_gen.svg" alt="pub package"></a>
  <a href="https://pub.dev/packages/fluent_gen/score"><img src="https://img.shields.io/pub/likes/fluent_gen" alt="likes"></a>
  <a href="https://pub.dev/packages/fluent_gen/score"><img src="https://img.shields.io/pub/points/fluent_gen" alt="pub points"></a>
  <a href="https://github.com/whuppi/fluent_gen"><img src="https://img.shields.io/github/stars/whuppi/fluent_bundle?style=flat&logo=github" alt="GitHub stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="license: MIT"></a>
</p>

The compile-time half of [`fluent_bundle`](https://pub.dev/packages/fluent_bundle). It reads your `.ftl` files at build time, infers each message's parameter types from how the arguments are actually used, and emits one typed accessor class plus a locale enum — so a typo'd message id, a missing argument, or a `String` where a plural wants a `num` is an analyzer error, not a runtime surprise.

```dart
bundle.formatMessage('welcom', args: {'nam': 'Aria'});   // runs, silently wrong
messages.welcome(name: 'Aria');                          // the typo can't compile
```

Ships only as a `dev_dependency` — nothing from this package ends up in your app; the generated file depends on `fluent_bundle` alone.

> **This is the compile-time add-on, not a starting point.** Flutter apps start at [`fluent_flutter`](https://pub.dev/packages/fluent_flutter); pure Dart starts at [`fluent_bundle`](https://pub.dev/packages/fluent_bundle). Add this when you want message ids and arguments checked by the analyzer.

> like it? a [⭐ star](https://github.com/whuppi/fluent_gen) or [👍 like](https://pub.dev/packages/fluent_gen) is the entire marketing budget. [Bugs & features →](https://github.com/whuppi/fluent_gen/issues)

---

<details>
<summary><b>👀 Peek inside</b></summary>

- [Install](#install)
- [Quick start](#quick-start)
- [Type inference](#type-inference)
- [Usage](#usage)
  - [The locale enum](#the-locale-enum)
  - [Attributes](#attributes)
  - [Markup](#markup)
  - [Reserved words and transitive references](#reserved-words-and-transitive-references)
  - [Errors at runtime](#errors-at-runtime)
- [Build-time diagnostics](#build-time-diagnostics)
- [Platform support](#platform-support)
- [Not in the box](#not-in-the-box)
- [Docs](#docs)
- [License](#license)

</details>

---

## Install

```yaml
dev_dependencies:
  fluent_gen:
  build_runner:
```

Configure it in `build.yaml` — the builder activates automatically once it's in dev_dependencies, but the options have no project-agnostic defaults, so `base_locale` at minimum is yours to state:

```yaml
targets:
  $default:
    builders:
      fluent_gen|fluent_gen:
        options:
          base_locale: en                          # the locale that defines the message set
          ftl_dir: lib/i18n                        # where the .ftl files live
          class_name: AppMessages                  # the generated accessor class
          output_path: lib/i18n/app_messages.g.dart
```

<details>
<summary><b>🧰 every builder option</b></summary>

<br>

| Option | Default | What it does |
|---|---|---|
| `base_locale` | (required) | The locale whose `.ftl` defines the canonical message set; every accessor and diagnostic is derived from it |
| `ftl_dir` | `lib/i18n` | Directory walked for FTL — either per-file (`en.ftl`) or per-directory (`en/messages.ftl`) layout; discovery detects which |
| `class_name` | `Translations` | Name of the generated accessor class |
| `locale_enum_name` | `AppLocale` | Name of the generated locale enum |
| `output_path` | `{ftl_dir}/translations.g.dart` | Where the generated file lands |
| `bundle_ftl` | `false` | Embed the FTL sources into the generated file so `AppLocale.load()` needs no asset pipeline — the pure-Dart / CLI lane. Flutter apps usually leave this off and load FTL as assets via [`fluent_flutter`](https://pub.dev/packages/fluent_flutter) |
| `warn_on_missing_messages` | `true` | Warn when a non-base locale is missing a base message |
| `warn_on_orphan_messages` | `true` | Warn when a locale carries a message the base doesn't |

</details>

Then generate — and regenerate whenever the FTL changes:

```sh
dart run build_runner build
```

---

## Quick start

Write FTL; call Dart. Given `lib/i18n/en.ftl`:

```ftl
welcome = Hello, { $name }!
items = You have { $count ->
    [one] one new message
   *[other] { $count } new messages
}.
```

the generated file gives you this:

```dart
import 'package:fluent_intl/fluent_intl.dart';
import 'i18n/app_messages.g.dart';

// The generated enum knows every locale you ship and builds ready bundles:
final messages = AppMessages(AppLocale.en.load(backend: IntlBackend()));

messages.welcome(name: 'Aria');   // "Hello, Aria!"
messages.items(count: 1);         // "You have one new message."
messages.items(count: 5);         // "You have 5 new messages."
```

`welcome(name:)` and `items(count:)` are real methods with real types. Rename a message, drop an argument, change a selector — the analyzer walks you to every call site that needs updating.

---

## Type inference

There are no annotations to write. The generator reads how each `$variable` is used across the message (and everything it references) and picks the narrowest safe Dart type:

| The variable is used… | Inferred type | Example |
|---|---|---|
| as a plural selector | `num` | `{ $count -> [one] … }` → `items({required num count})` |
| inside `NUMBER(...)` | `num` | `{ NUMBER($amount) }` → `price({required num amount})` |
| inside `DATETIME(...)` | `DateTime` | `{ DATETIME($d) }` → `launchedAt({required DateTime d})` |
| as a string-keyed selector | `String` | `{ $platform -> [ios] … }` → `device({required String platform})` |
| as text only | `Object?` | anything formats — numbers, dates, strings |
| as text only, with a comment pin | the pinned type | `# $name (String)` above the message → `String` |

The comment pin is the escape hatch for text-only variables you want narrowed anyway — it lives in the FTL comment, where the translator can see it too:

```ftl
# $name (String) - the person to greet.
welcome = Hello, { $name }!
```

Conflicting usage (the same variable as a plural selector *and* a `DATETIME` argument) is a build-time error naming the message — not a quiet `Object?`.

---

## Usage

Highlights below; the [example fixture](example/) exercises every emitted shape end to end, through the real `build_runner`, with its output pinned by test.

### The locale enum

One enum member per `.ftl` file found, with parsing, negotiation, and loading built in:

```dart
AppLocale.values.map((l) => l.languageTag);   // en, fr
AppLocale.base;                               // AppLocale.en — the base_locale

AppLocale.tryParse('FR');                     // AppLocale.fr (case-insensitive)
AppLocale.tryParse('nope');                   // null

// Exact tag → truncated subtags → language prefix → base. Same ladder
// as fluent_bundle's negotiateLocale, so the whole family agrees:
AppLocale.negotiate('fr-CA');                 // AppLocale.fr
AppLocale.negotiate('ja-JP');                 // AppLocale.en

// With bundle_ftl: true, load() builds a ready bundle from the embedded
// FTL — you pick the backend, the generator never does:
final messages = AppMessages(AppLocale.fr.load(backend: IntlBackend()));
messages.hello();                             // "Salut"
```

### Attributes

Each attribute emits its own method — named `message$attribute` — demanding only its *own* pattern's variables:

```ftl
login = Sign in
    .title = Welcome back
    .helper = Tap to continue, { $name }
```

```dart
messages.login();                       // "Sign in"
messages.login$title();                 // "Welcome back"
messages.login$helper(name: 'Aria');    // "Tap to continue, Aria"
```

### Markup

A message with inline tags gets an `AsSpans` sibling returning the walkable tree from `package:fluent_bundle/markup.dart` — same types, typed arguments:

```ftl
banner = Read <bold>{ $title }</bold> on our blog.
```

```dart
messages.banner(title: 'Pro');          // "Read <bold>Pro</bold> on our blog."
messages.bannerAsSpans(title: 'Pro');   // [text, bold(text), text] — for styled rendering
```

### Reserved words and transitive references

Two things the generator handles so you never think about them:

```ftl
greeting = Hi again, { $name }
welcomeBack = { greeting } — last seen { DATETIME($when, dateStyle: "short") }
```

```dart
// welcomeBack references greeting, so it inherits greeting's variables —
// the generated method demands BOTH, and `when` (a Dart keyword) is
// escaped to `$when` while the FTL argument name stays untouched:
messages.welcomeBack(name: 'Aria', $when: DateTime(2026, 1, 15));
// "Hi again, Aria — last seen 1/15/2026"
```

### Errors at runtime

Every accessor takes the standard `fluent_bundle` out-list — formatting never throws, problems land in the caller's list:

```dart
final errors = <FluentError>[];
messages.welcome(name: 'Aria', errors: errors);   // errors stays empty
```

A locale that's missing a message still formats (the bundle reports the miss into `errors`) — and the builder already told you about that gap at generation time, which is the better place to hear it.

---

## Build-time diagnostics

The generator is also the family's linter. During `build_runner`:

- **A non-base locale missing a message** the base locale has → a warning naming the locale and the id.
- **An orphan message** (present in a locale, absent from the base — so no accessor exists for it) → a warning; the base locale is the contract.
- **Malformed FTL** → the parse error with its source span, pointing at the file and line.
- **Conflicting type evidence** for a variable → an error naming the message and both usages.

Your translations get reviewed by the build pipeline on every generate, not by whoever happens to click through every screen in every language.

---

## Platform support

Two different questions, two different answers — both good:

| What | Runs on |
|---|---|
| **The generated code + `fluent_bundle`** (what ships in your app) | Android, iOS, macOS, Windows, Linux, **web** — everything |
| **The generator itself** (a `build_runner` dev-tool) | your dev machine and CI: macOS, Linux, Windows |

The generator is a build-time tool that reads files from disk, so like `build_runner`, `json_serializable`, and every other Dart generator, it isn't a web *runtime* — and never needs to be. Nothing from `fluent_gen` is in your compiled app.

---

## Not in the box

- **Runtime message loading strategy.** The generated `load()` covers the embedded-FTL lane; asset-based loading, locale lifecycle, and hot reload in a Flutter app are [`fluent_flutter`](https://pub.dev/packages/fluent_flutter)'s job — its `TypedFluentDelegate` hands your generated class the right bundle chain per locale.
- **Backend choice.** `load(backend: …)` makes you pick — the generator never bakes a formatting engine into your app. See [the backend seam](https://pub.dev/packages/fluent_bundle#the-backend-seam).
- **Translation management.** Extraction to translator platforms, ARB interop, machine translation — different jobs. The `.ftl` files are plain text in your repo; the generator reads them, it doesn't manage them.

---

## Docs

The README covers the everyday stuff. wanna go deeper?

| Doc | What's inside |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | How it's built: discovery, inference, emission, the builder pipeline |
| [Capabilities](docs/CAPABILITY_ROADMAP.md) | What's shipped, what's planned, what won't happen |
| [Updating](docs/UPDATING.md) | Maintenance recipes: goldens, the emitter contract, upstream watchlist |
| [Example](example/) | A real consumer fixture: FTL in, generated file committed, suite pinned |

---

## License

MIT. See [LICENSE](LICENSE).
