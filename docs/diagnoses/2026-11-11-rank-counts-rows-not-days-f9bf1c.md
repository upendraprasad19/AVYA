---
bug_id: f9bf1c
date: 2026-11-11
batch: coach-workout-parity-server
status: fixed
blast_radius: account
symptom: >-
  Coach workout parity 2 (S1): the server counted ROWS where the client counts DISTINCT completed days. The rank job's
  promotion-ceremony workout total (a head:true count of workout_logs rows), the i-see-you-callout Saturday gate
  (a head:true count of rows by logged_at) and getPromotionStatus (all-time total and the 28-day cadence, both row
  counts) over-counted a date that holds two workout_logs rows. weekly-recalc floored total_workouts_done from the
  DATES OF workout_log_exercises rows, so a day with exercise rows but no completed workout_logs row counted as a
  completed day. The client number (WorkoutReadService.completedWorkoutDayCount) and the server numbers drifted apart.
concept: completed_day_count_server
sot_registry_entry: completed_day_count_server
writers:
  - file: supabase/functions/_shared/distinct_dates.ts
    method: countDistinctDates (the ONE server completed-day counter; Set of trimmed YYYY-MM-DD dates, NULL / malformed ignored)
    line: 22
  - file: supabase/functions/evaluate-rank-promotions/index.ts
    method: handler per-user totalWorkouts (paged workout_logs date read, truncated read fails that user, then countDistinctDates)
    line: 252
  - file: supabase/functions/weekly-recalc/completed_days.ts
    method: completedDayCounts / mergeMonotonicTotal (per-user distinct completed days; max(recomputed, existing))
    line: 12
  - file: supabase/functions/_shared/tools/progress/getPromotionStatus.ts
    method: getPromotionStatus all-time total (countDistinctDates) and recent28Dates cadence numerator
    line: 164
  - file: supabase/functions/i-see-you-callout/streak_gate.ts
    method: hasDeepStreak / readDeepStreak (14 distinct completed days among the last 28 IST dates)
    line: 18
readers:
  - file: supabase/functions/evaluate-rank-promotions/index.ts
    method_or_widget: state.totalWorkouts into the rank ladder gates and the ceremony text (trigger_metadata.total_workouts)
    line: 303
  - file: supabase/functions/weekly-recalc/index.ts
    method_or_widget: completedDayCounts call at 300, mergeMonotonicTotal into user_progress.total_workouts_done at 418
    line: 300
  - file: supabase/functions/_shared/tools/progress/getPromotionStatus.ts
    method_or_widget: total_workouts / actual_4w in the coach tool result (also feeds the ETA at 263 and 357)
    line: 211
  - file: supabase/functions/i-see-you-callout/index.ts
    method_or_widget: checkFirstInStreakSaturday gate (readDeepStreak)
    line: 337
  - file: lib/core/services/workout_read_service.dart
    method_or_widget: completedWorkoutDayCount (the CLIENT counterpart this server counter now matches)
    line: 61
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: workout_logs
cloud_columns: [user_id, date]
contract_test_path: supabase/functions/_shared/distinct_dates_test.ts
ist_handling:
  - istDatesEnding(28, now) in i-see-you-callout/streak_gate.ts and recent28Dates (getPromotionStatus.ts:79) window on IST date strings; weekly-recalc bounds the read with its 28 IST window dates
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - "[evaluate-rank-promotions] user=<id> totalWorkouts err (console.error, user skipped, self-heals next night)"
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: 'select\("\*", \{ count: "exact", head: true \}\) on workout_logs for a day count', absent: true }
  - { pattern: 'new Set\(userLogs\.map\(\(l\) => l\.date\)\) as the weekly-recalc floor', absent: true }
proposed_fix: >-
  One helper countDistinctDates in _shared/distinct_dates.ts, used by every server completed-day counter. The rank job
  pages workout_logs dates and counts distinct ones; a truncated read throws, so a cut can never under-count into a wrong
  rank state (the per-user try/catch skips that user). weekly-recalc reads workout_logs (id, user_id, date) inside its 28
  IST dates and floors total_workouts_done with completedDayCounts, merged by mergeMonotonicTotal (the counter never
  decreases, 3a7b9f). getPromotionStatus counts the all-time total from distinct dates (a truncated read throws) and the
  28-day cadence from recent28Dates. The Saturday callout gate moves to streak_gate.ts. The four cron functions gain the
  export handler(req, deps = realDeps()) seam so the handlers are behaviourally testable.
