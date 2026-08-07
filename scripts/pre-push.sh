#!/bin/sh
# AVYA pre-push gate — blast-radius-tiered full-suite run.
#
# Lean-workflow batch (2026-06-01): the full `flutter test` (~7 min) used to run
# on EVERY push, duplicating CI (which runs it again) even for docs/data-only
# pushes. Now it runs locally only when the pushed change is risky enough to
# warrant a gate BEFORE it leaves the machine:
#
#   - blast-radius `feature` (docs, scripts, .claude, backups, profile-only UI)
#     -> SKIP the local full suite; CI runs it ~2 min after push (the backstop).
#   - `account` / `platform` / `catastrophic` (auth, ai_coach, sync, ai-proxy,
#     payment, migrations, CLAUDE.md, ...) -> RUN the full suite locally.
#
# Tier comes from scripts/blast_radius_from_diff.dart over the pushed range
# (origin/main..HEAD). FAIL-SAFE: if the range or tier can't be computed, we RUN
# the full suite (never skip on uncertainty). Force it any time with
# PRE_PUSH_FULL=1. CI is the full-suite source-of-truth regardless.
#
# Audit 2026-05-20 / I10 introduced the pre-commit(fast)/pre-push(full) split;
# this batch makes pre-push itself risk-aware. Install: `sh scripts/setup-hooks.sh`.
# Bypass: `git push --no-verify` (sparingly; CI catches anyway).

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Same git-hook env leak the pre-commit hook guards against — see the long
# comment on the `flutter()` wrapper in scripts/pre-commit.sh. GIT_DIR overrides
# `git -C`, so flutter reading its own version out of $FLUTTER_ROOT gets THIS
# repo instead and concludes the SDK is unavailable. Scoped to flutter only:
# blast_radius_from_diff.dart below needs the real git env.
flutter() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE flutter "$@"
}

# Pre-push receives ref updates on stdin; consume so we don't break the protocol.
cat > /dev/null

run_full_suite() {
  echo "[pre-push] $1 -> flutter test (full suite, ~7 min)..."
  flutter test
  echo "[pre-push] OK -- full suite green."
  exit 0
}

# Explicit override: always run the full suite.
if [ "${PRE_PUSH_FULL:-0}" = "1" ]; then
  run_full_suite "PRE_PUSH_FULL=1"
fi

# Fail-safe: need origin/main to compute the pushed range.
if ! git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  run_full_suite "origin/main unknown -- fail-safe"
fi

# Files in the pushed range. Empty -> fail-safe.
RANGE_FILES=$(git diff origin/main..HEAD --name-only 2>/dev/null || true)
if [ -z "$RANGE_FILES" ]; then
  run_full_suite "empty/undetermined push range -- fail-safe"
fi

# Max blast-radius tier across the pushed files. Reuse the preamble-tolerant
# extraction from prepare-commit-msg.sh:41-43 -- `dart run` prepends a
# "Running build hooks..." preamble with no trailing newline, so match the token
# anywhere on the line (-oE), never anchored. A dart failure / no match leaves
# TIER empty -> fail-safe runs the suite.
TIER=$(printf '%s\n' "$RANGE_FILES" \
  | dart run scripts/blast_radius_from_diff.dart - 2>/dev/null \
  | grep -oE 'Blast-radius: (feature|account|platform|catastrophic)' \
  | tail -1 | awk '{print $2}' || true)

if [ "$TIER" = "feature" ]; then
  echo "[pre-push] blast-radius=feature (low-risk) -- skipping local full suite; CI will run it."
  echo "[pre-push] (force locally with: PRE_PUSH_FULL=1 git push)"
  exit 0
fi

run_full_suite "blast-radius=${TIER:-unknown}"
