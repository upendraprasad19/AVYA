---
bug_id: a3f8d1
date: 2026-08-13
batch: oi60-streak-identity
blast_radius: platform
status: fixed
symptom: >
  TWO defects in the same six lines of ActiveWorkoutNotifier.completeWorkout's
  weekly-streak block. (1) FOB-2, flag-gated: getCurrentWeekNumber() clamps to
  [1,4] and a hold week starts at plan_start+28, so the dedup gate was `4 != 4`
  — current_streak_weeks froze for the entire hold — and the streaks row key was
  always week 4's Monday, so every hold completion OVERWROTE that one row (cloud
  streaks is UNIQUE(user_id, week_start)); hold weeks got no row at all.
  (2) LIVE for all PRO users, found while scoping (1): `planned` filtered
  `type == 'workout'` while `completedCount` applied no type filter, so the
  denominator excluded custom-template days while the numerator counted them. At
  100% template conversion `planned == 0`, and both the increment and the row
  write are gated on `planned > 0` — a PRO user with a fully self-built week and
  perfect adherence received zero streak credit and no cloud row.
concept: streaks
sot_registry_entry: streaks
writers:
  - { file: lib/features/train/providers/train_provider.dart, line: 533, source: "resolveStreakWeekState — NEW pure-ish extraction returning (streakWeekId, weekStartDate, planned, completedCount). Hold arm derives the identity BY DATE (unclamped date-week index) and keys the row on normalizeToMonday(workoutDate); non-hold arm stays CLAMPED via getCurrentWeekNumber(). Extracted so both arms are testable without driving completeWorkout." }
  - { file: lib/features/train/providers/train_provider.dart, line: 1867, source: "the completeWorkout call site — sources holdOrdinal from holdStatusProvider (isHolding/todayHoldOrdinal ONLY, never its stale session counts)" }
  - { file: lib/features/train/providers/train_provider.dart, line: 1891, source: "last_streak_week now written from streakWeek.streakWeekId — still an int; widens {1..4} -> {1..N} during a hold" }
  - { file: lib/core/utils/phase_completion.dart, line: 55, source: "isTrainingDayType — the ONE shared predicate now used on BOTH sides of the ratio; EXCLUSION-shaped so it counts custom_template, logged, and a type-less legacy row" }
readers:
  - { file: lib/features/train/providers/train_provider.dart, line: 1876, source: "the sole reader of last_streak_week — `(progress['last_streak_week'] as int?) ?? -1`; the reason the field must stay an int (completeWorkout has no try/catch)" }
  - { file: lib/features/train/providers/train_provider.dart, line: 1895, source: "weekStartDate gates + keys the healthBox 'streaks' row (streak_<Monday>)" }
  - { file: lib/core/services/sync/sync_workout.dart, line: 586, source: "_syncStreaks upsert onConflict user_id,week_start — a new Monday is a new cloud row, which is why keying by date needs no migration" }
hive_key_prefix: streaks
hive_key_formula: "'streaks' (singleton List in healthBox); per-row local_id = 'streak_' + formatDateKey(weekStartDate)"
sync_methods: [_syncStreaks]
restore_methods: [_restoreStreaks]
cloud_table: streaks
cloud_columns: [user_id, week_start, workouts_planned, workouts_completed, is_streak_maintained]
contract_test_path: test/contracts/hold_week_streak_identity_behavioral_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 1425, fn: "normalizeToMonday — raw-weekday normalizer, the SAME one holdWeek() built rollStart with, so (holdMonday - plan_start) % 7 == 0 holds exactly" }
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 1025, fn: "getCurrentWeekNumber — clock-derived and clamped [1,4]; retained verbatim for the non-hold arm" }
provider_invalidations: [currentPlanProvider, workoutStatsProvider, calendarWeekProvider, streakProvider, todayWorkoutProvider, allExercisePRsProvider, aiInsightProvider]
telemetry_op_types:
  success: [sync_streaks]
  failure: [sync_streaks]
cross_account_guard: >
  Unchanged and already present — ActiveWorkoutNotifier watches
  authUserIdTokenProvider, and every Hive touch routes through the existing
  user-scoped boxes. resolveStreakWeekState performs no box access of its own;
  it reads through the injected WorkoutScheduleReadService.
