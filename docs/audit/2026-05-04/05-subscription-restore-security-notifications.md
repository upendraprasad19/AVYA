# Audit 5: subscription + restore + Edge Function security + notifications findings

Audit date: 2026-05-04. Scope: cross-device restore, subscription/paywall correctness, Edge Function security, notification hygiene. Reviewer: claude (Opus 4.7 1M).

---

## P0 (payment bypass, restore loses data, security hole)

### P0-1. Streak freezes lost on reinstall — premium-feel breaker
`lib/core/services/sync_service.dart:700-806` (`restoreFromCloud` / `restoreFromCloudForUser`).
`streak_freezes_available` and `streak_freezes_used_dates` live in `userBox['progress']`. Cloud `user_progress` table has **no columns for either** (zero matches across `supabase/migrations/`). `_restoreUserProgress` (`sync_service.dart:2600-2629`) merges only what the cloud row contains. Read sites confirm Hive-only: `home_provider.dart:217`, `workout_repository.dart:167,234`, `rank_service_record_sheet.dart:204`. Per CLAUDE.md memo (Bug C / "Streak freezes are HIVE-ONLY") this is intentional — but per audit goal "my PRO status survives reinstall", a paying user reinstalling loses their unused freezes silently. **Either:** add migration adding `streak_freezes_available INT`, `streak_freezes_used_dates TEXT[]`, `streak_freezes_last_refill TIMESTAMPTZ` to `user_progress` and project them in `_syncUserProgress`/`_restoreUserProgress`; **or** document the loss explicitly in PRO marketing. Today it is a silent regression on every device migration.

