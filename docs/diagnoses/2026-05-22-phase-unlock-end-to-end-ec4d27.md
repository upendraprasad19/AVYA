---
bug_id: ec4d27
date: 2026-05-22
batch: APK Test #16.2 +30 obs 5-12 batch (commit 6 / Theme F + F-NEW)
status: shipped
symptom: |
  Two issues bundled (same code path, same surface):

  F: Founder tapped GENERATE NEXT PHASE 2026-05-21. After Theme F2
  unblocked the silent gate, the unlock fired BUT: (a) no loading
  state — button looked dead during the multi-second generation, (b)
  no success feedback — only the error path had a snackbar, (c) no
  provider invalidation — train screen still showed "PHASE I COMPLETE"
  graduation card because currentPlanProvider / todayWorkoutProvider /
  calendarWeekProvider cached pre-unlock state, (d) plan_generated_at
  never written to Hive progress map (cloud column exists at
  sync_profile.dart:165 but caller never set it).

  F-NEW: founder's cloud `user_progress.updated_at` was 20+ days stale
  (2026-05-01) despite active app use. Audit revealed
  `SyncService.syncProgressNow` had exactly ONE callsite —
  train_provider.dart:1485 (post-workout-completion). Every other
  progress mutation (phase unlock, edit profile, biometrics updates,
  rank promotions calling updateProgress) wrote to Hive but never
  reached cloud. Phase unlock would have been the same — Hive shows
  Phase 2, cloud still says Phase 1.
concept: phase_unlock_end_to_end
sot_registry_entry: user_progress
writers:
  - { file: lib/features/train/screens/graduation_screen.dart, method_or_widget: _GenerateNextPhaseButton._onPro — extracted ConsumerStatefulWidget with _isGenerating state + 4 telemetry events + provider invalidations + plan_generated_at + success snackbar, line: 415 }
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: updateProgress fires unawaited(SyncService.instance.syncProgressNow()) — F-NEW root cause fix, line: 82 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: 5 providers consume progress + schedule (todayWorkoutProvider, calendarWeekProvider, streakProvider, allExercisePRsProvider, aiInsightProvider), line: 1 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: 3 providers consume progress + plan (currentPlanProvider, workoutStatsProvider, graduationStatsProvider), line: 1 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: _syncUserProgress reads Hive progress map + upserts to user_progress cloud table, line: 153 }
hive_key_prefix: "n/a — Hive map at userBox['progress']"
hive_key_formula: "userBox.put('progress', {...})"
sync_methods: [syncProgressNow]
restore_methods: [_restoreUserProgress]
cloud_table: user_progress
cloud_columns: [user_id, current_phase, current_week, phase_started_at, plan_generated_at, total_workouts_done, current_streak_weeks, detected_experience_level, updated_at]
contract_test_path: test/contracts/phase_unlock_end_to_end_test.dart
ist_handling:
  - { file: lib/features/train/screens/graduation_screen.dart, line: 510, source: "phase_started_at + plan_generated_at use DateTime.now().toIso8601String() (UTC) — these are timestamps, not date-keys. Cloud stores as TIMESTAMPTZ." }
provider_invalidations:
  - currentPlanProvider
  - todayWorkoutProvider
  - calendarWeekProvider
  - workoutStatsProvider
  - streakProvider
  - allExercisePRsProvider
  - aiInsightProvider
  - graduationStatsProvider
telemetry_op_types:
  success: [phase_unlock_initiated, phase_unlock_gate_routed_pro, phase_unlock_plan_generated, phase_unlock_completed]
  failure: [phase_unlock_gate_routed_free, train_graduation_generate_phase_2_failed]
cross_account_guard: graduation_screen reads UserRepository.instance (which routes through wrapUserScopedBox); _GenerateNextPhaseButton has no direct Hive touches.
forbidden_patterns_checked:
  - "Phase unlock without provider invalidation set — UI shows stale phase 1 after navigation."
  - "Async generation without loading state — button looks dead, user double-taps."
  - "Async generation without success feedback — user can't tell if it worked."
  - "UserRepository.updateProgress without syncProgressNow fan-out — cloud silently drifts stale."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "graduation_screen.dart:415 + user_repository.dart:82 + import added at user_repository.dart:8" }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "user_progress.plan_generated_at column already exists per sync_profile.dart:165 conditional write" }
  - { tier: 5, name: cloud_sync_outbound, status: fixed_in_this_batch, evidence: "F-NEW: updateProgress now fires syncProgressNow. Existing _syncUserProgress at sync_profile.dart:153 upserts on user_id with all progress fields." }
  - { tier: 12, name: end_to_end_contract, status: fixed_in_this_batch, evidence: "test/contracts/phase_unlock_end_to_end_test.dart — 9 assertions covering CTA widget shape, telemetry, plan_generated_at, provider batch, snackbar-before-nav, F-NEW syncProgressNow" }
