---
bug_id: c4e8b1
date: 2026-11-16
batch: generator-step3d-a
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  FOB-4 (OI-175, generator step 3D, Unit 3D-a). A free user who keeps training Phase I takes hold weeks (H1, H2, ...),
  but two server texts read the clamped program week. The Sunday Brief push (`weekly-recap-ready`) said
  "<name> — Week 4 debrief ready. Stand to." every Sunday of every hold. The weekly report prompt (`weekly-report`)
  said "Current week: 4", so the model wrote about week 4 of the program to someone repeating Phase I for the
  third time. b6e1f4 recorded why no redeploy alone could fix it: the cloud has no hold column of any spelling.
concept: hold_week_server_signal
sot_registry_entry: hold_week_server_signal
contract_test_path: supabase/functions/_shared/hold_week_test.ts
related_bugs: [d7f3a9, c8b3f2, a3f8d1, f4c8e1, d5b8f3, b6e1f4, e7c4a2, b9d4c2, d7f3b2]
recurrence: |
  A recurrence of the hold-week identity class: a reader of the program week that never learned holds exist.
  Prior instances: f4c8e1 (the app clamped the hold's identity to week 4), d5b8f3 (the stamp rendered raw),
  b6e1f4 (FOB-3, the coach told every holder "week 4"; the known-good fix there was a separate HOLD WEEKS prompt
  block keyed on the hold's own number, live in ai-proxy, payload v5_862f0bc), c8b3f2 / a3f8d1 / e7c4a2 / b9d4c2 /
  d7f3b2 (stale week, streak identity, reconciler, phase completion, regen cycling) and d7f3a9 (the mechanic itself).
  The known-good fix is applied the same way: the reader is given the hold's own number and its own wording, and it
  falls back to today's text whenever the number cannot be read. b6e1f4 found the server had no hold column; this
  batch uses the one server-side mark that exists, `scheduled_workouts.week_number > 4` for a Phase-I user (the app's
  holdWeek stamps `week: 4 + n` and the push copies it). Bug-history lookup (CLAUDE.md 4.1.5): grep of
  docs/diagnoses for "FOB-4", "weekly-recap-ready", "weekly-report", "hold_ordinal", "hold week" and "Week 4"
  (token and concept); the hits are the nine above plus notification / cron diagnoses (e4a1b7, f7b3d1, b2d8e4, c9f4a2,
  93aeac, c3f8a1, a7c3f9) that touch the same functions for unrelated reasons.
writers:
  - { file: lib/core/services/workout_schedule_write_service.dart, method_or_widget: "holdWeek stamps week: 4 + n, is_hold and hold_ordinal on each hold day (unchanged by 3D-a)", line: 264 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "the schedule push sends 'week_number': entry['week'] to scheduled_workouts (unchanged)", line: 2350 }
readers:
  - { file: supabase/functions/_shared/hold_week.ts, method_or_widget: "fetchHoldOrdinals / holdOrdinalFromWeekNumbers / phaseOneUserIds / istWeekBounds (the one server read rule)", line: 81 }
  - { file: supabase/functions/weekly-recap-ready/index.ts, method_or_widget: "the per-batch hold read for Phase-I users over the IST Monday-Sunday; processUser's recapMessage", line: 268 }
  - { file: supabase/functions/weekly-report/index.ts, method_or_widget: "step 3b: today's hold for a Phase-I user; reportWeekLine in the prompt", line: 232 }
hive_key_prefix: "workoutBox schedule_<date>['week'] / ['hold_ordinal'] / ['is_hold'] (written by holdWeek, read by the app; not touched by 3D-a)"
hive_key_formula: "week = 4 + hold ordinal on a hold day; the cloud copy is scheduled_workouts.week_number"
sync_methods:
  - "SyncService schedule push (sync_workout.dart): week_number from entry['week'] (unchanged); is_hold and hold_ordinal have no cloud column"
restore_methods:
  - "the schedule restore maps week_number back to week (sync_workout.dart 2824-2825, unchanged); not read by 3D-a"
cloud_table: scheduled_workouts
cloud_columns:
  - scheduled_workouts.week_number
  - scheduled_workouts.scheduled_date
  - user_progress.current_phase
  - user_progress.current_week
ist_handling:
  - { file: supabase/functions/_shared/hold_week.ts, method_or_widget: "istWeekBounds: the IST Monday-Sunday from istWeekStartIso (scheduled_date holds IST dates); the report's todayStr is the IST date it already used", line: 34 }
provider_invalidations:
  - "none: server only; no client provider reads these texts"
telemetry_op_types:
  success: []
  failure: ["[hold_week] read failed: <error name> (console.error)", "weekly-recap-ready response and summary line hold_read_failed=true"]
cross_account_guard: "Service-role reads keyed by user_id: the recap reads only the batch's own user ids, the report only targetUserId; a row of another user cannot reach a text because the result map is keyed by the row's own user_id."
forbidden_patterns_checked:
  - { pattern: "a hold read for a user whose progress row is missing or whose current_phase is not exactly 1 (phaseOneUserIds; the recap reads none when the progress read failed)", absent: true }
  - { pattern: "a throw from the hold read reaching the function (fetchHoldOrdinals catches every failure; tests: page error, throwing builder, throwing from())", absent: true }
  - { pattern: "UTC week bounds on an IST date column (istWeekBounds tests at Sunday 14:30 UTC and Sunday 18:40 UTC)", absent: true }
  - { pattern: "a Peak or Deload claim in the report's hold line (the server cannot tell which hold week copied the deload)", absent: true }
  - { pattern: "the error object or row values in the failure log (the error's name only)", absent: true }
proposed_fix: |
  Plan docs/plans/2026-11-16-generator-step3d-hold-weeks.md (rev 5, section 2.3; five review rounds, 3D split under
  section 4.12.1). One shared module `_shared/hold_week.ts`: a hold row is a `scheduled_workouts` row with an
  integer `week_number > 4` in the window, read only for users whose `user_progress.current_phase` is exactly 1
  (fail closed). The hold number is max(week_number - 4). The recap reads the IST Monday-Sunday of the run and says
  "<name> — Hold H<n> debrief ready. Stand to."; the report reads today and prints "Current week: hold week H<n>
  (the user chose to keep training Phase I; a repeat of a Phase I week)". Every failure keeps today's text; the recap
  reports `hold_read_failed` in its response and summary line. No schema change, no client change.
regression_test_planned: |
  supabase/functions/_shared/hold_week_test.ts (15: the ordinal rule, IST bounds at the cron hour and across midnight
  and a month end, the phase gate, both texts, the query's filters and window against a stub that applies them, the
  100-id chunk, no users, a page error, a throwing builder, a throwing client);
  supabase/functions/weekly-recap-ready/index_test.ts (4 source pins: the phase gate, the IST window, the message
  helper, hold_read_failed in the response);
  supabase/functions/weekly-report/index_test.ts (2 appended pins: today's window and the phase gate, the week line).
impact_analysis: |
  Platform tier (two cron / on-demand Edge Functions, one shared module). Only a Phase-I user with a hold row in the
  window sees a different text. Phases 2-12 write weeks 1-4 (measured live 2026-11-16: phases 2 / 3 / 5 hold
  week_number 1-4 only); one Phase-I tester has weeks 5-7 from dev toggling and would read "Hold H3". Each run adds one
  paged read of scheduled_workouts per batch (recap) or per report. Holds reach real users only after
  `enable_hold_weeks` flips (3D-b); both deploys went live 2026-11-16 on the founder's go (weekly-recap-ready v29, weekly-report v41). The app
  is not live.
touched_layers_checked:
  - { layer: client_code, status: not_applicable, evidence: "no Dart file changes in 3D-a; the writer (holdWeek) and the push are read, not changed" }
  - { layer: postgres_schema, status: verified, evidence: "scheduled_workouts.week_number (integer) and scheduled_date (date), user_progress.current_phase exist (backups/live_schema_columns.json); no column added" }
  - { layer: postgres_data, status: verified, evidence: "read-only GROUP BY 2026-11-16: phases 2 / 3 / 5 have week_number 1-4 only; one phase-1 tester has 5-7" }
  - { layer: edge_function_code, status: fixed_in_this_batch, evidence: "_shared/hold_week.ts, weekly-recap-ready, weekly-report; deno check of both functions clean; deno test of the three test files green; ten mutants all red (below)" }
  - { layer: edge_function_deploy, status: verified, evidence: "not deployed by this commit; deployed 2026-11-16 after the merge on the founder's go: recap v28 -> v29 and report v40 -> v41, each live bundle verified file-for-file against 63af8c63, rollback sources 1040800f / c760037e recorded first (generator-step3d.closure.yaml FOB-4-DEPLOY)" }
  - { layer: cron_jobs, status: verified, evidence: "CRON_REGISTRY row 061 (weekly-recap-ready, Sunday 20:00 IST = 14:30 UTC) updated with the new reads; the schedule is unchanged" }
  - { layer: client_server_contract, status: verified, evidence: "the app's holdWeek writes week: 4 + n and sync_workout.dart:2350 pushes it as week_number; the server rule reads exactly that" }
---

# Sunday push and weekly report say "Week 4" to every holder (FOB-4)

## Root cause

- **The texts read the clamped program week.** `weekly-recap-ready` built its message from
  `user_progress.current_week`, and `weekly-report` printed `Current week: ${current_week}`. During a hold,
  `current_week` stays 4 (the program week clamps; f4c8e1), so every hold week read "Week 4".
- **There was no hold signal to branch on** (b6e1f4). The app keeps `is_hold` and `hold_ordinal` in Hive only. What
  reaches the cloud is `week: 4 + n`, pushed as `scheduled_workouts.week_number`.
  - Writer: `holdWeek` (`workout_schedule_write_service.dart:264`) and the push (`sync_workout.dart:2350`).
  - Readers before the fix: `weekly-recap-ready/index.ts` (message) and `weekly-report/index.ts` (prompt line),
    both reading `current_week` only.

## Fix

See `proposed_fix`. The design and its review history are in plan section 2.3.
- **Phase gate.** Phases 2-12 never write weeks above 4 today, but nothing forbids it. So the rule reads only
  Phase-I users, and a missing or non-1 phase is not read as 1.
- **The report reads today, not the week.** It matches what the app shows: `holdOrdinalForDate(today)`.
- **No Peak or Deload claim.** The server cannot tell which hold copied the deload, so it makes neither claim.

## Mutations

Each mutant was applied with a script (`mutate_a.py`), and its application was confirmed by a count of the changed
text. It was then run against the three test files and restored from a backup copy.

| # | Mutant | Result |
|---|---|---|
| A1 | a missing phase read as 1 | red, 1 of 15 |
| A2 | week 4 counted as a hold (`w <= 4` became `w < 4`) | red, 1 of 15 |
| A3 | Sunday = Monday + 7 | red, 3 of 15 |
| A4 | week bounds in UTC | red, 1 of 15 |
| A5 | the filter widened to `week_number > 0` | red, 1 of 15 |
| A6 | the catch removed (rethrow) | red, 3 of 15 |
| A7 | hold and no-hold texts swapped | red, 2 of 15 |
| A8 | the recap's hold read removed | red, 1 of 4 (recap pins) |
| A9 | the report reads the last seven days instead of today | red, 1 of 13 (report pins) |
| A10 | the report skips the phase gate | red, 1 of 13 (report pins) |

All ten went red and were restored. The hold_week tests passed again after each restore.

The IST date gate (`check_local_date_key_drift.dart`) then flagged the Sunday line's raw UTC arithmetic. `istWeekBounds`
now takes both dates from `istDateStr` of the IST Monday's instant. A3 and A4 were re-applied to the new line: A3
(`+ 7` days) red, 3 of 15; A4 (a UTC Monday from `getUTCDay`) red, 1 of 15. A third variant parses the IST Monday's
date as UTC midnight. It is equivalent, because that instant falls on the same IST date (green, 15 of 15, as
expected).

## Not changed

- No client code, no schema, no cron schedule.
- The deploys needed the founder's go, one per function; given 2026-11-16 and done the same day (recap v29,
  report v41). The live versions and their git sources were recorded first; the rollback is that source's payload.

## B-pass (docs/reviews/generator-step3d-a-bpass.md)

One fresh seat on fa793157 found 2 P2 and 3 P3, all fixed in the B-pass commit:
- the recap's window order and the two map hand-offs (recap and report) were unpinned: three seat mutants stayed
  green;
- `hold_read_failed` was not in `cron_call_log`;
- the year-end and exactly-100-ids cases were not tested.

The fix moves both call-site steps into `_shared/hold_week.ts` helpers tested end to end:
- `recapHoldsForBatch` takes the `istWeekBounds` object whole;
- `reportWeekLineFor` runs the phase gate, the one-day read and the builder.

The stub client now applies its recorded `gte` / `lte` window to dated rows.

Mutants run after the fixes, each applied (the file differed) and restored from a backup:

| # | Mutant | Result |
|---|---|---|
| B1 | the helper's window swapped (Sunday first) | red, 1 of 32 |
| B2 | the recap's `holdMap = holds.map` became `new Map()` | red, 1 of 32 |
| B3 | `reportWeekLineFor`'s lookup became `null` | red, 1 of 32 |
| B4 | the report's call site bypassed (the raw `current_week` line) | red, 1 of 32 |
| B5 | the `cron_call_log` error summary dropped | red, 1 of 32 |
| B6 | the helper's phase gate bypassed (every user asked) | red, 1 of 32 |