regression_test_planned:
  - supabase/functions/_shared/distinct_dates_test.ts
  - supabase/functions/evaluate-rank-promotions/index_test.ts
  - supabase/functions/weekly-recalc/index_test.ts
  - supabase/functions/weekly-recalc/completed_days_test.ts
  - supabase/functions/_shared/tools/__tests__/getPromotionStatus_test.ts
  - supabase/functions/i-see-you-callout/streak_gate_test.ts
  - supabase/functions/i-see-you-callout/index_test.ts
related_bugs:
  - 0ebfcb  # 1a: coach completions count the workout once per day; the client counts distinct completed days
  - 3a7b9f  # monotonic recompute: total_workouts_done may be raised by a recompute, never lowered
recurrence: |
  Writer drift between a server counter and a client counter of the same concept. The client's completed-day count was
  made the distinct-day rule in 0ebfcb (completedWorkoutDayCount); the server kept counting rows (rank job,
  getPromotionStatus, the Saturday gate) or exercise-row dates (weekly-recalc). Same class as the monotonic-field recompute
  of 3a7b9f for weekly-recalc: the floor must not lower the stored counter. The fix applies the known-good shape: one
  counting helper that every reader of the concept calls.
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "No client change in S1. The counterpart WorkoutReadService.completedWorkoutDayCount (workout_read_service.dart:61) already counts distinct completed days; the server now matches it." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "Service-role Edge Functions only; no Hive access." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "No schema change. workout_logs has user_id and date (backups/live_schema_columns.json), the only columns the new reads select (id, user_id, date)." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "Pre-launch, testers only (CLAUDE.md section 1). No data repair: total_workouts_done is monotonic and only ever raised. This batch ran no live query." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: verified, evidence: "Deployed from main 72862b2f with the founder's go (2026-11-11): GET /functions/<slug> reads evaluate-rank-promotions v25, weekly-recalc v31, i-see-you-callout v16 (all 06:21Z), ai-proxy (getPromotionStatus) v99 then v100 at 15:20Z with the S3 tile; verify_jwt false; each smoke answered its own 401." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "cron_call_log since the deploy: i-see-you-callout 14:00:07Z 2026-11-11 (19:30 IST) success 200. weekly-recalc has no cron.job (verified live earlier). evaluate-rank-promotions runs at 18:30Z (00:00 IST): its first run on v25 is after this record was written (no row before 15:45Z 2026-11-11), so the rank path's live run is not yet observed." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "Service-role reads of workout_logs; no policy touched." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret in S1." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "Client and server now count the same thing (distinct completed dates); weekly-recalc keeps the monotonic merge so a recompute never lowers the stored counter the client pushes with GREATEST. Verified by the Deno handler tests, not by a live flow." }
impact_analysis: >-
  A date with two workout_logs rows counts once for the rank ceremony total, the promotion tool, the cadence and the
  Saturday callout (14 distinct days, not 14 rows). weekly-recalc no longer counts a day that has only exercise rows and
  no completed workout_logs row. A truncated or failed read now throws (the rank job skips that user for the night; the
  tool returns an error) instead of showing a smaller number. No schema, no client change.
---

# The server counts workout_logs rows, the client counts completed days (f9bf1c)

## Root cause
Four server counters each derived "how many workouts" on their own. `evaluate-rank-promotions` read a head:true row count
of `workout_logs`; `getPromotionStatus` read two row counts (all-time, and 28 days by `logged_at`); the `i-see-you-callout`
Saturday gate read a row count by `logged_at`; `weekly-recalc` floored `total_workouts_done` from the dates of
`workout_log_exercises` rows. The client counts distinct completed days (`completedWorkoutDayCount`, 0ebfcb). A date with
two `workout_logs` rows therefore over-counted on the server, and a day with only exercise rows counted in weekly-recalc.

## Fix
- `countDistinctDates` (`supabase/functions/_shared/distinct_dates.ts:22`): the one counter.
- Rank job (`evaluate-rank-promotions/index.ts:252`): paged date read, truncated throws, per-user catch skips the user.
- `weekly-recalc` (`index.ts:300`, `completed_days.ts:12`/`:30`): a completed-days read bounded to the 28 IST dates,
  floor from `completedDayCounts`, `mergeMonotonicTotal` keeps the lifetime counter monotonic. A failed completed-days
  read does not fail the tick (B-pass S1-F1): it is logged, the map is empty, every stored total is kept and the
  experience levels are still written; the next Sunday raises the floor.
- `getPromotionStatus` (`:164`, `:211`): distinct all-time total, `recent28Dates` cadence; a truncated read throws.
- Saturday gate (`i-see-you-callout/streak_gate.ts:18`/`:27`, called at `index.ts:337`): 14 distinct completed days in the
  last 28 IST dates.
