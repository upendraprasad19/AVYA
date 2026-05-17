---
bug_id: 7faa3b
date: 2026-05-17
batch: open-issues OI-07-FOLLOWUP (snapshot orphan-reader fix)
status: fixed
symptom: |
  Silent personalization degradation. OI-07's snapshot contract
  manifest surfaced 11 orphan readers — cron Edge Functions reading
  named fields from `user_daily_snapshots.snapshot_json` that
  `AiCoachRepository.buildAiContext` never emitted. Symptoms in
  production:
  - morning-alert milestone templates rendered generic copy (PR
    placeholders, weight placeholders, streak day count placeholder
    all read null → default template selected).
  - streak-guardian PR shoutouts rendered generic ("you set a PR!"
    instead of "you set a PR on Squat at 80kg!").
  - protein-gap-alert read `daily_targets.protein` (never emitted).
  All silent — readers null-checked and fell through to defaults.
  Discoverable only by manifest sweep.
concept: snapshot_writer_contract
sot_registry_entry: ai_snapshot_building
writers:
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method: buildAiContext top-level alias block, line: 75 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method: _topLevelTodayWorkoutName, line: 1467 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method: _topLevelRecentPrField, line: 1479 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method: _topLevelYesterdayCalories, line: 1499 }
readers:
  - { file: supabase/functions/morning-alert/index.ts, method: snapshot field reads, line: 112 }
  - { file: supabase/functions/streak-guardian/index.ts, method: snapshot field reads, line: 150 }
  - { file: supabase/functions/protein-gap-alert/index.ts, method: snapshot field reads, line: 174 }
hive_key_prefix: ""
hive_key_formula: "snapshot_json.<top_level_key> emitted by buildAiContext"
sync_methods: [pushSnapshot]
restore_methods: []
cloud_table: user_daily_snapshots
cloud_columns: [snapshot_json, user_id, snapshot_date]
contract_test_path: test/contracts/snapshot_orphan_reader_aliases_test.dart
ist_handling:
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, line: 1500, fn: istDateStr in _topLevelYesterdayCalories }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "buildAiContext reads userBox + healthBox via HiveService — user-scoped"
forbidden_patterns_checked:
  - { pattern: "orphan reader in docs/snapshot_contract.yaml without writer alias", absent_outside_canonical: true }
proposed_fix: |
  Writer-side top-level alias block in `buildAiContext` emits the 11
  fields cron readers expect:
    - current_streak_weeks   (alias to progress.current_streak_weeks)
    - current_streak_days    (computed = streak_weeks * 7)
    - total_workouts_done    (alias to progress.total_workouts_done)
    - current_weight_kg      (alias to profile.current_weight_kg)
    - target_weight_kg       (alias to profile.target_weight_kg)
    - today_workout_name     (computed from _getTodayWorkout)
    - recent_pr_exercise     (computed from _getPRTimelineSummary)
    - recent_pr_weight       (computed from _getPRTimelineSummary)
    - yesterday_calories     (computed from nutritionBox)
    - daily_calorie_target   (alias to profile.tdee)
    - daily_targets.protein  (alias to profile.protein_g_target)

  Cost: ~120 bytes per snapshot. Drops first in _compactContext if
  size pressure (aliases are duplicative with nested forms; readers
  always have a fallback path via nested keys for legacy code).

  Writer-side is preferred over reader-side because (a) one file vs
  3 Edge Function redeploys, (b) snapshots are pushed daily by every
  client — fix propagates with next pushSnapshot. Cron readers needed
  no change.
regression_test_planned:
  - test/contracts/snapshot_orphan_reader_aliases_test.dart
---
# Body

## Manifest reference

Full 11-orphan-reader enumeration: `docs/snapshot_contract.yaml`
section `orphan_readers:`. Each entry includes the reader file:line
the writer top-level path (or "NOT EMITTED"), and the drift_class.

## Drift classes

- **nesting_mismatch (7 of 11)**: writer emits the data at a nested
  path; reader expects it at top level. Fix is purely a writer-side
  alias.
- **missing_writer (4 of 11)**: writer never emits the field at all.
  Fix is computing the value from existing Hive data + emitting at
  top level.

The two split based on whether the data already exists in Hive in
some form. All 11 fall into one of these two patterns.

## Why writer-side, not reader-side

Reader-side would require editing 3 Edge Function files
(morning-alert, streak-guardian, protein-gap-alert) AND redeploying
each via `node .claude/deploy_via_api.js`. Each Edge Function has
its own caching + cold-start window; rolling 3 deploys is the kind
of multi-step change that produces partial-application bugs.

Writer-side change is ONE file edit. The next `pushSnapshot()` from
any client picks up the new fields. Cron functions on their next
scheduled run see the aliased fields and render personalized copy.

Plus: `pushSnapshot()` fires fire-and-forget on every app launch
(and after every workout / nutrition mutation). So the fix
propagates within hours of +28 install, not days.

## Verification

- Contract test (source-grep) at
  `test/contracts/snapshot_orphan_reader_aliases_test.dart` — 7
  cases pinning all 11 aliases by emission pattern.
- The contract MANIFEST (`docs/snapshot_contract.yaml`) gates future
  drift via OI-03's planned gate script.

## Closing

closes-oi: OI-07-FOLLOWUP
