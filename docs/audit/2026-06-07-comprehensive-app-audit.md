# Comprehensive App Audit — 2026-06-07

**Scope:** app flow · functionality · correctness · SOT · logical flow · screen consistency · everything-in-sync / no-hardcoded-values (founder `/goal`, 2026-06-07).
**Method:** multi-agent workflow (12 scopes = 8 feature domains + 4 cross-cutting lenses), each finding adversarially verified; seeded with a live `client_errors` investigation. Lenses from `docs/audit/LENS_REGISTRY.md`; spec = `docs/architecture/functionality-flow.md` + `docs/sot_registry.yaml`; UX/brand lens = `.claude/skills/psychology-pass-fitness/SKILL.md`.
**Verification legend:** `[V-me]` re-read by the orchestrator personally · `[V-wf]` confirmed by an adversarial verifier subagent · `[cand]` finder-found, not yet independently re-verified.

> **Status: PASS 1 of 2.** Pass 1 covered 5 of 12 scopes (home, ai_coach, profile_rank, sot_drift, hardcoded_sync) — the other 7 finders hit a StructuredOutput tooling glitch and returned nothing. A lean re-run of {onboarding_auth, train, nutrition, subscription_payment, sync_restore, consistency_screens, edge_cron} is in flight; **Pass 2 findings append below when it lands.** The workflow's own verify stage largely failed (18/20 verifiers errored), so severities here rest on orchestrator re-reads of the P1s, not the subagent verify layer.

---

## 0. Live production signal — the `client_errors` "spike" is BENIGN (no action)

The session opened on alerts #19–26 (critical: 354 rows on 2026-06-06). Live query (`client_errors`, project `dedsavbjuwgarrhphgnl`) shows the entire spike is **one sim-polluted founder device on old build `1.0.0+28`** (main is `+33`):
- **787 rows** are benign `event` breadcrumbs (`restore_op_done`) — exactly what alert-tuning migration 086 was meant to exclude.
- **~127 `String`-coded** `upsert_*` rows are **device-offline** errors (`ClientException: Software caused connection abort`, `Failed host lookup … No address associated with hostname` = DNS down).
- **~40 `PostgrestException`** rows are **transient Supabase-platform** blips (504/522/57014/`PGRST002` schema-cache) clustered in three short windows; the client catches + retries correctly.

**Not a fleet regression.** One real app-code lead extracted → **F-reps** below.

---

## 1. Confirmed findings (re-verified)

### F1 · [P1] · `[V-me]` AI-coach free limit + 30-day trial: client contradicts server, and **locks free users out after 30 days**
- **Client:** `app_constants.dart:70` `freeAiMessagesPerDay = 15` + `:73` `freeAiTrialDays = 30`. **Server (SoT):** `ai-proxy/index.ts:63` `FREE_DAILY_LIMIT = 10`, OQ-1 "10/day **forever, no trial**".
- The client invents a 30-day trial: `TrialInfoData.build()` ([ai_coach_provider.dart:335](lib/features/ai_coach/providers/ai_coach_provider.dart:335)) → `isTrialExpired` after 30 days → `screen.dart:260` + `input_bar.dart:11-13` **disable the composer** even at 0 messages used. A free user >30 days post-install is paywalled out of a feature the server still grants. Also the `RATE_LIMITED` copy hardcodes "15/day" (`:754`) and a dead `TRIAL_EXPIRED` branch (`:751`) maps a code the server never sends.
- Drift is **4-way**: `app_constants=15`, `business-rules.md:23="15 msg/day"`, `supabase/functions/CLAUDE.md="Free trial 15/day"` vs server+`captain_manual.ts=10`.
- **Fix:** align client to server — `freeAiMessagesPerDay = 10` (new `ai_limits` SoT, pinned to server by a parity test), **remove the client trial subsystem** (`freeAiTrialDays`, `TrialInfoData` expiry path, the `isTrialExpired` composer gate, the profile "Xd AI trial remaining" chip, the dead `TRIAL_EXPIRED` branch), fix the two docs. Consumer map: 8 files (`app_constants`, `ai_coach_provider`, `screen`, `input_bar`, `compact_header`, `subscription_section`, `auth_session_bootstrapper`, `app.dart`/`day_rollover_service`). *(F16/F17 are sub-symptoms of this.)*

