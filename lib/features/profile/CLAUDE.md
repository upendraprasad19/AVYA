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
| `weight_logs` | `health_write_service.dart` (via Profile → Edit Weight or chat) | `weeklyReportDataProvider` (forward-fill), home `WeightTrendChart`. |
| `rank_promotion_log` | server-side `evaluate-rank-promotions` cron → writes `rank_promotion_log` rows | `rank_ladder_screen.dart` + `promotion_celebration_screen.dart`. |
| Progress photos (PRO) | `ProgressPhotoRepository.capture` enforces daily cap BEFORE pick (2/day free, 5/day PRO) + uploads to Supabase Storage `progress_photos` bucket. Image quality tier-gated: 2048/85 free, 3000/95 PRO. | `progress_photos_screen.dart`, `progress_comparison_screen.dart`. |
| `notification_preferences` | `NotificationPrefsRepository.write` → Hive `userBox`, then `_syncUserPreferences` → the `merge_notification_preferences` RPC (per-key additive). ⚠ NOT a plain upsert of the jsonb column — see `lib/core/services/CLAUDE.md`. | `NotificationPrefsRepository.read` locally; server-side the ten push jobs via `_shared/notification_prefs.ts`, which reads `user_preferences.notification_preferences` first and only falls back to the legacy `snapshot_json` key for users the column does not answer for (that fallback retires with APK +39 — **OI-141**). Restored by `_restoreUserPreferences` → `adoptFromCloud`, per-key LOCAL-wins. OI-98 / `e4a1b7`. |
| `equipment_access` / `equipment_exclusions` / `equipment_owned` | `edit_profile_screen._save` writes all three into `userBox['profile']`; `sync_profile.dart:196-205` mirrors them to `user_profile` as CONDITIONAL entries, so a profile that never answered cannot overwrite a cloud value with `[]`. Migration 104 added exclusions, **124** added owned. | ⑦ **OI-89.** Nothing reads these three raw — they are combined into ONE derived set, `effective = EquipmentVocab.tierItems[tier] ∪ owned − exclusions` (`EquipmentVocab.effectiveItems`), and every consumer keys on `equipment_needed` via `EquipmentCapability.canPerform`. **NEVER on `equipment_tier`**, which is a curation hint. Two producers that deliberately disagree: `TrainingHistoryAnalyzer.resolveCapabilityFromProfile` is null ABOVE the bodyweight tier (the hard floor is scoped there), while `effectiveEquipmentForSnapshot` answers at every tier because the AI coach needs the truth for a `home_dumbbells` user too. Restore is free — `_restoreUserProfile` merges every non-null cloud key. `equipment_access` ABSENT resolves to `bodyweight` via `equipmentAccessOf` (`lib/core/constants/equipment_defaults.dart`), never per-site: 14 sites once disagreed across four values, and because the floor is bodyweight-scoped a wrong default turned it OFF. Diagnoses `f7b2c4` / `d3a8f5`. |
| `referral_redemption` | `apply_referral_sheet` → server-side validate-referral edge function | `subscription_service.isPro()` (7-day PRO grant). |
| `submissions` | `submissionsRepository` (custom exercise + custom food submission queue) | `submissions_screen.dart`. |

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Progress-photo upload fails with PhotoQuotaException | Daily cap exceeded. Free: 2/day, PRO: 5/day. Enforced at `ProgressPhotoRepository.capture` by counting today's `progress_photos` rows for the user BEFORE pick. UI should catch `PhotoQuotaException`, surface the paywall for free users (`feature: 'progress_photos'`) or a "come back tomorrow" snackbar for PRO. Image quality differs by tier too: 2048/85% free, 3000/95% PRO. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Weekly Report sparkline dips to 0 between weigh-ins | By design only for calories/protein/workouts (zero-fill = genuinely no activity). Weight series is **forward-filled** from last known — if you see it dropping to zero on un-weighed days, `weeklyReportDataProvider` has regressed. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Edit Profile saves but home doesn't refresh | `ProfileWriteService` must invalidate the same provider set as the onboarding completion path: `userProfileProvider`, `homeProvider`, `dietPlanProvider` (when goal/weight changes), `nutritionTargetsProvider`. Missing any one = stale UI. | `user_full_name` SoT |
| Profile screen `usageWeeks` counter reads dead Hive key | Fixed 2026-05-20 (commit `00c36cc`). `usageWeeks` now reads `users.created_at` from Supabase, NOT the dead `configBox['signup_at']` key. Don't reintroduce a Hive-side counter — Supabase signup date is canonical. | `feedback_writer_reader_field_drift_recurring.md` |
| Edit Profile silently recomputes calories from a fabricated body-fat | `recalculateTargets` reads `body_fat_percent` and feeds it into `BmrCalculator.calculateTargets` via **Katch-McArdle** on EVERY edit. It is the CONSUMING reader of onboarding's body-fat. Pre-Unit-4, onboarding SAVED a fabricated `18.0` for skip-users (their own calc ignored it) → the first profile edit recomputed from a made-up 18% lean mass. Fixed (c3f2d8, 2026-06-14): onboarding saves `null` on skip; `BodyFatDefaultHealer` (boot) clears legacy 18.0. Never reintroduce a body-fat default — null → Mifflin is correct. | SoT `onboarding_bodyfat_calc_input`; diagnose c3f2d8 |
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