### P0-2. Rank promotion history not restored
`rank_promotions` table exists (migration 040) and is written by `RankService.evaluateAndPromote()` + `evaluate-rank-promotions` cron. `restoreFromCloudForUser` (sync_service.dart:750-806) does NOT pull it. The current rank survives because `user_profile.current_rank_code` is restored; but the **history list** shown in `RankServiceRecordSheet` (the bottom sheet for the rank chip — APK Test #8) reads `rank_promotions` server-side or shows empty. Effect on reinstall: user sees current rank but the "last 5 promotions" panel is empty until they earn a new rank. `_restoreRankPromotions` is missing. Add a `_restoreRankPromotions(userId)` op that pulls `rank_promotions WHERE user_id = userId ORDER BY promoted_at DESC LIMIT 50` and writes a Hive list cache, OR keep the UI reading from cloud directly (no cache → show spinner on reinstall, ok).

### P0-3. Subscription not pulled by `restoreFromCloudForUser`
`SyncService.restoreFromCloudForUser` (sync_service.dart:750-806) has no entry for `subscriptions` or for invoking `SubscriptionService.refreshFromSupabase()`. Today the PRO-state hydration depends on a *separate* hook in `auth_provider.dart:585` (`unawaited(SubscriptionService.instance.refreshFromSupabase())`). If that hook ever drifts out of the post-auth flow (or RestoringScreen replaces it), users will land on `/home` with `isPro=false` until app re-launch. Fragile. Add `_safeRestoreOp('subscription', SubscriptionService.instance.refreshFromSupabase())` to the Step A wave so subscription state is part of the restore contract.

### P0-4. Notifications inbox is Hive-only — lost on reinstall
`lib/features/profile/services/notification_inbox_service.dart` writes to `notificationsBox` (Hive). No corresponding cloud table (no `app_notifications` migration). On reinstall, the entire inbox (PR detection cards, weekly recap card, plateau-alert dispatch) is gone. For a "my coach remembers me" UX this is a noticeable trust hit. Either (a) add a `notifications` table and project on every inbox write (parallels other domains), or (b) classify as ephemeral and document in copy. Decide.

### P0-5. Razorpay webhook DERIVES plan FROM client-supplied notes, not amount
`supabase/functions/razorpay-webhook/index.ts:300-302` extracts `plan = notes.plan` directly from the payment object's `notes` (set during checkout creation). Per CLAUDE.md §16 rule 1 plan must be derived from amount, NEVER from client. Today this is partially mitigated by `computeExpectedAmount` (line 345-362) which DOES validate amount matches plan-derived expected — so a tampered `notes.plan='yearly'` with a ₹349 paid amount would fail the amount check (line 349) and 400 out. **However**, the symmetry vs. `verify-payment/index.ts:374` (which uses `derivePlanFromAmount` — the recommended pattern) is broken. If a user pays ₹349 and notes says `plan='monthly'`, that works; if a tester or attacker manipulates `notes.plan='yearly'` and pays ₹2,999, the amount check passes both branches → user gets yearly. That is the intended path. The actual hole: `notes.plan` is the source-of-truth for endDate computation (line 367-371). If a bug ever made `expectedPaise` = full price for a yearly note while user paid `MONTHLY_PAISE`, the amount check would fail correctly — but if `notes.plan` is missing or empty, line 305-313 returns 400. **Conclusion: webhook is structurally inferior to verify-payment but practically safe due to amount validation.** Recommend rewriting webhook to call `derivePlanFromAmount(actualPaise, promoCode, supabase)` like verify-payment does and dropping reliance on `notes.plan` entirely. P0 because every new contributor reading this will think §16 rule 1 is already satisfied.

---

## P1 (premium-feel breaker, paywall regression)

### P1-1. Saved diet plan is `configBox`-only — lost on reinstall
`configBox['saved_diet_plan']` (per CLAUDE.md §15 source-of-truth note for `dietPlanProvider`) is Hive-only. No cloud table. User invests minutes building a diet plan, reinstalls, plan gone. Add `saved_diet_plans` table or sync into `user_progress`.

### P1-2. Coach `coaching_notes` extraction lost between reinstall and next nightly job
Splash → `daily-snapshot` extraction happens at 11 PM IST. Reinstall before that → `_restoreCoachMemory` (sync_service.dart:3421-3456) only pulls 9 specific fields (committed_at, induction_completed_at, why_now, definition_of_winning, known_injuries, typical_wake_time, preferred_workout_time, body_part_priorities, committed_to_lt_cdr). It does NOT pull `coaching_notes` (the AI-extracted facts). On next ai-proxy turn, `buildAiContext` reads `coachBox['coaching_notes']` which is empty → coach loses its memory until the next nightly extraction. Add `coaching_notes` and `last_proactive_type` to the field whitelist in `_restoreCoachMemory:3425-3429`.

### P1-3. `gate()` callsites that show snackbars instead of paywall on PRO branch
`lib/features/nutrition/widgets/cart_auditor_section.dart:152-155`, `food_logger_section.dart:55-58`, `scan_meal_section.dart:166-170` use `onPro: () { showSnackBar('You have reached the daily limit') }`. This is the CORRECT pattern (PRO user hit per-day cap → toast), but reads like a regression at first glance and there's no source comment clarifying why a PRO user is hitting a free-side branch. Add a `// PRO user hit per-day cap (10/day) — soft snackbar, NOT paywall` comment at each callsite to prevent future "fix" PRs.

### P1-4. `gate()` for `ai_body_composition` is not in `allProFeatures`
`edit_profile_screen.dart:1334` calls `subscription.gate('ai_body_composition', ...)`. The string `'ai_body_composition'` is not in `SubscriptionService.allProFeatures` (subscription_service.dart:25-41) and not in `AppConstants.feature*` constants. It will work because `gate()` only special-cases `_highValueFeatures`, but the literal-string callsite is fragile (no compile-time check, no audit surface). Promote to `AppConstants.featureAiBodyComposition` and add to `allProFeatures`.

### P1-5. `_highValueFeatures` matches Test #2 spec — clean
subscription_service.dart:129-133 contains exactly `{phases_2_to_12, ai_coach_unlimited, progress_photos}`. `featureActiveWorkoutMode` is correctly absent (Test #2 / Q6). Lock-down test exists at `test/subscription/high_value_features_test.dart`.

### P1-6. `_downgradeLocally` clears 4 keys, not 5 listed in audit prompt
subscription_service.dart:361-368 clears: `_isProKey` (set to false, not deleted), `_expiresAtKey`, `_planKey`, `localActivationAt`, `_lastVerifiedKey`. That's 5 operations; the prompt's expectation list of 4 unique keys + `localActivationAt` matches exactly. **Clean.**

### P1-7. `localActivationAt` cleared after grace period — clean (with subtlety)
subscription_service.dart:191-195, 240-246. Grace period is 10 minutes. Clean. Subtlety: line 244 only clears if there's an exception in the try block (i.e., network error path). The success path at line 195 also clears. The path that doesn't clear: `refreshFromSupabase` returns early at line 196 *while still inside grace period*. That's by design.

### P1-8. Notification dedup is per-IST-day, not "two consecutive days"
`_shared/proactive_dedup.ts:55-56` blocks same `last_proactive_type` within the same IST date. CLAUDE.md "prevent same-type push twice per IST day" matches. The original brainstorm rule in §11 says "Never repeat same trigger type two days in a row" — the implementation is more permissive than the brainstorm rule (would allow morning_brief Day1, morning_brief Day2 because IST date differs). If user-perceived "spam" is the concern, tighten to "≥2 IST days since last same-type". Today the implementation matches the documented contract; flagging only because the brainstorm wording is stricter.

---

## P2 (polish, doc updates)

- subscription_service.dart:25-41 `allProFeatures` includes `featureActiveWorkoutMode` even though Test #2 / Q6 deprecated it. Memo says "kept as `@Deprecated` so legacy callers don't break" — but its presence in `allProFeatures` makes it act like a PRO feature in any audit query. Remove or re-comment.
- ai-proxy-pro is supposed to be a 410-Gone stub but contains 0 matched lines for sanitization grep. File appears empty/missing. Confirm 410 stub is still deployed; if it's genuinely empty in source, redeploy with a single-line 410 handler.
- `restoreFromCloud` (sync_service.dart:700) and `restoreFromCloudForUser` (line 750) duplicate the entry list. Future drift risk — every new restore op needs to be added in two places. Refactor into a single shared list.

---

## Per-Edge-Function security summary table

| Function | JWT | Input limits | SSRF | Rate limit | Sanitised errors | Notes |
|---|---|---|---|---|---|---|
| `ai-proxy` | Manual `auth.getUser` (verify_jwt off) | message ≤5K, snapshot ≤10K | n/a | food_text 50/200 daily via trigger | yes (`request_id`) | Clean. |
| `ai-media-proxy` | Manual `auth.getUser` | message ≤5K, image ≤5MB | **Storage prefix allowlist** | 5 lifetime free image cap, video paywall | yes | Clean. |
| `razorpay-webhook` | HMAC sig | UUID regex on user_id, plan whitelist | n/a | 5-min replay window | yes | **P0-5 plan-from-notes** |
| `verify-payment` | Manual `auth.getUser` | payment_id required | n/a | 20/user/10min via `ai_coach_interactions` | yes | Clean — derives plan from amount correctly. |
| `validate-promo` | Manual `auth.getUser` | code length implied | n/a | none | yes | Clean. |
| `redeem-referral` | Manual auth | RPC enforces self-referral CHECK | n/a | UNIQUE(referee_id) idempotency | yes | Clean. |
| `verify-subscription` | Manual auth | n/a | n/a | none | yes | Clean. |
| `assess-body-composition` | Manual auth | n/a | n/a | none | yes | Clean — but image URL not allowlisted (relies on caller). |
| `beat-my-coach` | Manual auth | n/a | n/a | none | yes | Clean. |
| `future-prediction` | Manual auth | n/a | n/a | once-free monthly-PRO logic | yes | Clean. |
| `daily-snapshot` | Manual auth | n/a | n/a | nightly cron | yes | Clean. |
| `weekly-report` | Manual auth | n/a | n/a | n/a | yes | Clean. |
| `rolling-context` | service-role (cron) | n/a | n/a | nightly cron | yes | Clean. |
| `morning-alert` | service-role (cron) | n/a | n/a | per-15-min quarter | yes | Clean. |
| `streak-guardian` | service-role (cron) | n/a | n/a | dedup + 8 PM IST | yes | Clean. |
| `weekly-recap-ready` | service-role (cron) | n/a | n/a | dedup + Sunday | yes | Clean. |
| `workout-window-closing` | service-role (cron) | n/a | n/a | dedup + 21:00 IST | yes | Clean. |
| `protein-gap-alert` | service-role (cron) | n/a | n/a | dedup + PRO-only filter | yes | Clean. |
| `plateau-alert` | service-role (cron) | n/a | n/a | dedup + PRO-only filter | yes | Clean. |
| `pr-detection` | service-role (cron) | n/a | n/a | dedup + 15-min window | yes | Clean. |
| `re-engagement` | service-role (cron) | n/a | n/a | dedup + 12:00 IST | yes | Clean. |
| `expiry-reminder` | service-role (cron) | n/a | n/a | n/a | yes | Clean. |
| `evaluate-rank-promotions` | service-role (cron) | n/a | n/a | UNIQUE(user_id, rank_code) | yes | Clean. |
| `compute-coach-signals` | service-role (cron) | n/a | n/a | nightly | yes | Clean. |
| `i-see-you-callout` | (cron) | n/a | n/a | n/a | unverified | Sample. |
| `weekly-recalc` | (cron) | n/a | n/a | n/a | unverified | Sample. |
| `log-client-error` | `verify_jwt: true` + manual | n/a | n/a | none | yes | Clean. |
| `promote-community-item` | `verify_jwt: true` (admin) | n/a | n/a | n/a | unverified | Verify admin RLS still enforced. |
| `create-razorpay-order` | Manual auth (verify_jwt false) | n/a | n/a | none | yes | Clean. |
| `clean-orphan-media` | service-role | n/a | n/a | daily | yes | Clean. |
| `video-render-trigger` | (deferred per CLAUDE.md) | n/a | n/a | n/a | n/a | Empty / deferred. |
| `video-status` | 410 Gone | n/a | n/a | n/a | n/a | Empty / 410 stub. |
| `ai-proxy-pro` | 410 Gone | n/a | n/a | n/a | n/a | Empty per CLAUDE.md. |

---

## Per-notification-trigger summary table

| # | Trigger | Cron (UTC → IST) | Tier check | Dedup | Sample copy | PII risk |
|---|---|---|---|---|---|---|
| 1 | `morning-alert` | `*/15 22-23,0-6 UTC` (per-quarter) → wake-time IST | both | `shouldSendProactive('morning_brief')` | personalised first-name allowed | low — first name only |
| 2 | `workout-window-closing` | `30 15 * * *` → 21:00 IST | both | `workout_window` | implicit only | low |
| 3 | `protein-gap-alert` | `30 14 * * *` → 20:00 IST | **PRO-only** filter at line 75-79 | `protein_gap` | "Upendra — 38g short on protein today. Try 2 boiled eggs + dal. Want a dinner suggestion?" | first name + protein number — low risk |
| 4 | `streak-guardian` | (existing) → 20:00 IST | both | `streak_protection` | streak count only | low |
| 5 | `pr-detection` | `*/15 * * * *` → near-real-time | both | `pr_celebration` (15-min window) | exercise name + weight | low |
| 6 | `plateau-alert` | `30 13 * * *` → 19:00 IST | **PRO-only** | `plateau_alert` | implicit only | low |
| 7 | `weekly-recap-ready` | (existing) Sunday | both | `weekly_recap` | implicit only | low |
| 8 | `re-engagement` | `30 06 * * *` → 12:00 IST | both | `re_engagement` | "We miss you" style | low |

**All 8 cron-driven, all use shared dedup helper, all use service-role token from `private.morning_alert_get_service_key()`.** No PII leak in sampled copy. Good hygiene overall. Caveat: dedup key is per-IST-day + per-type, so a user could receive 2 different proactives in one day (e.g., morning_brief + protein_gap + workout_window). Three pushes/day is the theoretical max; if abuse complaints surface, add a global "max 2 proactive pushes/IST-day" rail in `proactive_dedup.ts`.

---

## Quick wins

1. **(P0-3)** Add subscription refresh to `restoreFromCloudForUser` Step A — 1 line. Highest leverage.
2. **(P1-2)** Add `coaching_notes` + `last_proactive_type` to `_restoreCoachMemory` whitelist — 2 lines.
3. **(P1-4)** Promote `'ai_body_composition'` literal to `AppConstants.featureAiBodyComposition` — 3 lines + edit_profile_screen update.
4. **(P0-5)** Refactor `razorpay-webhook` to use `derivePlanFromAmount` parity with `verify-payment` — ~30 LOC; eliminates the §16-rule-1 ambiguity for good.
5. **(P2)** Deduplicate the restore op list between `restoreFromCloud` and `restoreFromCloudForUser` — extract a single `_buildRestoreOps(userId, since, includeBulk)` helper.

---

## Things checked and clean

- HMAC verification on webhook (razorpay-webhook:154-164).
- Promo amount tolerant validation (razorpay-webhook:78-89, verify-payment:62-73).
- Webhook idempotency (razorpay-webhook:384-422 — pre-SELECT + 23505 catch).
- Promo redemption guard (razorpay-webhook:448 — `!alreadyProcessed`).
- 5-min replay window (razorpay-webhook:204-219).
- verify-payment rate limit 20/10min (verify-payment:186-209).
- verify-payment plan derived from amount (verify-payment:374).
- ai-proxy 5K msg / 10K snapshot limits (ai-proxy:419-425).
- ai-media-proxy SSRF allowlist (ai-media-proxy:81-89).
- ai-media-proxy 5MB image cap with content-length pre-check (ai-media-proxy:102-110).
- All sampled Edge Functions return `{error, request_id}` on 5xx with `console.error` carrying the request_id.
- `progress_photos` table RLS owns-row (migration 022:33-45).
- `isPro()` null-expiry → `kDebugMode` only (subscription_service.dart:106-109).
- `isPro()` profile-id mismatch force-downgrade (subscription_service.dart:88-103).
- `_downgradeLocally` clears all 5 keys correctly.
- `verifyFromServer` 5-min cache TTL (subscription_service.dart:51, 264-271).
- `_highValueFeatures` exact set matches Test #2 spec.
- All proactive triggers use `shouldSendProactive`/`markProactiveSent` shared helper.
- PRO-only triggers (`protein-gap-alert`, `plateau-alert`) actually filter on subscription.
- Storage cleanup cron exists for `coach-media` (migration 047) — 30-day TTL for free users.
