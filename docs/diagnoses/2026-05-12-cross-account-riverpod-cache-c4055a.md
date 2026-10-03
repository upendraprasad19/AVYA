---
bug_id: c4055a
date: 2026-05-12
batch: APK Test #15.3
status: in_progress
symptom: |
  After signOut+signUp on the same app session, every user-scoped
  Riverpod provider continues to serve the previous user's cached state
  even though Hive boxes have correctly switched to the new user's
  namespaced files via HiveUserSession.openForUser (Test #15.1 / Bug C).

  Founder reproduced 2026-05-12 morning: signed up as
  sumitt@gmail.com on a device previously logged in as
  upendraprasad19@gmail.com. Cloud user_profile for sumitt has
  height_cm=175, current_weight_kg=75, target_weight_kg=73,
  date_of_birth=2001-01-01. Edit Profile screen rendered Upendra's
  174 / 77.8 / 80.0 / 1988-06-30 — every field wrong, identity of
  the previous account.

  The leak surfaces wherever a Notifier/Provider's build() body reads
  user-scoped data (UserRepository / HiveService.<X>Box / MigratedKey /
  SubscriptionService / user-filtered Supabase tables) without
  subscribing to any auth-state source — so the cached state survives
  the auth transition.
concept: user_scoped_riverpod_providers
sot_registry_entry: user_scoped_hive_keys
writers:
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: UserProfileNotifier.build, line: 34 }
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: currentUserProvider, line: 34 }
  - { file: lib/features/auth/providers/auth_invalidation_provider.dart, method_or_widget: authUserIdTokenProvider, line: 30 }
readers:
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: _EditProfileScreenState (ref.read(userProfileProvider)), line: 105 }
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: _EditProfileScreenState._save read profile, line: 1373 }
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: _EditProfileScreenState._save updateProfile, line: 1420 }
hive_key_prefix: "userBox['profile']"
hive_key_formula: "single key 'profile' inside the per-user HiveUserSession-scoped userBox"
sync_methods:
  - SyncService.syncProfileNow
restore_methods:
  - SyncService._restoreUserProfile
cloud_table: user_profile
cloud_columns:
  - user_id
  - full_name
  - date_of_birth
  - gender
  - height_cm
  - current_weight_kg
  - target_weight_kg
  - body_fat_percent
  - primary_goal
  - activity_level
  - lifestyle_activity
  - fitness_experience
  - pace_preference
  - days_per_week
  - equipment_access
  - injuries
  - diet_preference
  - daily_calories
  - protein_grams
  - carb_grams
  - fat_grams
  - bmr
  - tdee
  - onboarding_completed_at
contract_test_path: test/contracts/auth_invalidation_contract_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
provider_invalidations:
  - authUserIdTokenProvider
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: |
  This fix ADDS a new layer of cross-account guard at the Riverpod
  cache layer. Existing layers protect adjacent surfaces but missed
  this one:
    • Test #15.1 / Bug C — HiveUserSession.openForUser switches Hive
      to per-user namespaced files on auth change (Hive-layer guard).
    • APK Test #1 batch 2026-04-24 — Android Auto Backup disabled +
      splash_screen profile-id check force-clears Hive on cold-start
      mismatch (cold-start guard).
    • Test #11.1 — UserConfigMigrator v2 moves 25 keys from shared
      configBox to per-user userBox (config-bleed guard).
  None of those touched Riverpod's in-memory provider cache.
  authUserIdTokenProvider watches authStateProvider (the Supabase
  auth stream) AND currentUserProvider; on every sign-in / sign-out
  / token refresh, the token's identity changes from <prev-uid> →
  <new-uid> (or → '<anon>' on sign-out). Every user-scoped provider
  watching the token rebuilds, re-reads the now-correctly-namespaced
  Hive, and produces fresh state for the new identity.
forbidden_patterns_checked:
  - { pattern: "Notifier.build() reading UserRepository without ref.watch(authUserIdTokenProvider)", absent: true }
  - { pattern: "ref.watch(authUserIdTokenProvider) missing from any provider listed in audit", absent: true }