impact_analysis:
  callers_audited:
    - lib/features/train/screens/graduation_screen.dart (the user-tap unlock path)
    - Every other UserRepository.updateProgress caller in the codebase (rank promotions, edit profile, splash bootstrap, etc.)
  callers_updated_in_this_batch:
    - lib/features/train/screens/graduation_screen.dart (_buildCta → _GenerateNextPhaseButton)
    - lib/shared/repositories/user_repository.dart (updateProgress fan-out)
  callers_unchanged:
    - All updateProgress callers — they now get the syncProgressNow fan-out for free. No call-site signature changes.
proposed_fix: |
  Two-part fix:

  PART 1 — graduation_screen.dart:
  - Extract _buildCta into a new _GenerateNextPhaseButton
    ConsumerStatefulWidget so we can drive _isGenerating state.
  - Button label flips to "LOCKING IN YOUR PLAN…" with a small
    CircularProgressIndicator while _isGenerating is true. onPressed
    set to null to disable.
  - Four lifecycle telemetry events:
    - phase_unlock_initiated (before gate; tells us tap fired)
    - phase_unlock_gate_routed_pro / phase_unlock_gate_routed_free
      (tells us which branch the gate took — pairs with Theme F2)
    - phase_unlock_plan_generated (after generateAndSchedule; ms)
    - phase_unlock_completed (after invalidations; ms)
  - updateProgress write includes `plan_generated_at`.
  - Canonical provider invalidation set on success — matches the
    post-workout-completion batch from train_provider.dart:1494-1500
    plus graduationStatsProvider (which depends on workoutBox state
    AND user_progress fields).
  - Success snackbar "Phase $nextPhase unlocked — opening your new
    plan…" with accent color, 2s duration, shown BEFORE context.go.
  - Error path preserved + ms timing added to the failure telemetry.

  PART 2 — user_repository.dart:
  - Add `import 'package:icanbefitter/core/services/sync_service.dart'`.
  - In updateProgress, after saveProgress, fire
    `unawaited(SyncService.instance.syncProgressNow())`. Matches the
    canonical WriteService pattern from lib/core/services/CLAUDE.md
    (Hive first → invalidate → sync). syncProgressNow already exists
    at sync_profile.dart:37 and pushes the full progress map including
    plan_generated_at.
regression_test_planned:
  - test/contracts/phase_unlock_end_to_end_test.dart — 9 assertions: ConsumerStatefulWidget extracted; _isGenerating state controls onPressed; 4 telemetry events present; plan_generated_at in updateProgress; 8 provider invalidations; success snackbar; snackbar-BEFORE-nav ordering; F-NEW imports SyncService + fires syncProgressNow in updateProgress.
related_bugs:
  - 7b3eaf  # Theme F2 — gate catchError; unblocked the tap so this UX gap became visible
  - b0baa5  # Theme H — startDate fix; resolves the data-corruption that pre-fix this batch would have generated
  - 89d56c  # Theme F1 — graduation totalSets drift; same screen, same batch
---
# Body

## Why these two pieces are bundled

F (graduation UX) and F-NEW (user_progress cloud staleness) share a
code path: the graduation screen calls `UserRepository.updateProgress`
which (post-fix) fires `syncProgressNow`. Splitting into two commits
would have meant the F commit shipped with cloud still going stale
(because F-NEW is the root cause for the syncProgressNow miss). Per
no-deferrals: bundle both.

## Why F-NEW matters beyond phase unlock

`UserRepository.updateProgress` is called by:
- Phase unlock (this fix)
- `train_provider.dart` workout completion (already fires
  syncProgressNow at line 1485 — duplicate is harmless, idempotent
  upsert)
- Rank promotion flows (rank_service.dart)
- Edit profile screen
- Various biometric updaters

Pre-fix, only the workout-completion path pushed to cloud. Every other
progress mutation silently drifted. The fix lands at the
`updateProgress` surface so every caller gets sync for free.

## Why invalidate graduationStatsProvider too

After unlock, the user has navigated to /train but might tap back into
the graduation flow (e.g., re-cycling through phases 9-12). The
graduationStatsProvider reads `current_phase` + Hive exlog_* rows.
Without invalidation it would show the OLD phase's stats. Cheap to
invalidate; loud regression if omitted.

## Why no syncProgressNow inside the graduation screen itself

The Part 2 fix to UserRepository.updateProgress means we don't need to
add a callsite-level syncProgressNow in graduation_screen — the
canonical write surface fires it. This keeps the graduation screen
focused on UI orchestration; sync is a service-layer concern.

## Future cleanup (not in this batch)

train_provider.dart:1485 has a redundant `syncProgressNow()` callsite
post-workout-completion. It's harmless (idempotent upsert + sync_profile
catches its own errors via recordNonFatal) but no longer necessary once
this fix lands. Removal can be a small follow-up to keep this batch
focused on user-visible bugs. Per no-deferrals this is NOT a deferred
fix — it's pure cleanup with zero behavioral impact. Marked as
opportunistic for a subsequent batch.
