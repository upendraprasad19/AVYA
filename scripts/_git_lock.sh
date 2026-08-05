#!/usr/bin/env sh
# scripts/_git_lock.sh -- SOURCED (not executed) by safe_commit.sh /
# safe_push.sh / safe_merge.sh. Provides git_lock_acquire / git_lock_release
# around each wrapper's git-mutating section.
#
# WHY THIS EXISTS (2026-08-03 near-miss, terms-accepted-fix backfill
# follow-up). A safe_commit.sh foreground attempt timed out. Per established
# lessons a timeout does NOT kill the process, so the liveness check used to
# decide "safe to retry" was a `ps aux | grep` for a specific process name --
# which sampled a real GAP between two short-lived subprocess spawns inside
# the pre-commit hook's bounded-parallel gate loop, concluded attempt 1 was
# dead, and a second attempt was started. Both ran concurrently; attempt 1
# won and committed, attempt 2 correctly found nothing left to commit --
# benign ONLY because both attempts had staged byte-identical content. A
# process-NAME sample is not proof of death; this lock removes the need to
# guess at all. See feedback_git_landing_verification.md's 2026-08-03
# section for the full incident.
#
# LOCK KEY: `$(git rev-parse --git-dir)/.safe_git_op.lock` -- deliberately
# NOT `--show-toplevel` + `/.git`. In a git WORKTREE, `<worktree>/.git` is a
# plaintext FILE (pointing at the real per-worktree admin dir under
# `.git/worktrees/<name>/`), so a claim attempt inside that path fails
# outright. `--git-dir` is the only form that resolves correctly in BOTH
# places:
#   - run from a linked worktree  -> that worktree's own private admin dir
#     (protects same-worktree races -- the actual 2026-08-03 incident).
#   - run from primary            -> the shared common dir, since primary is
#     not itself a linked worktree (protects two different SESSIONS' merge/
#     push integration steps in primary from racing each other too).
# One lock key, two useful scopes, for free -- see CLAUDE.md §4.13 for why
# primary-folder cross-session races are a documented, real risk class here.
#
# CLAIM MECHANISM -- round-2 review rewrite (2026-08-03), replacing the
# round-1 mkdir-then-separate-write design:
#
# The ORIGINAL design (`mkdir "$lock_path"` to claim, THEN a separate later
# `>` write of a `holder` file inside it) left a real window: a reader could
# see the lock dir present but `holder` missing/empty and conclude "stale,
# reclaim" while the true holder was still alive but merely slow to write
# (a `date` subprocess spawn alone measured 61-89ms on this exact
# Windows/Git-Bash/MSYS2 stack -- the same subprocess-spawn-timing class
# that caused the ORIGINAL incident this file exists to fix). Round-1 added
# a brief re-read/sleep before declaring a lock stale, which narrows that
# window but cannot close it -- no sleep duration is provably long enough,
# and "narrow the sampling gap" is exactly the "sample a gap" mistake this
# whole file exists to eliminate, one level down. Round-2 review reproduced
# the resulting cascade live (an injected delay on one side): a slow
# original holder's delayed write, arriving AFTER a reclaimer has already
# taken over the same PATH, silently clobbers the reclaimer's holder file --
# because a plain `>` redirect targets a path, not the specific filesystem
# object the writer's own `mkdir` created. Both processes end up believing,
# from their own local state, that they exclusively hold the mutex.
#
# THE FIX: never make the claim visible before it is fully populated.
# Prepare the complete holder content in a uniquely-named, private candidate
# directory first (PID-suffixed -- nothing else can see or race this), then
# publish it to the canonical lock path in ONE atomic filesystem operation:
# `mv -T candidate lock_path` (GNU coreutils --no-target-directory; this
# repo's Git-for-Windows/MSYS2 toolchain ships GNU coreutils 8.32, confirmed
# via `mv --version` before relying on this). `mv -T A B` is a single
# `rename()` syscall: it either fully succeeds (B now IS A, fully populated,
# in one indivisible step -- there is no window where B exists but is
# incomplete) or fully fails with BOTH sides untouched (when B already
# exists and is non-empty). Verified empirically against this exact
# toolchain before writing this fix, including under GENUINE CONCURRENT
# contention -- 5 parallel processes racing `mv -T` against an
# already-populated target (all 5 failed cleanly, target untouched, all 5
# candidates survived intact) and 5 parallel processes racing a fresh claim
# with no pre-existing target (exactly 1 succeeded, the other 4 failed
# cleanly with their own content intact). See the round-2 fix-up section of
# `docs/diagnoses/2026-08-03-discipline-tooling-hardening-c9f4e1.md` for the
# full empirical record. This closes the gap structurally, not by narrowing
# a timing window: whatever a reader finds at the canonical lock path, if
# anything, was placed there whole by a single atomic publish, so a
# holder-less (or partially-written) directory at that path can no longer
# occur as a legitimate in-flight state, regardless of scheduler delay.
#
# NO AUTOMATIC RECLAIM -- the OI-92 decision (2026-08-05, founder-ratified).
#
# Earlier revisions tried to auto-reclaim a lock whose holder PID was dead.
# That reclaim failed independent review FOUR consecutive times, every time on
# the SAME check-then-act shape, each fix relocating the defect one step
# rather than removing it:
#
#   round 1  release deleted a lock it no longer owned
#   round 2  claim became visible before the holder file was written
#   round 3  reclaim decided-then-acted (blind `rm -rf`)
#   round 4  reclaim's restore-then-delete: `mv -T "$graveyard" "$lock_path"`
#            FAILS into a non-empty destination (the very semantic the claim
#            path depends on), but the following `rm -rf "$graveyard"` ran
#            UNCONDITIONALLY. A third process claiming the momentarily-emptied
#            path made the restore fail and the stolen LIVE lock get deleted --
#            leaving its owner and the new claimant both believing they held
#            the mutex. Reproduced by execution, not argument.
#
# There is no correct version of that reclaim on this toolchain, which is why
# this is a removal and not a fifth layer. `flock` is NOT available on this
# Git-Bash/MSYS2 stack (checked). With only `mkdir` / `mv -T` / `kill -0` there
# is no atomic "remove THEIR lock AND install MINE": a directory destination
# makes `mv -T` fail-if-present (correct for claiming, useless for replacing),
# and a file destination makes it replace unconditionally (exactly backwards).
# The operation the reclaim needs cannot be expressed by the primitives here.
#
# So a lock whose holder is dead is REFUSED, with the one-line manual clear
# printed. The `started=` timestamp in the holder file lets a human sanity-check
# a suspiciously old holder before clearing it. The failure direction is always
# "wait / manual `rm -rf`", never "silently proceed concurrently" -- which was
# already this file's stated contract for the PID-reuse case; it now simply
# holds universally.
#
# What this costs, stated plainly: a holder killed WITHOUT its trap running
# (`kill -9`, power loss) leaves a lock needing one manual `rm -rf`. That set is
# small and got smaller -- the trap now also catches HUP, so closing a terminal
# no longer leaks a lock. It notably does NOT include the incident this file was
# built for: a timed-out `safe_commit.sh` is not killed (a timeout does not kill
# the process), so its trap runs normally. That incident needed the CLAIM path,
# which is verified sound under 5-way contention -- never the reclaim.
#
# Usage (from a caller script, after `set -u`):
#   . "$(dirname "$0")/_git_lock.sh"
#   git_lock_acquire "commit" || exit 1
#   ...git-mutating work...
#   git_lock_release   # also runs automatically via the EXIT/INT/TERM trap

