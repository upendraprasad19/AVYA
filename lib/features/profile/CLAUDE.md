---
scope: profile
parent: ../../../CLAUDE.md
created: 2026-05-18
updated: 2026-05-21
status: active
---

# Profile — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/features/profile/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

## What lives here

`lib/features/profile/` owns the 👤 Profile tab and the suite of settings
screens hanging off it. Screens:

- `profile_screen.dart` — top-of-tab rank pill + bio stats + goal card + targets + ladder + edit / progress photos / reports / submissions / subscription / referrals / settings / logout.
- `edit_profile_screen.dart` — full editor for the user_profile fields (name, DOB, sex, goal, weight, height, body fat, activity level, lifestyle activity, diet preference, injuries, equipment access, days/week, fitness experience, pace preference, target weight).
- `settings_screen.dart` — notifications toggle, health-sync toggle, theme (locked dark), DPDP delete account, sign out, build info.
- `reports_screen.dart` — Weekly Report (PRO) — sparklines + protein/calorie/workout trend.
- `progress_photos_screen.dart` + `progress_comparison_screen.dart` — PRO daily-cap'd photo log + comparison sheet.
- `rank_ladder_screen.dart` — Indian Navy 11-rung lifetime ladder + promotion celebrations.
- `notifications_screen.dart` + `notification_settings_screen.dart` — inbox via `NotificationInboxService`.
- `invite_friends_sheet.dart` + `apply_referral_sheet.dart` — 7-day PRO referral promo (APK Test #2).
- `delete_account_screen.dart` — DPDP §17 hard-delete.
- `submissions_screen.dart` — user-contributed exercise / food submissions.
- `promotion_celebration_screen.dart` — rank-up modal.

Service layer: `lib/features/profile/services/profile_write_service.dart` and
`notification_inbox_service.dart`. Models in `models/`, providers in `providers/`.

## Single-source-of-truth contracts

| Concept | Writer | Reader |
|---|---|---|
| user_profile fields (goal, weight, height, body fat, etc.) | `profile_write_service.dart` updates `userBox['profile']` map then fires `unawaited(syncService.syncOnboarding())` | `userProfileProvider` reads `userBox['profile']`. Every screen reads via the provider, never raw Hive. |
| `weight_logs` | `health_write_service.dart` (via Profile → Edit Weight or chat) | `weeklyReportDataProvider` (forward-fill), home `WeightSparkline`. |
| `rank_promotion_log` | server-side `evaluate-rank-promotions` cron → writes `rank_promotion_log` rows | `rank_ladder_screen.dart` + `promotion_celebration_screen.dart`. |
| Progress photos (PRO) | `ProgressPhotoRepository.capture` enforces daily cap BEFORE pick (2/day free, 5/day PRO) + uploads to Supabase Storage `progress_photos` bucket. Image quality tier-gated: 2048/85 free, 3000/95 PRO. | `progress_photos_screen.dart`, `progress_comparison_screen.dart`. |
| `referral_redemption` | `apply_referral_sheet` → server-side validate-referral edge function | `subscription_service.isPro()` (7-day PRO grant). |
| `submissions` | `submissionsRepository` (custom exercise + custom food submission queue) | `submissions_screen.dart`. |

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Progress-photo upload fails with PhotoQuotaException | Daily cap exceeded. Free: 2/day, PRO: 5/day. Enforced at `ProgressPhotoRepository.capture` by counting today's `progress_photos` rows for the user BEFORE pick. UI should catch `PhotoQuotaException`, surface the paywall for free users (`feature: 'progress_photos'`) or a "come back tomorrow" snackbar for PRO. Image quality differs by tier too: 2048/85% free, 3000/95% PRO. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Weekly Report sparkline dips to 0 between weigh-ins | By design only for calories/protein/workouts (zero-fill = genuinely no activity). Weight series is **forward-filled** from last known — if you see it dropping to zero on un-weighed days, `weeklyReportDataProvider` has regressed. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Edit Profile saves but home doesn't refresh | `ProfileWriteService` must invalidate the same provider set as the onboarding completion path: `userProfileProvider`, `homeProvider`, `dietPlanProvider` (when goal/weight changes), `nutritionTargetsProvider`. Missing any one = stale UI. | `user_full_name` SoT |
| Profile screen `usageWeeks` counter reads dead Hive key | Fixed 2026-05-20 (commit `00c36cc`). `usageWeeks` now reads `users.created_at` from Supabase, NOT the dead `configBox['signup_at']` key. Don't reintroduce a Hive-side counter — Supabase signup date is canonical. | `feedback_writer_reader_field_drift_recurring.md` |
| Delete account leaves orphan rows | `delete_account_screen` → `delete-account` Edge Function executes the DPDP §17 hard-delete + pseudonymization. Migration 049 set ON DELETE SET NULL on `user_custom_exercises`, `user_custom_foods`, `community_reviews.reviewer_id`, `food_corrections`, `promo_code_uses`. **Read consumers MUST tolerate `user_id = NULL`** ("deleted user" preserved for community signal). | `supabase/migrations/CLAUDE.md` |

## Tests pinning the rules here

- `test/contracts/full_name_backfill_test.dart`
- `test/contracts/delete_account_safety_contract_test.dart`
- `test/contracts/usage_weeks_signup_date_test.dart` (commit `00c36cc`)
- `test/contracts/progress_photo_quota_test.dart`

## See also

- `lib/features/auth/CLAUDE.md` — sign-out + cross-account guard.
- `lib/features/onboarding/CLAUDE.md` — initial profile capture.
- `docs/architecture/subscription.md` — PRO gate pattern.
- `docs/architecture/payment.md` — Razorpay + delete-account DPDP flow.
