---
bug_id: 4f8e2d
date: 2026-05-19
batch: APK Test #16.2 observations (2026-05-19 — obs 1+2 batch)
status: shipped
symptom: |
  Founder install of APK Test #16.2 on 2026-05-19 (Tue). RestoringScreen
  sat on "Pulling your dispatch. Stand by, soldier." long enough for the
  15-second safety-net timer at restoring_screen.dart:42 to fire,
  exposing the "This is taking a while." subtitle + "CONTINUE" escape
  CTA. Founder asked "what is taking so much time? and why?". Before
  this batch there was no per-op timing or per-step timing in
  restoreFromCloudForUser — _safeRestoreOp wrapped failures but not
  successes, so post-mortem could not point at a long-pole op. This
  batch is instrument-then-fix: ship timing + dynamic progress text;
  use the next install's data to drive a targeted fix in the follow-up
  batch (background-restore mode is the candidate big lever).
concept: restore_long_pole_timing_visibility
sot_registry_entry: sync
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: SyncService.restoreFromCloudForUser orchestrates Steps A/B/C + subscription refresh, line: 791 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: _safeRestoreOp wraps each restore op with Stopwatch + emits restore_op_done, line: 1180 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: restoreProgressLabel ValueNotifier surfaced for RestoringScreen, line: 315 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: ExlogKeyMigrator + NlogKeyMigrator wrapped with Stopwatch + emit restoring_screen_migrator_done, line: 173 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: ValueListenableBuilder binds progress label to SyncService.restoreProgressLabel, line: 310 }
readers:
  - { file: lib/core/services/error_telemetry.dart, method_or_widget: ErrorTelemetry.logEvent emits restore_op_done / restore_step_done / restoring_screen_migrator_done via log-client-error edge function, line: 237 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: ValueListenableBuilder<String> reads SyncService.restoreProgressLabel, line: 310 }
hive_key_prefix: "n/a (telemetry batch — no Hive contract changes)"
hive_key_formula: "n/a"
sync_methods: [restoreFromCloudForUser, syncWorkoutData, syncFreezes]
restore_methods: [restoreFromCloudForUser]
cloud_table: client_errors
cloud_columns: [op_type, message, user_id]
contract_test_path: test/contracts/streak_freeze_refill_telemetry_test.dart
ist_handling:
  - { file: lib/core/services/sync_service.dart, line: 791, source: restoreFromCloudForUser uses ISO timestamps; no date-key math in the timing batch }
provider_invalidations: [streakFreezeProvider, streakProvider]
telemetry_op_types:
  success: [restore_op_done, restore_step_done, restoring_screen_migrator_done, restore_completed]
  failure: [restore_from_cloud_for_user, subscription_refresh_on_restore]
cross_account_guard: SyncService.restoreFromCloudForUser already calls HiveUserSession.openForUser before any restore op runs; no change in this batch.
forbidden_patterns_checked:
  - "Restore steps without timing telemetry — would re-introduce the long-pole-invisible problem."
  - "Static progress label on RestoringScreen — leaves user staring at the same text for the full restore."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "_safeRestoreOp wraps every op with Stopwatch; step boundaries emit restore_step_done; migrators wrapped" }
  - { tier: 5, name: cloud_sync_outbound, status: verified, evidence: "log-client-error edge function v7 already lives at 2000/day limit per skill §2.13; LOW-priority op_types land in rate-limited lane — acceptable for one-week diagnostic window" }
  - { tier: 12, name: end_to_end_contract, status: verified, evidence: "test/contracts/streak_freeze_refill_telemetry_test.dart pins restore_op_done + restore_step_done + restoring_screen_migrator_done + ValueListenableBuilder binding" }
impact_analysis:
  callers_audited:
    - lib/features/auth/screens/restoring_screen.dart (consumes restoreProgressLabel ValueNotifier)
    - lib/features/auth/screens/splash_screen.dart (kicks off restoreFromCloudForUser via runRolloverNow / nav to /restoring)
  callers_updated_in_this_batch:
    - lib/core/services/sync_service.dart (added Stopwatch + telemetry + ValueNotifier; preserved restore order, cancellation gates, and pre-existing telemetry contracts)
    - lib/features/auth/screens/restoring_screen.dart (migrator timing + ValueListenableBuilder for label)
  callers_unchanged:
    - lib/core/services/error_telemetry.dart (existing logEvent API used as-is)
    - lib/features/auth/screens/restoring_screen.dart timeout-CTA logic (15s safety-net still fires; the CTA escape unchanged)
