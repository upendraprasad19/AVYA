#!/usr/bin/env sh
# scripts/safe_merge.sh <branch> [extra git-merge args...]
#
# Wraps `git merge --no-ff` for the ONE integration step that had no wrapper
# at all before Unit 3c (discipline-tooling-hardening, 2026-08-03) --
# safe_commit.sh and safe_push.sh already guard commit/push, and
# git_safety_hook.dart actively DENIES a raw `git commit`/`git push` that
# bypasses them. Verified by reading git_safety_hook.dart directly rather
# than assuming: it has NO clause for `git merge` at all -- not a recognized-
# and-exempted integration op, just an absence of any check, so a raw
# `git merge --no-ff <branch>` in primary has always been unguarded. That is
# exactly the moment "is local main caught up with origin/main" matters most
# -- a merge onto a stale local main can silently drop or conflict with work
# that already landed on origin/main.
#
# CLAUDE.md §4.13: this IS the integration step primary exists for. Detection
# uses the SAME two git invocations as
# scripts/check_commit_from_worktree.dart (--git-dir vs --git-common-dir,
# both --path-format=absolute) and the SAME normalization before comparing
# (lowercase + backslash-to-slash + strip trailing slash -- see `_norm`
# below, a shell port of that file's `_norm()`). Round-1 review finding #12:
# an earlier version claimed this "mirrors exactly" while doing a raw
# string compare with no normalization -- true only by coincidence on this
# machine's paths. One deliberate divergence, stated rather than silently
# copied: on an UNRESOLVABLE git-dir, the Dart gate fails OPEN (never wedge
# a routine commit on a git introspection hiccup) but this script fails
# CLOSED (refuses to merge) -- landing on main is high-stakes enough here to
# warrant the stricter default, unlike a gate that runs on every commit.
#
# Concurrency: acquires the shared scripts/_git_lock.sh lock around the
# fetch-compare-merge sequence -- in primary this resolves to the shared
# common git-dir, so it also blocks a concurrent safe_commit.sh/safe_push.sh/
# safe_merge.sh integration attempt from a different session. See that
# file's header for the 2026-08-03 incident this whole unit closes.
#
# Usage: sh scripts/safe_merge.sh <branch> [extra git-merge args...]
#   Extra args pass straight through to `git merge --no-ff` (e.g. -m "custom
#   subject") -- round-1 review finding #13: this repo's dominant merge
#   convention is `Merge branch 'X' — <description>` (90 of the last 443
#   first-parent merges on main, including all of the last 20), which this
#   script could not produce without this passthrough.
#
#   Round-2 review blocking #2: the first version of this passthrough
#   collapsed extra args into ONE string (`EXTRA_ARGS="$*"`) and re-expanded
#   it UNQUOTED at the call site -- which word-splits on whitespace, so a
#   multi-word `-m` message (this repo's own dominant convention, quoted
#   above) got shredded into many separate argv tokens and git failed
#   outright ("branch - not something we can merge"). Reproduced live by the
#   round-2 reviewer; none of this script's own tests exercised the path
#   (all 4 call it with just a branch name), so it shipped broken. Fixed by
#   keeping the extra args as REAL, separate positional parameters (`shift`
#   then `"$@"`, properly quoted) instead of flattening and re-splitting
#   them -- the standard POSIX-sh-correct pattern, and simpler than the
#   broken one. safe_push.sh had the identical latent flaw (same
#   EXTRA_ARGS="$*" pattern) -- fixed there too, same commit, since its
#   typical single-token extra args (-u, --tags) happened not to trigger it
#   but the underlying bug was the same.

set -u

BRANCH="${1:-}"
if [ -z "$BRANCH" ]; then
  echo "usage: sh scripts/safe_merge.sh <branch> [extra git-merge args...]" >&2
  exit 2
fi
shift 1

REPO_ROOT="$(git rev-parse --show-toplevel)"
if [ -z "$REPO_ROOT" ]; then
  echo "[safe_merge] FAILED: git rev-parse --show-toplevel returned empty (not a git repo?)." >&2
  exit 1
fi
cd "$REPO_ROOT" || { echo "[safe_merge] FAILED: cd \"$REPO_ROOT\" failed." >&2; exit 1; }

# Shell port of check_commit_from_worktree.dart's `_norm()`:
# p.replaceAll('\\','/').replaceAll(RegExp(r'/+$'), '').toLowerCase();
_norm() {
  printf '%s' "$1" | tr '\\' '/' | sed 's:/*$::' | tr '[:upper:]' '[:lower:]'
}

