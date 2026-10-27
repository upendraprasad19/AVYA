# Cross-account leak hotfix — Test #10.1

**Branch:** `fix/cross-account-leak-hotfix` off `main` (post Test #11 merge `c57fdaa` + docs `ae9f891`)
**Date:** 2026-05-04
**Severity:** **CRITICAL** — privacy (one user sees another user's profile / AI prediction / pattern insights) + revenue (PRO entitlement inheritable across signOut→signUp)
**Estimated scope:** 7 fix items · ~6–8h · 1 batch APK (10.1)
**Migrations:** 0 (Postgres) · 1 one-shot local key migration (configBox → userBox)
**Edge function deploys:** 0
**Audit reference:** see in-conversation audit on 2026-05-04 (cloud confirmed sumit's `user_profile` is empty NULLs but Edit Profile rendered upendra's data → leak is purely on-device).

**Test #11 reconciliation (2026-05-04):**
- C1 (FoodLogNotifier `items[]` via WriteService) — Test #11 already shipped; my deferred AI food log bug is closed.
- A (subscription fold-in into restore) — Test #11 folded subscription INTO restore flow but storage in configBox unchanged → still a leak vector.
- M3 (counter resets in IST) — reset timing fixed, storage unchanged → still a leak vector.
- 4 keys ADDED to my migration list since the original audit: `_swapWeekStartKey`, `_swapsThisWeekKey`, `_travelStartKey`, `_travelEndKey` (workout schedule per-user state).
- `clearAllData()` untouched, partial-failure foundation bug remains.

**One-shot migration flag storage decision:**
Original plan called for `SharedPreferences`. Audit found `shared_preferences` is NOT a dependency. Adding it for a hotfix = scope creep. Switched to a **new `migrationBox`** shared Hive box that's opened in `HiveService.init()` and **never cleared** by `clearAllData()`. Same anti-leak property (survives sign-out + cross-account guard) without a new package dependency.

## Reproducer (locked)

1. Sign in as User A (upendra). Complete onboarding. Data populates Hive.
2. Sign out.
3. Sign UP with new email User B (sumit).
4. Expected: User B lands on `/onboarding/mission-brief` with empty Edit Profile.
5. Actual: User B lands on `/home`. Edit Profile shows User A's full_name / DOB / height / weight / target. PRO state, AI prediction, AI pattern insights, saved diet plan, rate-limit counters all leaked too.

## Root cause (locked)

| Layer | Status | Why it didn't catch the bug |
|---|---|---|
| L1 Auto Backup excl. (`data_extraction_rules.xml`) | ✅ working | Reinstall vector — not this scenario |
| L2 Splash startup id mismatch check | ✅ working | Cold-start only — in-session signup-after-signout never re-enters splash |
| L3 `_ensureLocalUser` cross-account guard | ✅ logic correct | Calls `clearAllData()` and trusts it; no verify-after-clear |
| L4 HiveUserSession namespaced boxes | ✅ working | Storage isolation correct; leak vectors are NOT user-scoped boxes |
| L5 GuardedBox runtime ownership | ✅ working | Throws on session/owner mismatch — but the throw KILLS the rest of `clearAllData()` chain |
| L6 RestoringScreen post-auth gate | ✅ working | Never reached when `_authRedirect` reads `configBox['onboarding_completed']` = leaked `true` |
| L7 signOut sequence | ❌ partially broken | One throwing `.clear()` aborts the sequence; remaining boxes (incl. `configBox`) stay populated |

**Net:** `configBox` is shared (NOT namespaced) and holds 18+ user-specific keys. When `clearAllData()` partial-fails, those keys leak into the next user's session. Even when the cross-account guard fires (L3), it can't recover because the storage layer keeps re-leaking.

## Scope summary

| # | Theme | Key change |
|---|---|---|
| 1 | Make `clearAllData()` non-failable | Per-box try/catch; return `ClearResult` so callers can detect partial failure |
| 2 | Move 18 user-scoped keys to userBox | One-shot SharedPreferences-gated copy on `_ensureLocalUser`; update all readers/writers |
| 3 | Verify-after-clear in cross-account guard | After `clearAllData()`, re-read `userBox['profile']`. If still populated, force-signOut + crash to `/sign-in` |
| 4 | Gate `_migrateLegacySharedBoxes` to run-once-ever | Move flag from configBox (cleared) to SharedPreferences (survives) |
| 5 | Router: read onboarding flag from userBox | `_authRedirect` reads `userBox['profile']['onboarding_completed_at']` instead of `configBox['onboarding_completed']` |
| 6 | Subscription / usage counters: same treatment | Move PRO state + rate-limit counters into userBox |
| 7 | Contract tests | `cross_account_signout_signup_test.dart` + `clear_all_data_partial_failure_test.dart` + `config_to_user_migration_test.dart` |

## The 18 keys to migrate (audited list)

### Critical (privacy / revenue)
- `onboarding_completed`
- `_isProKey`, `_expiresAtKey`, `_planKey`, `_lastVerifiedKey`, `localActivationAt` (subscription state)
- `prediction_text`, `prediction_date`, `prediction_stale`, `prediction_generated_at` (AI prediction)
- `pattern_insights` (AI behavior patterns)

### High (UX / billing shape)
- `ai_text_log_count_today`, `scan_meal_count_today`, `cart_auditor_count_today`, `last_daily_reset` (rate limits)
- `saved_diet_plan`
- `plan_start_date`, `plan_end_date`, `preferred_training_days` (workout plan dates)

### Medium (wrong defaults)
- `ai_trial_start`, `last_ai_greeting_date`, `telegram_connected`, `coach_channel`
- `pending_referral_code`, `pending_onboarding_sync`
- `swap_week_start`, `progress_photo_count`, `first_report_viewed`
- profile-nudge `dismissedAt`
- `logout_in_progress`

### Stays in configBox (genuinely device-level)
- `units_metric`, `health_sync_enabled`, `first_launch_date`, `last_compact_at`
- `exlog_key_migration_v6`, `nlog_key_migration_v6`, `sync_reliability_v1` (one-shot migration flags)
- `last_known_today_date` (day rollover sentinel)
- `exercise_library_seeded_v1`, `food_library_seeded_v2`, `seeded` (seed-on-install gates)

---

## Per-fix detail

### Fix 1 · `clearAllData()` non-failable

`lib/shared/repositories/user_repository.dart` (lines 200–211):

```dart
class ClearResult {
  final Map<String, Object> failures; // box name → exception
  ClearResult(this.failures);
  bool get hasFailures => failures.isNotEmpty;
  bool failedFor(String box) => failures.containsKey(box);
}

Future<ClearResult> clearAllData() async {
  final failures = <String, Object>{};

  Future<void> tryClear(String label, Future<void> Function() op) async {
    try { await op(); }
    catch (e) {
      failures[label] = e;
      debugPrint('[clearAllData] $label failed: $e');
    }
  }

  await tryClear('userBox',          () async => _hive.userBox.clear());
  await tryClear('workoutBox',       () async => _hive.workoutBox.clear());
  await tryClear('nutritionBox',     () async => _hive.nutritionBox.clear());
  await tryClear('healthBox',        () async => _hive.healthBox.clear());
  await tryClear('coachBox',         () async => _hive.coachBox.clear());
  await tryClear('customBox',        () async => _hive.customBox.clear());
  await tryClear('notificationsBox', () async => _hive.notificationsBox.clear());
  await tryClear('syncBox',          () async => _hive.syncBox.clear());
  // configBox last — but EVERY box gets attempted regardless of earlier failures
  await tryClear('configBox',        () async => _hive.configBox.clear());

  return ClearResult(failures);
}
```

**Callers updated:**
- `auth_provider.signOut()` lines 273–290 — now logs the result; no behavior change for the single-user path
- `auth_provider._ensureLocalUser` line 346 — wired into Fix 3 (verify-after-clear)
- `splash_screen._runDeferredInit` line 124 — same as above

### Fix 2 · Move 18 user-scoped keys to userBox + one-shot copy migration

**Phase A — write the migration helper.**

NEW file: `lib/core/services/user_config_migrator.dart`

```dart
/// One-shot migration: copies user-specific keys from the SHARED `configBox`
/// into the CURRENT user's userBox, then deletes them from configBox.
///
/// Gated by a SharedPreferences flag (NOT a Hive flag — must survive
/// `clearAllData()`). Runs at most once per device lifetime, only when a
/// user is signed in.
class UserConfigMigrator {
  static const String _flagKey = 'user_config_migration_v1_done';

  static const List<String> _userKeys = [
    'onboarding_completed',
    // subscription
    'isPro', 'expiresAt', 'plan', 'lastVerified', 'localActivationAt',
    // prediction
    'prediction_text', 'prediction_date', 'prediction_stale', 'prediction_generated_at',
    // pattern + ai
    'pattern_insights', 'last_ai_greeting_date', 'ai_trial_start',
    'telegram_connected', 'coach_channel',
    // rate limits
    'ai_text_log_count_today', 'scan_meal_count_today', 'cart_auditor_count_today',
    'last_daily_reset',
    // plan
    'plan_start_date', 'plan_end_date', 'preferred_training_days',
    'swap_week_start',
    // diet plan
    'saved_diet_plan',
    // misc per-user
    'pending_referral_code', 'pending_onboarding_sync',
    'progress_photo_count', 'first_report_viewed',
    'profile_nudge_dismissed_at',
    'logout_in_progress',
  ];

  /// Runs after HiveUserSession.openForUser. Idempotent.
  static Future<void> runIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_flagKey) == true) return;

    final cfg = HiveService.instance.configBox;
    final userBox = HiveService.instance.userBox; // GuardedBox — session must be open
    int copied = 0;

    for (final key in _userKeys) {
      if (!cfg.containsKey(key)) continue;
      final value = cfg.get(key);
      try {
        await userBox.put(key, value);
        await cfg.delete(key);
        copied++;
      } catch (e) {
        debugPrint('[UserConfigMigrator] $key copy failed: $e');
      }
    }

    await prefs.setBool(_flagKey, true);
    debugPrint('[UserConfigMigrator] copied $copied keys configBox → userBox');
  }
}
```

**Phase B — update every reader/writer.** Each callsite changes from `configBox.get/put('foo')` → `userBox.get/put('foo')`.

Files affected:
- `lib/shared/repositories/user_repository.dart` (onboarding_completed reader/writer at lines 83, 89; saved_diet_plan at 184/189)
- `lib/features/auth/providers/auth_provider.dart` (onboarding_completed writes at lines 432, 534, 557; ai_trial_start at 469)
- `lib/core/router/app_router.dart` (line 535–540 — reads from userBox; new fallback to /restoring if box not yet open)
- `lib/core/services/subscription_service.dart` (lines 86, 105, 185, 190, 195, 240, 244, 265, 308, 320, 325, 363–367)
- `lib/core/services/usage_counter_service.dart` (lines 67, 78, 79, 87, 96, 112, 114–117)
- `lib/core/services/prediction_service.dart` (lines 58–62, 75, 80)
- `lib/core/services/workout_schedule_service.dart` (lines 210, 211, 214, 339, 370, 373–378, 561, 580, 667, 711, 723, 1304)
- `lib/core/services/sync_service.dart` (lines 564, 572, 633, 2839, 2840, 2928, 2931, 3704–3718)
- `lib/features/ai_coach/repositories/ai_coach_repository.dart` (lines 1172, 1178)
- `lib/features/ai_coach/providers/ai_coach_provider.dart` (lines 296, 301, 699, 717, 890, 899, 906, 908, 911, 923)
- `lib/features/ai_coach/services/pattern_detector.dart` (line 80)
- `lib/features/profile/providers/profile_provider.dart` (lines 474, 489, 512)
- `lib/features/onboarding/providers/onboarding_provider.dart` (lines 473, 476, 490, 651–653)
- `lib/features/home/widgets/profile_nudge_card.dart` (line 25 + writer)
- `lib/features/auth/screens/sign_in_screen.dart` (lines 137, 145)
- `lib/main.dart` (line 65)

**Phase C — wire the migration in.** `lib/features/auth/providers/auth_provider.dart` `_ensureLocalUser`, after the cross-account guard but before the cloud profile pull:

```dart
await HiveUserSession.openForUser(user.id);
// Cross-account guard …
if (needsClear) { … }

// Test #10.1 — one-shot config → userBox migration. Runs once per device.
await UserConfigMigrator.runIfNeeded();

// Continue with cloud profile pull, etc.
```

### Fix 3 · Verify-after-clear

`lib/features/auth/providers/auth_provider.dart` `_ensureLocalUser` line 344–347:

```dart
if (needsClear) {
  debugPrint('[auth/_ensureLocalUser] Cross-account guard fired: $clearReason');
  final result = await UserRepository.instance.clearAllData();

  // Verify clear actually succeeded for the keys that matter.
  final reCheckProfile = userBox.get('profile');
  final reCheckOnboarding = userBox.get('onboarding_completed');

  if (reCheckProfile != null || reCheckOnboarding == true || result.hasFailures) {
    debugPrint('[auth/_ensureLocalUser] CRITICAL: clear partial-failed. '
               'profile=$reCheckProfile, onboarding=$reCheckOnboarding, failures=${result.failures}');
    // Force-sign-out so user lands on /sign-in instead of poisoned /home
    await _supabase.client.auth.signOut();
    state = state.copyWith(
      status: AuthStatus.error,
      errorMessage: 'Couldn\'t clean up the previous session. Please sign in again.',
    );
    throw StateError('Cross-account clear partial-failed');
  }
}
```

The thrown `StateError` propagates up through `signUpWithEmail` / `signInWithEmail` which already have a `try { await _ensureLocalUser(...) } catch (_) {}` — that catch needs updating to a `rethrow` for `StateError` so the auth state correctly reflects the failure.

### Fix 4 · Gate `_migrateLegacySharedBoxes` via SharedPreferences

`lib/core/services/hive_user_session.dart` line 103–141:

```dart
static Future<void> _migrateLegacySharedBoxes(String userId) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('hive_legacy_migration_v1_done') == true) return;

  // … existing migration body unchanged …

  await prefs.setBool('hive_legacy_migration_v1_done', true);
  debugPrint('[HiveUserSession] legacy migration complete (one-shot)');
}
```

**Why SharedPreferences not configBox:** `clearAllData()` clears configBox. SharedPreferences survives. The migration must run AT MOST ONCE PER DEVICE LIFETIME, never per-user.

### Fix 5 · Router reads onboarding flag from userBox

`lib/core/router/app_router.dart` line 488–548 `_authRedirect`:

```dart
// Signed in but not onboarded -> go to onboarding.
bool isOnboarded = false;
try {
  final profile = HiveService.instance.userBox.get('profile');
  if (profile is Map) {
    isOnboarded = profile['onboarding_completed_at'] != null
                || profile['onboarding_completed'] == true;  // legacy fallback
  }
} catch (_) {
  // userBox not yet open (HiveUserSession race). Bounce to /restoring,
  // which will block-then-decide.
  return state.matchedLocation == '/restoring' ? null : '/restoring';
}

if (!isOnboarded) {
  return isOnOnboarding ? null : '/onboarding';
}
```

### Fix 6 · Subscription + usage counters in userBox

Same mechanism as Fix 2 but the SubscriptionService and UsageCounterService get their internal `_hive.configBox` references swapped to `_hive.userBox`. No public API change. SubscriptionService.refreshFromSupabase() already handles "no session" correctly — it short-circuits when `currentUser` is null. So userBox unavailability isn't a new risk.

### Fix 7 · Contract tests

NEW: `test/safety/cross_account_signout_signup_test.dart`
- Mock Supabase auth that lets us fake user A sign-in, sign-out, user B sign-up
- Hive starts with user A's profile + workout + onboarding flag
- After signOut → signUp(B): assert userBox has no `profile`, no `onboarding_completed`, no PRO state, no rate-limit counts

NEW: `test/safety/clear_all_data_partial_failure_test.dart`
- Inject a GuardedBox that throws on `.clear()` for `userBox`
- Call `UserRepository.clearAllData()`
- Assert `configBox` and all OTHER boxes still got cleared
- Assert `ClearResult.hasFailures == true` and `failures` contains 'userBox'

NEW: `test/safety/config_to_user_migration_test.dart`
- Pre-populate configBox with the 18 user-specific keys
- Open HiveUserSession for a fake user
- Run `UserConfigMigrator.runIfNeeded()`
- Assert all 18 keys present in userBox, removed from configBox
- Run again — assert no-op (idempotent via SharedPreferences flag)

---

## Test plan

```bash
# New tests
flutter test test/safety/cross_account_signout_signup_test.dart
flutter test test/safety/clear_all_data_partial_failure_test.dart
flutter test test/safety/config_to_user_migration_test.dart

# Full suite — must pass before APK build
flutter test
```

Expected: 919 → ~925 pass after this batch (3 new tests + maybe 2 updated existing tests if any pin configBox key positions).

## Manual QA checklist (post-APK install)

- [ ] Sign in as User A, complete onboarding, log a workout + meal, become PRO via promo code
- [ ] Sign out
- [ ] Sign UP with brand new email User B
- [ ] Verify: lands on `/onboarding/mission-brief` (NOT home)
- [ ] Verify: Edit Profile fields are empty (no User A name/DOB/height/weight)
- [ ] Verify: PRO badge NOT present (back to free tier)
- [ ] Verify: AI coach has no greeting, no prediction, no pattern insights from User A
- [ ] Verify: Rate-limit counters reset (can do 10 AI text analyses again)
- [ ] Verify: No saved diet plan visible
- [ ] Verify: Streak counter is 0
- [ ] Sign back in as User A → verify all data restored from cloud (clean state cleared but cloud restore brings everything back)

---

## Rollout

1. Branch `fix/cross-account-leak-hotfix` off `main`.
2. Implement Fix 1 (clearAllData refactor) FIRST — it's the foundation; subsequent fixes depend on partial-failure detection.
3. Implement Fix 4 (legacy migration gate) — small, prevents the leak vector while the rest is in flight.
4. Implement Fix 2 phases A → B → C (migration helper, all callsites, wire-in).
5. Implement Fix 5 (router) and Fix 6 (subscription/counters) as part of Fix 2 since they're callsite changes.
6. Implement Fix 3 (verify-after-clear) — depends on Fix 1's `ClearResult`.
7. Add Fix 7 contract tests as each fix lands.
8. Run full test suite; resolve any non-pre-existing failures.
9. Commit on branch, merge `--no-ff` to main with batch commit message.
10. `/build-apk` (skill verifies main + clean tree, builds APK +10.1).
11. Run manual QA checklist.
12. Write retrospective `project_cross_account_leak_hotfix.md` covering:
    - All 18 keys migrated
    - SharedPreferences-vs-Hive separation rule for one-shot migration flags
    - `ClearResult` pattern for any future critical clears
    - Why we picked Option C over A/B

---

## Out of scope (explicitly deferred)

- AI food log items[] sync gap (Test #11 — the `nlog_*` legacy paths bug audited earlier today)
- Any user-facing UX from the Test #10 install round (still in observation gathering)
- Restructuring `configBox` into a typed `UserConfigService` — surgical edits this round, refactor later

---

## Risk register

| Risk | Mitigation |
|---|---|
| Migration runs while box not yet open | Migration is invoked from `_ensureLocalUser` AFTER `HiveUserSession.openForUser`; userBox is guaranteed available |
| User signed out while migration mid-flight | Each `userBox.put()` wrapped in try/catch (per-key); failures logged, flag NOT set if any key fails |
| `SharedPreferences` not initialized | Already initialized via `flutter_dotenv` setup in main.dart; await is safe |
| Router race during cold start | Try/catch on userBox read in `_authRedirect`; bounce to `/restoring` which is the proper gate anyway |
| Subscription state lost during migration | Pre/post snapshot test in `config_to_user_migration_test.dart`; verify-after-migration check in `_ensureLocalUser` |
| ~17 file edits introduce regressions | Each fix is small, independently testable; full suite gates the merge |
