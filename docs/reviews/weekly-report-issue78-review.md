---
reviewed_at: 2026-10-07T00:00:00+05:30
staged_against: 88ce1db (round 1), e1ec97d (round 2), fad7232 delta (round 3)
blast_radius: account
reviewer: claude-sonnet-via-skill (3 fresh context-blind rounds; round 2 on the post-fix tree, round 3 on the delta of round 2's fixes)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 13
verdict: accepted
---

# Code Review — GitHub issue #78 (Weekly Report: dead video, capped refresh, coach copy)

Diff reviewed: `origin/main..` the branch (reports_screen.dart, the new `weekly_report_refresh_policy.dart`,
`wardroom_copy.dart`, tests, registry, diagnose `d7b2e5`). All rounds were dispatched context-blind and
read-only (no scripts, no network, no file edits). Every finding below is closed in the same batch.

## Round 1 (on 88ce1db) — 6 findings

### Finding 1 — P2 — guard_without_its_mirror
- **file:line:** reports_screen.dart (free-user line); weekly-report/index.ts:124-153
- **claim:** "Your first dispatch is on us." is gated on the per-device Hive flag `first_report_generated`; the server's rule is a lifetime ledger. A reinstall / second device / sign-out shows the promise, then Generate returns 403 and a raw error.
- **verification:** `grep -rn first_report_generated lib supabase` (one file); `configBox` cleared on sign-out.
- **status:** accepted — fixed: a 403 from an explicit Generate sets the flag and opens the paywall (round 2 later narrowed it to a NOT_PRO body, see R2-2).

### Finding 2 — P2 — guard_without_its_mirror
- **claim:** once-per-IST-day cap + no Regenerate means a workout logged after the morning refresh shows next IST day; the initState comment still said "refresh on every open".
- **status:** accepted — founder decision (option B, "Regenerate removed"); stale comment corrected. Not a defect to fix further.

### Finding 3 — P2 — blast_radius_mismatch
- **claim:** diagnose doc declared `tier: s_fix` / `blast_radius: feature` but the diff touches `lib/core/copy` (account tier) and 3 product files.
- **status:** accepted — re-tiered `m_fix` / `account`; this review + a plan-review record added.

### Finding 4 — P3 — missing_input / writer_reader_drift
- **claim:** stamp written with `DateTime.now()`, policy reads `nowWall()` (test-clock seam); the test never fed the production (local, no-Z) stamp format.
- **status:** accepted — stamp written with `nowWall()`; no-Z case added; test green in IST, UTC and America/Los_Angeles.

### Finding 5 — P3 — guard_without_its_mirror
- **claim:** `onFree: () {}` is evaluated once at open; a free user who upgrades while the screen is open gets no refresh. No in-flight dedupe.
- **status:** accepted — `ref.listen(subscriptionInfoProvider)` re-runs the refresh on free→PRO; the dedupe became R2-1.

### Finding 6 — P3 — stale prose
- **claim:** `hold_week_identity_behavioral_test.dart` header still listed the removed share-as-video surface ("four surfaces").
- **status:** accepted — fixed.

## Round 2 (on e1ec97d, the post-fix tree) — 3 findings

### R2-1 — P2 — guard_without_its_mirror (the fix's own mirror)
- **claim:** the cap reads a stamp written only AFTER the slow Gemini call; a re-open, the new free→PRO listener, or the Generate card during that window each fire another thinking-on call. The listener added in round 1 created the second trigger without a guard.
- **status:** accepted — static one-call-at-a-time guard (`if (_inFlight) return;`, cleared in `finally`), Generate card disabled while a silent call runs.

### R2-2 — P3 — guard_without_its_mirror
- **claim:** the 403 branch keyed on status alone; a 403 that is not the free-quota answer would set the flag and open the paywall.
- **status:** accepted — `isLifetimeFreeReportSpent()` requires the `NOT_PRO` body code (map or JSON string); behavioral test.

### R2-3 — P3 — asserted_fixture_value (pins weak vs respell/move/decoy)
- **claim:** four new source pins pass under a decoy, a re-indent, a dropped `prev != null`, an unconditional refresh, a `DateTime.now().toUtc()` stamp.
- **status:** accepted — pins scoped to method bodies and order-checked; 9 mutants applied and every one reddened (one "mutant" that only added a comment was equivalent and was redone as a real hoist, which reddened).

## Round 3 (delta e1ec97d..fad7232: round 2's own fixes) — 4 findings

### R3-1 — P2 — guard_without_its_mirror
- **file:line:** reports_screen.dart (static `_inFlight`, `finally`, Generate `onPressed`)
- **claim:** `_inFlight` was a plain static bool; the `finally` rebuilt only the screen that ran the call. A PRO user who re-opened the screen mid-call got a new State whose Generate button stayed disabled (no spinner, no text) and which never re-read the cache, so it never showed the fresh report. Before the guard that second screen would have run its own call.
- **verification:** `grep -n _inFlight lib/features/profile/screens/reports_screen.dart` (readers: the guard and `onPressed` only; nothing subscribed to completion).
- **status:** accepted — fixed: `WeeklyReportCallGate` (observable `ValueNotifier`); every screen subscribes in `initState`, unsubscribes in `dispose`, and on change re-reads the cache and rebuilds (deferred to a microtask because the gate can flip inside a build/listen phase).

### R3-2 — P2 — unbounded call
- **claim:** `callFunction` has no timeout of its own and `retryColdStart` retries 502/503/504 three times, so the gate (and a disabled Generate card) could be held for minutes.
- **verification:** `grep -n timeout lib/core/services/supabase_service.dart` (only the token refresh has one).
- **status:** accepted — fixed: `.timeout(WeeklyReportCallGate.callTimeout)` (120s) at the call site, a friendly `TimeoutException` message, and a behavioral test that a timed-out body clears the flag.

### R3-3 — P3 — setState before the try
- **claim:** `_inFlight = true;` and `setState` ran before `try {`, so a throw there (unmounted State, setState during build) skipped the `finally` and wedged the flag.
- **status:** accepted — fixed: the flag now lives in `runExclusive`'s own try/finally, and the explicit path guards `if (!mounted) return;` before `setState`.

### R3-4 — P3 — pins defeatable
- **claim:** order-only text checks passed under moving the set below the await, discarding the helper's result, putting the listener's call outside its `if`, and a second matching button.
- **status:** accepted — the guard became a behavioral unit (`runExclusive`: second call does not run its body, throw clears, timeout clears, listeners see true then false); the pins were re-anchored on `if (e is FunctionException && isLifetimeFreeReportSpent(...))`, on the call being the body of the transition `if`, and on the real `.timeout(` at `callFunction`. 11 mutants of the new code, every one reddened.

## Verified clean in round 3
- `FunctionException.details` is the DECODED JSON map for a `application/json` response (`functions_client-2.7.1` `functions_client.dart:221-270`), and the weekly-report 403 sends `Content-Type: application/json` with `code: "NOT_PRO"`, so the 403 branch fires in production; `FunctionsHttpException extends FunctionException`.
- A `return` inside `catch` still runs `finally`; a disposed widget is handled by `mounted`.

## Lenses that returned clean (rounds 1-2)
- secrets_in_tree: no credential-shaped literal in the diff.
- function_exception_swallow: no new `.functions.invoke`; the silent branch swallows by design and logs.
- unawaited_no_error_sink: `gateAndVerify` is synchronous for this non-high-value feature; `_runCallback` reports callback throws; `mounted` checked in `onPro`.
- missing_input: every symbol exists (`FunctionException` show-import, `nowWall`, `WardroomCopy.reportCard*`); `flutter analyze lib/` has no warning/error in the touched files.
- asserted_fixture_value (IST boundary instants, copy strings) recomputed independently and correct.
- Other tests grepping `reports_screen.dart` (canonical_target, lifetime_meter, pro_gate, reports_this_week_count, hold_week_identity) pass; no other consumer of the removed symbols.

## Founder triage notes
Round 3 reviewed round 2's fixes and found two P2s in them, so a fourth round on the round-3 delta was NOT run; those fixes are covered by 11 mutants, 24 contract tests (5 behavioral on the gate) and the full suite at pre-push. See the plan-review record caveat.
