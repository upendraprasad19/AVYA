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

# `--verify --quiet` is load-bearing, NOT decoration (OI-172, 2026-09-10).
#
# Plain `git rev-parse <unresolvable>` prints the NAME ITSELF to STDOUT and
# exits 128 -- so `$(... || echo "")` captured the literal string
# "no-such-branch-xyz", the `-z` guard below never fired, and this script went
# on to `git push` a bogus refspec and report a confusing FAILED instead of the
# clear message below. The exit on this path was effectively unreachable for the
# case it was written for. `--verify --quiet` prints NOTHING on failure while
# resolving a real branch or tag identically (verified both ways).
# Found by the OI-172 record test asserting that a pre-push abort leaves the
# PRIOR record untouched -- it found a FAILED record, because the abort was not
# aborting.
LOCAL_SHA="$(git rev-parse --verify --quiet "$BRANCH" 2>/dev/null || echo "")"
if [ -z "$LOCAL_SHA" ]; then
  echo "[safe_push] FAILED: could not resolve local ref for branch '$BRANCH'." >&2
  exit 1
fi

# --- push-result record (OI-172) --------------------------------------------
#
# A durable record of what happened to this push, so a push that was reaped,
# interrupted, or run in a terminal that is now closed leaves something to read
# afterwards. Before OI-172 nothing did: the ONLY in-flight evidence was the
# lock's `holder` file, and _git_lock.sh releases the lock via a trap on
# EXIT/HUP/INT/TERM, so on any normal exit that file is GONE. The lock can
# answer "is a push running right now" and structurally cannot answer "what
# happened".
#
# ⚠ READ scripts/push_result_lib.dart BEFORE CONSUMING THIS FILE. The reader
# rules are not guessable and getting one wrong produces a confident wrong
# answer rather than an error:
#   * a MISSING or unparseable record means UNVERIFIED -- NEVER failed. Reading
#     absent as failed re-creates the bad-news-vs-no-news inversion this whole
#     mechanism exists to kill.
#   * a record applies only when BOTH `ref` AND `local_sha` match what the
#     reader is asking about. Not the sha alone: two refs legitimately share a
#     tip after a fast-forward merge or on a freshly-cut branch, so a sha-only
#     check lets one ref's verdict be read as proof about another.
#   * `result=STARTED` is not a verdict. Pair it with `kill -0 <pid>`.
#   * `LANDED` never means CI-green. CI runs after we return -- that is what
#     arm_ci_reconcile.sh below is for.
#
# Location: `$(git rev-parse --absolute-git-dir)/.safe_push_result`, i.e. inside
# .git and NOT in the worktree. A gitignored file written into a WORKTREE makes
# that worktree permanently unretirable -- three prior instances (CLAUDE.md §5,
# diagnose b4d7e9, OI-128), and this script's own arm_ci_reconcile.sh call is
# one of them. `--absolute-git-dir` rather than `--git-dir` because the latter
# returns a RELATIVE `.git` in the primary worktree, which a reader standing
# somewhere else would resolve against its own cwd. Per-worktree, matching the
# scope of the lock acquired above, so writes here are already serialised.
RESULT_PATH=""
_ABS_GIT_DIR="$(git rev-parse --absolute-git-dir 2>/dev/null || echo "")"
if [ -n "$_ABS_GIT_DIR" ]; then
  RESULT_PATH="$_ABS_GIT_DIR/.safe_push_result"
  # KILL SWITCH: `touch "$(git rev-parse --absolute-git-dir)/.safe_push_result.disabled"`
  # makes every write below a no-op, exactly like `.claude/.reconcile_ci.disabled`
  # does for the CI reconciler. Satisfies `docs/blast_radius.yaml`'s
  # `platform: requires: [... feature_flag]`, which nothing enforces mechanically
  # — `check_blast_radius_coverage.dart` never reads that list — so it is the
  # reviewer, not a gate, that catches its absence (B-pass F4).
  #
  # ⚠ Deliberately NOT `.claude/.safe_push_result.disabled`, despite that being
  # where the two existing kill switches live. Neither of those is listed in
  # `retire_worktree_lib.dart`'s `regenerableIgnoredPaths`, so a worktree where
  # someone flipped one is UNRETIRABLE until they remember to delete it — the
  # same class this record's own location exists to dodge. Copying the
  # precedent's SHAPE (a marker file whose presence disables) is right; copying
  # its LOCATION would import the hazard.
  if [ -e "$RESULT_PATH.disabled" ]; then
    RESULT_PATH=""
  fi
fi

# The ref this push is ABOUT (refs/heads/x for a branch, refs/tags/x for a tag)
# vs the ref probe_remote_sha() actually queries, which is ALWAYS
# refs/heads/$BRANCH. Recording both makes the tag-passed-positionally case
# self-diagnosing: the tag pushes fine, the probe looks in the wrong namespace,
# and this script reports FAILED for a push that landed. The record keeps the
# verdict the script reached -- it must not silently disagree with stdout -- but
# a reader can now SEE why it is untrustworthy (push_result_lib.dart's
# probedTheWrongNamespace).
REF="$(git rev-parse --symbolic-full-name "$BRANCH" 2>/dev/null || echo "")"
if [ -z "$REF" ]; then
  REF="refs/heads/$BRANCH"
