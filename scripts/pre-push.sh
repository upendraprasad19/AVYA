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
#     payment, migrations, CLAUDE.md, ...) -> RUN the full suite locally,
#     EXCEPT on a BRANCH push (2026-10-10, OI-275): a push whose every ref is a
#     `refs/heads/<x>` branch other than main/develop skips the ~39-minute
#     local suite, because the PR's CI runs the same suite in ~13 minutes and
#     scripts/safe_pr_merge.sh refuses to merge a PR that is not green. A push
#     that only DELETES such branches lands nothing and skips too. main/develop,
#     tags, mixed pushes, malformed or empty stdin, an unknown tier and
#     PRE_PUSH_FULL=1 all keep the full suite (see push_class below).
#     The golden-image tests are NOT in either suite (both pass
#     `--exclude-tags golden`); they run only under PRE_COMMIT_FULL=1 or by hand.
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

# Resolve the Dart binary ONCE -- `flutter/bin/dart` is a wrapper that takes
# the SDK update lock and shells out to git on EVERY call (~4.0s vs ~0.3s for
# the SDK exe, measured). See scripts/_dart_bin.sh. Falls back to `dart`.
if [ -r "$REPO_ROOT/scripts/_dart_bin.sh" ] && sh -n "$REPO_ROOT/scripts/_dart_bin.sh" 2>/dev/null; then
  . "$REPO_ROOT/scripts/_dart_bin.sh" || true
  DART_BIN="$(resolve_dart_bin)" 2>/dev/null || DART_BIN="dart"
else
  # Guarded, and the guard is load-bearing: this file runs under `set -e`, so an
  # unguarded `.` of a missing file ABORTS the hook outright. `_dart_bin.sh`.s
  # own contract is "never wedge a hook", and sourcing it must honour that too.
  #
  # `[ -r ]` covers ABSENT. It does NOT cover CORRUPT: a truncated or
  # syntactically broken helper passes the readable test and then dies inside
  # `set -e`, wedging commit, push, merge AND commit-msg at once. Review round 1
  # (2026-08-17) reproduced it -- a stray paren in the helper made a merge exit 1
  # with `syntax error near unexpected token`.
  #
  # `. file || true` DOES NOT FIX THAT, and was tried first: POSIX requires a
  # non-interactive shell to ABORT on a syntax error in a dotted script, so the
  # `||` never runs. Verified -- it still exited 2. The working guard is a parse
  # check BEFORE sourcing (`sh -n`), which reads the file without executing it;
  # the `|| true` and the `|| DART_BIN="dart"` below then cover the remaining
  # runtime failures. Corrupt now falls back to a bare `dart` and the hook runs.
  # Caught by test/scripts/pre_push_analyze_always_e2e_test.dart, which builds a
  # temp repo holding only the hook script -- the same shape as a partial
  # checkout or a hook copied somewhere without its helper.
  DART_BIN="dart"
fi

# Same git-hook env leak the pre-commit hook guards against — see the long
# comment on the `flutter()` wrapper in scripts/pre-commit.sh. GIT_DIR overrides
# `git -C`, so flutter reading its own version out of $FLUTTER_ROOT gets THIS
# repo instead and concludes the SDK is unavailable. Scoped to flutter only:
# blast_radius_from_diff.dart below needs the real git env.
flutter() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE flutter "$@"
}

# Pre-push receives ref updates on stdin (`<local ref> <local sha> <remote ref>
# <remote sha>`, one line per ref). Capture them (this used to be drained with
# `cat > /dev/null`) so the push can be classified below -- see push_class. An
# empty or unreadable stdin classifies OTHER, i.e. the fail-safe full suite.
PUSH_REFS=$(cat)

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

# Targeted SoT contract sweep (OI-220) -- runs for EVERY tier, above the full
# suite, so a contract regression surfaces in ~2 min instead of after a full
# run. `--warn-only || true` is the §4.11 baseline: the flip to hard-fail
# (after one clean batch) removes BOTH tokens. The Dart runner owns the
# `flutter test` spawn -- a literal `flutter test` on this line would be
# pinned to CI's invocation by test/scripts/pre_push_matches_ci_invocation_test.dart.
# Guards: CONTRACT_SWEEP_SKIP=1 / CONTRACT_SWEEP_NESTED=1 (see the runner header).
echo "[pre-push] contract sweep (targeted SoT contract tests, warn-only baseline)..."
"$DART_BIN" run scripts/contract_sweep.dart --warn-only || true

