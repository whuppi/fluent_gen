// fluent_gen showcase — the generated API end to end in one runnable file.
//
// Everything here calls `lib/i18n/app_messages.g.dart`, which fluent_gen
// emitted from `lib/i18n/*.ftl` (run `dart run build_runner build` to
// regenerate). The tour exercises every kind of thing the generator
// emits; `test/showcase_test.dart` runs it and pins the output.
//
// Run with: dart run fluent_gen_example:main  (or `dart run lib/main.dart`)

import 'package:fluent_bundle/markup.dart';
import 'package:fluent_gen_example/i18n/app_messages.g.dart';
import 'package:fluent_intl/fluent_intl.dart';

/// Every section of the tour, as `label: value` lines. The showcase test
/// asserts on these — keep labels stable.
List<String> runShowcase() => [
  ...localeEnumShowcase(),
  ...accessorShowcase(),
  ...markupAndAttributeShowcase(),
  ...errorShowcase(),
  ...fallbackShowcase(),
];

// ── §1 AppLocale — the generated locale enum + negotiation + loading ────

List<String> localeEnumShowcase() {
  // negotiate: exact tag → truncated subtags → language prefix → fallback.
  final ca = AppLocale.negotiate('fr-CA');
  final unknown = AppLocale.negotiate('ja-JP');
  return [
    'locale.values: ${AppLocale.values.map((l) => l.languageTag).join(',')}',
    'locale.base: ${AppLocale.base.languageTag}',
    'locale.tryParse: ${AppLocale.tryParse('FR')?.languageTag} / '
        '${AppLocale.tryParse('nope')}',
    'locale.negotiate: fr-CA→${ca.languageTag} ja-JP→${unknown.languageTag}',
    'locale.manifest: ${AppMessages.accessorNames.length} accessors',
  ];
}

/// The generated `load()` builds a ready bundle from the embedded FTL
/// (`bundle_ftl: true`); the backend decides CLDR fidelity.
AppMessages messagesFor(AppLocale locale) =>
    AppMessages(locale.load(backend: IntlBackend()));

// ── §2 Typed accessors — inferred parameter types, per-pattern params ──

List<String> accessorShowcase() {
  final en = messagesFor(AppLocale.en);
  final fr = messagesFor(AppLocale.fr);
  return [
    'msg.plain: ${en.hello()}',
    'msg.fr: ${fr.hello()}',
    // A comment pin (`# $name (String)`) narrows text-only usage.
    'msg.pinned: ${en.welcome(name: 'Aria')}',
    // $count drives a plural selector → num, CLDR category via backend.
    'msg.plural: ${en.items(count: 1)} / ${en.items(count: 5)}',
    // String-keyed selector → String.
    'msg.select: ${en.device(platform: 'mac')}',
    // NUMBER(...) usage → num; DATETIME(...) usage → DateTime.
    'msg.number: ${en.price(amount: 42)}',
    'msg.datetime: ${en.launchedAt(d: DateTime(2026, 1, 15))}',
    // Text-only usage with no pin stays Object? — anything formats.
    'msg.unpinned: ${en.greeting(name: 'Aria')}',
    // `when` is a Dart keyword → the parameter is escaped to `$when`;
    // the FTL argument name is unchanged. Also a transitive message
    // reference: welcomeBack pulls greeting's variables into its own.
    'msg.reserved: ${en.welcomeBack(name: 'Aria', $when: DateTime(2026, 1, 15))}',
  ];
}

// ── §3 Attributes + markup — per-attribute methods, span variants ──────

List<String> markupAndAttributeShowcase() {
  final en = messagesFor(AppLocale.en);
  final spans = en.bannerAsSpans(title: 'Pro');
  return [
    // Attributes emit their own methods, each demanding only its own
    // pattern's variables — login() needs nothing, login$helper() needs
    // $name.
    'attr.value: ${en.login()}',
    'attr.title: ${en.login$title()}',
    'attr.helper: ${en.login$helper(name: 'Aria')}',
    // Messages with inline markup also get an AsSpans sibling.
    'markup.flat: ${en.banner(title: 'Pro')}',
    'markup.spans: ${spans.map(_describe).join(' | ')}',
  ];
}

String _describe(FluentSpan span) => switch (span) {
  FluentTextSpan(:final text) => 'text(${text.trim()})',
  FluentMarkupSpan(:final tag, :final children) =>
    '$tag(${children.map(_describe).join(' ')})',
};

// ── §4 Errors — every accessor takes the standard out-list ─────────────

List<String> errorShowcase() {
  final en = messagesFor(AppLocale.en);
  final errors = <FluentError>[];
  // Formatting never throws; problems land in the caller's list.
  final out = en.welcome(name: 'Aria', errors: errors);
  return ['errors.clean: $out (${errors.length} errors)'];
}

// ── §5 Locale fallback — a locale missing a message falls back ─────────

List<String> fallbackShowcase() {
  // fr.ftl deliberately omits `device`; the generated accessor formats
  // through the fr bundle, which reports the miss — the builder already
  // warned about it at generation time. Apps that want silent base-locale
  // fallback chain bundles; the accessor surface is identical.
  final fr = messagesFor(AppLocale.fr);
  final errors = <FluentError>[];
  final out = fr.device(platform: 'mac', errors: errors);
  return ['fallback.missing: $out (${errors.length} error)'];
}

void main() => runShowcase().forEach(print);