### F2 · [P1] · `[V-me]` Lifetime Ladder "DEPLOYMENTS" reads the wrong field — two surfaces disagree
- [rank_ladder_screen.dart:302](lib/features/profile/screens/rank_ladder_screen.dart:302) `final deployments = (progress['total_workouts_done'] as int?) ?? 0;` under a **"DEPLOYMENTS"** label, while the RANK card [service_record_section.dart:204](lib/features/profile/widgets/service_record_section.dart:204) correctly reads `progress['deployments_complete']`. Writer (`user_repository.saveProgress`) stamps `deployments_complete = current_phase-1`. A user with 40 Phase-1 workouts sees DEPLOYMENTS=40 on the ladder but =0 on the RANK card.
- **Fix:** `rank_ladder_screen.dart:302` → `progress['deployments_complete']`. Extend `deployments_complete_writer_to_reader_test.dart` to pin BOTH display readers.

### F3 · [P1] · `[V-me]` Streak "Field Manual" explainer describes a weekly-80% rule the streak does not use
- [streak_explainer_sheet.dart:84](lib/features/home/widgets/streak_explainer_sheet.dart:84) "You earn +1 each week you complete at least 80% of your scheduled workouts." The actual reader `WorkoutRepository._calculateStreak` ([workout_repository.dart:262](lib/features/train/repositories/workout_repository.dart:262)) does `streak += 1` **per completed scheduled DAY** (walk-back; rest/off/travel skipped; missed day breaks unless freeze-protected). No weekly/80% logic exists. The other 3 explainer rules (freezes) are correct.
- **Fix:** rewrite the first rule to the real algorithm ("+1 for every scheduled training day you complete; rest days never count against you"). Pin the copy semantic with a contract test.

### F4 · [P2] · `[V-wf]` Profile Daily-Goals weight/workout dots read a **device-local** date key vs the IST writer
- [daily_completion.dart:11](lib/features/profile/screens/profile/daily_completion.dart:11) builds `todayStr` from device-local y/m/d, then reads `healthBox.get('weight_$todayStr')` (`:26`) and filters workout `raw['date']==todayStr` (`:13-16`). Writers are IST (`health_write_service.dart:122`, `workout_write_service.dart:525`). The sibling `profile_provider.dart:427` was fixed to `istDateStr` on 2026-06-05; this site was missed by that sweep (recurring IST-sweep-gap class). Off-by-one for any non-IST device.
- **Fix:** `final todayStr = istDateStr(today);` + contract assertion. *(Part of the IST cluster, §2.)*

### F5 · [P2] · `[V-wf]` `weight_logs` regression test is a false-confidence source-grep (pins the wrong file)
- `weight_logs_writer_to_reader_test.dart:39-71` greps **`home_provider.dart`** for the writer contract, but `WeightLogNotifier.logWeight` (`home_provider.dart:863`) just delegates to `HealthWriteService.logWeight` — the literals it asserts (`'weight_log'`, `syncWeightNow`) live in reader code + comments, never the true writer (`health_write_service.dart:114-150`). The canonical writer could drift and all 8 assertions still pass. (`feedback_source_grep_false_confidence.md` class; registry sets `behavioral_test_required: true` with no path.)
- **Fix:** point writer assertions at `health_write_service.dart`; add a real `logWeight → read-back` behavioral round-trip.

---

## 2. IST reader-drift cluster (same class as F4 — recurring `feedback_ist_sweep_gap`)

Multiple **readers** build date keys from device-local `DateTime.now()` y/m/d while their **writers** use `istDateStr`. Off-by-one for any non-IST device (NRI/traveller/emulator-on-UTC). Each fix = swap the manual string for `istDateStr(...)` + a boundary contract test.

| ID | Sev | Site | Writer it drifts from |
|---|---|---|---|
| F4 | P2 `[V-wf]` | `daily_completion.dart:11` | `health_write_service.dart:122` (IST) |
| F6 | P2 `[cand]` | `home_provider.dart:81` `CalendarWeekNotifier` (device-local week boundaries) | `WeeklyCalendar`/schedule keys (IST) |
| F8 | P2 `[cand]` | `ai_snapshot_builder.dart:605,715` `_getTodayNutrition`/`_getNutritionTrend7d` | `nutrition_write_service.dart:88` `nlog_<istDateStr>` |
| F9 | P2 `[cand]` | `coach_memory_service.dart:181` `isFirstMessageToday` (greeting dedup) | `:189 markGreetedToday` (IST) — writer & reader disagree |
| F7 | P3 `[cand]` | `home_provider.dart:825` `TodayStepsNotifier` + `health_sync_service.dart:161` (both device-local) | doc claims HealthWriteService IST, but steps bypass it |

