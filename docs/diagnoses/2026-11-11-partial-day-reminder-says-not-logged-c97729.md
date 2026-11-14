---
bug_id: c97729
date: 2026-11-11
batch: coach-workout-parity-server
status: fixed
blast_radius: account
symptom: >-
  Coach workout parity 2 (S2): on a day when the user had logged SOME of the planned exercises through the coach but had
  no completed workout_logs row yet (a partial day, shown as IN PROGRESS on Train since 1b), the 9 pm push
  (workout-window-closing, "haven't seen it logged") and the 8 pm push (streak-guardian, the streak-family line) said the
  user had not trained. Both pushes opened /ai_coach, where nothing showed the partial day.
concept: partial_day_reminder_count
sot_registry_entry: partial_day_reminder_count
writers:
  - file: supabase/functions/_shared/partial_day_count.ts
    method: countPartialDay (pure count of planned exercises left; swapped_from tolerant; null = cannot count)
    line: 59
  - file: supabase/functions/_shared/partial_day_loader.ts
    method: loadPartialDays (batched plan + wle reads, kill switch DISABLE_PARTIAL_DAY_REMINDER at 84, never throws)
    line: 73
  - file: supabase/functions/workout-window-closing/message.ts
    method: selectWindowClosingMessage (partial line or today's template) and windowClosingScreen (/train or /ai_coach)
    line: 14
  - file: supabase/functions/workout-window-closing/index.ts
    method: handler (safeLoad at 296, message at 365, screen at 372, partial_sent / partial_fallback counters)
    line: 296
  - file: supabase/functions/streak-guardian/message.ts
    method: selectStreakMessage (family title kept, body swapped for the partial line)
    line: 62
  - file: supabase/functions/streak-guardian/index.ts
    method: handler (safeLoad at 233, partialDay passed to selectStreakMessage at 319)
    line: 233
readers:
  - file: supabase/functions/workout-window-closing/index.ts
    method_or_widget: the 9 pm push (pd = partial.get(userId) feeds the body and the screen)
    line: 364
  - file: supabase/functions/streak-guardian/index.ts
    method_or_widget: the 8 pm push (partialDay: partial.get(userId))
    line: 324
  - file: lib/features/train/screens/train/planned_expansion.dart
    method_or_widget: _buildPlannedExpansion (the /train screen shows the partial day: LOGGED SO FAR + COMPLETE WORKOUT, 24e630)
    line: 6
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: user_progress
cloud_columns: [plan_json]
contract_test_path: supabase/functions/_shared/partial_day_loader_test.ts
ist_handling:
  - todayIST from the cron (istDateStr) builds both the plan key schedule_<todayIST> (partial_day_loader.ts:) and today's workout_log_id (UUID v5 of workout_<IST date>, workoutLogIdForDate)
provider_invalidations: []
telemetry_op_types:
  success:
    - "[partial-day] users=<n> counted=<n> null=<n> (one line per run) and workout-window-closing partial_sent / partial_fallback in the response"
  failure:
    - "[partial-day] read failed: <ErrorName> (loader read-level catch, no row data)"
    - "[partial-day] loader threw: <ErrorName> (call-site safeLoad)"
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: 'a push that says "not logged" for a user whose plan row has some planned exercises logged', absent: true }
  - { pattern: 'a loader read without .in("user_id", chunk)', absent: true }
proposed_fix: >-
  One server helper countPartialDay over TODAY'S plan row and the user's live workout_log_exercises names for today's
  workout_log_id (tombstones excluded). A planned exercise counts as logged by exercise_name or swapped_from. It returns
  null for every case it cannot count (no plan row, rest / moved / dropped / completed row, nothing logged, all logged,
  a stale plan whose logged names match none of the planned ones, a read failure, the kill switch) and the caller keeps
  today's line byte-identical. loadPartialDays batches the reads (chunks of 100; the fallback plan read chunks of 10) and
  never throws; each cron also wraps it in a call-site safeLoad. The 9 pm partial push opens /train, where the partial
  day is shown and completed; every other push keeps /ai_coach. Kill switch DISABLE_PARTIAL_DAY_REMINDER (exactly
  lowercase true), read once per run.