# The local full suite MUST be invoked the same way CI invokes it, or this gate
# blocks pushes CI would have passed — which is worse than not gating, because
# the only way past a false red is `--no-verify`, and that disables the REAL
# gates too.
#
# CI is .github/workflows/test.yml: `TZ: Asia/Kolkata` at workflow level (:28)
# and `flutter test test/ --exclude-tags golden` (:112). This ran a bare
# `flutter test`, diverging on BOTH:
#
#   - No TZ. Several date-boundary contracts assert IST behaviour and read the
#     ambient zone; under UTC they fail. Measured 2026-08-20 on a container:
#     logout_login_round_trip_test.dart and
#     session_date_and_home_start_behavioral_test.dart failed bare and passed
#     24/24 under TZ=Asia/Kolkata, same commit, same machine.
#   - No `--exclude-tags golden`. The goldens are rendered on Windows; on any
#     other platform they fail on font rasterisation, which is why CI excludes
#     the TAG. (Not a path exclusion — bare `flutter test` already defaults to
#     `test/`, so the SCOPE never diverged. `test/` is passed explicitly anyway
#     to mirror CI literally rather than rely on that default.)
#
# Both are environment mismatches, never code defects, so a developer meeting
# them learns that this gate lies — the failure mode that makes a gate worse
# than useless. Pinned by test/scripts/pre_push_matches_ci_invocation_test.dart,
# which parses BOTH files and compares them, so a future edit to either side
# reddens rather than silently re-opening the gap.
run_full_suite() {
  echo "[pre-push] $1 -> flutter test (full suite, CI-equivalent invocation)..."
  TZ=Asia/Kolkata flutter test test/ --exclude-tags golden
  echo "[pre-push] OK -- full suite green."
  exit 0
}

# Classify what is being pushed from the stdin captured above. Prints one word:
#   BRANCH_ONLY  >= 1 line, every line is a well-formed 4-field update or delete
#                of a `refs/heads/<x>` branch that is NOT main/develop.
#   DELETE_ONLY  as BRANCH_ONLY but every line deletes (all-zero local sha):
#                nothing lands, so there is nothing to test.
#   OTHER        everything else -- main/develop, tags, notes, mixed with any
#                of those, a malformed line, or empty stdin. OTHER is the
#                fail-safe: it keeps the full-suite behaviour exactly as before.
# awk reads the WHOLE string and prints a verdict; a `while read` after a pipe
# would lose its variables in the pipe's subshell.
push_class() {
  printf '%s\n' "$PUSH_REFS" | awk '
    NF == 0 { next }
    { n++ }
    NF != 4 { bad = 1; next }
    $3 !~ /^refs\/heads\// || $3 == "refs/heads/main" || $3 == "refs/heads/develop" { other = 1; next }
    $2 ~ /^0+$/ { del++; next }
    { upd++ }
    END {
      if (n == 0 || bad || other) { print "OTHER"; exit }
      if (upd == 0 && del > 0) { print "DELETE_ONLY"; exit }
      print "BRANCH_ONLY"
    }'
}
PUSH_CLASS=$(push_class)

# Explicit override: always run the full suite.
if [ "${PRE_PUSH_FULL:-0}" = "1" ]; then
  run_full_suite "PRE_PUSH_FULL=1"
fi

# A push that only deletes non-main/develop branches lands no code. It sits
# BEFORE the origin/main and empty-range fail-safes on purpose: a deletion
# leaves the pushed range empty, which those guards read as "cannot tell" and
# answer with the full suite (e.g. `mint_oi.sh --prune`).
if [ "$PUSH_CLASS" = "DELETE_ONLY" ]; then
  echo "[pre-push] delete-only branch push -- nothing lands; analyze passed; skipping local full suite."
  exit 0
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
  | "$DART_BIN" run scripts/blast_radius_from_diff.dart - 2>/dev/null \
  | grep -oE 'Blast-radius: (feature|account|platform|catastrophic)' \
  | tail -1 | awk '{print $2}' || true)

if [ "$TIER" = "feature" ]; then
  echo "[pre-push] blast-radius=feature (low-risk) -- analyze passed; skipping local full suite."
  echo "[pre-push] (this branch gets CI only if it has an OPEN PR; otherwise the suite next runs"
  echo "[pre-push]  on the push to main. See the CORRECTION note at the top of this file.)"
  echo "[pre-push] (force locally with: PRE_PUSH_FULL=1 git push)"
  exit 0
fi

# A BRANCH push (never main/develop, tag, or anything malformed) at a risky tier
# no longer runs the ~39-minute local suite: CI runs the same suite on the open
# PR (~13 min), and scripts/safe_pr_merge.sh refuses to merge a PR whose
# required jobs are not all green. Only a KNOWN tier skips -- an empty or
# unrecognised TIER still falls through to the suite (never skip on
# uncertainty). main/develop pushes, tags, mixed pushes and PRE_PUSH_FULL=1 keep
# the full suite (OI-275, docs/plans/2026-10-10-release-cycle-speedup.md).
if [ "$PUSH_CLASS" = "BRANCH_ONLY" ]; then
  case "$TIER" in
    account|platform|catastrophic)
      echo "[pre-push] blast-radius=$TIER on a branch push -- analyze passed; skipping the local full suite."
      echo "[pre-push] CI on the open PR is the full-suite gate: open the PR now, and merge it with"
      echo "[pre-push]   sh scripts/safe_pr_merge.sh <pr>   (refuses unless the required jobs are green)."
      echo "[pre-push] NOTE: CI runs ONLY for a PR into main/develop. Until that PR exists NO test suite has run"
      echo "[pre-push] anywhere for this branch -- only analyze (the old hook ran the suite here)."
      echo "[pre-push] (force the local suite with: PRE_PUSH_FULL=1 git push)"
      exit 0
      ;;
  esac
fi

run_full_suite "blast-radius=${TIER:-unknown}"
