# Agent 4 Findings — Cluster 5 (Sync fan-out + restore completeness)

**Date:** 2026-05-16

## Root-cause class for all 8 RED FLAG zero-row tables

**Same class:** sync methods exist and are technically correct, but they are invoked ONLY in `weeklyFullSync()` (line 514, daily on app launch), NOT immediately after the user-action Hive mutation. The fire-and-forget call site is missing.

This is the SAME drift class as Tests #11/#12/#16 but at the WIRING layer rather than the FIELD layer.

## Per-table cards

### `user_saved_meals` — CONFIRMED_BUG (missing fan-out trigger)
- Hive prefix: `saved_meal_*` in nutritionBox
- Writer: `lib/core/services/sync/sync_nutrition.dart:232 _syncSavedMeals`
- Restore: `_restoreSavedMeals` L401 ✅
- Root cause: `syncNutritionData()` calls `_syncSavedMeals()`, but the saved-meal creation path (`NutritionWriteService.saveMealPreset`) likely doesn't go through `syncNutritionData()`. Need to add `unawaited(SyncService.instance.syncNutritionData())` to the save path.

### `user_custom_foods` — CONFIRMED_BUG (missing fan-out trigger)
- Hive prefix: `custom_food_*` in customBox
- Writer: `lib/core/services/sync/sync_community.dart:140 _syncCustomItems`
- Restore: `_restoreCustomFoods` L371 ✅
- Public wrapper: `syncCustomItemsNow()` L88 exists but not wired into create flow (likely `custom_food_sheet.dart`).

### `sleep_logs` — CONFIRMED_BUG (missing fan-out trigger)
- Hive prefix: `sleep_log_YYYY-MM-DD` in healthBox
- Writer: `lib/core/services/sync/sync_health.dart:171 _syncSleepLogs`
- Restore: `_restoreSleepLogs` L329 ✅
- Public wrapper: `syncSleepNow()` L38 exists; called on manual sync only, not after AI coach `conversational_log_handler._logSleep` L44-85.
- **Linked to F2-R2 (Agent 1):** `profile_provider.dart:498 BiometricNotifier.logSleep` writes directly to Hive without firing sync.

### `body_measurements` — CONFIRMED_BUG (missing fan-out trigger)
- Hive prefix: `measurement_YYYY-MM-DD` in healthBox
- Writer: `lib/core/services/sync/sync_health.dart:139 _syncMeasurements`
- Restore: `_restoreMeasurements` L301 ✅
- Public wrapper: `syncMeasurementsNow()` L91 exists but not called after measurement creation.

### `saved_diet_plans` — CONFIRMED_BUG (missing fan-out trigger)
- Hive prefix: `saved_diet_plan` (single key) via MigratedKey
- Writer: `lib/core/services/sync/sync_restore_completeness.dart:96 syncSavedDietPlan`
- Restore: `_restoreSavedDietPlan` L236 ✅
- CLAUDE.md §15 comment claims it's called from `diet_plan_screen._savePlan`, but grep for `_savePlan` in `diet_plan_screen.dart` returns no match. Either the method renamed or the wiring never happened.

### `referral_codes` — FRAMEWORK_GAP (missing restore method)
- Hive prefix: NONE — cloud-authoritative only
- Writer: `lib/core/services/supabase_service.dart:127 _generateNewCode` (direct cloud upsert)
- Restore: **NONE** ❌
- **Root cause:** Generated on-demand from Profile → Invite Friends; never pulled back to Hive on cross-device restore. Founder codes from Test #2 vanish on new device. `restoreFromCloudForUser()` L725 doesn't call any referral-code restore.

### `promo_code_uses` — FRAMEWORK_GAP (RPC-only, no client surface)
- Hive prefix: NONE
- Writer: `increment_promo_used_count(p_code)` RPC from `razorpay-webhook`
- Restore: NONE
- **Root cause:** Server-side webhook should be firing this on subscription create. 3 promo codes exist; 0 uses recorded. Either (a) no one redeemed, or (b) webhook idempotency path skipping RPC, or (c) RPC failing silently. Verify via `client_errors` telemetry + webhook logs.

### `referral_redemptions` — FRAMEWORK_GAP (paired with referral_codes)
- Hive prefix: NONE
- Writer: `redeem-referral` Edge Function via `redeem_referral_atomic` RPC
- Restore: NONE
- **Root cause:** Audit table populated by RPC; 0 rows because no one has redeemed AND `referral_codes` is 0 anyway. Cascade dependency.

## Secondary findings

### F5-S1: `applied_migrations.json` parity gap — CONFIRMED_BUG
- `backups/applied_migrations.json` has 71 migration versions
- Disk has 74 files (`supabase/migrations/`)
- **Migration 024 missing from JSON**; all others present
- Pair-update rule from `feedback_migration_apply_record_pair.md` violated at some point

### F5-S2: Fan-out parity — PASS (with above gaps)
Every Hive prefix in `workoutBox` / `nutritionBox` / `healthBox` has a corresponding `_syncXxx` method. The gap is in the trigger-site wiring, not the projection.

### F5-S3: Restore-completeness parity — Mostly PASS
Most cloud tables in CLAUDE.md §7 have `_restoreXxx` methods. Notable gaps:
- `referral_codes` — no restore
- `referral_redemptions` — no restore
- `promo_code_uses` — no restore (RPC-driven, restore N/A)
- `account_deletion_log` — no restore (audit-only, restore N/A)
- `daily_quotes` — no restore (deferred)
- `video_renders` — no restore (deferred)

## Recommended fix scope

1. **CONFIRMED_BUG ×5** (saved meals, custom foods, sleep, measurements, diet plan): wire `unawaited(syncXxx())` at each mutation site. ~2-3 LoC each.
2. **FRAMEWORK_GAP ×2** (referral_codes, referral_redemptions): add `_restoreReferralCodes` + `_restoreReferralRedemptions` in `sync_restore_completeness.dart`. Critical for cross-device — users will lose their generated codes.
3. **VERIFY** (promo_code_uses): check webhook telemetry; could be empty because no actual usage, not a bug.
4. **DATA PARITY**: regenerate `backups/applied_migrations.json` from live `supabase_migrations.schema_migrations`.