forbidden_patterns_checked: >
  The unclamped date-week index exists ONLY in the hold arm and never reaches
  getWeek() — mutation-proven: feeding it to the non-hold arm reddens both
  flag-OFF cases (Actual 5 vs Expected 4). This matters because redoWeek4 (the
  CURRENT flag-OFF path) extends only plan_end and never writes plan_start, so a
  user who rolled week 4 sits at a true date-index >= 5 while
  getCurrentWeekNumber() reports 4; an unclamped read would hand them a
  different week's rows and a different row key with the flag OFF.
  `4 + hold_ordinal` is NOT used — the ordinal is a label, not a date offset (a
  late return puts ordinal 1 at date-week 8); mutation-proven to redden the
  late-return case. HoldWeekInfo.weekStart is NOT used for the row key — it is
  the first SURVIVING hold date, so a missing Monday row makes it a Tuesday;
  mutation-proven by the missing-Monday case. last_streak_week stays an int and
  never takes -1 (the init sentinel) since a hold identity is always >= 5 at
  materialization. Hold state is read ONLY via holdStatusProvider — the helper
  references neither PlanEngineFlags nor holdOrdinalForDate (pinned by a
  comment-stripped source assertion). The identity is derived at COMPLETION time
  from the then-current plan_start, of which there are four write sites
  (read_service:188 and :348, sync_workout.dart:1126,
  plan_integrity_reconciler.dart:175); no behavioural claim is made here about
  one of them firing under a live hold — that question is filed as its own OI
  after three review rounds each produced a different wrong answer.
proposed_fix: >
  Extract resolveStreakWeekState (both arms) and give the ratio ONE shared
  predicate. Hold arm: identity = (normalizeToMonday(workoutDate) - plan_start)
  in whole weeks + 1 (unclamped, always >= 5 at materialization, correct across
  a late-return date gap), row key = that Monday, counts = a FRESH
  holdWeekSessionProgress(ordinal) read. Non-hold arm: byte-identical to the
  prior behaviour except that both counts now share isTrainingDayType.
  Session counts are deliberately NOT taken from holdStatusProvider: it watches
  currentPlanProvider, which completeWorkout does not invalidate until after
  this block, and the awaited markCompleted invalidates nothing — so a cached
  HoldStatusData predates the completion just written and would under-count by
  exactly one session at the 80% threshold. isHolding/todayHoldOrdinal ARE taken
  from it (a completion never changes hold membership, and markCompleted merges
  three keys rather than replacing the row, so is_hold/hold_ordinal survive).