regression_test_planned:
  - supabase/functions/_shared/partial_day_count_test.ts
  - supabase/functions/_shared/partial_day_loader_test.ts
  - supabase/functions/workout-window-closing/index_test.ts
  - supabase/functions/streak-guardian/index_test.ts
related_bugs:
  - 24e630  # 1b: the coach-day rule; Train shows a partial day as IN PROGRESS and completes it (where the push now points)
  - 0ebfcb  # 1a: a partial day does not count as a workout, so the server cannot see it as a completed log
recurrence: |
  Not a recurrence of a stored-value bug. It is the server half of a client rule: 24e630 made the app treat a partly
  logged coach day as IN PROGRESS, but the two reminder crons kept the older binary view (completed workout_logs row or
  not). Same class as server counter vs client counter drift (f9bf1c). The fix gives the server the same swap-tolerant
  count the client uses (loggedPlannedExerciseCount) behind one helper.
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "No client change in S2. /train already shows the partial day (planned_expansion.dart, 24e630); the push now opens it." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "Service-role crons; no Hive access." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "No schema change. user_progress.plan_json and workout_log_exercises (user_id, workout_log_id, exercise_id, exercise_name, deleted_at) exist in backups/live_schema_columns.json; the template-literal select strings keep check_schema_column_refs.dart from reading the jsonb path as a column." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "U2 (2026-11-11, founder go, read-only): the primary arrow-path select returned HTTP 200 and matched the fallback on 35 of 35 user_progress rows, 13 of them non-null (see Hard precondition U2). No data written." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: verified, evidence: "Deployed from main 72862b2f with the founder's go (2026-11-11): GET /functions/<slug> reads streak-guardian v31 (07:08Z) and workout-window-closing v20 (06:21Z), verify_jwt false (re-read on the evening of 2026-11-11). First live runs read the same evening (founder go): both emitted the loader line `[partial-day] users=1 counted=0 null=1`." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "cron_call_log 2026-11-11: streak-guardian 14:30:06Z (20:00 IST) success 200; workout-window-closing 15:30:08Z (21:00 IST) success 200, its summary line `checked=1 sent=1 errors=0 partial_sent=0 partial_fallback=1`. The one user in scope had no countable day (null), so today's line was sent, as designed. The partial line itself is not yet seen live: it needs a part-logged planned day at 20:00/21:00 IST." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "Service-role reads; no policy touched." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "New KILL switch DISABLE_PARTIAL_DAY_REMINDER (a flag, not a credential); documented in SECRET_INVENTORY.md; current state unset (partial lines ON). It is set only by the founder in the Dashboard, each flip with its own go." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "The push is sent through the existing sendPushNotification (OneSignal); only the text and the screen change." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "Deno tests over the REAL loader (kill switch unset and on) assert the partial line, the /train screen and byte-identical fallback lines. The live end-to-end flow (a partial day, the 9 pm push, the tap into Train) is a deploy-step check, not run in this batch." }
impact_analysis: >-
  A user with some, not all, planned exercises logged on a day gets "N exercise(s) left in <plan day>. Finish up and tap
  Complete." at 9 pm (opening /train) and the same body under the streak title at 8 pm. Every other user gets today's
  lines unchanged. A failed read, a thrown loader or the kill switch all degrade to today's line.
---

# The reminder pushes say "not logged" on a partly logged day (c97729)

## Root cause
`workout-window-closing` (9 pm) selected users without a completed `workout_logs` row for today and sent "haven't seen it
logged"; `streak-guardian` (8 pm) sent the streak-family line to every eligible user. Neither looked at the plan row or at
the day's `workout_log_exercises` rows, so a coach-logged partial day (IN PROGRESS on Train since 24e630) read as an
untrained day. Both opened `/ai_coach`.