fi
VERIFIED_REF="refs/heads/$BRANCH"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")"

# Collapse to ONE printable line. `reason` carries raw git stderr, and an
# embedded newline would inject a bogus `key=value` line and corrupt the record
# for every parser; a stray `=` would do the same to the field split.
#
# ⚠ It collapses and truncates; it does NOT REDACT. A credential-shaped
# substring in git's stderr (an `https://user:pass@host/...` remote) would be
# persisted verbatim. Not reachable in this repo — `origin` is SSH
# (`git@github.com:...`), which cannot embed a password — and not reachable from
# any current call site either, since every `reason` passed below is a
# script-authored single-line string rather than raw stderr. Stated for whoever
# reuses this against an HTTPS remote or starts passing stderr through
# (B-pass F6). That same fact is why making this a passthrough reddens ZERO
# tests: it is defensive for FUTURE callers and is NOT mutation-proven here.
_sanitize_reason() {
  printf '%s' "$1" | tr '\n\r\t=' '    ' | tr -cd '\040-\176' | cut -c1-200
}

# _write_push_result <result> <exit> <remote_sha> <reason>
#
# ALWAYS returns 0. The record is advisory; the push verdict is not. A failure
# to record must never turn a landed push into a reported failure -- the same
# reasoning arm_ci_reconcile.sh already uses, and the reason every call below is
# unconditional rather than guarded on this function's status.
#
# Publishes with `mv -T`, NOT plain `mv`, and that flag is load-bearing twice
# over. Measured on this stack: with a DIRECTORY at the destination, plain `mv`
# exits 0 and moves the file INSIDE it -- the record would land where no reader
# looks while the push reported success. `mv -T` refuses outright (exit 1). Onto
# an existing regular FILE it replaces unconditionally, which is what every
# push after the first needs. _git_lock.sh:96-102 documents the same asymmetry
# from the other side, where it was the wrong shape for that file's problem.
_write_push_result() {
  [ -n "$RESULT_PATH" ] || return 0
  _wpr_ended=""
  if [ "$1" != "STARTED" ]; then
    _wpr_ended="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")"
  fi
  {
    echo "result=$1"
    echo "exit=$2"
    echo "branch=$BRANCH"
    echo "ref=$REF"
    echo "remote=$REMOTE"
    echo "local_sha=$LOCAL_SHA"
    echo "remote_sha=$3"
    echo "verified_ref=$VERIFIED_REF"
    echo "pid=$$"
    echo "started=$STARTED_AT"
    echo "ended=$_wpr_ended"
    echo "worktree=$REPO_ROOT"
    echo "reason=$(_sanitize_reason "$4")"
  } > "$RESULT_PATH.tmp" 2>/dev/null
  # Atomic publish. `mv -T`, never plain `mv` -- see the note above. On refusal
  # (a directory squatting at the path) remove the candidate instead of leaving
  # litter inside .git for every later push to add to.
  mv -T "$RESULT_PATH.tmp" "$RESULT_PATH" 2>/dev/null || rm -f "$RESULT_PATH.tmp" 2>/dev/null
  return 0
}

# STARTED, written BEFORE the push and carrying this process's pid.
#
# Without this the record cannot answer the incident that motivated OI-172: the
# push was still RUNNING, so no terminal verdict existed yet and a
# terminal-only record would have been absent at exactly the moment it was
# wanted. Note this deliberately OVERWRITES any prior record the instant a new
# attempt begins, so a reader can never mistake a previous push's verdict for
# this one's.
_write_push_result STARTED "-" "" ""

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
  # Arm a CI-reconcile entry. This wrapper proves the push LANDED; it cannot
  # know what CI concludes, because CI runs asynchronously after we return.
  # scripts/reconcile_ci.dart closes that at the next SessionStart.
  #
  # `|| true` is load-bearing: the arm is advisory, the push verdict is not.
  # A failure to record must never turn a landed push into a reported failure.
  # It lives HERE rather than in the caller because an arm step that depends on
  # someone remembering to run it decays, and an unarmed push is
  # indistinguishable from a push that was fine (CLAUDE.md 4.13 point 6).
  sh "$REPO_ROOT/scripts/arm_ci_reconcile.sh" "$BRANCH" "$LOCAL_SHA" >/dev/null 2>&1 || true
  _write_push_result LANDED 0 "$REMOTE_SHA" ""
  exit 0
fi

echo "" >&2

# git itself reported failure and the remote does not match: definitively failed.
if [ "$GIT_EXIT" -ne 0 ]; then
  echo "[safe_push] FAILED (git exit $GIT_EXIT) -- see output above." >&2
  _write_push_result FAILED 1 "$REMOTE_SHA" "git push exited $GIT_EXIT; see the push output"
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
  _write_push_result UNVERIFIED 2 ""     "git push exited 0 but ls-remote could not reach $REMOTE on either probe"
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
_write_push_result FAILED 1 "$REMOTE_SHA"   "git exited 0 but $VERIFIED_REF on $REMOTE is ${REMOTE_SHA:-absent}, not $LOCAL_SHA"
rm -f "$LOG"
exit 1
