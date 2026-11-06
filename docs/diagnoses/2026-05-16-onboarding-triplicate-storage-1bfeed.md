---
bug_id: 1bfeed
date: 2026-05-16
batch: audit-2026-05-16 reader-side / F3-2.1 (Phase B agent finding)
status: fixed
symptom: |
  Onboarded users (cloud `user_profile` populated with goal/weight/phase)
  could land on `/onboarding/mission-brief` on fresh install when (a)
  cloud `user_profile.onboarding_completed_at` was NULL (cloud sync had
  failed during original onboarding) AND (b) the self-heal path read
  the obsolete configBox value for the boolean fallback. Devices that
  had run UserConfigMigrator v2 had the value in userBox; reading
  directly from configBox returned false; self-heal skipped; user
  routed back through onboarding.
concept: onboarding_completed_at
sot_registry_entry: onboarding_completed_at
writers:
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method: completeOnboarding, line: 691 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method: _stampOnboardingCompletedAt, line: 213 }
readers:
  - { file: lib/features/auth/screens/restoring_screen.dart, method: _selfHealMismatch, line: 86 }
  - { file: lib/core/router/app_router.dart, method: redirect logic, line: 551 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method: _getOnboardingCompletedAt, line: 1928 }
  - { file: lib/features/train/repositories/workout_repository.dart, method: _earliestUserAnchor, line: 134 }
hive_key_prefix: "(MigratedKey 'onboarding_completed' + userBox['profile']['onboarding_completed_at'])"
hive_key_formula: "MigratedKey 'onboarding_completed' (bool, derived) + userBox['profile']['onboarding_completed_at'] (ISO datetime, canonical local)"
sync_methods: [_syncUserProfile]
restore_methods: [_restoreUserProfile]
cloud_table: user_profile
cloud_columns: [user_id, onboarding_completed_at]
contract_test_path: test/contracts/onboarding_completed_migrated_key_test.dart
ist_handling: []
provider_invalidations: [userProfileProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "MigratedKey reads route through userBox once a session is open — user-scoped after Test #11.1 UserConfigMigrator v2"
forbidden_patterns_checked:
  - { pattern: "configBox.get('onboarding_completed'", absent_outside_canonical: true }
proposed_fix: |
  `RestoringScreen._selfHealMismatch` at line 86 now reads
  `MigratedKey.readWithDefault<bool>('onboarding_completed', false)`
  instead of `HiveService.instance.configBox.get('onboarding_completed',
  defaultValue: false)`.
  The MigratedKey helper checks userBox first (post-migration storage),
  falls back to configBox (pre-migration installs). This gives correct
  results for devices that have run UserConfigMigrator v2 AND devices
  that haven't.
  Import added: `package:icanbefitter/core/services/migrated_key.dart`.
  Other onboarding readers were audited; all other consumer sites
  already use either MigratedKey (auth_provider, app_router,
  user_repository) or the canonical userBox profile timestamp
  (ai_coach_repository, workout_repository, profile_screen). No
  additional consolidation needed.
regression_test_planned:
  - test/contracts/onboarding_completed_migrated_key_test.dart
---
# Body

## Symptom

Returning user signs in on a fresh install:
1. `RestoringScreen` runs the post-auth gate.
2. Cloud `user_profile` row exists with goal/weight/phase populated
   but `onboarding_completed_at IS NULL` (original onboarding's
   cloud sync had failed silently).
3. Self-heal path at line 73-105 attempts to stamp
   `onboarding_completed_at` if Hive shows the user IS onboarded.
4. Hive check reads `configBox.get('onboarding_completed', false)`
   directly — returns false because Test #11.1's UserConfigMigrator
   v2 moved the key to userBox.
5. Self-heal sees "no Hive evidence of onboarding" -> routes user to
   `/onboarding/mission-brief`.
6. User has to re-do onboarding despite being onboarded.

## Root cause

Triplicate storage:
- Cloud `user_profile.onboarding_completed_at` (timestamp)
- Hive `userBox['profile']['onboarding_completed_at']` (timestamp)
- MigratedKey `'onboarding_completed'` (boolean derived flag)

After Test #11.1's UserConfigMigrator v2, the boolean lives in
userBox (not configBox). The self-heal fallback at
`restoring_screen.dart:87` used the pre-migration access pattern —
`configBox.get('onboarding_completed')` directly — bypassing the
migration helper.

Reading from configBox returns the LEGACY value on devices that
have run the migration. For migrated devices, that value is null
(the migrator deleted it from configBox after copying to userBox).
So the self-heal always saw false on the affected install path.

This was finding F3-2.1 from Phase B agent inventory. Initially
deferred along with sleep-dual-key. Founder pushback reclassified
as in-scope per `feedback_no_deferrals_recurrence.md` (5th instance).

## Fix

See `proposed_fix` in frontmatter. Single-line read change at line
86 + import statement.

## Regression test

`test/contracts/onboarding_completed_migrated_key_test.dart` — 3
source-grep contract tests:
- Self-heal reads `onboarding_completed` via `MigratedKey.readWithDefault`
- Self-heal does NOT read `configBox.get('onboarding_completed')` directly
- `MigratedKey` is imported
