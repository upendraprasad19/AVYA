# Full-sweep audit — consolidated findings (2026-05-04)

5 parallel agents reviewed 21 dimensions of the codebase. Headline: **22 P0s** across sync, UX, code quality, performance, and subscription/restore. Many are 5–30 line fixes; a few are architectural.

Source reports:
- `01-sync-and-ai-context.md` — sync fan-out, AI snapshot, hallucination guards, coach persona, IST, schema drift
- `02-ux-premium-feel.md` — Wardroom consistency, microcopy lies, onboarding, accessibility, motion, water target
- `03-code-quality.md` — SoT violations, naming, repository pattern, tests, plan generator V4, diet plan accuracy
- `04-performance-observability-privacy.md` — cold start, APK size, error swallowing, kDebugMode, DPDP
- `05-subscription-restore-security-notifications.md` — restore completeness, paywall, payment security, Edge Function security, notifications

---

## P0 cluster map

Grouped by theme, not by audit number, so fixes batch naturally.

### THEME A: Cross-device restore is incomplete (premium-trust killer for paying users)
*A returning user reinstalls and silently loses freezes / rank history / inbox / subscription state.*

| # | Finding | File | Audit |
|---|---------|------|-------|
| A1 | **Streak freezes are Hive-only.** No cloud columns in `user_progress` (`streak_freezes_available`, `streak_freezes_used_dates`, `streak_freezes_last_refill`). Reinstall = freezes gone. | `lib/core/services/streak_freeze_service.dart` + restore | 5 |
| A2 | **`rank_promotions` history not in restore.** Current rank survives via `user_profile.current_rank_code`, but the "last 5 promotions" panel reads empty until the next promotion fires. | `sync_service.dart` `restoreFromCloudForUser` | 5 |
| A3 | **Subscription refresh not in `restoreFromCloudForUser`.** Currently relies on a separate hook in `auth_provider.dart:585`. Fragile — anyone changing post-auth flow can break it. | `sync_service.dart` + `auth_provider.dart:585` | 5 |
| A4 | **Notifications inbox is Hive-only.** No cloud table → entire inbox lost on reinstall. | `notificationsBox` writers + restore | 5 |
| A5 | **Saved diet plan is Hive-only** (P1 in audit 5; promoted here for theme cohesion). | `configBox['saved_diet_plan']` + restore | 5 |
| A6 | **`coaching_notes` not in `_restoreCoachMemory` whitelist** (P1). Coach loses memory between reinstall and the next 11 PM IST extraction. | `sync_service.dart` `_restoreCoachMemory` | 5 |

**Effort:** ~6–8 h. New migration adds cloud columns/table for freezes + notifications inbox + saved diet plan. Add to restore op list. Fold subscription refresh into `restoreFromCloudForUser`.

---

### THEME B: IST/UTC drift breaks AI coach context for users who use the app between 00:00–05:30 IST
*Snapshots filed under the wrong day, AI snapshot keys mismatch Hive write keys, morning-alert wake-time RPC misses the user.*

| # | Finding | File | Audit |
|---|---------|------|-------|
| B1 | **`compileDailySnapshot` builds `snapshot_date` in UTC, not IST.** | `sync_service.dart:377` | 1 |
| B2 | **5 `ai_coach_repository` date helpers use device-local `DateTime.now()`** instead of `istDateStr(...)`: `_getThisWeekWorkouts`, `_getStepHistory`, `_getTodaySteps`, `_getMealsToday`, `_getCurrentPlanSummary`. | `lib/features/ai_coach/repositories/ai_coach_repository.dart` | 1 |
| B3 | **`morning-alert/index.ts:178` `getDay()` is server UTC.** Wrong day-of-week for early-IST cron ticks. | `supabase/functions/morning-alert/index.ts:178` | 1 |

**Effort:** ~2–3 h. Mechanical replacement using existing `lib/core/utils/ist_date.dart` helpers + matching Edge Function helper.

---

### THEME C: Silent data loss — search-mode food logs hit cloud without `items[]`
*Test #10 deferred bug. Cloud `nutrition_log_items` empty for those rows, so weekly-report / protein-gap-alert / rolling-context see "user ate nothing".*

