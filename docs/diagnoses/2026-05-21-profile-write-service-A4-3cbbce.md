---
bug_id: 3cbbce
date: 2026-05-21
batch: Tech-debt audit 2026-05-20 / B2 continuation (finding A4)
status: shipped
symptom: |
  Profile map mutations (goal changes from the AI Coach, weight
  updates from the home weight tile, post-sign-in cloud merge,
  brand-new user stub creation, phase_started_at stamping during
  onboarding plan generation, cloud-restore hydration) all wrote
  `userBox.put('profile', ...)` directly with no canonical service.
  Seven independent call sites — no chokepoint to enforce any
  future profile-class invariant (BMR recompute on weight change,
  badge revalidation on goal change, IST-stamped updated_at, sync
  fan-out, mutex against read-modify-write races between concurrent
  goal vs. weight writers landing within milliseconds). Audit
  finding A4 — same architectural asymmetry that produced pre-Test-#6
  workout/nutrition writer drift and pre-Test-#16.2 health-domain
  drift.
concept: profile_write_service
sot_registry_entry: profile_write_service
writers:
  - { file: lib/features/profile/services/profile_write_service.dart, method: ProfileWriteService.updateProfile, line: 60 }
  - { file: lib/features/profile/services/profile_write_service.dart, method: ProfileWriteService.patchProfile, line: 86 }
  - { file: lib/features/profile/services/profile_write_service.dart, method: ProfileWriteService.updateField, line: 110 }
readers:
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: UserRepository.getProfile (canonical read), line: 42 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: home_provider reads userBox['profile'] for greeting + weight tile, line: 768 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: tool_dispatcher reads userBox['profile'] before goal change, line: 890 }
hive_key_prefix: profile
hive_key_formula: "userBox.get('profile') — single-keyed entry"
sync_methods: [SyncService.syncProfileNow]
restore_methods: [SyncService._restoreUserProfile]
cloud_table: user_profile
cloud_columns: [user_id, primary_goal, current_weight_kg, height_cm, gender, date_of_birth, activity_level, days_per_week, fitness_experience, equipment_access, phase_started_at, daily_calories, protein_grams, carbs_grams, fat_grams, water_target_ml, bmr, tdee, full_name, email, updated_at]
contract_test_path: test/contracts/profile_write_service_only_test.dart
ist_handling:
  - { file: lib/features/profile/services/profile_write_service.dart, line: 67, fn: ProfileWriteService.updateProfile stamps istNow().toIso8601String() onto updated_at }
  - { file: lib/features/profile/services/profile_write_service.dart, line: 95, fn: ProfileWriteService.patchProfile stamps istNow().toIso8601String() onto updated_at }
provider_invalidations: [userProfileProvider, weightLogNotifierProvider, primaryGoalProvider]
telemetry_op_types:
  success: [upsert_user_profile]
  failure: [profile_write_service_update_profile, profile_write_service_patch_profile, upsert_user_profile]
