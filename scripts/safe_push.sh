#!/usr/bin/env sh
# scripts/safe_push.sh [remote] [branch] [extra git-push args...]
#
# Wraps `git push` with the two fixes from feedback_git_landing_verification.md:
#   1. SSH keep-alive, so a long pre-push suite (~7-10 min for platform/account
#      tier) doesn't idle the SSH channel into a silent SIGPIPE (exit 141, no
#      git error -- 2026-07-03 audit-fixwave incident).
#   2. Output redirected to a LOG FILE, never a pipe (same exit-code-masking
#      class as safe_commit.sh), then an independent `ls-remote` check that the
#      remote ref actually moved -- never trusting the push's own exit code.
#
# Usage: sh scripts/safe_push.sh [remote] [branch] [extra args...]
#   Defaults: remote=origin, branch=current branch.
#   Extra args pass straight through to `git push` (e.g. -u, --force-with-lease,
#   --tags) -- review round 1 (discipline-overhead batch, 2026-07-19, F7) found
#   the original 2-positional-arg-only form had no path for these; a caller
#   needing them would otherwise fall back to the raw (unverified) command.
#
# CLAUDE.md §4.3: this is the ONLY sanctioned push path. A PreToolUse hook
# (scripts/git_safety_hook.dart) blocks a raw `git push` outright, and --
# separately -- locally re-runs the plan-review-record check before any push
# as an ADVISORY warning (review round 2, N1: never a hard block with no
# escape hatch on the one path that lands work on main -- CI is the real,
# authoritative backstop for this check regardless).

set -u

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

REMOTE="${1:-origin}"
BRANCH="${2:-$(git rev-parse --abbrev-ref HEAD)}"
EXTRA_ARGS=""
if [ "$#" -gt 2 ]; then
  shift 2
  EXTRA_ARGS="$*"
fi

LOCAL_SHA="$(git rev-parse "$BRANCH" 2>/dev/null || echo "")"
if [ -z "$LOCAL_SHA" ]; then
  echo "[safe_push] FAILED: could not resolve local ref for branch '$BRANCH'." >&2
  exit 1
fi

LOG="$(mktemp 2>/dev/null || echo "/tmp/safe_push_$$.log")"

# shellcheck disable=SC2086 -- EXTRA_ARGS is an intentional word-split passthrough.
GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=120}" \
  git push "$REMOTE" "$BRANCH" $EXTRA_ARGS > "$LOG" 2>&1
GIT_EXIT=$?

cat "$LOG"

REMOTE_SHA="$(git ls-remote "$REMOTE" "refs/heads/$BRANCH" 2>/dev/null | cut -f1)"

if [ "$REMOTE_SHA" = "$LOCAL_SHA" ]; then
  echo ""
  echo "[safe_push] OK -- $REMOTE/$BRANCH now at $REMOTE_SHA (matches local)."
  rm -f "$LOG"
  exit 0
fi

# Review round 1 (F6): don't cry wolf on a genuinely successful push just
# because the SEPARATE ls-remote verification round-trip hit a transient
# blip. Only escalate to FAILED if a retry also can't confirm.
if [ "$GIT_EXIT" -eq 0 ] && [ -z "$REMOTE_SHA" ]; then
  REMOTE_SHA2="$(git ls-remote "$REMOTE" "refs/heads/$BRANCH" 2>/dev/null | cut -f1)"
  if [ "$REMOTE_SHA2" = "$LOCAL_SHA" ]; then
    echo ""
    echo "[safe_push] OK -- $REMOTE/$BRANCH now at $REMOTE_SHA2 (matches local; confirmed on retry)."
    rm -f "$LOG"
    exit 0
  fi
  if [ -z "$REMOTE_SHA2" ]; then
    echo "" >&2
    echo "[safe_push] WARNING: git reported exit 0, but ls-remote could not resolve $REMOTE/$BRANCH" >&2
    echo "  even after a retry (possible transient network issue on the VERIFICATION round-trip," >&2
    echo "  not necessarily the push itself). Trusting git's exit code, but verify manually:" >&2
    echo "    git ls-remote $REMOTE refs/heads/$BRANCH" >&2
    rm -f "$LOG"
    exit 0
  fi
  REMOTE_SHA="$REMOTE_SHA2"
fi

if [ "$REMOTE_SHA" = "$LOCAL_SHA" ]; then
  echo ""
  echo "[safe_push] OK -- $REMOTE/$BRANCH now at $REMOTE_SHA (matches local; confirmed on retry)."
  rm -f "$LOG"
  exit 0
fi

echo "" >&2
if [ "$GIT_EXIT" -eq 0 ]; then
  echo "[safe_push] FAILED: git reported exit 0 but the remote ref did NOT move." >&2
  echo "  local  $BRANCH = $LOCAL_SHA" >&2
  echo "  remote $REMOTE/$BRANCH = ${REMOTE_SHA:-<unresolved>}" >&2
  echo "  This is exactly the SIGPIPE-after-idle-SSH class this wrapper exists to catch --" >&2
  echo "  a plain retry will NOT help if the suite idles the channel the same way again." >&2
else
  echo "[safe_push] FAILED (git exit $GIT_EXIT) -- see output above." >&2
fi
rm -f "$LOG"
exit 1