proposed_fix: |
  Telemetry-only batch — A5 (background-restore mode) deferred.

  A1. _safeRestoreOp wraps op with Stopwatch; on success emits
      ErrorTelemetry.logEvent('restore_op_done', message: 'op=$label
      ms=$elapsed'). Failure path keeps the existing _reportSyncFailure
      with the elapsed ms appended to the debug log.

  A2. restoreFromCloudForUser brackets Step A / Step B / Step C /
      subscription refresh with separate Stopwatch instances. Each step
      emits ErrorTelemetry.logEvent('restore_step_done', message:
      'step=A|B|C|sub ms=$elapsed'). restore_completed (existing event)
      now carries 'total_ms=$elapsed' in its message — single-event
      post-mortem reads end-to-end duration.

  A3. RestoringScreen wraps ExlogKeyMigrator + NlogKeyMigrator with
      Stopwatch + emits ErrorTelemetry.logEvent(
      'restoring_screen_migrator_done', message: 'migrator=exlog|nlog
      ms=$elapsed did_run=$bool'). These run AFTER restoreFromCloudForUser
      but BEFORE /home navigation, so their cost extends RestoringScreen's
      perceived duration beyond restore_completed.

  A4. SyncService exposes a public final ValueNotifier<String>
      restoreProgressLabel (initial 'Pulling your dispatch.'). Each
      step start in restoreFromCloudForUser updates the value
      ('Loading profile & plan' → 'Catching up your history' →
      'Finishing up'). RestoringScreen renders the title via
      ValueListenableBuilder<String> bound to the notifier. UX patch
      — doesn't make restore faster, but gives the user a signal
      something is happening during long restores.

  A5 deferred — background-restore mode (let /home render after Step
  A + migrators, finish Step B in background) requires every consumer
  of workout_logs / nutrition_logs / coach_interactions to handle
  "data still loading" gracefully. Right call is to first see from A1+A2
  telemetry which Step B op is the actual long pole.
regression_test_planned:
  - test/contracts/streak_freeze_refill_telemetry_test.dart — pins all four telemetry event names + the restoreProgressLabel ValueNotifier wiring.
---
# Body

## Why instrument-then-fix is the right shape

The pre-fix codebase had `_reportSyncFailure` emitting `restore_$label` ONLY when an op failed. Successes were silent. With 14 ops in Step B running in parallel via `Future.wait(eagerError: false)`, the post-mortem question "which op took 10 of those 15 seconds" was unanswerable from `client_errors` alone.

Shipping a candidate fix (e.g., backgrounding Step B, or batching network calls) without this telemetry would amount to guessing. Past batches that guessed at perf optimisations have moved the slowness instead of fixing it (see project history on the migrator/sync interplay through Tests #12.5–#12.8).

## The next install will tell us which step is the long pole

Once founder runs this APK, a single query against `client_errors` returns the timing breakdown:

```sql
SELECT op_type, message, created_at
FROM client_errors
WHERE user_id = '<founder>'
  AND op_type IN (
    'restore_started', 'restore_op_done', 'restore_step_done',
    'restoring_screen_migrator_done', 'restore_completed'
  )
ORDER BY created_at DESC
LIMIT 50;
```

The pattern `restore_step_done step=B ms=N` will show whether Step B (bulk history) is the long pole. Cross-reference `restore_op_done op=<label> ms=N` for the 14 sub-ops to pick the specific table that dominates the wait — and that's the target for any A5-style or query-optimisation follow-up.

## What changed and what did NOT change

Changed: `_safeRestoreOp`, the inside of `restoreFromCloudForUser`, the inside of RestoringScreen's `_ensureOwnershipBeforeHome` migrator wrappers, and the static Text widget that previously read `'Pulling your dispatch.'`.

NOT changed: the order of restore operations, the cancellation gate semantics, the `eagerError: false` propagation, the 15-second CONTINUE safety net, or any of the writer/reader contracts touched by parallel work in 9c4a17. The telemetry batch is strictly additive.

## Rate-limit consideration

`log-client-error` v7 (per debugging skill §2.13) caps at 2000 events/day per user with a HIGH_PRIORITY_OP_TYPES allowlist. The four new op_types here are LOW priority and will share the limit with all other LOW events. For a single restore pass we emit at most: 14 × `restore_op_done` + 4 × `restore_step_done` + 2 × `restoring_screen_migrator_done` + 1 × `restore_started` + 1 × `restore_completed` = 22 events. Even with 10 cold-starts per day (heavy founder testing) that's 220 events — well below the cap.