proposed_fix: |
  Introduce a single new token provider
  `authUserIdTokenProvider` at
  `lib/features/auth/providers/auth_invalidation_provider.dart`.
  It watches `authStateProvider` (the Supabase auth state stream)
  AND `currentUserProvider`, exposing `user?.id ?? '<anon>'` as its
  value. Anonymous sessions resolve to `'<anon>'` so providers also
  re-emit on sign-out (token transitions from `<id>` → `<anon>`).

  Every user-scoped Notifier/Provider's `build()` body adds
  `ref.watch(authUserIdTokenProvider)` as its FIRST line. When the
  auth state changes, the token re-emits → all downstream providers
  rebuild against the now-correctly-namespaced Hive.

  Audit found 47 vulnerable + 9 partially-protected providers across
  14 files. All are fixed in this commit:

  | File | Notifier/Provider declarations modified |
  |------|------------------------------------------|
  | lib/features/profile/providers/profile_provider.dart | UserProfileNotifier, UserStatsNotifier, SubscriptionInfoNotifier, BiometricNotifier, ProgressPhotosNotifier, UsageWeeksNotifier, FirstReportViewedNotifier |
  | lib/features/profile/providers/profile_completeness_provider.dart | profileCompletenessProvider |
  | lib/features/profile/providers/weekly_report_data_provider.dart | WeeklyReportDataNotifier |
  | lib/features/profile/providers/notifications_inbox_provider.dart | NotificationInboxNotifier |
  | lib/features/profile/providers/promotion_history_provider.dart | promotionHistoryProvider |
  | lib/features/profile/providers/referral_eligibility_provider.dart | referralEligibilityProvider |
  | lib/features/home/providers/home_provider.dart | CalendarWeekNotifier, UserGreetingNotifier, UserFirstNameNotifier, UserInitialNotifier, StreakNotifier, StreakFreezeNotifier, streakFreezeMaxProvider, StreakWarningEligibilityNotifier, TodayWorkoutNotifier, NutritionSummaryNotifier, WeightHistoryNotifier, AiInsightNotifier, RecentFoodLogsNotifier, DailyQuoteNotifier, TodayStepsNotifier, TodayWeightLoggedNotifier, AllExercisePRsNotifier |
  | lib/features/home/widgets/insight_card.dart | topInsightProvider |
  | lib/features/train/providers/train_provider.dart | CurrentPlanNotifier, SelectedWeekNotifier, workoutStatsProvider, ActiveWorkoutNotifier, TemplatesNotifier, graduationStatsProvider |
  | lib/features/train/providers/preview_plan_provider.dart | previewPlanProvider |
  | lib/features/train/providers/video_render_provider.dart | VideoRenderNotifier |
  | lib/features/nutrition/providers/diet_plan_provider.dart | DietPlanNotifier |
  | lib/features/nutrition/providers/nutrition_provider.dart | DailyNutritionNotifier, MacroTargetsNotifier, WaterIntakeNotifier, WaterUnitNotifier, UrineColorNotifier, SavedMealsNotifier, aiTextLogRemainingProvider, scanMealRemainingProvider, cartAuditorRemainingProvider, WeeklyNutritionNotifier, waterTargetProvider |
  | lib/features/ai_coach/providers/ai_coach_provider.dart | ChatHistoryNotifier, MessageLimitNotifier, TrialInfoNotifier, TelegramConnectionNotifier, ChannelNotifier, PredictionNotifier, coachInsightProvider, PendingLogActionsNotifier, WorkoutDraftNotifier |
  | lib/features/ai_coach/providers/pending_tool_intents_provider.dart | PendingToolIntentsNotifier |
  | lib/features/onboarding/providers/onboarding_provider.dart | OnboardingNotifier |

  Exempt (do not touch):
    • lib/features/auth/providers/auth_provider.dart — auth source
      itself; can't self-watch.
    • lib/features/auth/providers/auth_invalidation_provider.dart —
      the new token provider; can't self-watch.
    • lib/features/auth/providers/referral_code_stash_provider.dart —
      intentionally shared pre-auth crossing surface per CLAUDE.md
      §15. Excluded from contract test via its exemption set.

  A SOURCE-GREP contract test at
  `test/contracts/auth_invalidation_contract_test.dart` walks
  `lib/features/` recursively and asserts every file that
    1. declares a Provider/Notifier (Provider<, NotifierProvider<,
       FutureProvider.family<, StreamProvider<, extends Notifier< /
       AsyncNotifier< / StateNotifier<), AND
    2. reads user-scoped data (UserRepository / WorkoutRepository /
       NutritionRepository / AiCoachRepository /
       HiveService.instance / aliased <X>Box / MigratedKey /
       SubscriptionService / WaterTargetService /
       NotificationInboxService / Supabase user-filtered tables)
  also calls `ref.watch(authUserIdTokenProvider)`.

  Adding a new vulnerable provider without the watch causes the test
  to fail in CI, preventing Test #N+1 from re-surfacing the class.
