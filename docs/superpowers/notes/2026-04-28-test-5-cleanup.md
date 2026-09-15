# APK Test #5 — manual test-prep cleanup

**Run before installing the APK Test #5 build for verification.**

References: spec `docs/superpowers/specs/2026-04-28-apk-test-5-batch-design.md` §9.

## Step 1 — Wipe Supabase test accounts

Run in the Supabase SQL editor (project `dedsavbjuwgarrhphgnl`,
account `myfitnessjourney1988@gmail.com`):

```sql
DELETE FROM auth.users
WHERE email IN ('upendra.prasad@thinkingcode.com', 'avyaaanshfit@gmail.com');
```

Migration 039's `ON DELETE CASCADE` chain cleans:
- `public.users` (FK to auth.users)
- `user_profile`, `user_preferences`, `user_progress` (FK to public.users)
- `ai_coach_interactions`, `coach_memory`, `memory_embeddings`
- `workout_logs`, `workout_log_exercises`, `workout_log_sets`
- `nutrition_logs`, `nutrition_log_items`, `water_logs`
- `weight_logs`, `body_measurements`, `daily_steps`, `sleep_logs`
- `streaks`, `streak_freezes` (if present)
- `progress_photos`, `subscriptions`, `referral_codes`,
  `referral_redemptions`, `promo_code_uses`, `food_corrections`,
  `community_reviews`, `client_errors`, `user_daily_snapshots`,
  `coach_memory`, `rank_promotions`
- `user_custom_exercises`, `user_custom_foods`,
  `scheduled_workouts`, `workout_templates`, `template_exercises`
- `telegram_connections`

Verify cleanup:

```sql
SELECT email, deleted_at IS NOT NULL AS deleted
FROM auth.users
WHERE email IN ('upendra.prasad@thinkingcode.com', 'avyaaanshfit@gmail.com');
-- Expected: 0 rows (rows physically removed, not soft-deleted)
```

## Step 2 — Uninstall + reinstall on device

On the test Android device:

1. Settings → Apps → AVYA → Uninstall.
2. Confirm app data wiped.
3. Install `app-prod-release.apk` (versionCode +4) via `adb install` or
   manual sideload.
4. Open the app — should land on Welcome screen with no auto-restore.

This step matters because:
- Hive box files under `app_flutter/` are removed by uninstall.
- Auto Backup exclusion (verified in Task A-4) prevents Google Drive
  from re-restoring Hive on reinstall.
- Combined: device starts with truly empty local storage.

## Step 3 — Re-onboard both accounts

For each of the two test accounts:

1. Sign up fresh (or sign in if account auto-restored — see Step 1
   verification).
2. Complete the full onboarding flow (Mission Brief → Identity → Goal
   → Stats → Details → Plan → REPORT FOR DUTY).
3. Verify `user_profile.onboarding_completed_at IS NOT NULL` after
   completion:

```sql
SELECT user_id, primary_goal, fitness_experience, onboarding_completed_at
FROM user_profile
WHERE user_id IN (
  SELECT id FROM auth.users
  WHERE email IN ('upendra.prasad@thinkingcode.com', 'avyaaanshfit@gmail.com')
);
-- Expected: 2 rows, both with onboarding_completed_at populated
```

## Step 4 — Run §10 success criteria

Walk through C1, C2, C3 from spec §10. Document pass/fail in the
verification log on the branch `feat/apk-test-5-batch`.

C1: Sign in as Upendra → use coach (5 messages) → sign out →
    sign in as Avyaansh → AI coach screen shows EMPTY thread.
C2: Sign in as Avyaansh → Profile → no submissions → sign out →
    sign in as Upendra → see Upendra's submissions.
C3: Synthetic NULL `onboarding_completed_at` row in dev DB →
    sign in → routes to /home (self-heal stamps the flag).

For C3, manually inject the synthetic state in dev:

```sql
UPDATE user_profile
SET onboarding_completed_at = NULL
WHERE user_id = (
  SELECT id FROM auth.users WHERE email = 'upendra.prasad@thinkingcode.com'
);
```

Then sign in on device — should land on /home, AND a follow-up
SELECT should show `onboarding_completed_at` re-stamped:

```sql
SELECT onboarding_completed_at FROM user_profile WHERE user_id = ...;
-- Expected: non-null timestamp recent (within seconds of sign-in)
```

> **Branch note:** Plan A's Layer 4 reconciliation lands in
> `lib/features/auth/screens/splash_screen.dart::_navigateNext`
> on this branch (NOT in `RestoringScreen` as the original plan
> assumed) — `feat/apk-test-5-batch` was cut from `main` and pre-dates
> `feat/apk-test-4-batch`'s RestoringScreen introduction. C3 verifies
> the same self-heal contract regardless of the screen file location.
