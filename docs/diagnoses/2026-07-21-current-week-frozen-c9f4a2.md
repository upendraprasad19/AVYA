---
bug_id: c9f4a2
date: 2026-07-21
batch: current-week-fix
blast_radius: platform
status: fixed
symptom: >
  `user_progress.current_week` is a dead constant. Every writer sets the literal
  `1` (user_repository.dart:136, onboarding_provider.dart:473/786,
  graduation_screen.dart:673, pro_phase_advance.dart:107,
  simulation_service.dart:146/563) and nothing ever increments it. Live check on
  dedsavbjuwgarrhphgnl: all 17 users have current_week=1. Because the two Edge
  Functions that read the column just interpolate it, the weekly-recap push says
  "Week 1 debrief ready" forever (weekly-recap-ready/index.ts:190→:76) and the
  weekly AI report says "Current week: 1" (weekly-report/index.ts:460). Worse,
  the AI-coach snapshot carried TWO different week values in one prompt:
  ai_snapshot_builder.dart:88 emitted the live phase week (getCurrentWeekNumber,
  1..4) while :1206 emitted the frozen 1, both survived trimSnapshotToBudget's
  keep-set, and captain_manual.ts:317 pointed the model at the frozen one.
concept: program_week_projection
sot_registry_entry: program_week_projection
writers:
  - { file: lib/core/services/sync/sync_profile.dart, line: 189, source: "current_week upsert — now projects getProgramWeek(phase) (program week 1..12) unconditionally when the kill-switch is OFF; the `!= null` guard on the frozen Hive field is dropped so a restore/null-Hive user's column can't stay stale" }
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, line: 92, source: "progress.current_week — now getProgramWeek((progress['current_phase'] as int?) ?? 1) instead of getCurrentWeekNumber()" }
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, line: 1218, source: "current_plan_summary.week — now getProgramWeek(phase) instead of the frozen (progress['current_week'] as int?) ?? 1; the two snapshot fields now carry ONE value" }
readers:
  - { file: supabase/functions/weekly-recap-ready/index.ts, line: 190, source: "reads user_progress.current_week → push copy 'Week ${currentWeek} debrief ready' (:76); pure interpolation, no EF redeploy needed" }
  - { file: supabase/functions/weekly-report/index.ts, line: 460, source: "reads user_progress.current_week → 'Current week: ${current_week}' in the Gemini brief; pure interpolation" }
  - { file: supabase/functions/_shared/captain_manual.ts, line: 317, source: "points the coach at snapshot.current_plan_summary; now that :1218 is the program week the model reads a correct value; targets the object not the .week subfield, so no change needed" }
hive_key_prefix: user_progress
hive_key_formula: "n/a — user_progress.current_week is a cloud column; the derived value is getProgramWeek(phase) = ((max(1,phase)-1) % 3) * 4 + getCurrentWeekNumber()"
sync_methods: [_syncUserProgress]
restore_methods: [_restoreUserProgress]
cloud_table: user_progress
cloud_columns: [current_week, current_phase]
contract_test_path: test/contracts/program_week_projection_behavioral_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 844, fn: "getCurrentWeekNumber reads plan_start via nowWall() (seam-aware); getProgramWeek derives week-in-phase from it — no new IST surface" }
provider_invalidations: []
telemetry_op_types:
  success: [sync_user_progress]
  failure: [sync_user_progress]
cross_account_guard: >
  Unchanged — the sync write goes through the existing _syncUserProgress upsert
  keyed by the authenticated userId; the snapshot reads user-scoped boxes via
  HiveService. No new box access. The projection is behind the default-ON
  kill-switch `disable_program_week_projection`.
forbidden_patterns_checked: >
  Verified getProgramWeek is always [1,12], never 0 or negative: programWeekFor
  = ((max(1,phase)-1) % 3)*4 + weekInPhase, weekInPhase = getCurrentWeekNumber()
  clamped 1..4 (read_service:846); hand-checked phases 1-7, lapsed-PRO at phase 3
  (→12), and rank-ladder phase 30 (→9..12). Confirmed the 1..4 clamp on
  getCurrentWeekNumber() is UNTOUCHED — this batch does not un-clamp anything, so
  no in-app display string changes and the two dead Train fallbacks
  (train_provider.dart:531/760, `calendarWeek > 0 ? calendarWeek : frozen`) stay
  unreachable (getCurrentWeekNumber floors at 1). Verified via live query that
  user_progress has 0 triggers and no cron/DB-function writes current_week, so
  the client projection has no server-side writer to fight. getPromotionStatus
  does NOT read current_week.