# Primary-vs-linked-worktree detection (--path-format=absolute so this is
# correct from any cwd, including a subdirectory of primary).
GIT_DIR_ABS="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)"
GIT_COMMON_DIR_ABS="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
if [ -z "$GIT_DIR_ABS" ] || [ -z "$GIT_COMMON_DIR_ABS" ]; then
  echo "[safe_merge] FAILED: could not resolve git-dir/git-common-dir." >&2
  exit 1
fi
if [ "$(_norm "$GIT_DIR_ABS")" != "$(_norm "$GIT_COMMON_DIR_ABS")" ]; then
  echo "[safe_merge] FAILED: this is a LINKED worktree, not primary." >&2
  echo "  safe_merge.sh is the integration step -- CLAUDE.md §4.13 reserves" >&2
  echo "  merging into main for the PRIMARY worktree (the shared main folder)," >&2
  echo "  not a linked worktree. Run this from:" >&2
  echo "    cd \"$REPO_ROOT\"" >&2
  exit 1
fi

. "$REPO_ROOT/scripts/_git_lock.sh"
git_lock_acquire "safe_merge" || exit 1

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "[safe_merge] FAILED: current branch is '$CURRENT_BRANCH', not 'main'." >&2
  echo "  safe_merge.sh only merges INTO main. Checkout main first:" >&2
  echo "    git checkout main" >&2
  exit 1
fi

echo "[safe_merge] fetching origin/main..."
if ! git fetch origin main --quiet; then
  echo "[safe_merge] FAILED: git fetch origin main failed -- refusing to merge" >&2
  echo "  onto a base that could not be freshness-checked." >&2
  exit 1
fi

LOCAL_MAIN_SHA="$(git rev-parse main)"
REMOTE_MAIN_SHA="$(git rev-parse origin/main)"
if [ "$LOCAL_MAIN_SHA" != "$REMOTE_MAIN_SHA" ]; then
  BEHIND_COUNT="$(git rev-list --count main..origin/main 2>/dev/null || echo "?")"
  AHEAD_COUNT="$(git rev-list --count origin/main..main 2>/dev/null || echo "?")"
  if [ "$BEHIND_COUNT" != "0" ]; then
    echo "[safe_merge] FAILED: local main is behind origin/main by $BEHIND_COUNT commit(s)." >&2
    echo "  local  main = $LOCAL_MAIN_SHA" >&2
    echo "  remote main = $REMOTE_MAIN_SHA" >&2
    echo "  Merging onto a stale base risks silently dropping or conflicting with" >&2
    echo "  work that already landed on origin/main. Pull first:" >&2
    echo "    git pull origin main" >&2
    exit 1
  fi
  echo "[safe_merge] NOTE: local main differs from origin/main (ahead=$AHEAD_COUNT, behind=0) -- not stale, proceeding."
fi

echo "[safe_merge] main is caught up with origin/main ($LOCAL_MAIN_SHA). Merging '$BRANCH'..."

LOG="$(mktemp 2>/dev/null || echo "/tmp/safe_merge_$$.log")"
BEFORE_HEAD="$(git rev-parse HEAD 2>/dev/null || echo "")"

# Redirect, never pipe -- $? below is git's own exit code (feedback_git_
# landing_verification.md's masked-exit-code class, same as safe_commit.sh).
# "$@" (not a flattened/re-split string) preserves each extra arg as its own
# token -- see the round-2 fix note in this file's header.
git merge --no-ff "$BRANCH" "$@" > "$LOG" 2>&1
GIT_EXIT=$?

cat "$LOG"

AFTER_HEAD="$(git rev-parse HEAD 2>/dev/null || echo "")"

if [ "$GIT_EXIT" -ne 0 ]; then
  echo "" >&2
  echo "[safe_merge] FAILED (git exit $GIT_EXIT) -- see output above. HEAD unchanged ($BEFORE_HEAD)." >&2
  rm -f "$LOG"
  exit "$GIT_EXIT"
fi

if [ "$AFTER_HEAD" = "$BEFORE_HEAD" ]; then
  echo "" >&2
  echo "[safe_merge] FAILED: git reported exit 0 but HEAD did NOT advance ($BEFORE_HEAD)." >&2
  echo "  Possibly an already-up-to-date merge (branch fully contained in main)." >&2
  rm -f "$LOG"
  exit 1
fi

echo ""
echo "[safe_merge] OK -- HEAD advanced $BEFORE_HEAD -> $AFTER_HEAD."
git log -1 --oneline
rm -f "$LOG"
exit 0
