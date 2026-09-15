---
bug_id: 8c4ee3
date: 2026-05-12
batch: APK Test #15.4
status: in-progress
symptom: After completing the post-onboarding muster flow (MusterScreen) and entering shoulders as a known injury and legs as the body-part priority, Edit Profile continued to show injuries=['none'] and physique_focus='balanced'. Muster answers persisted to coachBox only and never bridged into userBox['profile'] — the AI coach saw the answers, but Edit Profile and the plan generator did not.
concept: muster_to_profile_bridge
sot_registry_entry: muster_answers
writers:
  - { file: lib/features/ai_coach/services/induction_service.dart, method_or_widget: InductionService.recordMusterAnswer, line: 47 }
  - { file: lib/features/ai_coach/services/induction_service.dart, method_or_widget: InductionService._bridgeToProfile, line: 1 }
  - { file: lib/features/ai_coach/services/induction_service.dart, method_or_widget: InductionService.backfillMusterToProfileIfNeeded, line: 1 }
readers:
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: _EditProfileScreenState.initState, line: 105 }
  - { file: lib/features/profile/providers/profile_completeness_provider.dart, method_or_widget: profileCompletenessProvider, line: 1 }
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, method_or_widget: ExerciseSelector, line: 1 }
hive_key_prefix: "coachBox: known_injuries / typical_wake_time / preferred_workout_time / body_part_priorities; userBox['profile']: injuries / wake_up_time / preferred_workout_time / physique_focus"
hive_key_formula: "muster keys are flat string keys in coachBox; profile fields live inside userBox['profile'] map"
sync_methods:
  - SyncService.syncProfileNow
  - SyncService.pushSnapshot
restore_methods: []
cloud_table: user_profile
cloud_columns:
  - injuries
  - wake_up_time
  - preferred_workout_time
  - physique_focus
contract_test_path: test/contracts/muster_profile_bridge_test.dart
ist_handling: []
provider_invalidations:
  - userProfileProvider
  - profileCompletenessProvider
telemetry_op_types:
  success:
    - muster_bridge_to_profile_succeeded
  failure:
    - muster_bridge_to_profile
    - muster_bridge_backfill
cross_account_guard: "Bridge runs synchronously after coachBox write inside recordMusterAnswer; backfill runs from _ensureLocalUser only after HiveUserSession.openForUser succeeded for the new user, gated by migrationBox['muster_bridge_backfill_v1_done'] flag so it cannot replay across users."
forbidden_patterns_checked:
  - "muster answers visible only to AI coach but not to Edit Profile"
  - "writer-reader bucket drift between coachBox keys and userBox['profile'] fields"
proposed_fix: "Inside InductionService.recordMusterAnswer, after the coachBox write call _bridgeToProfile(key, value) which switches on key and writes the corresponding profile field via UserRepository.updateProfileFields. Add new preferred_workout_time TEXT column via migration 063 + sync projection + Edit Profile picker tile. Convert MusterScreen Q5 to single-select matching physique_focus enum so the bridge maps 1:1. One-shot backfillMusterToProfileIfNeeded copies pre-bridge muster answers into profile defaults on next _ensureLocalUser, gated by migrationBox flag."
regression_test_planned:
  - "test/contracts/muster_profile_bridge_test.dart — bridge_writes_both_buckets (Phase 3)"
  - "test/contracts/muster_question_count_test.dart — muster_renders_3_questions (Phase 2)"
  - "test/contracts/muster_bridge_backfill_test.dart — backfill_idempotent_and_non_clobber (Phase 5)"
---
# Body

## Class

Recurring "writer/reader field drift" — same family as APK Test #6 → #15.3 → B1 above. Sub-class: writer and reader pointing at different Hive buckets. The muster (`MusterScreen` + `InductionService`) writes to `coachBox` exclusively; Edit Profile and the plan generator read from `userBox['profile']`. They share semantic facts (injuries, focus) but no key sharing — a pure SoT split.

## Bridge mapping

| Muster key (coachBox) | Profile field (userBox['profile']) | Notes |
|---|---|---|
| `known_injuries` (List<String>) | `injuries` (List<String>) | direct copy |
| `typical_wake_time` (`"HH:MM"`) | `wake_up_time` (`"HH:MM"`) | direct copy |
| `preferred_workout_time` (`"HH:MM"`) | `preferred_workout_time` (`"HH:MM"`) | new profile field, migration 063 |
| `body_part_priorities` (List<String>, len=1 after B2d) | `physique_focus` (String enum) | reads `[0]`; skipped if len > 1 (legacy multi-select) |
| `why_now` / `definition_of_winning` | — | not bridged; questions removed in B2a |

## Why two essay questions are dropped

Founder direction during brainstorm: "those are stupid questions." Low signal for AI context, high friction for users. Cloud `coach_memory` columns retained so legacy data round-trips on read; no cleanup migration.

## Q5 single-select rationale

Pre-fix Q5 offered 8 multi-select chips (`Back / Chest / Shoulders / Arms / Legs / Glutes / Core / None`) that didn't match the 4-value `physique_focus` enum (`balanced` / `glutes_legs` / `chest_shoulders_arms` / `strength`). Replacing the 8 chips with the 4 enum values + single-select makes the bridge an identity map. Legacy multi-select data is skipped by the bridge (length != 1) and the backfill (length != 1) — user can re-pick via Edit Profile.

## Backfill rules

`backfillMusterToProfileIfNeeded` runs from `_ensureLocalUser` after `HiveUserSession.openForUser` succeeds. Gated by `migrationBox['muster_bridge_backfill_v1_done']` so it executes at most once per device lifetime. Only writes to a profile field if the field is currently at its default value (`injuries == ['none']`, `wake_up_time IS NULL`, `physique_focus == 'balanced'`, `preferred_workout_time IS NULL`). Never clobbers a user-edited value. Skips legacy multi-select `body_part_priorities`. Sets the flag at the end of a successful run; failures leave the flag unset so the backfill retries on next launch.

## Files

- MOD: `lib/features/ai_coach/screens/muster_screen.dart` (drop Q1+Q2, Q5 single-select)
- MOD: `lib/features/ai_coach/services/induction_service.dart` (+ `_bridgeToProfile`, `backfillMusterToProfileIfNeeded`)
- MOD: `lib/core/services/sync_service.dart` (+ `preferred_workout_time` projection)
- MOD: `lib/features/profile/screens/edit_profile_screen.dart` (+ preferred_workout_time picker tile)
- MOD: `lib/features/auth/providers/auth_provider.dart` (call backfill after openForUser)
- NEW: `supabase/migrations/063_add_preferred_workout_time.sql`

Spec: `docs/superpowers/specs/2026-05-12-cross-account-race-and-muster-bridge-design.md`
Plan: `docs/superpowers/plans/2026-05-12-apk-test-15-4-batch.md`