cross_account_guard: HiveUserSession.openForUser scopes userBox to the active session; ProfileWriteService writes through HiveService.instance.userBox which is the GuardedBox wrapper — cross-account writes are blocked at the box layer. _fireSync reads SupabaseService.instance.currentUser?.id so a logged-out write does not push.
forbidden_patterns_checked:
  - { pattern: "userBox\\.put\\('profile'", absent: true }
  - { pattern: "_hive\\.userBox\\.put\\('profile'", absent: true }
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "ProfileWriteService created at lib/features/profile/services/profile_write_service.dart with 3 public methods; 7 prior call sites migrated; flutter analyze --no-fatal-infos clean on the 9 touched files" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "test/contracts/profile_write_service_only_test.dart 4/4 PASS — replace, merge, single-field, and create-from-empty semantics all exercised against real Hive on temp dir" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change — service writes to existing userBox['profile'] map; cloud user_profile table columns unchanged" }
  - { tier: 5, name: cloud_sync_outbound, status: verified, evidence: "ProfileWriteService._fireSync calls existing SyncService.instance.syncProfileNow(userId); skipSync: true path used for restore-class writes (sync_profile.dart:274, auth_provider.dart:619 + :762) to prevent cloud→Hive→cloud loop" }
  - { tier: 6, name: cloud_sync_restore, status: verified, evidence: "sync_profile.dart:274 _restoreUserProfile routed through ProfileWriteService.updateProfile(skipSync: true) — restore-class semantics preserved (cloud is the source; do not re-push)" }
  - { tier: 9, name: provider_invalidation, status: verified, evidence: "Existing provider invalidation paths in home_provider (BadgeService.checkAll), tool_dispatcher (post-goal-change refresh), and weightLogNotifier unchanged — service is a write chokepoint, not a state surface" }
  - { tier: 12, name: end_to_end_contract, status: verified, evidence: "scripts/check_profile_write_service_only.dart PASS — gate auto-tightens once canonical file exists; behavioral contract test pins replace + merge + single-field + create-empty semantics" }
impact_analysis:
  callers_audited:
    - lib/features/auth/providers/auth_provider.dart (post-sign-in cloud merge + minimal new-user stub)
    - lib/features/home/providers/home_provider.dart (weight tile current_weight_kg update)
    - lib/features/ai_coach/services/tool_dispatcher.dart (AI-driven primary_goal change)
    - lib/core/services/workout_schedule_service.dart (onboarding phase_started_at stamp)
    - lib/core/services/sync/sync_profile.dart (cloud→Hive restore-class hydration)
    - lib/shared/repositories/user_repository.dart (canonical saveProfile / updateProfileFields delegates)
  callers_updated_in_this_batch:
    - lib/features/auth/providers/auth_provider.dart (2 sites — both with skipSync: true since one is cloud-restore-class and the other is a pre-onboarding stub)
    - lib/features/home/providers/home_provider.dart (now ProfileWriteService.updateField — removed inline read-modify-write + explicit syncProfileNow + unused SyncService/SupabaseService imports)
    - lib/features/ai_coach/services/tool_dispatcher.dart (patchProfile for the 4-key goal change set)
    - lib/core/services/workout_schedule_service.dart (updateField for phase_started_at)
    - lib/core/services/sync/sync_profile.dart (updateProfile with skipSync: true)
    - lib/shared/repositories/user_repository.dart (saveProfile + updateProfileFields delegate to the new service)
  callers_unchanged:
    - All readers of userBox['profile'] — semantics preserved (the Hive shape is byte-identical except for a new updated_at field)
proposed_fix: |
  Create ProfileWriteService at lib/features/profile/services/
  profile_write_service.dart mirroring HealthWriteService:
  static singleton, single global mutex (profile is single-keyed),
  three public methods (updateProfile = replace, patchProfile =
  merge, updateField = single-key convenience), IST-stamped
  updated_at on every write, fire-and-forget syncProfileNow on
  non-restore writes.

  Migrate all 7 prior call sites. Two of them (sync_profile.dart's
  _restoreUserProfile and auth_provider's cloud-merge + new-user
  stub) are restore-class — they pass skipSync: true so the data
  that just came FROM cloud isn't immediately pushed BACK to cloud
  in a redundant loop.

  Gate 35 (scripts/check_profile_write_service_only.dart) auto-
  tightens from WARN to PASS once the canonical file exists — its
  existing logic already filters all production code outside the
  canonical path. No script change needed. Verified PASS after
  migration.

  Why this matters going forward: every future invariant that needs
  to attach to a profile write (BMR recompute, badge revalidation,
  goal-change history, audit logging) has exactly one place to land
  instead of seven. The drift class that caused Test #6 and Test
  #16.2 had the same shape — writer scattered, one site silently
  bypasses an invariant added in a later batch.
