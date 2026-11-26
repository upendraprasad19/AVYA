---
hermes_pass_id: 2026-06-27-hermes-sync-cost-debounce
ran_at: 2026-06-27T13:30:00+05:30
batch_scope: sync-cost-debounce (Unit H — H1a + H3 + H5)
lens_set: [L1, L11, L15, L16, L37, L40]
reviewer: context-blind Opus 4.8
findings_total: 0
findings_by_severity: { P0: 0, P1: 0, P2: 0, false_alarm: 0 }
verdict: accepted
---

# Hermes Pass — sync-cost-debounce (Unit H)

Deep multi-lens review of the platform-tier sync coalescing change, verified against
source (not just the diff). Run alongside the B-pass (which independently caught a P1 in
`flushPendingSyncs`, now fixed; this Hermes pass re-verified the fixed code).

## Findings by lens

### L1 — writer/reader drift — PASS
The coalesced-entry → `*Now()` split routes correctly. All ~14 fire-and-forget firers
(workout/nutrition/health WriteServices, train/onboarding/swap/template/tool_dispatcher) still
call the coalesced `syncWorkoutData()` / `syncNutritionData()` (bursts collapse — correct). The
2 awaited callers are repointed to `*Now()` (`scheduled_workouts_resync_migrator`,
`simulation_service`). `restoring_screen` fires the coalesced entry unawaited (fine —
full-sweep-backstopped). Tests updated consistently.

### L11 — concurrency / `SyncCoalescer.trigger` state machine — PASS
Read line by line: (a) no dropped final write — `_dirty=false` set before each pass, re-checked
after in the do-while → a mid-pass trigger re-raises it; (b) no infinite spin — only re-loops on a
fresh trigger; (c) no concurrent passes — `_inFlight` guard; (d) no wedge on throw — inner
try/catch + `finally` clears `_inFlight`; (e) no account-swap leak — `_onUserChanged` reassigns
both coalescers AND, decisively, `syncWorkoutDataNow()` re-resolves the owner via
`HiveUserSession.ensureOpenedForCurrentSession()` on every invocation, so a surviving trailing
pass writes the CURRENT session's box (idempotent upserts), never the old user's rows. (The flush
P1 the B-pass caught — a concurrent fan-out from `flushPendingSyncs` — was fixed by routing it
through `trigger`, which this pass re-verified.)

### L15 / L16 — restore/sync completeness — PASS
`syncWorkoutDataNow` re-pushes ALL local rows each pass (full box scan, idempotent upserts), so a
coalesced/dropped pass is a delay, not a loss — Hive remains SoT. On Flutter web,
`AppLifecycleState.paused` is unreliable, so `flushPendingSyncs` may not fire — but the next-login
full sweep is the real backstop, and it is sound. No loss window beyond the existing offline-first
delay envelope.

### L37 — budget / cap — PASS (goal met)
Genuinely reduces calls: a signup storm of ~18 `syncWorkoutData()` collapses to 1 in-flight + 1
trailing pass. `pushSnapshot` is deliberately NOT coalesced in this unit (the returning-user
`pushSnapshot` debounce is the separate H1b unit) — confirmed intentional. H3's `callFunction`
does not increase worst-case invokes that matter: retries fire only on transient cold-start
502/503/504 (calls that would otherwise have failed), bounded to 3 backoffs.

### L40 — EF contract — PASS
`callFunction` returns the full `FunctionResponse`, refreshes the token first (BUG-C d3a1c7
preserved; the redundant explicit refresh correctly dropped on the new path, retained on the
kill-switch path), same `daily-snapshot` name + body + auth. `response.data['coach_memory']` mirror
unchanged.

## Summary
No P0/P1/P2 findings on the (post-B-pass-fix) code. Every kill-switch defaults fix-active behind a
defensive try/catch on the `configBox` read. The coalescer state machine, the next-sweep backstop,
the EF contract, and H5's session guard are all sound.

verdict: accepted
