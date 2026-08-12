#!/bin/sh
# AVYA pre-push gate — unconditional analyze + blast-radius-tiered full suite.
#
# TWO parts, and the distinction between them is the whole design:
#
# 1. `flutter analyze` runs UNCONDITIONALLY, above every tier check and early
#    exit (2026-08-11). It moved here from pre-commit, where it cost 212s on
#    EVERY commit; here it costs 212s once per batch. Its placement is
#    load-bearing — see the comment block on the call itself.
#
# 2. The full `flutter test` suite stays blast-radius-tiered exactly as the
#    lean-workflow batch (2026-06-01) left it. It used to run on EVERY push,
#    duplicating CI even for docs/data-only pushes. It runs locally only when
#    the pushed change is risky enough to warrant a gate BEFORE it leaves the
#    machine:
#
#   - blast-radius `feature` (docs, scripts, .claude, backups, profile-only UI)
#     -> SKIP the local full suite.
#   - `account` / `platform` / `catastrophic` (auth, ai_coach, sync, ai-proxy,
#     payment, migrations, CLAUDE.md, ...) -> RUN the full suite locally.
#
# CORRECTION (2026-08-11): this header used to justify the `feature` skip with
# "CI runs it ~2 min after push (the backstop)". That is true only for a push to
# main, or for a branch with an OPEN PR. .github/workflows/test.yml triggers on
# `push: [main, develop]` AND `pull_request: [main, develop]`. Counted live:
# `git ls-remote --heads origin` = 29 refs (28 non-main), of which 8 have an
# open PR and therefore DO get CI on every push via `synchronize`; the other ~20
# — including most `claude/*` working branches — get none.
#   (An earlier draft of this comment said "42 branches, none of which run any
#   CI". Both halves were wrong: 42 is the count of remote-TRACKING refs from
#   `git branch -r`, which includes origin/main and refs already deleted
#   upstream, and the PR trigger was missed entirely. Same input-set-width trap
#   as memory/feedback_green_check_input_set_width.md. The conclusion survives —
#   a PR-less branch push genuinely has no remote backstop — but the number and
#   the "none" did not, so they are corrected rather than quietly dropped.)
# That PR-less majority is why part 1 above is unconditional rather than tiered.
#
# Note this means analyze also runs on pushes that cannot benefit (a tag-only
# push, or `git push --delete`). That is accepted deliberately: any predicate
# narrow enough to skip those re-introduces a skip path above the call, which is
# the exact failure mode part 1 exists to prevent. Do not "fix" it.
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

# UNCONDITIONAL analyze (2026-08-11). PLACEMENT IS THE POINT: this must stay
# ABOVE the PRE_PUSH_FULL early-return, above the origin/main + empty-range
# fail-safes, and above the `feature`-tier skip. Every one of those paths ends
# in `exit 0` (directly or via run_full_suite), so an analyze placed below any
# of them is a silent no-op on exactly the pushes that have no other check:
# a feature-tier branch push skips the suite here AND triggers no CI (see the
# CORRECTION note in the header). This is the only compile check such a push
# gets anywhere.
#
# Cost: 212s, paid once per batch rather than once per commit — that trade is
# the entire reason it moved off pre-commit. Pinned by
# test/contracts/hook_gate_placement_test.dart (ordering) and
# test/scripts/pre_push_analyze_always_e2e_test.dart (behaviour).
echo "[pre-push] flutter analyze (always -- runs even when the suite is skipped)..."
flutter analyze --no-fatal-infos

run_full_suite() {
  echo "[pre-push] $1 -> flutter test (full suite)..."
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
  echo "[pre-push] blast-radius=feature (low-risk) -- analyze passed; skipping local full suite."
  echo "[pre-push] (this branch gets CI only if it has an OPEN PR; otherwise the suite next runs"
  echo "[pre-push]  on the push to main. See the CORRECTION note at the top of this file.)"
  echo "[pre-push] (force locally with: PRE_PUSH_FULL=1 git push)"
  exit 0
fi

run_full_suite "blast-radius=${TIER:-unknown}"
