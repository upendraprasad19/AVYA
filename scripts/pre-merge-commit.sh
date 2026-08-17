#!/bin/sh
# AVYA pre-merge-commit gate — board integrity at the moment of the merge.
#
# WHY THIS HOOK EXISTS, and what was false without it
# ---------------------------------------------------
# `scripts/build_oi_index.dart:120-136` has a `duplicateIds()` check that fails
# closed when one OI number names two issues. Two places in the repo claimed it
# made board corruption unable to LAND:
#     docs/audit/open_issues.md:2426-2428  (OI-112)
#     docs/diagnoses/2026-08-13-oi-id-collision-renders-silently-b7e3d1.md:56-58
#   "a corrupt board can no longer render and cannot LAND — the merge commit
#    regenerates the index and the gate fires"
#
# It could not fire. Git invokes `pre-merge-commit` — NOT `pre-commit` — for an
# automatically-created merge commit, and only four hooks were installed
# (pre-commit, pre-push, commit-msg, prepare-commit-msg). On a CLEAN auto-merge
# NO hook ran at all, which is precisely the documented failure shape: the two
# sessions' board additions sat in different regions of the file and git
# combined them silently. A CONFLICTED merge was covered only incidentally,
# because the human then runs `git commit`, which does fire pre-commit.
#
# WHY IT IS NOT THE FULL pre-commit SUITE
# ---------------------------------------
# A merge needs cross-branch board integrity, not a re-scan of a tree that was
# already gated at every commit on BOTH sides. Running all 75 gates here would
# add ~145s to every merge for no new information. Measured cost of this hook:
# two dart invocations, ~2s. If you want the full suite at a merge, that is what
# `PRE_COMMIT_FULL=1 git commit` on a conflicted merge already gives you, and
# what CI gives you unconditionally on the push to main.
#
# Bypass: `git merge --no-verify` (same policy as every other hook — CLAUDE.md
# §4.3 requires explicit founder approval first).

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Same resolver the other four hooks use — `flutter/bin/dart` takes the SDK
# update lock and shells out to git on every call (~4.0s vs ~0.3s for the SDK
# exe). At two invocations that is the difference between a hook you notice and
# one you do not. See scripts/_dart_bin.sh.
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

# Identity anchor as CODE, matching scripts/pre-commit.sh:127 — a comment is the
# first thing a cleanup pass deletes, and a hook that cannot prove it is ours is
# a hook nothing can verify is installed.
HOOK_SOURCE="scripts/pre-merge-commit.sh"
export HOOK_SOURCE

echo "[pre-merge-commit] board integrity (2 gates; the full suite runs at push + CI)..."

# ---------------------------------------------------------------------------
# 1. WITHIN-FILE duplicates in the MERGED board.
#
# This is the check whose claim was false. A clean auto-merge of two boards that
# each minted OI-N produces a single file with TWO `## OI-N` headings, and
# build_oi_index.dart exits 1 on exactly that.
#
# VALIDATE ONLY — DO NOT STAGE. An earlier version of this hook regenerated
# OPEN_INDEX.md and ran `git add` on it, with a comment claiming that made "the
# merge commit carry an index matching the board it merged". Review round 1
# (2026-08-17) proved BOTH halves of that comment false by executing it:
#
#   * `git merge` computes the merge commit's TREE BEFORE running this hook, so
#     the `git add` reaches nothing. `git ls-tree -r HEAD` after the merge shows
#     OPEN_INDEX.md is NOT in the commit.
#   * the add therefore just leaves the file STAGED in the working index, so the
#     next unrelated commit sweeps it in — which is precisely the outcome the
#     comment claimed to prevent, and is the cross-session index-mixing shape
#     §4.13 exists to make impossible. On the primary worktree, shared with
#     every other session, that is the worst place to leave a stray staged file.
#
# So the hook now only READS. The generator writes OPEN_INDEX.md as a side
# effect of validating, so the file is restored afterwards to leave the tree
# exactly as the merge left it — a hook that silently mutates the working tree
# is indistinguishable from a bad merge when someone comes to debug one.
# ---------------------------------------------------------------------------
_OPEN_INDEX="docs/audit/OPEN_INDEX.md"
_INDEX_BACKUP=""
_INDEX_EXISTED=0
if [ -f "$_OPEN_INDEX" ]; then
  _INDEX_EXISTED=1
  _INDEX_BACKUP="$(mktemp)" || _INDEX_BACKUP=""
  [ -n "$_INDEX_BACKUP" ] && cp "$_OPEN_INDEX" "$_INDEX_BACKUP"
fi

# Restore the tree to exactly what the merge produced. BOTH directions matter:
# if the file existed, put the original back; if it did NOT, the generator just
# created it and leaving it behind means the hook silently adds an untracked
# file to the working tree on every merge. The second case was found by
# test/scripts/pre_merge_commit_e2e_test.dart, not by reading the code -- the
# first fix handled only the file-existed path, which is the common case in this
# repo and therefore the one that hides the bug.
_restore_index() {
  if [ "$_INDEX_EXISTED" -eq 1 ]; then
    if [ -n "$_INDEX_BACKUP" ] && [ -f "$_INDEX_BACKUP" ]; then
      cp "$_INDEX_BACKUP" "$_OPEN_INDEX"
      rm -f "$_INDEX_BACKUP"
    fi
  else
    rm -f "$_OPEN_INDEX"
  fi
}

if ! "$DART_BIN" run scripts/build_oi_index.dart; then
  _restore_index
  echo "[pre-merge-commit] FAIL: the merged OI board did not validate." >&2
  echo "  Most likely: both sides minted the same OI number and git combined" >&2
  echo "  them cleanly because they sat in different regions of the file." >&2
  echo "  Fix the board on the FEATURE branch (origin/main's numbers are" >&2
  echo "  published and fixed), then re-run the merge. Precedent: 0cb4120a." >&2
  exit 1
fi

# If the regenerated index differs from what the merge produced, the branch
# committed a stale index. Report it — do not silently repair it, because a
# repair here cannot reach the merge commit anyway (see above), so "fixed" would
# be a lie and the staleness would resurface on the next commit.
if [ -n "$_INDEX_BACKUP" ] && ! cmp -s "$_OPEN_INDEX" "$_INDEX_BACKUP"; then
  echo "[pre-merge-commit] NOTE: $_OPEN_INDEX is stale relative to the merged" >&2
  echo "  board. It is generated, so regenerate and commit it on the branch:" >&2
  echo "    dart run scripts/build_oi_index.dart && git add $_OPEN_INDEX" >&2
  echo "  Not blocking: the board itself validated, and this hook cannot write" >&2
  echo "  to a merge commit whose tree git already computed." >&2
fi
_restore_index

# ---------------------------------------------------------------------------
# 2. CROSS-BRANCH / CROSS-BOARD collisions.
#
# Complements gate 1 rather than repeating it: gate 1 sees one file and catches
# a number duplicated INSIDE it; this one compares against origin/main and the
# merge-base, and also catches a number sitting on the open AND closed boards.
# Fails OPEN when it cannot determine an answer, so an offline merge still works.
# ---------------------------------------------------------------------------
if ! "$DART_BIN" run scripts/check_oi_numbering_unique.dart; then
  echo "[pre-merge-commit] FAIL: OI numbering collision (detail above)." >&2
  exit 1
fi

echo "[pre-merge-commit] OK"
exit 0
