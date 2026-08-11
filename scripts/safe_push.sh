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
# Exit codes (three outcomes, not two -- round-2 review 2026-08-11):
#   0  LANDED     -- the remote ref was OBSERVED at the local tip.
#   1  FAILED     -- git push failed, or the probe succeeded and the ref did
#                    not move (including: the ref is absent entirely).
#   2  UNVERIFIED -- git push reported success but the remote could not be
#                    reached to confirm it, twice. Deliberately NOT 0: the old
#                    code exited 0 here ("Trusting git's exit code"), which is
#                    the one thing a landing verifier must never do. Also
#                    deliberately not 1: a caller must be able to tell "it did
#                    not land" from "I could not check".
#
# Usage: sh scripts/safe_push.sh [remote] [branch] [extra args...]
#   Defaults: remote=origin, branch=current branch.
#   Extra args pass straight through to `git push` (e.g. -u, --force-with-lease,
#   --tags) -- review round 1 (discipline-overhead batch, 2026-07-19, F7) found
#   the original 2-positional-arg-only form had no path for these; a caller
#   needing them would otherwise fall back to the raw (unverified) command.
#
#   Fixed 2026-08-03 (discipline-tooling-hardening Unit 3c round-2 review,
#   blocking #2): this passthrough used to collapse extra args into ONE
#   string (`EXTRA_ARGS="$*"`) and re-expand it UNQUOTED at the call site --
#   word-splitting on whitespace, which silently shreds any multi-word extra
#   arg (e.g. a `-m "multi word message"`) into separate argv tokens. This
#   file's own typical extra args (-u, --force-with-lease, --tags) are
#   single tokens, so the bug never bit here in practice, but it is the same
#   defect the round-2 reviewer caught live in safe_merge.sh's identical
#   pattern -- fixed the same way, same commit: keep extra args as REAL
#   separate positional parameters (`shift` then `"$@"`, properly quoted)
#   instead of flattening and re-splitting them.
#
# CLAUDE.md §4.3: this is the ONLY sanctioned push path. A PreToolUse hook
# (scripts/git_safety_hook.dart) blocks a raw `git push` outright, and --
# separately -- locally re-runs the plan-review-record check before any push
# as an ADVISORY warning (review round 2, N1: never a hard block with no
# escape hatch on the one path that lands work on main -- CI is the real,
# authoritative backstop for this check regardless).
#
# Concurrency: acquires the shared scripts/_git_lock.sh lock around the
# git-mutating section -- see that file's header for the 2026-08-03 incident
# this closes (a stale liveness check let two safe_commit.sh attempts race).

set -u

REPO_ROOT="$(git rev-parse --show-toplevel)"
if [ -z "$REPO_ROOT" ]; then
  echo "[safe_push] FAILED: git rev-parse --show-toplevel returned empty (not a git repo?)." >&2
  exit 1
fi
cd "$REPO_ROOT" || { echo "[safe_push] FAILED: cd \"$REPO_ROOT\" failed." >&2; exit 1; }

. "$REPO_ROOT/scripts/_git_lock.sh"
git_lock_acquire "safe_push" || exit 1

REMOTE="${1:-origin}"
BRANCH="${2:-$(git rev-parse --abbrev-ref HEAD)}"
if [ "$#" -ge 2 ]; then
  shift 2
elif [ "$#" -eq 1 ]; then
  shift 1
fi
# "$@" now holds zero or more extra args as real, separate positional
# parameters -- see the header note on why this replaced EXTRA_ARGS="$*".

LOCAL_SHA="$(git rev-parse "$BRANCH" 2>/dev/null || echo "")"
if [ -z "$LOCAL_SHA" ]; then
  echo "[safe_push] FAILED: could not resolve local ref for branch '$BRANCH'." >&2
  exit 1
fi

LOG="$(mktemp 2>/dev/null || echo "/tmp/safe_push_$$.log")"

GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=120}" \
  git push "$REMOTE" "$BRANCH" "$@" > "$LOG" 2>&1
GIT_EXIT=$?

cat "$LOG"