regression_test_planned:
  - test/contracts/profile_write_service_only_test.dart — BEHAVIORAL test (Hive on temp dir): seeds existing profile, exercises updateProfile (replace), patchProfile (merge), updateField (single-key), and patchProfile-on-empty (create) semantics. Source-grep ban of `userBox.put('profile')` outside the canonical service is enforced by Gate 35 (scripts/check_profile_write_service_only.dart) rather than duplicated here.
---
# Body

## What changed

Created `lib/features/profile/services/profile_write_service.dart` —
~130 lines. Three public methods on a static singleton, behind a
single global mutex (profile is one Hive key, not date-partitioned
like workouts/nutrition/health). Every method stamps `updated_at`
via `istNow().toIso8601String()` and fires
`SyncService.instance.syncProfileNow(userId)` fire-and-forget.

`skipSync: true` is the explicit opt-out for restore-class writes
(`sync_profile.dart` cloud-restore + `auth_provider.dart` post-sign-in
cloud merge + minimal-stub creation). Without it, every restore
would immediately re-push the just-restored data back to cloud — a
no-op functionally but a wasted upsert per launch.

## Why this isn't gold-plating

This wasn't about a current bug — it's about the next bug we already
know is coming. The Test #6 batch surfaced workout writer/reader
drift. Test #16.2 surfaced the same shape in the health domain
(`HealthWriteService` was the fix). Profile is the only major Hive
key prefix still without a write service. Tomorrow's invariant
(say, "every weight change must trigger BMR recompute") would land
in one place — `ProfileWriteService.updateField` — and silently
skip the six other writer sites unless we audited every one
manually. We've seen that audit miss multiple times.

## Migration touch list

| Site | Method chosen | Why |
|---|---|---|
| `user_repository.dart:50` | `updateProfile` / `patchProfile` | The pre-existing public API of UserRepository becomes a thin delegate. |
| `home_provider.dart:773` | `updateField('current_weight_kg', ...)` | Single-field intent at call site. The inline `syncProfileNow` and `SyncService`/`SupabaseService` imports were removed — the service handles both. |
| `tool_dispatcher.dart:901` | `patchProfile` (4 keys) | Multi-field atomic update for goal-change provenance. |
| `auth_provider.dart:615` | `updateProfile(skipSync: true)` | Cloud→Hive merge; restore-class. |
| `auth_provider.dart:753` | `updateProfile(skipSync: true)` | Minimal new-user stub; cloud row is created by onboarding sync later. |
| `workout_schedule_service.dart:438` | `updateField('phase_started_at', ...)` | Single-field timestamp during first plan gen. |
| `sync_profile.dart:270` | `updateProfile(skipSync: true)` | Restore-class — cloud is the source. |

## Gate 35 status

Before: `[Gate 35] WARN (B2-transitional): ProfileWriteService not
yet created; 7 profile write(s) outside canonical service.`

After: `[Gate 35] PASS: all userBox.put('profile') writes go through
ProfileWriteService.`

The gate script (`scripts/check_profile_write_service_only.dart`)
was unchanged — its existing logic auto-promotes from WARN to
hard-fail once `lib/features/profile/services/profile_write_service.dart`
exists. The exit-1 path is now armed for any future regression that
adds a non-canonical `userBox.put('profile', ...)` writer.

## Behavioral test

`test/contracts/profile_write_service_only_test.dart` — 4 tests,
all PASS. Spins up Hive on a temp directory, opens a fake user
session, exercises the actual service against the actual box:

1. `updateProfile` replaces the full shape — keys absent from the
   new map are gone after the write. `updated_at` is stamped.
2. `patchProfile` merges — only the patched key changes; other
   fields survive. `updated_at` is stamped.
3. `updateField` changes exactly one field; everything else intact.
4. `patchProfile` on empty Hive creates the profile from scratch
   (defensive — caller shouldn't typically do this but we don't
   throw).