> Recommend a follow-up grep sweep for **all** `DateTime.now()`-built date keys outside `ist_date.dart` to close the class, plus a lint/gate (`check_ist_date_key_drift.dart`) so new readers can't reintroduce it.

---

## 3. Hardcoded / everything-in-sync findings (fold into WS3 gated sweep)

| ID | Sev | Finding | Site |
|---|---|---|---|
| F11 | P2 `[V-me]` | Phase-variant paywall hardcodes `'₹349 / month · ₹2,999 / year'` instead of `AppConstants` | `paywall_sheet_phase_variant.dart:152` |
| F13 | P3 `[cand]` | `appVersion='1.0.0+28'` stale vs `pubspec=+33` → telemetry from +29..+33 mislabeled; parity gate is **build-time only**, not pre-commit | `app_constants.dart:112` |
| F15 | P3 `[cand]` | Daily steps goal `10000` hardcoded ×4, no SoT (unlike water/calorie targets) | `home_screen.dart:763,809,838` + `today_workout_card.dart:53` |
| — | — | 9 raw-hex color files + 298 inline copy literals (gate baselines, WS3) | gates shipped 2026-06-07 |

**Gates already shipped (2026-06-07, §4.11):** `check_raw_hex_in_features.dart` (9-file baseline), `check_hardcoded_pricing_and_limits.dart` (5-literal baseline), `check_copy_centralization.dart` (298 warn-only) — auto-wired in pre-commit + CI, green on current tree.

---

## 4. UX / brand-soul findings (psychology-pass-fitness lens)

| ID | Sev | Finding | Site |
|---|---|---|---|
| F10 | P2 `[cand]` | "AI COACH · INSIGHTS" card with a green **live dot** renders an identical **static** "QUICK WINS" protein list for every user — implies AI personalization that isn't happening (fake-AI / generic-wellness drift the skill flags as a failure) | `ai_insight_card.dart:75-87` |
| F14 | P3 `[cand]` | Two profile-completeness nudges render at once for the same data (non-dismissible top bar + dismissible mid-feed card) for percentage ∈ [1,80) | `home_screen.dart:230` + `:468` |

---

## 5. Dead-code / latent findings

| ID | Sev | Finding | Site |
|---|---|---|---|
| F12 | P2 `[cand]` | `sot_registry.yaml` `weight_logs` names wrong writer file + wrong line range + misattributed regression test | `sot_registry.yaml:2616-2667` |
| F16 | P2 `[cand]` | Trial badge "Nd TRIAL LEFT" is unreachable (mutually-exclusive guard); composer over-gated (part of F1) | `input_bar.dart:170-194` |
| F17 | P3 `[cand]` | Dead `TRIAL_EXPIRED` client branch (server never emits it) | `ai_coach_provider.dart:751` |
| F18 | P3 `[cand]` | Dead "in ~N workouts" next-rank copy — no rank gate sets `totalWorkoutsAtLeast`, so `workoutsRemaining` is always null | `rank_service.dart:251-255` |

---

## 6. Refuted (correctly rejected by the verifier)

