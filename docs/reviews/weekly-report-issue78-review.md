---
reviewed_at: 2026-10-07T00:00:00+05:30
staged_against: 88ce1db (round 1), e1ec97d (round 2)
blast_radius: account
reviewer: claude-sonnet-via-skill (2 fresh context-blind rounds; round 2 on the post-fix tree)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 9
verdict: accepted
---

# Code Review — GitHub issue #78 (Weekly Report: dead video, capped refresh, coach copy)

Diff reviewed: `origin/main..` the branch (reports_screen.dart, the new `weekly_report_refresh_policy.dart`,
`wardroom_copy.dart`, tests, registry, diagnose `d7b2e5`). Both rounds were dispatched context-blind and
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

## Lenses that returned clean (both rounds)
- secrets_in_tree: no credential-shaped literal in the diff.
- function_exception_swallow: no new `.functions.invoke`; the silent branch swallows by design and logs.
- unawaited_no_error_sink: `gateAndVerify` is synchronous for this non-high-value feature; `_runCallback` reports callback throws; `mounted` checked in `onPro`.
- missing_input: every symbol exists (`FunctionException` show-import, `nowWall`, `WardroomCopy.reportCard*`); `flutter analyze lib/` has no warning/error in the touched files.
- asserted_fixture_value (IST boundary instants, copy strings) recomputed independently and correct.
- Other tests grepping `reports_screen.dart` (canonical_target, lifetime_meter, pro_gate, reports_this_week_count, hold_week_identity) pass; no other consumer of the removed symbols.

## Founder triage notes
Round-2 fixes (fad7232) were verified by mutation + the targeted suite, not by a third independent review.