- `export handler(req, deps = realDeps())` with `if (import.meta.main) serve((req) => handler(req))` on the four cron
  functions (rank, weekly-recalc, and the two reminder crons of S2), so the handlers are tested through their real code.

## Mutation evidence (rule 21)
Run by `mutate.py` in the session scratchpad (backup copy, apply, confirm applied, run the named test, restore, `cmp`);
the full table is in the session scratchpad `l2-mutations.md`. Rows for this slice (every `applied=True restored=True`):

| id | file | edit | result |
|---|---|---|---|
| M23 | `_shared/distinct_dates.ts` | countDistinctDates returns rows.length | RED: distinct_dates_test.ts 1 pass / 5 fail |
| M24 | `evaluate-rank-promotions/index.ts` | back to the head:true row count | RED: index_test.ts 3 pass / 4 fail |
| M25 | `weekly-recalc/index.ts` | floor back to wle dates | RED: index_test.ts 14 pass / 3 fail (completed_days_test.ts stays green, the helper is untouched) |
| M26 | `weekly-recalc/completed_days.ts` | mergeMonotonicTotal returns recomputed | RED: completed_days_test.ts 3 pass / 1 fail; index_test.ts 16 pass / 1 fail |
| M34 | `getPromotionStatus.ts` | getPromotionStatus counts rows | RED: getPromotionStatus_test.ts 5 pass / 3 fail |
| M35 | `evaluate-rank-promotions/index.ts` | per-user try/catch removed | RED: index_test.ts 5 pass / 2 fail |
| M43 | `getPromotionStatus.ts` | recent28Dates window starts a day early | RED: 7 pass / 1 fail |
| M50a | `i-see-you-callout/streak_gate.ts` | hasDeepStreak back to a row count | RED: streak_gate_test.ts 5 pass / 2 fail |
| M50b | `i-see-you-callout/index.ts` | Saturday call site back to the head:true logged_at count | RED: index_test.ts 2 pass / 1 fail (streak_gate_test.ts stays green, as expected) |
| M51c | `evaluate-rank-promotions/index.ts` | realDeps member stubbed | RED: index_test.ts 6 pass / 1 fail |
| M51d | `weekly-recalc/index.ts` | realDeps member stubbed | RED: index_test.ts 16 pass / 1 fail |
| M52 | `_shared/distinct_dates.ts` | malformed dates accepted | RED: distinct_dates_test.ts 5 pass / 1 fail |
| M53 | `weekly-recalc/index.ts` | completed-days read loses its window bounds | RED: index_test.ts 16 pass / 1 fail |
| M54 | `getPromotionStatus.ts` | all-time total derived from the 365-day window | RED: 7 pass / 1 fail |
| M56a | `evaluate-rank-promotions/index.ts` | rank read: truncated no longer throws | RED: index_test.ts 6 pass / 1 fail |
| M56b | `getPromotionStatus.ts` | all-time read: truncated no longer throws | RED: 7 pass / 1 fail (first run SURVIVED; see below) |
| M56c | `i-see-you-callout/streak_gate.ts` | readDeepStreak: truncated no longer throws | RED: streak_gate_test.ts 6 pass / 1 fail |
| M57 | `i-see-you-callout/streak_gate.ts` | readDeepStreak loses its .gte/.lte bounds | RED: streak_gate_test.ts 6 pass / 1 fail |

- **M56b first run survived.** The test used rows inside the 365-day window, so the later 365-day read's own truncation
  guard masked the removed all-time guard. The test now uses rows older than 365 days; the mutant re-ran RED.
- M25: `completed_days_test.ts` stays green by design (the mutant leaves the helper untouched); the handler test carries
  the red.
- Every file was restored byte-identical (`cmp`).

B-pass additions (2026-11-11, `docs/reviews/coach-workout-parity-server-bpass.md`), restored by sha256:

| id | file | edit | result |
|---|---|---|---|
| B1 | `weekly-recalc/index.ts` | the completed-days read's `.catch` removed (a failure fails the tick again) | RED: index_test.ts 16 pass / 1 fail |
| B2 | `i-see-you-callout/streak_gate.ts` | window built from the UTC date (`now - 5h30m`) | RED: streak_gate_test.ts 7 pass / 1 fail (the 10:00Z tests stay green: the gap the review named) |
| B3 | `getPromotionStatus.ts` | `recent28Dates` window from the UTC date | RED: getPromotionStatus_test.ts 8 pass / 1 fail |