regression_test_planned: >
  test/contracts/hold_week_streak_identity_behavioral_test.dart — 12 cases,
  all calling resolveStreakWeekState directly against a real
  WorkoutScheduleReadService over seeded Hive with holds materialized by the
  REAL holdWeek() writer. Five mutations were RUN and each reddened only its
  intended cases: clamping the hold arm -> 3 identity cases; `4 + ordinal` ->
  the late-return case; narrowing `planned` to `type == 'workout'` -> the
  blackout + logged cases; dropping the numerator's type filter -> the
  completed-rest case; feeding the unclamped index to the non-hold arm -> both
  flag-OFF cases including the redoWeek4 regression guard. This is the FIRST
  test coverage this block has ever had.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean on both touched lib files; 48/48 green across the new test plus hold_display_read_path, hold_week_mechanic and streaks_writer_to_reader; 5 mutations run and each reddened only its intended cases" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "progress.last_streak_week + current_streak_weeks and the healthBox 'streaks' list (local_id streak_<Monday>) — pinned by the new behavioral test" }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "no migration. streaks.week_start is date NOT NULL with UNIQUE(user_id, week_start) (migrations 004 + 012), so a new Monday is simply a new row; no CHECK on week_start" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "forward-only, NO backfill — a hold week whose row was already collapsed onto week 4's Monday is unreconstructible. Also recorded: founder_metrics_engagement takes each user's MOST RECENT week_start, so post-fix a holder's newest row is the hold Monday and streak_maintained_current_week reads lower for holders until they clear 80% mid-week; no SQL change needed" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this batch" }
  - { tier: 6, name: edge_function_deploy, status: verified, evidence: "the only EF touch is two comment-only citation fixes in ai-proxy; no redeploy. NOTE the deployed bundle is now comment-drifted from source, so the next ai-proxy deploy's SHA delta is expected" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron reads last_streak_week or the streaks local_id" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy change" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage surface" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret surface" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no external service" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "last_streak_week is Hive-LOCAL only — absent from sync_profile's projection and absent from user_progress in backups/live_schema_columns.json — so widening its range to {1..N} crosses no wire. The streaks row reaches cloud unchanged via _syncStreaks' existing onConflict user_id,week_start" }
impact_analysis: >
  Defect (1) is inert today (enable_hold_weeks is default OFF) and is one of
  OI-60's flip-on preconditions; without it a holder's streak froze for the
  whole hold and every hold week's row overwrote week 4's. Defect (2) is LIVE
  and changes behaviour for real users on this commit: template-heavy PRO users
  who were accruing weekly streak on partial adherence (the old denominator
  excluded their converted days while the numerator counted them) will now be
  measured against all of them and some will stop accruing. That is the correct
  reading and it kills the 100%-conversion blackout, but it is user-visible and
  not backfillable. current_streak_weeks is NOT local-only — it syncs and is
  read by badge_service and by pattern_detector (a `> 2` check fires a proactive
  nudge), so the tightening propagates to badges and coach nudges.
  Because the batch now changes live behaviour it is NOT §4.12.4 ship-dark tier;
  it took the full review (4 rounds to converge) plus a B-pass. Blast radius
  MEASURED as platform via scripts/blast_radius_from_diff.dart (stdin form, with
  the required `-` argument). Per-file: train_provider.dart is feature
  (docs/blast_radius.yaml:251), phase_completion.dart is account (the
  "anywhere else in lib/ ... lib/core/utils ... is account" catch-all), and the
  ai-proxy comment edit escalates account -> platform (blast_radius.yaml:54).
  A review round asserted the Dart changes alone were feature-tier; running the
  tool showed account. The B-pass was therefore required regardless of the
  comment edit.
---

# The weekly streak was dead during a hold — and blind to self-built weeks

## Root cause

Both defects live in the same six lines of `completeWorkout`, and both come from
one variable doing three jobs — week identity, row key, and day source:

```dart
final currentWeekNum = WorkoutScheduleService.instance.getCurrentWeekNumber();
final weekDays = repo.getWeek(currentWeekNum);
final planned = weekDays.where((d) => d['type'] == 'workout').length;
final completedCount = weekDays.where((d) => d['status'] == 'completed').length;
```

**1. The clamp.** `getCurrentWeekNumber()` ends `.clamp(1, 4)`. A hold starts at
`plan_start + 28`, so it always reports `4`. The dedup gate
`currentWeekNum != lastStreakWeek` became `4 != 4` → the streak froze after the
first hold completion; and the row key `plan_start + 7*(4-1)` was always week 4's
Monday → every hold completion rewrote that one row.

**2. The asymmetry.** The denominator filters by `type`, the numerator does not.
With 5 workout days converted to user templates and all completed:

| converted | `planned` | threshold | `completedCount` | ticks? |
|---|---|---|---|---|
| 0 | 5 | 4 | 5 | yes |
| 3 | 2 | 2 | 5 | yes — on 3/5 real adherence |
| **5** | **0** | — | 5 | **no — and no cloud row either** |

Both the increment and the row write are gated on `planned > 0`.

## Fix

`resolveStreakWeekState` returns all four values, with the two arms kept
explicitly distinct, and `isTrainingDayType` applied to *both* sides of the
ratio. The hold arm derives the identity by date; the non-hold arm stays clamped.

## Why the non-hold arm must stay clamped

`redoWeek4` — the current flag-OFF path — extends only `plan_end`
(`grep -n "_planStartKey" workout_schedule_write_service.dart` returns nothing).
So a user who has rolled week 4 sits at a true date-index of 5 while
`getCurrentWeekNumber()` reports 4. An earlier draft of this fix fed the
unclamped index to `getWeek()` in both arms; that would have handed those users a
different week's rows and a different row key **with the flag off**. Caught by
review round 2, mutation-proven here.

## Deliberately out of scope (filed, not deferred)

What happens to the identity if `plan_start` moves while a hold is live consumed
three review rounds and produced a different wrong answer each time. Live risk is
nil and the fix is correct either way, so it is filed as its own OI — scoped to
the two *unguarded* re-anchor movers (`sync_workout.dart:1126`,
`plan_integrity_reconciler.dart:175`) and routed to the piece that already owns
the reconciler. This doc therefore enumerates the four `plan_start` write sites
as fact and makes no behavioural claim about them.
