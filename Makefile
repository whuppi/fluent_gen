.PHONY: check hooks lint-shell analyze analyze-floor platforms format test test-example clean

# ═══════════════════════════════════════════════════════════════════
# SDK resolution
#
# Uses fvm by default. Contributors without fvm can override:
# make check DART=dart
# fluent_gen is pure Dart, VM-only — a build_runner code generator, not
# a browser runtime, so there is no web lane. example/ is its own
# package (the consumer fixture that runs the Builder through
# build_runner); it resolves, generates, and tests from its OWN root so
# its generated output and language version are its own.
# ═══════════════════════════════════════════════════════════════════

DART    ?= fvm dart
# analyze_core.sh requires FLUTTER even in pure-Dart packages (it
# analyzes a Flutter example when one exists; ours are bare files).
FLUTTER ?= fvm flutter
TEST_RESULTS_DIR ?= test-results
TIMEOUT := $(if $(CI),--timeout=30x,)
VERBOSE := $(if $(CI),--verbose,)

# ═══════════════════════════════════════════════════════════════════
# § 1 — Gate
# ═══════════════════════════════════════════════════════════════════
#
# make check    Full local gate before handing work over.

check: lint-shell analyze analyze-floor test test-example

# make hooks    Activate the repo's git hooks (commit-msg, pre-commit).
#               Run once after cloning — they stay dormant otherwise.
#               Idempotent. The hooks live at the repo root
#               (.githooks/), stamped from the shared whuppi set.
hooks:
	@git config core.hooksPath .githooks
	@echo "✓ git hooks active (core.hooksPath → .githooks)"

# make lint-shell  Shell portability gate: shellcheck + a bash-version scan
#                  over the repo's shell scripts. Shared gate
#                  tool/lint_shell.sh (canonical in whuppi/ci, stamped).
lint-shell:
	@bash tool/lint_shell.sh


# make platforms  BLOCKED pre-release, deliberately not in `check`: pana
#                 snapshots the GIT REPO, and the fluent_bundle path dep lives
#                 in a sibling repo whose required version is not yet
#                 published. Activates when the family deps go hosted — the
#                 release checklist flips it into `check`.
#                 At release this gate expects native-only (no web) — the
#                 generator is a dart:io build_runner tool.
platforms:
	@echo "platforms gate is BLOCKED pre-release for fluent_gen:"
	@echo "  pana snapshots the git repo; ../fluent_bundle (a sibling repo whose"
	@echo "  required version is not yet published) can never resolve in it."
	@echo "  Activates at release when the family deps go hosted — see the"
	@echo "  family release checklist (fluent_bundle/docs/UPDATING.md §6)."
	@exit 2

# ═══════════════════════════════════════════════════════════════════
# § 2 — Analyze
# ═══════════════════════════════════════════════════════════════════
#
# make analyze  Resolve, format, analyze at --fatal-infos. Resolve runs
#               FIRST because `dart format` reads the resolved language
#               version — an unresolved tree formats differently.
#               Locally format fixes in place; under CI a diff fails.
#               example/ is excluded — it is its own package, gated by
#               its own generate-then-analyze e2e in `test-example`.

analyze:
	@echo "=== Dart: pub get ==="
	@$(DART) pub get
	@echo "=== Dart: format ==="
	@if [ -n "$$CI" ]; then \
	  $(DART) format --set-exit-if-changed lib test tool; \
	else \
	  $(DART) format lib test tool; \
	fi
	@echo "=== Dart: analyze (shared core) ==="
	@DART="$(DART)" FLUTTER="$(FLUTTER)" ANALYZE_DIRS="lib test tool" EXAMPLE_DIR="" bash tool/analyze_core.sh

# make analyze-floor  Resolve to the OLDEST in-range dependencies and
#                     analyze the shipped code (lib). The wide lower
#                     bounds are only honest if the code analyzes against
#                     them, not just the newest a fresh resolve picks.
#                     Tests are excluded on purpose — a consumer sees
#                     lib, never your tests. Snapshots and restores the
#                     lock so a local run leaves the tree clean.
analyze-floor:
	@$(DART) pub get >/dev/null
	@cp pubspec.lock pubspec.lock.floorbak; \
	$(DART) pub downgrade >/dev/null && $(DART) analyze --fatal-infos lib; rc=$$?; \
	mv pubspec.lock.floorbak pubspec.lock; \
	$(DART) pub get >/dev/null 2>&1 || true; \
	exit $$rc

# make format   Format in place (analyze also formats; this is the
#               standalone entry).
format:
	@$(DART) format lib test tool

# ═══════════════════════════════════════════════════════════════════
# § 3 — Test
# ═══════════════════════════════════════════════════════════════════
#
# make test     The full VM suite — inference, emission goldens,
#               builders, discovery, validation, config.

test:
	@echo "=== VM suite ==="
	@mkdir -p $(TEST_RESULTS_DIR)
	@$(DART) test $(TIMEOUT) --file-reporter json:$(TEST_RESULTS_DIR)/vm.json

# make test-example  The build_runner e2e — generate the fixture's typed
#                    class through the REAL Builder, then run the example's
#                    own suite over the generated output (smoke, showcase,
#                    locale enum, unused-message diagnostics, analyzes-clean).
#                    Regenerates in place, so a hand edit or a stale golden
#                    is caught on every gate run.
test-example:
	@echo "=== Example: build_runner e2e (generate then test) ==="
	@mkdir -p $(TEST_RESULTS_DIR)
	cd example && $(DART) pub get && \
	  $(DART) run build_runner build --delete-conflicting-outputs && \
	  $(DART) test $(TIMEOUT) --file-reporter json:../$(TEST_RESULTS_DIR)/example.json

# ═══════════════════════════════════════════════════════════════════
# § 4 — Clean
# ═══════════════════════════════════════════════════════════════════

clean:
	@rm -rf .dart_tool $(TEST_RESULTS_DIR)
	@echo "✓ clean"