_GIT_LOCK_DIR=""

# Portable PID-liveness check. Verified empirically in this repo's actual
# Git-Bash-on-Windows environment (2026-08-03): `kill -0 <pid>` correctly
# reports a live PID as alive and a nonexistent PID as dead, so no
# `tasklist`-based fallback is needed (and one is deliberately NOT added --
# `tasklist //FI` argument-mangling under MSYS2 path-conversion is its own
# footgun this repo has no existing precedent for handling).
_pid_alive() {
  pid="$1"
  [ -z "$pid" ] && return 1
  kill -0 "$pid" 2>/dev/null
}

# A release MUST verify it still owns the lock -- compare the holder file's
# recorded pid to $$ -- before removing anything.
#
# Round-1 review finding #1 (blocking) established this against an earlier
# version that removed $_GIT_LOCK_DIR unconditionally. The cascade it
# demonstrated ran THROUGH the auto-reclaim: holder A's lock is reclaimed as
# stale (a false positive) by process B, B legitimately acquires, then A's EXIT
# trap deletes B's lock out from under it. **That specific cascade can no longer
# originate in this file** -- OI-92 removed the auto-reclaim, so nothing here
# ever takes over another process's lock path.
#
# The check stays, and is still load-bearing, for the paths that remain:
# a human running the documented manual `rm -rf "$lock_path"` while the original
# holder is somehow still alive, and anything outside this file placing content
# at the lock path. Both end with $_GIT_LOCK_DIR pointing at a directory this
# process no longer owns, which is exactly what the pid comparison catches.
# Cheap, and the failure it prevents (deleting a live lock) is severe.
git_lock_release() {
  if [ -n "$_GIT_LOCK_DIR" ] && [ -d "$_GIT_LOCK_DIR" ]; then
    owner_pid=""
    if [ -f "$_GIT_LOCK_DIR/holder" ]; then
      owner_pid="$(sed -n 's/^pid=//p' "$_GIT_LOCK_DIR/holder" 2>/dev/null)"
    fi
    if [ "$owner_pid" = "$$" ]; then
      rm -rf "$_GIT_LOCK_DIR" 2>/dev/null
    else
      echo "[git-lock] NOTE: lock at $_GIT_LOCK_DIR is no longer owned by this" >&2
      echo "  process (pid=$$); current holder is pid=${owner_pid:-unknown}." >&2
      echo "  NOT removing another process's lock." >&2
    fi
  fi
  _GIT_LOCK_DIR=""
}