regression_test_planned:
  - test/contracts/auth_invalidation_contract_test.dart
  - test/contracts/user_scoped_provider_rebuilds_on_auth_change_test.dart
---

# Bug 5 — Cross-account Riverpod state cache leak (c4055a)

## Symptom

Founder reproduced on 2026-05-12 morning:

1. App previously signed in as `upendraprasad19@gmail.com`.
2. Founder signed out, then signed up as `sumitt@gmail.com` (new
   account, fresh email).
3. Cloud `user_profile` row for the new user is correct:
   `height_cm=175`, `current_weight_kg=75`, `target_weight_kg=73`,
   `date_of_birth=2001-01-01`.
4. Edit Profile screen renders `174` / `77.8` / `80.0` /
   `1988-06-30` — every field is Upendra's, not Sumit's.

## Root cause

`UserProfileNotifier.build()` at
`lib/features/profile/providers/profile_provider.dart:33-35`
(pre-fix shape):

```dart
class UserProfileNotifier extends Notifier<Map<String, dynamic>> {
  @override
  Map<String, dynamic> build() {
    return UserRepository.instance.getProfile() ?? {};
  }
}
```

The build body reads user-scoped data once per provider lifetime
(first `ref.watch` from any consumer) and Riverpod caches the
returned `Map<String, dynamic>` until the provider is explicitly
invalidated. No `ref.watch(...)` on any auth-state source means the
notifier has no reason to rebuild when the user changes.

Test #15.1 / Bug C correctly switched the underlying Hive files via
`HiveUserSession.openForUser(B.id)`, but the in-memory Riverpod
cache survives that switch — readers continue to receive A's cached
profile until the app is fully torn down. 55 other Notifier /
Provider build bodies have the same anti-pattern across the
codebase (audited 2026-05-12).

## Fix

### 1. New token provider — `authUserIdTokenProvider`

`lib/features/auth/providers/auth_invalidation_provider.dart`:

```dart
final authUserIdTokenProvider = Provider<String>((ref) {
  ref.watch(authStateProvider);
  final user = ref.watch(currentUserProvider);
  return user?.id ?? '<anon>';
});
```

Watching `authStateProvider` (the Supabase auth stream) is what
gives this provider any signal at all — `currentUserProvider` reads
synchronously from `SupabaseService.instance.currentUser` and does
not itself subscribe to the auth stream.

### 2. Every user-scoped provider watches the token

For Notifier-style providers:

```dart
@override
SomeData build() {
  ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
  // ... existing logic
}
```

For `Provider<X>((ref) { ... })` builders, the same watch as the
first line of the builder body.

### 3. Source-grep contract test

`test/contracts/auth_invalidation_contract_test.dart` is the
forever pin. Scans `lib/features/` for any file that declares a
provider AND reads user-scoped data AND does not watch the token.
Three legitimate exemptions are listed in the test (auth_provider,
auth_invalidation_provider, referral_code_stash_provider).

## Why this matters

Without the watch, the leak surfaces wherever a user-scoped
provider gates UI behaviour:

* Edit Profile screen shows previous user's fields (founder's
  reproduction case).
* Profile completeness card flags fields as missing using previous
  user's profile.
* Streak chip on home shows previous user's streak.
* AI coach chat history surfaces previous user's messages.
* Today's workout card may resolve to previous user's schedule
  entries even though those entries no longer exist in the new
  user's Hive box.
* Subscription pill may stay GO PRO when the new user is genuinely
  PRO (and vice versa) until the next manual app-relaunch.

The class fix prevents support escalation paths of the form
"my account is showing data from someone else."

## Related

* Test #15.1 / Bug C (c7d4f6): HiveUserSession.openForUser + mutex.
  Closes the Hive-layer leak. This bug closes the Riverpod-layer
  leak that sits above it.
* APK Test #1 batch 2026-04-24: Android Auto Backup disabled +
  splash startup profile-id check. Closes the cold-start cross-
  account leak. Doesn't help with in-session signOut+signUp.
* Test #11.1: UserConfigMigrator v2 moves 25 keys from shared
  configBox to per-user userBox. Closes the config-bleed surface.
* `feedback_source_of_truth_audit.md`: every state-mismatch bug
  fix must name writer + reader by file:line. The writer here is
  the Notifier.build body (cached state); the reader is any UI
  surface that ref.watches the leaked provider.
