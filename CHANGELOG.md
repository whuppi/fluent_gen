# Changelog

<!--
═══════════════════════════════════════════════════════════════════════
CHANGELOG STANDARD — read before editing. Applies to both changelogs.
═══════════════════════════════════════════════════════════════════════
Two INDEPENDENT lane changelogs — do NOT mirror one from the other:
  • CHANGELOG.pre.md — the prerelease lane (`## X.Y.Z-dev.N`). Add an
    entry per prerelease you cut on dev.
  • CHANGELOG.md — the stable lane (`## X.Y.Z`). Add an entry per stable
    release, CONSOLIDATING the prerelease entries that ship under it.
They share prose but track their OWN version sequences. There is no
`cp + sed` regen: that mirror falsely assumed every prerelease becomes a
same-numbered stable, so it manufactured stable headings for versions
that never shipped — which the release tooling's `--check-versions` flags.
Hand-edit each lane's file directly.

ADDING A VERSION
  Add a heading at the TOP (newest first) of the right lane's file and
  write the summary. Exactly ONE new (untagged) version may sit at the
  top of each file — every heading BELOW it must already have its git tag
  (or a verified `release: no-tag` HTML-comment directive). `--check-versions`
  enforces this at PR + release time: a second un-released version is
  rejected, since it would collapse into the one release the merge cuts.
  Versions, commit lists, tags, publishing — the release tooling owns all
  of it; you only write the human summary.

ENTRY SHAPE
  ## X.Y.Z-dev.0
  <one-line prose lead — only to frame a big release or signal "no
   behavior change"; omit when the bullets speak for themselves>
  - **Breaking:** <what changed> → <migration step, INLINE>   ← always first
  - <upgrade action>                                          ← any required action next
  - Added/Changed <capability or improvement>                ← then improvements
  - Fixed <bug> ([#N](issue-url) reported by [@user](abs-url), [PR #N](abs-url))  ← fixes last

  Order IS the grouping — Breaking → action → added/changed → fixed. No
  `###` subsections: bullet order carries the categories. Only Breaking
  is bold-tagged; everything else is verb-led. Fixes start with "Fixed".

  EXCEPTION — the genesis entry (a ground-up build, no prior published
  version) uses facet tags instead of deltas: **API:** / **Platforms:** /
  etc., describing the new package's dimensions. See the 1.0.0-dev.0 entry.

CONTENT RULES (never change)
  • Migrate from the entry ALONE — breaking changes inline, old → new.
    (pub.dev freezes each version's CHANGELOG as a snapshot, so an entry
    can't rely on anything that later moves.)
  • NEVER link a living doc (README, docs/*) from an entry — it rots when
    the doc moves on.
  • Links point only at IMMUTABLE targets — a PR, commit, or issue:
    ([#N](https://github.com/whuppi/fluent_gen/issues/N) reported by
    [@user](https://github.com/user), [PR #N](https://github.com/whuppi/fluent_gen/pull/N)).
    Credit the issue + reporter when a reported issue drove the fix; the PR
    (or commit) link alone otherwise.
  • No capability inventories — "what's shipped" lives in README +
    docs/CAPABILITY_ROADMAP.md; the changelog says only what CHANGED.
═══════════════════════════════════════════════════════════════════════
-->

<!-- Add new versions below, newest first. -->

## 0.1.0

First release — typed Dart calls for fluent_bundle, generated from your `.ftl` files at build time.

- **What it does:** reads your `.ftl` files during `build_runner` and generates a Dart class — call `messages.welcome(name: ...)` instead of a string id.
- **Type safety:** a misspelled message name, a missing argument, or a `String` where a number belongs is a compile error. Argument types are worked out from how each variable is used — no annotations to write.
- **Also checks:** during the build it warns about messages missing from a language, stray messages, and malformed `.ftl`.
- **Footprint:** a dev-dependency only — nothing from it ships in your app.