proposed_fix: >
  Project the derived PROGRAM week (getProgramWeek, 1..12 — "true deployment
  progress") into user_progress.current_week on sync, and emit the same value at
  both AI-snapshot week fields, so the weekly push, weekly report and coach all
  agree and the snapshot is single-valued. Founder chose program week over phase
  week (1..4) so an advancing PRO user reads a monotonic "Week 6" rather than a
  confusing reset to "Week 1" — and it already matches the roadmap's
  program-week counter. Fixes the two EFs with NO redeploy (they read the
  column). All three edits behind the default-ON kill-switch
  `disable_program_week_projection` (§4.6); the OFF path is byte-identical to the
  pre-fix behaviour (frozen passthrough / legacy emissions). ACCEPTED coherence
  residual: the in-app Train banner still shows phase week "WK 2 OF 4" while the
  coach/push show program week "Week 6" — this split already exists today
  (banner vs roadmap) and is out of scope for this batch (it is week-model work).
regression_test_planned: >
  test/contracts/program_week_projection_behavioral_test.dart — behavioral:
  getProgramWeek returns 1..12 for (plan_start, phase) pairs; buildAiContext
  emits ONE week value == getProgramWeek and NOT the frozen 1 (FAILS before the
  fix — demonstrated by reverting the :1218 edit: Expected 7, Actual 1);
  getCurrentWeekNumber floors at 1 so the Train fallback stays dead; the
  kill-switch ON restores the verbatim legacy emissions; plus source-wiring
  assertions that both snapshot sites + the sync write gate on the SAME flag key
  and the sync write drops the frozen-field guard.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean (1 info-only null-aware nit, matches surrounding idiom); 6/6 behavioral tests green; revert-demo proved fail-without-fix" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "the frozen Hive progress.current_week is now vestigial — re-hydrated by the restore merge (sync_profile:348-353) but read by nobody (the two Train fallbacks are dead code); pinned by the floors-at-1 test" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "no schema change — same column, meaningful value instead of a constant" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "live: 17/17 rows current_week=1 pre-fix; forward-only — existing rows correct themselves on the next sync; no backfill" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: edge_function_deploy, status: verified, evidence: "NO EF redeploy — weekly-recap-ready:190/76 and weekly-report:460 read the column by pure interpolation; captain_manual:317 targets the object not .week" }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "live: sole cron reader is weekly_recap_ready_sunday (jobid 21); it reads, does not write, current_week" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy change" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage surface" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret surface" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "OneSignal push copy is built server-side from the column; corrected by the projection, no config change" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "live query: 0 triggers on user_progress, no cron/DB-function writes current_week, getPromotionStatus does not read it — the client projection has no server-side writer to fight" }
impact_analysis: >
  Live and wrong for every user today, independent of any hold/week-model
  feature: the Sunday weekly-recap push and the weekly AI report both said
  "Week 1" forever, and the AI coach was pointed at a frozen 1 while a
  contradictory live value sat in the same snapshot. Program-capping was
  considered and rejected in favour of the program week (getProgramWeek) which
  the roadmap already uses; the value is provably [1,12] for every reachable
  phase so the push copy can never read nonsense. Forward-only: no backfill;
  each user's column self-corrects on their next profile sync. Blast radius
  platform (lib/core/services/sync/** → blast_radius.yaml), shipped behind a
  default-ON kill-switch with a byte-identical OFF path.
---

# `current_week` was a frozen constant — the weekly push, report, and coach all said "Week 1"

## Root cause

`user_progress.current_week` had six writers, all writing the literal `1`, and
no incrementer. The column was therefore a dead constant. Three surfaces read it
and surfaced the wrong value to users:

```ts
// weekly-recap-ready/index.ts:76
message: `${firstName} — Week ${currentWeek} debrief ready. Stand to.`   // always "Week 1"
```

The AI snapshot was worse — it carried two *different* week numbers:

```dart
// ai_snapshot_builder.dart:88  (live phase week, 1..4)
'current_week': WorkoutScheduleService.instance.getCurrentWeekNumber(),
// ai_snapshot_builder.dart:1218 (frozen)
final week = (progress['current_week'] as int?) ?? 1;   // always 1
```

and `captain_manual.ts:317` directed the model at the frozen one.

## Fix

Project the derived **program week** (`getProgramWeek`, 1..12 — the roadmap's
"true deployment progress") into the column on sync, and emit the same value at
both snapshot fields:

```dart
// sync_profile.dart — unconditional when the kill-switch is OFF (no frozen guard)
final currentWeekOut = projectionOff
    ? (p['current_week'] as int?)
    : WorkoutScheduleService.instance.getProgramWeek((p['current_phase'] as int?) ?? 1);
...
if (currentWeekOut != null) 'current_week': currentWeekOut,
```

The two Edge Functions read the column by pure interpolation, so fixing the
column fixes the push and the report with **no EF redeploy**. All three edits sit
behind the default-ON kill-switch `disable_program_week_projection`; its OFF path
reproduces the pre-fix behaviour verbatim.

## Why program week, not phase week

The founder chose program week so an advancing PRO user reads a monotonic
"Week 6" instead of a confusing reset to "Week 1" at each phase, and because it
already matches the roadmap counter. The in-app Train banner still shows phase
week ("WK 2 OF 4") — that banner-vs-roadmap split exists today and belongs to
the separate week-model work, not this batch.
