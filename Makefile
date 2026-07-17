.PHONY: check hooks lint-shell analyze analyze-floor platforms format test test-example goldens clean

# ═══════════════════════════════════════════════════════════════════
# SDK resolution
#
# Uses fvm by default. Contributors without fvm can override:
# make check DART=dart
# fluent_gen is pure Dart. example/ is its own package (the consumer
# fixture that runs the Builder through build_runner) — it resolves,
# formats, and analyzes from its OWN root so its generated output and
# language version are its own.
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