- **R1** — "weight_logs realtime handler is insert-only (drops same-date edits)". **REFUTED:** insert-only-on-existing-key is the deliberate codebase-wide **Hive-first-wins** invariant (CLAUDE.md rule #1); realtime + restore + pull are all uniformly insert-only, and the finder's "restore would overwrite" premise is false (`sync_health.dart:300`, `sync_service.dart:1238`). A narrow cross-device edit-propagation limitation exists but is intentional, not handler-specific drift.

---

## 7. Pass-2 findings (re-run of 7 scopes — all returned)

**onboarding_auth**
| ID | Sev | Finding | Site |
|---|---|---|---|
| F19 | **P1** `[V-me]` | "Recompose" goal (the **pre-selected default**) maps to `'recompose'`, which `BmrCalculator` doesn't branch on → falls to `default` = **maintenance calories + lowest protein (1.6)**. Every default-goal user gets the opposite of a recomp. | `plan_screen.dart:663` + `bmr_calculator.dart:172-192` |
| F20 | P2 `[cand]` | Stats BACK button writes extras key `'current_weight_kg'` but the flow reads `'weight_kg'` → typed weight lost, resets to 75.0 default on return | `stats_screen.dart:329` |
| F21 | P2 `[cand]` | Sign-in shows fabricated `'ENLISTED · 18,866 SAILORS ACTIVE'` (no data source, pre-launch) — dark pattern that contradicts the on-screen "Honest data" promise | `sign_in_screen.dart:323` |
| F22 | P3 `[cand]` | Sign-in footer hardcodes `'v1.0.0+3'` instead of `AppConstants.appVersion` (doubly stale) | `sign_in_screen.dart:335` |

**train**
| ID | Sev | Finding | Site |
|---|---|---|---|
| F23 | **P1** `[cand]` | Superset persistence reads `schedule_<localdate>` but writer keys IST → on non-IST devices the row misses, superset pairing **silently lost** on restart *(IST cluster — write-side data loss)* | `train_provider.dart:1184` |
| F24 | P2 `[cand]` | `todayWorkout` getter compares local-date key vs IST day keys → wrong "today" on non-IST devices *(IST cluster)* | `train_provider.dart:416` |
| F25 | P3 `[cand]` | `PlanExpiredCard` passes the gate-KEY `'phases_2_to_12'` as the paywall `feature` → generic subtitle instead of "You crushed Phase 1" | `plan_expired_card.dart:95` |
| F26 | P3 `[cand]` | TodayWorkoutCard hardcodes `~340 kcal` for every workout + defaults unmatched names to `PUSH DAY` | `today_workout_card.dart:23,65` |

**nutrition**
| ID | Sev | Finding | Site |
|---|---|---|---|
| F27 | P2 `[cand]` | Daily/weekly macro sums filter on local-date key vs IST writer → **just-logged meals vanish from the calorie ring** on off-IST devices *(IST cluster)* | `nutrition_read_service.dart:96` + `nutrition_provider.dart:302` |
| F28 | P2 `[cand]` | AI usage "remaining today" chips never invalidated after increment → scarcity counter shows stale value until midnight/restart | `nutrition_provider.dart:1493` + `food_logger_section.dart:83` |
| F29 | P3 `[cand]` | Usage-chip semantics inconsistent (cart shows *remaining*, scan/text show *used* in the same slot) | `cart_auditor_section.dart:78` |
| F30 | P3 `[cand]` | Stale scan/cart limit doc comments ("3/month" vs constant "3/day"; "PRO 3/day" vs "10/day") | `scan_meal_section.dart:23` |

**subscription_payment** *(server items need deploy auth)*
| ID | Sev | Finding | Site |
|---|---|---|---|
| F31 | **P1** `[cand]` SERVER | `verify-payment` double-redeems promo on a 23505 webhook race (fall-through to unconditional `redeemPromo`) → `used_count` over-decremented, duplicate audit row | `verify-payment/index.ts:506-568` |
| F32 | P2 `[cand]` SERVER | Webhook replay-age guard uses payment-entity `created_at` → rejects slowly-approved UPI-collect captures **forever**, PRO never unlocks via webhook | `razorpay-webhook/index.ts:303` |
| F33 | P2 `[cand]` SERVER | `verify-payment` returns `verified:true` on a non-23505 insert failure without writing the row → PRO sticks optimistically then vanishes on cold start | `verify-payment/index.ts:530` |
| F34 | P3 `[cand]` | Only 3 features server-verified; AI-cost features (scan/cart/text) trust local `isPro()` | `subscription_service.dart:328` |
| F35 | P3 `[cand]` | Paywall rounds discount in whole rupees; server charges paise-rounded → displayed price ≠ charged by up to ₹0.50 | `paywall_sheet.dart:181` |

**sync_restore**
| ID | Sev | Finding | Site |
|---|---|---|---|
| F36 | P2 `[cand]` | Restore/push write **naive local** `DateTime.now().toIso8601String()` into `timestamptz` cols (no `.toUtc()`) → IST values stored 5.5h in future, corrupts `completed_at` newest-wins merge | `sync_workout.dart:500` + `sync_health.dart:*` |
| F37 | P2 `[cand]` | `_restoreSleepLogs` has no pagination/`.limit()` → silently truncated at PostgREST 1000-row cap (loses oldest sleep history) | `sync_health.dart:348` |
| F38 | P2 `[cand]` | `restoreLightweightAlways` (every-launch path) omits `_restoreWorkoutPlan` → cross-device `plan_start_date` drift never re-anchored | `sync_service.dart:889` |
| F39 | P3 `[cand]` | `_restoreWorkoutLogs` reads `sets_completed` (dropped in migration 067) → always-null dead read | `sync_workout.dart:596` |

**consistency_screens**
| ID | Sev | Finding | Site |
|---|---|---|---|
| F40 | **P1** `[cand]` | `progress_photos_screen._capture` has **no try/catch** → `PhotoQuotaException` unhandled → upload spinner sticks forever, documented paywall/"come back tomorrow" never fires | `progress_photos_screen.dart:54-71` |
| F41 | P2 `[cand]` | Reports header "SHARE" is a dead affordance (gold/bold like a button, no `onTap`) | `reports_screen.dart:219` |
| F42 | P2 `[cand]` | `plan_expired_card` drifts to generic-wellness tone (🎉 emoji, "Keep going") on a key retention surface — brand-soul FAILURE per the skill | `plan_expired_card.dart:120` |

**edge_cron** *(server items need deploy auth)*
| ID | Sev | Finding | Site |
|---|---|---|---|
| F43 | **P1** `[cand]` SERVER | `pr-detection` scans by `created_at` (sync time) not `completed_at` (workout time) → offline-synced PRs fire stale "New PR!" pushes days late | `pr-detection/index.ts:66` |
| F44 | **P1** `[cand]` SERVER-SEC | `proactive-coach-promotion` is `verify_jwt=false` with **no auth gate** → unauthenticated POST drives Gemini cost + OneSignal push + `ai_coach_interactions` write to any `user_id` | `proactive-coach-promotion/index.ts:67` |
| F45 | P2 `[cand]` SERVER | `i-see-you-callout` scans ALL users unconditionally + 4 sequential per-user queries → unbounded daily cost/latency | `i-see-you-callout/index.ts:67` |
| F46 | P3 `[cand]` | `streak-guardian` docstring "8PM IST" but registry schedules 23:50 IST | `streak-guardian/index.ts:1` |
| F47 | P3 `[cand]` SERVER | CRON_REGISTRY names `proactive-triggers` (no such function dir) — possible dead/404 cron | `CRON_REGISTRY.md:27` |

---

## 8. Consolidated triage

**The 9 P1s:** F1 (AI free-tier lockout), F2 (DEPLOYMENTS field), F3 (streak copy), **F19 (default-goal → maintenance calories)**, F23 (superset IST loss), F31 (promo double-redeem ⟂), F40 (progress-photo spinner), F43 (stale PR push ⟂), F44 (unauth coach-promotion ⟂). *(⟂ = server-side, needs deploy auth.)*

**IST/UTC date-key drift — the dominant recurring class (~10 sites):** F4 ✓, F6, F7, F8, F9, F23, F24, F27, F36, plus the F19 family. Recommend a **single dedicated sweep** (swap every local `DateTime.now()` date-key/timestamp for `istDateStr`/`.toUtc()`) **+ a new gate** `check_local_date_key_drift.dart` so it can't recur (`feedback_ist_sweep_gap`).

**Client vs server split (per §4.3 — server needs explicit deploy go):**
- **Client (~28, ship in next APK, no prod-apply):** F1–F30 (minus F12 reg-doc), F34–F42, F46. Includes the whole IST client cluster + the in-sync/hardcoded sweep + brand-soul copy.
- **Server (7, Edge-Function/cron — explicit deploy auth each):** F31, F32, F33, F43, F44, F45, F47.

**Judgment calls needing founder intent:**
- **F19 recompose:** map `'recomp'` → `'lose_fat'` (simple, deficit-leaning) **or** add a first-class recomp profile (slight deficit + 2.0 g/kg protein)? *(Recommend first-class recomp.)*
- **F21 social proof:** remove the fabricated count, or replace with an honest non-numeric cue ("Founding cohort — enlistment open")?
- **F10 AI-insight card:** make "QUICK WINS" reflect the real protein deficit, or drop the live-AI badge and relabel it a static cheat-sheet?

All fixes carry writer/reader naming + diagnose-doc + contract test per §4.5; ≥account self-review before any merge.