# Probe the remote ref, capturing the probe's OWN exit status SEPARATELY.
#
# Round-2 review, 2026-08-11. The previous form was:
#     REMOTE_SHA="$(git ls-remote ... 2>/dev/null | cut -f1)"
# which was wrong twice over:
#
#   1. An EMPTY result meant two OPPOSITE things -- "the ref genuinely does not
#      exist on the remote" (the push did NOT land: a real failure) and "the
#      probe itself could not reach the remote" (we simply do not know). With
#      those conflated there was no honest answer available: the code had to
#      pick between crying wolf on a transient verification blip (the F6 false
#      positive this retry logic was added to prevent) and exiting 0 having
#      verified nothing. It picked exit 0 -- i.e. the one behaviour a landing
#      verifier must never have, in the file whose entire purpose is to be
#      trusted about whether a push landed.
#   2. Piping into `cut` makes `$?` the exit status of CUT (always 0), never
#      git's. That is the exact exit-code-masking class this wrapper exists to
#      catch (feedback_git_landing_verification.md), reproduced INSIDE the
#      verifier.
#
# `git ls-remote` exits 0 with EMPTY output for a ref that does not exist, and
# non-zero when it cannot reach or authenticate to the remote. The probe's exit
# status is therefore precisely the signal that separates "did not land" from
# "could not check" -- so capture it, and never pipe it away.
probe_remote_sha() {
  _probe_out="$(git ls-remote "$REMOTE" "refs/heads/$BRANCH" 2>/dev/null)"
  PROBE_EXIT=$?
  REMOTE_SHA="$(printf '%s' "$_probe_out" | cut -f1)"
}

probe_remote_sha
RETRIED=0

# Review round 1 (F6): don't cry wolf on a genuinely successful push just
# because the SEPARATE verification round-trip hit a transient blip. Retry ONLY
# the ambiguous case -- a FAILED probe. A probe that SUCCEEDED has already given
# a definitive answer and must never be retried into a different one.
#
# DELIBERATELY NOT gated on GIT_EXIT (B-pass 2026-08-11, finding 1). The old
# retry required `GIT_EXIT -eq 0`, so a push that reported failure got only ONE
# probe. That is backwards for this wrapper's founding scenario: a push whose
# data LANDED and then died on an idle SSH channel (SIGPIPE, exit 141) reports
# failure while the remote ref is correct. The old code already let an observed
# remote override GIT_EXIT on the FIRST probe (its `$REMOTE_SHA = $LOCAL_SHA`
# test ran before any GIT_EXIT check) -- it just refused to retry a flaky probe
# in that case. Applying the same rule to both probes is the consistent
# behaviour, not a widening of trust: an OBSERVED remote at our tip is proof the
# work is on the remote, whatever git's exit code claimed.
# Pinned by the "git push FAILED but the ref is observed at our tip" test.
if [ "$PROBE_EXIT" -ne 0 ]; then
  RETRIED=1
  probe_remote_sha
fi

# Landed: the remote ref is observed at our local tip. Checked before GIT_EXIT
# because an observed-correct remote is stronger evidence than git's own exit
# code -- which is the founding premise of this wrapper.
if [ "$PROBE_EXIT" -eq 0 ] && [ "$REMOTE_SHA" = "$LOCAL_SHA" ]; then
  echo ""
  if [ "$RETRIED" -eq 1 ]; then
    # Keep "the first probe was unreachable" visible in the log: it is the only
    # signal that the verification round-trip is flaky, which is precisely the
    # condition the retry exists to absorb (B-pass 2026-08-11, finding 2).
    echo "[safe_push] OK -- $REMOTE/$BRANCH now at $REMOTE_SHA (matches local; first probe was unreachable, confirmed on retry)."
  else
    echo "[safe_push] OK -- $REMOTE/$BRANCH now at $REMOTE_SHA (matches local)."
  fi
  rm -f "$LOG"
  exit 0
fi

echo "" >&2

# git itself reported failure and the remote does not match: definitively failed.
if [ "$GIT_EXIT" -ne 0 ]; then
  echo "[safe_push] FAILED (git exit $GIT_EXIT) -- see output above." >&2
  rm -f "$LOG"
  exit 1
fi

# git reported success but we could not reach the remote to confirm it.
# UNVERIFIED is its own outcome with its own exit code (2): not evidence of
# failure, and -- critically -- not reported as success either.
if [ "$PROBE_EXIT" -ne 0 ]; then
  echo "[safe_push] UNVERIFIED (exit 2): git push reported exit 0, but" >&2
  echo "  \`git ls-remote\` could not reach $REMOTE to confirm it -- twice." >&2
  echo "  This is NOT evidence the push failed, and NOT evidence it landed." >&2
  echo "  Confirm before assuming either:" >&2
  echo "    git ls-remote $REMOTE refs/heads/$BRANCH" >&2
  rm -f "$LOG"
  exit 2
fi

# The probe succeeded, so REMOTE_SHA is authoritative: the ref is either absent
# (empty) or points somewhere other than our local tip. Either way the push did
# not land what we have.
echo "[safe_push] FAILED: git reported exit 0 but the remote ref did NOT move." >&2
echo "  local  $BRANCH = $LOCAL_SHA" >&2
echo "  remote $REMOTE/$BRANCH = ${REMOTE_SHA:-<absent>}" >&2
echo "  This is exactly the SIGPIPE-after-idle-SSH class this wrapper exists to catch --" >&2
echo "  a plain retry will NOT help if the suite idles the channel the same way again." >&2
rm -f "$LOG"
exit 1
