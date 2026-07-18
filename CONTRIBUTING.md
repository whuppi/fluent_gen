# Contributing

Contributions are welcome.

---

## Setup

```bash
git clone https://github.com/whuppi/fluent_gen.git
cd fluent_gen
make hooks               # activates commit-msg + pre-commit (run once)
fvm install              # downloads the SDK version pinned in .fvmrc
fvm dart pub get

cd example && fvm dart pub get && cd ..
fvm dart test
```

**Requires:** [FVM](https://fvm.app) (`.fvmrc` pins the exact SDK
version).

**Without FVM:** all Makefile commands accept `DART` and `FLUTTER`
overrides:

```bash
make check DART=dart FLUTTER=flutter
```

---

## Before submitting a PR

```bash
make check
```

Runs `lint-shell` + `analyze` (package + example fixture, each from
its own root) + `analyze-floor` + `platforms` (the same pana pub.dev
runs; native-only expectation) + `test` (inference, emission goldens,
builder pipeline) + `test-example` (the consumer fixture through the
real build_runner).
Must pass. Don't suppress with `// ignore:` — fix the underlying
issue.

---

## PR workflow

All PRs target `dev`. That's the only branch contributors touch.

```
your fork / feature branch ──PR──► dev
                                    ↓ CI: make targets via the make-target action
                                    ↓ PR title: Conventional Commits (feat: / fix: / etc.)
                                    ↓ squash-merge when green
                                    ↓ Full test suite via "ready-to-test" label
                                      (suites × OS matrix)
```

CI calls Makefile targets — same commands locally and in CI.

You don't write changelog entries, bump versions, or touch `prod`.
The maintainer handles releases.

---

## Code style

- Match existing code in the repo.
- Emitter output changes go through `make goldens` — regenerate, then
  READ EVERY LINE of the diff; one unintended change is a bug for every
  consumer. Commit the regenerated goldens with the emitter change.
- The example fixture's generated file is COMMITTED source — regenerate
  it (`cd example && dart run build_runner build`) whenever the emitter
  or the fixture FTL changes.
- New inference evidence kinds are build-time errors on conflict, never
  a quiet `Object?`.

---

## Maintenance recipes

Step-by-step recipes (goldens, the emitter contract) live in
[`docs/UPDATING.md`](docs/UPDATING.md).

---

## Releases

Handled by the maintainer, via the family release checklist
(the fluent_bundle repo's `docs/UPDATING.md`).
