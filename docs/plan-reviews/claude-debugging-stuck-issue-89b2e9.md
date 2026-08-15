---
branch: claude/debugging-stuck-issue-89b2e9
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
tier: platform
reviewed_at: 2026-08-15T13:45:00+05:30
---

# Plan review — realtime PRO gate (e4a7c9)

## What shipped

One fix, three commits:

| commit | contents |
|---|---|
| `bfb0415c` | SoT concept `sync_realtime_subscription`; e4a7c9 diagnose-doc corrected |
| `b6b0c89e` | The gate (sink), the downgrade teardown, the duplicate-teardown collapse, kill-switch, 7-case behavioral test |
| `52602ac9` | B-pass P0 fix + 2 further regression cases |

`realtime.list_changes()` was 6,463s of 18,279s lifetime database CPU (35.4%)
across 900,823 calls, serving a PRO-only feature to a PRO population of ~zero,
because the entitlement check lived on one of two callers.

## Round 1 — 4 BLOCKING

1. **The in-flight join was redundant.** gotrue 2.27.1 already de-duplicates
   concurrent `refreshSession()` on the refresh-token string
   (`_pendingRefreshes`, `gotrue_client.dart:1549`). I verified this in the
   pinned package rather than trusting the reviewer — an external quote is a
   hypothesis until fetched. This deleted an entire planned fix.
2. **10 of 11 `refreshSession()` sites are deliberate post-401 hard refreshes**
   that must not be collapsed; the one convertible site would have deleted the
   literal string a source-grep test greps for.
3. **The `_withLock` ceiling had no named duration or ordering invariant** — at
   45s-inner/20s-outer the correction would have been a silent no-op.
4. **The Phase-B ceiling could drop the ToS/DPDP consent write** — once per
   account, no retry, a regression of the closed b3f9e7 P0.

## Round 2 — 2 BLOCKING, including one against round 1's own correction

Round 2 exists because corrections introduce defects, and it earned its keep:

- **Round 1's "carry the keep-newest clause" was wrong on its merits.**
  `cron.job_run_details` has no `id` column (verified live: `jobid, runid,
  job_pid, database, username, command, status, return_message, start_time,
  end_time`), so the clause would not compile — and the obvious repair
  (keep-newest *overall*) would delete the last run of 23 of 24 jobs, causing
  precisely the harm the correction was written to prevent.
- **The identity re-check guarded only one of two post-await returns.**
  `supabase_service.dart:199` returns the entry-captured `session`, and that is
  the *likelier* swap path since `signOut()` invalidates the refresh token
  server-side so `_doRefresh` throws rather than returning stale data.

Plus: `signInWithPassword` is unbounded and is the call that actually 504'd, so
naming the constant `signInTimeout` would have misrepresented the fix.

## Why the batch was split

§4.12: *"When successive reviews keep surfacing new material issues, that is the
signal the unit is too large — split it and ship the smallest converged piece."*
Two rounds, both with blocking findings, and round 2 invalidating a round-1
correction. Fix 1 was the only piece neither round found a blocking issue in,
and the highest-value one. Fixes a9c4e2 / d7b1f8 / the log-retention migration
are HELD with their findings recorded — each has a validated diagnose-doc and a
specific next action, and they ship as their own batches.

## B-pass — 1 P0, accepted and fixed

`docs/reviews/realtime-pro-gate-bpass.md`. The `guard_without_its_mirror` lens
found that `unsubscribeRealtime()` re-armed the anti-flood latch, and
`day_rollover_service` calls it on every `AppLifecycleState.paused` — so a free
user re-fired the skip telemetry (an Edge Function call plus a `client_errors`
row) on every foreground. Bug-class 2.13 reintroduced by the anti-flood
mechanism itself.

The shipped test passed because its "logged ONCE" case never modelled a pause.
Written from the same mental model as the code; the exact reason the lens says a
diff's own tests are not evidence.

## Ground truth verified

Every load-bearing claim was checked against source or live state, not prose:
gotrue's dedup read from the pinned package; `_locks` / `_withLock` read from
`auth_session_bootstrapper.dart`; the ToS write's position relative to the seven
migrator blocks; `_downgradeLocally`'s 8 call sites (the plan said 4);
`cron.job_run_details`'s columns via live SQL; the 900,823 / 6,463s figures via
`pg_stat_statements`.

Two gates caught errors I made and were not worked around:
`check_sot_registry_parity` rejected a citation pointing at the teardown *block*
instead of the method, then rejected five line-ranges my own edits had shifted
plus an unrelated pre-existing `day_rollover` citation my change moved.

## Mutation proof

Six mutations run and measured, each reverted:

| mutation | red |
|---|---|
| neuter the entitlement gate | 2 |
| delete `onDowngrade?.call()` | 1 |
| drop the `_realtimeSkipLogged` latch | 1 |
| `proStateSnapshot()` → `isPro()` | 1 |
| restore the B-pass P0 | 1 (1 vs 5) |
| delete the swap reset | 3 |

Counts are measured, not predicted — my predictions were wrong on two of the
first four. Mutation 6 reddens 3 rather than 1 because the latch lives on the
singleton and the swap reset doubles as this file's test isolation; stated so the
number is not read as stronger than it is.

## Known condition outside this batch

`main` is RED on `Supabase Integration Tests` (OI-121, `qa@icanbefitter.com`
absent from `auth.users`), owned by a separate in-flight thread. The branch is
unaffected; the merge is gated on that.