## Fix
- `countPartialDay` (`_shared/partial_day_count.ts:59`) and `loadPartialDays` (`_shared/partial_day_loader.ts:73`) as in
  `proposed_fix`. Messages: `selectWindowClosingMessage` / `windowClosingScreen` (`workout-window-closing/message.ts:14`,
  `:32`), `selectStreakMessage` (`streak-guardian/message.ts:62`).
- Kill switch `DISABLE_PARTIAL_DAY_REMINDER`: exactly lowercase `true` (`partialDayKillSwitchOn`, `partial_day_count.ts:125`).

## Accepted: the 8 pm and 9 pm repeat (plan B-F9 / R3)
On a partial day a user can get BOTH pushes: the two crons use different dedup types (`workout_window` and `streak_protection`; plan R3 notes
`proactive_dedup.ts` has a single `last_proactive_type` slot), and both carry the partial copy. A
rest-day user with a streak still gets the 8 pm streak push (unchanged, out of scope). This is accepted, not a defect.
Also accepted (R4, B-F10): the app shows the tile for an off-plan-only log; the server returns null for it and keeps
today's line.

## Hard precondition U2 (VERIFIED live 2026-11-11, read-only)
The primary plan read is a PostgREST select with a hyphenated JSON arrow path and an alias:
`today_row:plan_json->schedules->schedule_<YYYY-MM-DD>` on `user_progress` (`_shared/partial_day_loader.ts:106`).
It was verified live with the founder's go on 2026-11-11, read-only, through the service-role PostgREST REST path that
the function's client uses. The check made two GETs per run and printed only status codes, counts and key shapes (no
row values, no user ids). Project `dedsavbjuwgarrhphgnl`.
- **Run 1, today's key.** `schedule_2026-11-11` on the first 20 rows by id. The primary read returned HTTP 200, with the
  `today_row` key on every row. The fallback read returned HTTP 200. They agreed on 20 of 20. All 20 were null (no
  row for today), so this run proves only that the shape is ACCEPTED, not that the values match.
- **Run 2, a populated key.** The date key most present among the fallback rows was `schedule_2026-10-05` (13 of the
  35 rows the table holds). The primary read for those rows returned HTTP 200 with 13 non-null rows. Primary and
  fallback agreed on 35 of 35, including all 13 non-null rows (deep, key-sorted equality), with 0 disagree. Each
  non-null value is the schedule object, with top-level keys including `date`, `exercises` (an array of 7 in the two printed), `status`, `type` and `workout_name`.

