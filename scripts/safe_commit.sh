#!/usr/bin/env sh
# scripts/safe_commit.sh "<message>"
#
# Wraps `git commit` so "it reported success" and "it actually landed" can
# never silently diverge -- the fix for 6 documented incidents
# (feedback_git_landing_verification.md, 2026-06-05 -> the workout-generator
# batch) where a backgrounded or piped commit reported exit 0 while the
# pre-commit hook had actually failed. Root cause each time: a PIPE's exit
# code is the LAST STAGE's (not git's), and a trailing command in a compound
# statement masks git's real exit code the same way. This script redirects to
# a LOG FILE instead (never a pipe), reads git's own exit code directly, then
# independently verifies HEAD advanced and the tree is clean -- never trusting
# the wrapper's exit code alone.
#
# Usage: sh scripts/safe_commit.sh "<message>"
#
# CLAUDE.md §4.3: this is the ONLY sanctioned commit path. A PreToolUse hook
# (scripts/git_safety_hook.dart) blocks a raw `git commit` outright.
#
# Concurrency: acquires the shared scripts/_git_lock.sh lock around the
# git-mutating section, so two overlapping invocations (same worktree or
# primary) refuse/wait instead of racing -- see that file's header for the
# 2026-08-03 incident this closes.

set -u

MSG="${1:-}"
if [ -z "$MSG" ]; then
  echo "usage: sh scripts/safe_commit.sh \"<message>\"" >&2
  exit 2
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
if [ -z "$REPO_ROOT" ]; then
  echo "[safe_commit] FAILED: git rev-parse --show-toplevel returned empty (not a git repo?)." >&2
  exit 1
fi
cd "$REPO_ROOT" || { echo "[safe_commit] FAILED: cd \"$REPO_ROOT\" failed." >&2; exit 1; }

. "$REPO_ROOT/scripts/_git_lock.sh"
git_lock_acquire "safe_commit" || exit 1

LOG="$(mktemp 2>/dev/null || echo "/tmp/safe_commit_$$.log")"
BEFORE_HEAD="$(git rev-parse HEAD 2>/dev/null || echo "")"

# Redirect, never pipe -- $? below is git's own exit code, not a pipeline's.
git commit -m "$MSG" > "$LOG" 2>&1
GIT_EXIT=$?

cat "$LOG"

AFTER_HEAD="$(git rev-parse HEAD 2>/dev/null || echo "")"
STAGED_LEFT="$(git diff --cached --name-only)"

if [ "$GIT_EXIT" -ne 0 ]; then
  echo "" >&2
  echo "[safe_commit] FAILED (git exit $GIT_EXIT) -- see output above. HEAD unchanged ($BEFORE_HEAD)." >&2
  rm -f "$LOG"
  exit "$GIT_EXIT"
fi

if [ "$AFTER_HEAD" = "$BEFORE_HEAD" ]; then
  echo "" >&2
  echo "[safe_commit] FAILED: git reported exit 0 but HEAD did NOT advance ($BEFORE_HEAD)." >&2
  echo "  This is exactly the masked-failure class this wrapper exists to catch -- do not" >&2
  echo "  assume the commit landed. Investigate the log above before retrying." >&2
  rm -f "$LOG"
  exit 1
fi

if [ -n "$STAGED_LEFT" ]; then
  echo "" >&2
  echo "[safe_commit] WARNING: HEAD advanced to $AFTER_HEAD, but files are still staged:" >&2
  echo "$STAGED_LEFT" >&2
  echo "  This can mean the intended scope only partially committed. Verify with:" >&2
  echo "    git show --stat $AFTER_HEAD" >&2
fi

echo ""
echo "[safe_commit] OK -- HEAD advanced $BEFORE_HEAD -> $AFTER_HEAD."
git log -1 --oneline
rm -f "$LOG"
exit 0
