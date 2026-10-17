---
branch: discipline-tooling-hardening
diagnose: c9f4e1
date: 2026-08-05
blast_radius: platform
pass: B
verdict: accepted
---

# B-pass — discipline-tooling-hardening (Units 3a + 3c, diagnose c9f4e1)

Self-initiated per §4.3 (≥account) and required independently at `platform`
per §4.12.3.

**Initial verdict: rejected — 1 × P1.** Fixed, regression-tested, and
negative-controlled by execution; **final verdict: accepted**.

## P1 — the trap handlers cleaned up but did not terminate, so a signalled wrapper kept running WITHOUT the lock it had just released

The change under review added `HUP` to the existing trap:

```sh
trap 'git_lock_release' EXIT HUP INT TERM
```

In POSIX sh, a trapped signal runs its handler and then **resumes execution at
the point of interruption**. The handler here does not exit. So on Ctrl-C the
lock is released and the wrapper *carries on* — past `git_lock_acquire`, into
its git-mutating section — while another process is now free to acquire and run
concurrently. That is precisely the mutual exclusion this file exists to
provide, absent on the one path no test covered.

**Verified by execution rather than reasoned about.** A minimal script trapping
`TERM` with a non-exiting handler printed `CLEANUP_RAN`, then
`RESUMED_AFTER_SIGNAL — script continued past the trap!`, then `CLEANUP_RAN`
again via EXIT, and exited **0**.

This was **pre-existing** for `INT`/`TERM` — rounds 1-3 never examined the trap —
and adding `HUP` would have extended it to a third signal.

**Fix.** Handlers release *and* terminate, with conventional 128+signum status:

```sh
trap 'git_lock_release' EXIT
trap 'git_lock_release; exit 129' HUP
trap 'git_lock_release; exit 130' INT
trap 'git_lock_release; exit 143' TERM
```

**Fix verified, including the parts that could have gone wrong:**

- **Double-release is safe.** A signal handler's `exit` also fires the EXIT
  trap, so `git_lock_release` runs twice. The first call clears
  `$_GIT_LOCK_DIR`, and the guard `[ -n "$_GIT_LOCK_DIR" ]` makes the second a
  no-op — so it cannot delete a path this process may no longer own.
- **Traps only exist while the lock is held.** Both `_GIT_LOCK_DIR=` and the
  `trap` statements sit inside the publish-success branch, after the atomic
  `mv -T`. A run that never acquires installs no handler.
- **No caller overwrites them.** The lock script is *sourced*, so its traps land
  in the caller's shell — a caller setting its own `trap ... EXIT` would silently
  replace them and leak the lock forever. Checked: none of `safe_commit.sh`,
  `safe_push.sh`, `safe_merge.sh` sets a trap.

**Regression test added** — `a signal (TERM) releases the lock AND terminates`.
It asserts a `RESUMED.marker` written after the interrupted sleep does **not**
exist, that the lock directory is gone (so the fix does not trade a race for a
wedged lock), and that a fresh acquire then succeeds.

The kill is issued from **inside a shell**, deliberately: on Windows, Dart's
`Process.kill` maps to `TerminateProcess` and runs no handler at all, so a
Dart-issued kill could not distinguish the fixed code from the broken code. The
test would have been vacuous.

**Negative-controlled:** reverting the trap to `EXIT HUP INT TERM` makes **only**
this test fail; the other five pass. Script restored from a byte-copy, md5
re-verified (`752c5f3f…`).

## Verified sound (attacked, not inspected)

- **The deletion is complete.** No dangling reference to
  `_RECLAIM_MIN_AGE_SECONDS`, `graveyard=`, or `stolen_pid` anywhere in
  `scripts/` or `test/`.
- **The removal is pinned from the opposite direction.** The stale-lock test was
  *inverted*, not deleted, and asserts `isNot(contains('Reclaiming stale
  lock'))`. Re-adding a naive auto-reclaim (`rm -rf "$lock_path"` + `continue`,
  the shape a well-meaning future patch would take) makes **only** that test
  fail. Two tests whose subject genuinely no longer exists were deleted, with an
  in-file note recording what covered their guarantee instead — so the coverage
  loss is explicit rather than silent.
- **The caller wiring adds only what it claims.** `safe_commit.sh` adds the lock
  source + acquire and nothing else. `safe_push.sh` adds that plus a round-2
  word-splitting fix (`EXTRA_ARGS="$*"` re-expanded unquoted → real positional
  `"$@"`), which has its own test.
- **The vanish-race retry cannot spin.** Bounded by the same `attempt < 3`, and
  it is now the only looping path, which is what keeps the exhaustion message
  meaningful.

## Why `accepted` despite a P1

The P1 was in *pre-existing* code, is now fixed and independently regression-
tested, and the rest of the change is a **net deletion** of the component that
failed four review rounds. The retained surface — the atomic-publish claim path —
is the part that three rounds and two cascade repros already failed to break.

Noted for the future: `kill -9` and power loss still leave a lock needing one
manual `rm -rf`. That is the accepted, documented cost of removing auto-reclaim,
and the message that prints when it happens now says so explicitly.