| # | Finding | File | Audit |
|---|---------|------|-------|
| C1 | **`nutrition_provider.logFood` (search mode) writes Hive without `items[]` array.** | `lib/features/nutrition/providers/nutrition_provider.dart` | 1, 3 |
| C2 | **`AiBreakdownNotifier.saveMeal` early-returns silently on empty state** (Test #10 deferred). | `lib/features/nutrition/providers/...` | (CLAUDE.md note) |
| C3 | **No round-trip test from `NutritionWriteService.logMeal` → `AiCoachRepository._getMealsToday`** would have caught this. | `test/contracts/` gap | 3 |

**Effort:** ~2 h. Wire items[] into the search-mode write path + add round-trip contract test.

---

### THEME D: Two writers for workout exercise logs (SoT violation)
*WriteService is supposed to be the sole writer; legacy WorkoutRepository methods still write a parallel schema.*

| # | Finding | File | Audit |
|---|---------|------|-------|
| D1 | **`WorkoutRepository.logExercise` / `updateExerciseLog` write legacy schema.** Still called by `conversational_log_handler`. | `lib/shared/repositories/workout_repository.dart` + handler | 1 |
| D2 | **Restore writes legacy field names** `sets_completed` / `sets_detail` instead of canonical `set_number` / `sets`. After cross-device restore, exlog rows look "0 sets" to PR rescan + AI snapshot. | `sync_service.dart:2266` | 1 |

**Effort:** ~3–4 h. Migrate the 2 legacy methods to delegate to WriteService; rename restore output fields; add restore round-trip test.

---

### THEME E: UX lies + onboarding silent defaults (smallest fixes, highest user-perceived impact)

| # | Finding | File | Audit |
|---|---------|------|-------|
| E1 | **Water target plumbing exists end-to-end but 4 UI sites hardcode 3000 ml.** `weight × 35 ml` is computed and synced, then ignored. 60 kg user sees "100% at 3 L" (real target 2.1 L); 95 kg user sees "100% at 3 L" (real 3.3 L). | `hydration_card.dart:53`, `home_screen.dart:470`, `nutrition_screen.dart:365`, `water_quick_sheet.dart:31` | 2 |
| E2 | **Welcome screen lies: "No streaks, no gimmicks."** Whole app is built on streaks. | `welcome_screen.dart:149` | 2 |
| E3 | **`app.dart:66` ships "Please restart the app"** — explicitly forbidden by CLAUDE.md §11. | `lib/app.dart:66` | 2, 4 |
| E4 | **Identity sex defaults to `'male'` silently.** Every user who taps CONTINUE without touching the pill gets male-BMR forever. No required-field gate. | `identity_screen.dart:62` | 2 |
| E5 | **Identity step-label drift.** Progress shows `01 · 05`; section eyebrow says `QUESTION 0`. | `identity_screen.dart` | 2 |

**Effort:** ~1 h cluster fix. All 5 are 1–10 line edits.

---

### THEME F: Plan generator V4 library is shallow for some muscle/pattern triples
*CLAUDE.md §12 target is 0 attempt3 + 0 attempt4 + 0 universalPool. Diagnostic shows 32 attempt3 + 6 attempt4 picks. `vertical_push × bodyweight × advanced` has 0 exercises in library.*

| # | Finding | File | Audit |
|---|---------|------|-------|
| F1 | Sample-plans diagnostic shows 38 cascade-degraded picks across 12 combos. | `test/plan_generator/v4_diagnostic_output.md` | 3 |

**Effort:** ~2–4 h. Mostly data work — expand `assets/data/exercise_library.json` for the missing triples and re-run diagnostic.

---

### THEME G: Coach persona inconsistency
*Only `ai-proxy` and `weekly-report` use the shared `CAPTAIN_MANUAL` system prompt. The other 6 proactive triggers ship hardcoded English ("Triple digits. You're officially unstoppable!") that breaks the briefing-style Captain voice — premium-feel killer.*

| # | Finding | File | Audit |
|---|---------|------|-------|
| G1 | `morning-alert`, `streak-guardian`, `re-engagement`, `workout-window-closing`, `protein-gap-alert`, `plateau-alert`, `pr-detection` all redefine tone/copy. | `supabase/functions/<each>/index.ts` | 1 |

**Effort:** ~3–4 h. Promote `CAPTAIN_MANUAL` to a shared module, re-deploy 6 functions.

---

### THEME H: DPDP + cold-start performance

| # | Finding | File | Audit |
|---|---------|------|-------|
| H1 | **Delete Account is soft-flag only.** No `auth.users` deletion, no Storage purge, no Razorpay revoke. **DPDP §17 erasure violation = legal risk.** No data-export flow either. | `profile_screen.dart:2200-2275` | 4 |
| H2 | **Splash logo loaded full-resolution** without `cacheWidth` → 200–400 ms cold-start jank. **Do NOT compress the asset** (founder direction 2026-05-04: logo + founder photo are brand touch points, must stay full quality). Add `cacheWidth`/`cacheHeight` only — render-time downsample, file untouched. | `splash_screen.dart:289` | 4 |
| ~~H3~~ | ~~Compress logo + founder photo.~~ **Removed per founder direction 2026-05-04** — these are premium touch points, source assets stay at full quality. | — | — |

**Effort:** H1 ~4–6 h (Edge Function for hard delete cascade). H2 ~5 min (`cacheWidth` only, no asset edits).

---

### THEME I: Razorpay webhook plan-derivation drift from `verify-payment`

| # | Finding | File | Audit |
|---|---------|------|-------|
| I1 | **`razorpay-webhook` derives plan from `notes.plan` (client-supplied)** rather than from amount. Practically safe today because `computeExpectedAmount` validates that the amount matches the plan, but it violates §16 rule 1 in spirit and is structurally inferior to `verify-payment`. Fragile if validation logic ever loosens. | `supabase/functions/razorpay-webhook/index.ts` | 5 |

**Effort:** ~1–2 h. Mirror `verify-payment`'s `derivePlanFromAmount` helper.

---

### THEME J: Stale tests masquerading as bugs

| # | Finding | File | Audit |
|---|---------|------|-------|
| J1 | **`sync_gap_test.dart:73-87`** searches for inline sync calls in `DeleteNutritionLogNotifier`, but the call now lives inside `NutritionWriteService.deleteLog`. Sync IS fired; test grep is wrong. | `test/sync/sync_gap_test.dart:73-87` | 3 |
| J2 | **3 `rank_service` LS/PO/SubLt static-mirror tests** never updated for the Test #6 hybrid sailor/officer model + Lt insertion. | `test/rank/rank_service_test.dart` | 3 |

**Effort:** ~1 h. Delete or update.

---

### THEME L: AI breakdown card has no save confirmation (user-reported bug, 2026-05-04)
*User reported: "I tried to log food via AI analysis, it didn't get logged."*

**Root cause: data IS being saved correctly. The UI gives no signal.**

| # | Finding | File | Audit |
|---|---------|------|-------|
| L1 | **`AiBreakdownNotifier.saveMeal` writes Hive + cloud with `items[]` correctly**, but `ai_breakdown_card` shows no snackbar/haptic/toast. Card disappears (state goes null), user assumes save failed. Second tap hits silent early-return. Other paths all confirm: scan_meal "Meal saved ✓", food_search "Logged $name", barcode snackbar. | `lib/features/nutrition/widgets/ai_breakdown_card.dart:110-128`, `nutrition_provider.dart:731-765` | 6 |

**Effort:** ~5 min. 1-line snackbar after `logMeal` returns + a more graceful "already saved" state instead of silent return on second tap.

---

### THEME M: Rate-limit counters are wrong / dead / drift at IST midnight
*Counter UX is broken in 4 different ways. User-perceptible.*

| # | Finding | File | Audit |
|---|---------|------|-------|
| M1 | **Counters increment on save, not on API call.** AI text + scan counters bump only when `NutritionWriteService.logMeal` runs. Free user can analyse 50× without saving, sees "50 remaining" in UI while server has counted every call and will 429 on the next one. Truth: API calls cost server quota whether or not the user saves the result. | `lib/core/services/usage_counter_service.dart` callsites in WriteService | 6 |
| M2 | **Cart auditor client counter is dead code.** No callsite passes `NutritionWriteSource.cart` to `logMeal`. Free users see "1 scan remaining today" forever; only server abuse cap (15/day) actually fires. | grep for `NutritionWriteSource.cart` returns 0 hits | 6 |
| M3 | **Counter resets use device-local `DateTime.now()`** instead of IST. Same drift class as Theme B. `usage_counter_service.dart:107` + `ai_coach_repository.dart:585`. | as listed | 6 |
| M4 | **`quantityG: 0` on AI-text + scan + coach-tool paths.** Cloud `nutrition_log_items.quantity_g` meaningless on most rows. Only barcode passes a real value. Breaks any analysis that needs portion size (rolling-context summarization, weekly-report). | AiBreakdownNotifier, scan_meal_section, tool_dispatcher | 6 |
| M5 | **`MessageLimitNotifier.build` rescans whole `coachBox` on every rebuild.** O(N) perf smell on the AI coach screen as conversations grow. | `lib/features/ai_coach/providers/...` | 6 |

**Effort:** ~3–4 h. Move counter increments into the API-call site (not save site). Wire cart auditor counter or delete it. Fold IST fix into Theme B. Pass real `quantityG` through the 3 missing paths. Cache `MessageLimitNotifier` count instead of rebuilding.

---

### THEME K: Repository pattern violations (widgets calling Supabase directly)

| # | Finding | File | Audit |
|---|---------|------|-------|
| K1 | `submissions_screen.dart:157, 163, 338, 347, 356`, `my_submissions_screen.dart:46, 52`, `profile_screen.dart:2242` query Supabase tables directly from widgets. Bypasses repository pattern, makes testing harder, scatters auth logic. | as listed | 3 |
| K2 | `edit_profile_screen.dart:1368` invokes Edge Function directly from widget. | as listed | 3 |

**Effort:** ~2–3 h. Push into appropriate repositories.

---

## P1 highlights (full lists in source reports)

- **Coach voice:** P1 fold-in with G above.
- **AI snapshot omits:** `water_today` (only 7d aggregate), custom foods, last AI tool invocations, mood notes. (Audit 1)
- **6 sites leak `e.toString()` to user without `kDebugMode` guard:** `preview_workout_screen.dart:86`, `auth_provider.dart:121,185`, `ai_coach_screen.dart:1632`, `switch_goal_diff.dart:68`. (Audit 4)
- **2 raw `print(`** in `preview_plan_provider.dart:74, 80`. (Audit 4)
- **3 Edge Functions missing `request_id` / Internal Server Error pattern:** `clean-orphan-media`, `log-client-error`, `promote-community-item`. (Audit 4)
- **`notificationsBox` / `coachBox` lack retention pruning** — grow unbounded. (Audit 4)
- **Sign-in hint contrast ~1.5:1** fails WCAG. Unselected onboarding chips at opacity 0.55 look disabled. (Audit 2)
- **`'ai_body_composition'` literal not promoted to `AppConstants`.** (Audit 5)
- **5 dartdoc files still claim "5,000 foods"** when actual is 1431. (Audit 2)
- **Paywall sheet uses "AI" 8× in 13 lines.** (Audit 2)
- **AI coach has no first-time empty state with example prompts.** (Audit 2)
- **User-id name drift:** `userId` / `supaUserId` / `uid` / inline `currentUser?.id` (70+ sites). (Audit 3)
- **`WorkoutReceiptData.fromExerciseLogs` re-implements index lookup** at `workout_receipt_card.dart:253-259` instead of routing through `WorkoutRepository.getExerciseLogsForDate`. (Audit 3)
- **Direct `client.auth` calls scattered** across nutrition/profile features. (Audit 3)

## P2 highlights

- `featureActiveWorkoutMode` still in `allProFeatures` despite Test #2 deprecation. (Audit 5)
- Restore op list duplicated between two methods. (Audit 5)
- `041_chunks/` orphan directory still in repo. (Audit 1)
- Splash 3 s floor hurts fast devices. (Audit 4)

---

## Verified clean (so the user knows scope was actually covered)

**Sync + AI:** ai-proxy v48 day-of-week injection (IST) present. Prediction sanitiser JSON+YAML guards present. `sync_fanout_contract_test` locks fan-out (6 workout / 3 nutrition helpers). WriteService callsites fire `unawaited(syncX + pushSnapshot)` 14/14. Test #4 audit snapshot keys (yesterday_workout, sleep_7d, streak_freezes, active_workout) all present in builder.

**Subscription + payment:** `isPro()` kDebugMode guard. Profile-id mismatch downgrade in 2 places. `_downgradeLocally` clears all 5 keys. `_highValueFeatures` matches Test #2 spec. `verify-payment` plan-from-amount, 20/10min rate limit, idempotent. `ai-proxy` / `ai-media-proxy` 5K msg / 10K snapshot / 5MB image limits, Storage prefix SSRF allowlist, sanitised errors with request_id. 28 of 33 Edge Functions sanitized. All 8 proactive triggers use shared dedup; PRO-only triggers actually filter; sampled copy carries no PII risk. `progress_photos` table has RLS owns-row. `coach-media` storage has 30-day TTL cron for free users.

**Code quality:** Zero `Hive.box(` calls in `lib/features/**`. Zero `configBox.get('isPro')` outside `subscription_service.dart`. `featureActiveWorkoutMode` properly `@Deprecated`, no live `gate()` callsites. Diet plan `[95%, 115%]` band tests still pass. WriteServices are sole writers for `nlog_*`/`exlog_*`. No empty `catch {}` in `sync_service.dart`.

**Performance + privacy:** Crashlytics init order. HiveOwnershipException recovery. Auto Backup XML correct. `log-client-error` wired in 7 paths. 23505/23503 surfacing. `cached_network_image` used for long-lived images. Consent capture, profile-id mismatch downgrade, data minimization clean.

**UX:** No legacy electric-cyan / green leak in production widgets. Notification copy is empathetic and on-brand. Edit Profile sync fixed. Home screen priority matches §13. RestoringScreen branches cleanly. PaywallSheet is single source of truth. Active-workout gating removed correctly.

---

## Water target — concrete recommendation (revised 2026-05-04 per user)

Today: 4 UI sites hardcode 3000 ml; cloud has the right value computed by `weight × 35 ml`. Fixing the read sites is P0 (above). Refined formula:

```
base   = weight_kg × 0.035 L
+ 0.5  L on training days
+ 0.3  L if lifestyle_activity ∈ {active, very_active}
clamp  2.5 L .. 4.0 L          ← floor lifted to 2.5 L per user 2026-05-04
                                  (no female -0.3 deduction; floor handles small users)
```

Plus an **EDIT TARGET** affordance in the water widget — tap → numeric input sheet, persist override to `userBox['water_target_override_ml']`. Read precedence: override → computed → 2500 fallback.

Rationale: ICMR India guidance is ~2.5 L total water for adult men in temperate climate. User wants the app to never show a target below 2.5 L (no one should be told "you only need 2 L") and let the user manually push it higher if they choose. A flat 3 L is too high for a 55 kg sedentary user and too low for a 95 kg lifter; the formula + 2.5 L floor + manual override covers all three cases honestly.

Don't ship the formula change without the read-path fix. The current bug is "value exists, never used."

---

## Sequencing for APK Test #11 — fix everything in one batch (revised 2026-05-04 per founder)

Solo-dev workflow, single APK test cadence, themes mostly independent — no real reason to phase. Fix all 13 themes in one push.

**Total scope:** ~28–36 h ≈ 4–5 working days.

**Order within the batch (matters for risk + early verification, not for shipping cadence):**

1. **First — quick wins (~2 h).** Theme L, E, J, H2. All 5–30 min fixes. Closes the user-reported bug + the obvious lies/defaults + clears the 4 stale test fails. Get these to green before touching anything risky.
2. **Second — counter + IST cluster (~4–5 h).** Theme M + Theme B. Both touch IST helpers + counter logic. Same files, ship together.
3. **Third — items[] + two-writers cluster (~5–6 h).** Theme C + Theme D. Same write path, same contract tests, ship together.
4. **Fourth — coach voice + plan library (~5–7 h).** Theme G + Theme F. Theme G re-deploys 6 Edge Functions; Theme F is a data update + diagnostic re-run. Independent but both touch the AI quality story, group for cohesion.
5. **Fifth — repository pattern cleanup (~2–3 h).** Theme K. Mechanical, deferable if time runs short on the day.
6. **Sixth — payment hardening (~1–2 h).** Theme I. Razorpay webhook plan-from-amount.
7. **Seventh — restore completeness (~6–8 h, RISK).** Theme A. Adds migration with new cloud columns/table for streak freezes + notifications inbox + saved diet plan + rank_promotions in restore + subscription folded into restore. Migration can't be cleanly rolled back — ship after Steps 1–6 are verified passing locally so you don't compound debugging.
8. **Eighth — DPDP hard delete (~4–6 h, RISK).** Theme H1. Edge Function cascading delete: `auth.users` → public.users CASCADE → Storage objects (progress photos, coach-media) → Razorpay subscription cancel. High blast radius; ship last in the batch with a "are you absolutely sure" 2-step confirm flow.

**Why this order, not alphabetical:**
- Steps 1–2 verify the baseline plumbing (counters, IST, snackbars) before touching schema (Step 7) or auth.users deletion (Step 8).
- Steps 7 and 8 are the only ones with non-trivial rollback cost. Doing them last lets earlier work catch any environmental issues first.
- Within the test #11 cycle, you'd commit each step as a separate sub-PR onto the feature branch, so if Test #11 surfaces a regression you can `git bisect` the cluster.

**Risk-isolated steps that could be split if you change your mind later:**
- Theme A (Step 7) — migration + restore changes
- Theme H1 (Step 8) — hard delete

Everything else is genuinely safe to ship together.

---

## What's NOT recommended

- **Don't refactor naming consistency in one go.** 70+ sites of `userId`/`uid`/`supaUserId` — risky as a single PR. Adopt one canonical name per type and tighten it as you touch each file. Lower-priority cleanup.
- **Don't promote every literal to `AppConstants`.** Pick the ones that recur (e.g., `'ai_body_composition'`, magic feature keys) and stop there.
- **Don't try to bundle-shrink aggressively in this batch.** APK at 111 MB is heavy but not breaking. Logo + founder photo compression (~600 KB) is a quick win; bigger restructuring (download exercise library on first run) is a separate effort.
