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
if [ -r "$REPO_ROOT/scripts/_dart_bin.sh" ]; then
  . "$REPO_ROOT/scripts/_dart_bin.sh"
  DART_BIN="$(resolve_dart_bin)"
else
  # Guarded, and the guard is load-bearing: this file runs under `set -e`, so an
  # unguarded `.` of a missing file ABORTS the hook outright. `_dart_bin.sh`'s
  # own contract is "never wedge a hook", and sourcing it must honour that too.
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
# build_oi_index.dart exits 1 on exactly that. It also regenerates
# docs/audit/OPEN_INDEX.md; we stage the result so the merge commit carries an
# index that matches the board it merged, rather than a stale one that the next
# unrelated commit would silently "fix".
# ---------------------------------------------------------------------------
if ! "$DART_BIN" run scripts/build_oi_index.dart; then
  echo "[pre-merge-commit] FAIL: the merged OI board did not validate." >&2
  echo "  Most likely: both sides minted the same OI number and git combined" >&2
  echo "  them cleanly because they sat in different regions of the file." >&2
  echo "  Fix the board on the FEATURE branch (origin/main's numbers are" >&2
  echo "  published and fixed), then re-run the merge. Precedent: 0cb4120a." >&2
  exit 1
fi
git add docs/audit/OPEN_INDEX.md 2>/dev/null || true

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