Result: `planRead: "primary"` ships unchanged. The fallback (`schedules:plan_json->schedules` in chunks of
`PLAN_FALLBACK_CHUNK_SIZE` = 10, today's key picked in code) stays tested and remains the one-line switch if a
PostgREST upgrade ever rejects the shape.

## Mutation evidence (rule 21)
Run by `mutate.py` in the session scratchpad (backup copy, apply, confirm applied, run the named test, restore, `cmp`);
the full table is in the session scratchpad `l2-mutations.md`. Rows for this slice (every `applied=True restored=True`):

| id | file | edit | result |
|---|---|---|---|
| M14 | `_shared/partial_day_count.ts` | swapped_from match dropped | RED: partial_day_count_test.ts 21 pass / 1 fail |
| M15 | `_shared/partial_day_count.ts` | .toLowerCase().trim() dropped | RED: 20 pass / 2 fail |
| M16 | `_shared/partial_day_loader.ts` | .is("deleted_at", null) removed | RED: partial_day_loader_test.ts 17 pass / 2 fail |
| M17 | `_shared/partial_day_loader.ts` | .in("user_id", chunk) removed from the wle read | RED: loader 17 pass / 2 fail |
| M18 | `_shared/partial_day_count.ts` | matched == 0 returns a partial instead of null | RED: count 21 / 1; loader 18 / 1 |
| M19 | `workout-window-closing/message.ts` | plural/singular inverted | RED: index_test.ts 15 pass / 5 fail |
| M20 | `workout-window-closing/message.ts` | partial copy chosen when pd.left == 0 | RED: 19 pass / 1 fail |
| M21 | `_shared/partial_day_count.ts` | rest/moved rows counted as partial | RED: 21 pass / 1 fail |
| M22a | `streak-guardian/message.ts` | selectStreakMessage ignores partialDay | RED: index_test.ts 15 pass / 3 fail |
| M22b | `streak-guardian/index.ts` | handler passes partialDay: null | RED: 17 pass / 1 fail |
| M27 | `_shared/partial_day_loader.ts` | kill switch not honoured by the loader | RED: loader 18 / 1; window-closing 19 / 1 |
| M29 | `_shared/partial_day_loader.ts` | loader read-level try/catch removed | RED: loader 17 pass / 2 fail (handler tests stay GREEN: the call-site safeLoad absorbs it, as planned) |
| M30 | `_shared/partial_day_loader.ts` | workout_log_id computed for the wrong date | RED: loader 7 pass / 12 fail |
| M31 | `_shared/partial_day_loader.ts` | user_progress read loses .in(user_id, chunk) | RED: loader 17 pass / 2 fail |
| M36 | `_shared/partial_day_count.ts` | partialDayKillSwitchOn case-insensitive | RED: count 21 / 1; loader 18 / 1 |
| M37 | `_shared/partial_day_count.ts` | stale-plan guard removed | RED: 21 pass / 1 fail |
| M38 | `_shared/partial_day_loader.ts` | per-user try/catch around computeUser removed | RED: loader 18 pass / 1 fail |
| M42 | `_shared/partial_day_count.ts` | typeof string guard removed | RED: count 20 / 2; loader 18 / 1 |
| M46 | `workout-window-closing/index.ts` | partial-day push opens /ai_coach | RED: index_test.ts 18 pass / 2 fail |
| M46b | `workout-window-closing/message.ts` | not-trained push opens /train | RED: 14 pass / 6 fail |
| M47 | `_shared/partial_day_loader.ts` | date key built from the previous day | RED: loader 17 pass / 2 fail |
| M48 | `_shared/partial_day_loader.ts` | wle grouping hard-coded to the first requested user | RED: loader 16 pass / 3 fail |
| M49a | `workout-window-closing/index.ts` | safeLoad try/catch removed | RED: 19 pass / 1 fail |
| M49b | `streak-guardian/index.ts` | safeLoad try/catch removed | RED: 17 pass / 1 fail |
| M51a | `workout-window-closing/index.ts` | realDeps member stubbed | RED: 19 pass / 1 fail |
| M51b | `streak-guardian/index.ts` | realDeps member stubbed | RED: 17 pass / 1 fail |
| M55a | `_shared/partial_day_count.ts` | matched == planned treated as partial | RED: 21 pass / 1 fail |
| M55b | `_shared/partial_day_count.ts` | completed row treated as partial | RED: 21 pass / 1 fail |
| M55c | `_shared/partial_day_count.ts` | zero-planned row treated as partial | GREEN (SURVIVED), see below |

- **M55c survived and was an EQUIVALENT mutant** (the redundant guard). With zero planned object elements `matched` is
  always 0, so `if (matched === 0 || ...) return null` already returned null; the explicit `planned.length === 0` guard
  was redundant by construction and no fixture could tell the two apart. The guard was removed from
  `partial_day_count.ts`, so it no longer exists. The test file still pins the behaviour (`exercises: []` and
  `exercises: ["x", 3]` give null).
- M29: the handler tests stay GREEN by design (the call-site safeLoad absorbs a throwing loader); the loader tests carry
  the red.
- Not part of this slice: the S3 mutants (M1-M13, M28, M32, M32b, M33, M39-M41, M44, M45).
- **Coordinator re-verification:** removing `.in("user_id", chunk)` from the wle read in `_shared/partial_day_loader.ts`
  reddened 2 loader tests (17 passed, 2 failed); restored byte-identically.