# git_lock_acquire <op-label>
# Returns 0 with the lock held (released automatically on EXIT/INT/TERM via
# trap, or explicitly via git_lock_release). Returns 1 and prints a reason to
# stderr if the lock could not be acquired -- caller MUST check the return
# code and refuse to proceed, never race ahead regardless.
git_lock_acquire() {
  op_label="${1:-git operation}"
  git_dir="$(git rev-parse --git-dir 2>/dev/null)"
  if [ -z "$git_dir" ]; then
    echo "[git-lock] FAILED: not a git repo (git rev-parse --git-dir empty)." >&2
    return 1
  fi
  lock_path="$git_dir/.safe_git_op.lock"

  attempt=0
  # Bounded at 3. Since the OI-92 removal of auto-reclaim, the ONLY path that
  # loops is the vanish race below (the lock was released between our failed
  # publish and our read) -- every other outcome returns immediately. So this
  # bound now means "give up if the lock keeps appearing and vanishing 3 times
  # in a row", which is the only way to exhaust it. The earlier rationale here
  # described retrying after a reclaim; that path no longer exists.
  while [ "$attempt" -lt 3 ]; do
    attempt=$((attempt + 1))

    # Prepare the FULL holder content in a private, uniquely-named candidate
    # first -- nothing else can see or race this path, so writing to it is
    # always safe regardless of how slow `date` or anything else is.
    candidate="$git_dir/.safe_git_op.lock.candidate.$$"
    rm -rf "$candidate" 2>/dev/null
    if ! mkdir "$candidate" 2>/dev/null; then
      echo "[git-lock] FAILED: could not create private candidate dir $candidate." >&2
      return 1
    fi
    {
      echo "pid=$$"
      echo "op=$op_label"
      echo "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$candidate/holder" 2>/dev/null

    # Single atomic publish. Succeeds iff $lock_path did not already exist
    # as a non-empty directory at the instant of the underlying rename();
    # see this file's header for the empirical verification (including
    # under genuine concurrent contention) backing that claim.
    if mv -T "$candidate" "$lock_path" 2>/dev/null; then
      _GIT_LOCK_DIR="$lock_path"
      # HUP included (OI-92): without it, closing the terminal killed the shell
      # without running the trap and leaked a lock. That mattered little while a
      # dead-holder lock auto-reclaimed; now that a stale lock is a manual
      # `rm -rf`, keeping the leak set as small as possible is the whole point.
      #
      # THE SIGNAL HANDLERS MUST `exit`, NOT just clean up (OI-92 B-pass). A
      # trapped signal whose handler does not exit runs the handler and then
      # RESUMES execution at the point of interruption -- verified by execution
      # on this stack, not assumed. The previous `trap 'git_lock_release' EXIT
      # INT TERM` therefore meant a Ctrl-C released the lock and let the script
      # CARRY ON without it, so another process could acquire and run
      # concurrently: precisely the mutual exclusion this file exists to
      # provide, lost on the one path nobody tested. Each signal now releases
      # and terminates with the conventional 128+signum status.
      #
      # The EXIT trap still fires after a signal handler's `exit`, calling
      # git_lock_release a second time. That is harmless and deliberate: the
      # first call clears $_GIT_LOCK_DIR, so the guard at the top of
      # git_lock_release makes the second a no-op (confirmed by execution --
      # no double-delete, and no attempt to remove a path this process may no
      # longer own).
      trap 'git_lock_release' EXIT
      trap 'git_lock_release; exit 129' HUP
      trap 'git_lock_release; exit 130' INT
      trap 'git_lock_release; exit 143' TERM
      return 0
    fi
    rm -rf "$candidate" 2>/dev/null

    # Publish failed -- $lock_path already exists (a real holder, or a
    # stale one from a dead process). No read-after-write gap to worry
    # about here: whatever is at $lock_path, if anything, was placed there
    # by a single atomic publish (this same mv -T), so `holder` is either
    # absent (nothing there / a foreign, non-lock-protocol directory) or
    # complete -- never mid-write.

    # VANISH RACE (benign, retryable -- OI-92). The previous holder may have
    # RELEASED in the window between our publish attempt failing and this
    # read, leaving nothing at $lock_path at all. That is ordinary contention,
    # not staleness. Retry the publish rather than reporting a stale lock that
    # no longer exists -- without this, losing a race to a short-lived holder
    # would print a "clear it by hand" instruction for a path that is already
    # gone. This is the ONLY looping path now that reclaim is removed, which is
    # what keeps the "after $attempt attempts" message below meaningful: it can
    # now only mean the lock kept appearing and vanishing.
    if [ ! -d "$lock_path" ]; then
      continue
    fi

    holder_pid=""
    holder_started=""
    if [ -f "$lock_path/holder" ]; then
      holder_pid="$(sed -n 's/^pid=//p' "$lock_path/holder" 2>/dev/null)"
      holder_started="$(sed -n 's/^started=//p' "$lock_path/holder" 2>/dev/null)"
    fi

    if [ -n "$holder_pid" ] && _pid_alive "$holder_pid"; then
      holder_op="$(sed -n 's/^op=//p' "$lock_path/holder" 2>/dev/null)"
      echo "[git-lock] REFUSING: another git operation is in progress -- not racing it." >&2
      echo "  holder pid=$holder_pid op=\"$holder_op\" started=$holder_started" >&2
      echo "  Wait for it to finish. If you are CERTAIN it is actually dead" >&2
      echo "  (e.g. the started timestamp is implausibly old), clear it manually:" >&2
      echo "    rm -rf \"$lock_path\"" >&2
      return 1
    fi

    # NO RECLAIM -- OI-92, founder-ratified 2026-08-05. Reaching here means the
    # holder PID is dead, OR there is a directory at $lock_path that this
    # protocol did not create (a lock published by this code ALWAYS carries a
    # complete `holder` file, because the publish is one atomic `mv -T`; a
    # holder-less lock dir cannot be a legitimate in-flight state).
    #
    # Both are REFUSED and never cleared automatically. The four rounds of
    # review that killed the previous auto-reclaim, and why no correct version
    # of it exists with the primitives on this toolchain, are in the
    # NO AUTOMATIC RECLAIM section of this file's header.
    echo "[git-lock] REFUSING: a lock is already present at" >&2
    echo "    $lock_path" >&2
    if [ -n "$holder_pid" ]; then
      echo "  and its holder pid=$holder_pid is NOT alive (started=${holder_started:-unknown})." >&2
      echo "  That makes it STALE -- almost certainly a process killed without its" >&2
      echo "  trap running (kill -9, or a power loss). A timeout does NOT do this:" >&2
      echo "  a timed-out wrapper keeps running and releases normally." >&2
    else
      echo "  but it carries no readable 'holder' file, so it was NOT created by" >&2
      echo "  this lock protocol (whose publish is atomic and always complete)." >&2
    fi
    echo "  It is not cleared automatically, by design. Confirm no git operation" >&2
    echo "  is genuinely running, then clear it by hand:" >&2
    echo "    rm -rf \"$lock_path\"" >&2
    return 1
  done

  echo "[git-lock] FAILED: could not acquire the lock after $attempt attempts." >&2
  return 1
}
