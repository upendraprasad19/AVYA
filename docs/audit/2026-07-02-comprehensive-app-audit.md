---
title: Comprehensive functional audit — every user action × correct DB × correct SoT
date: 2026-07-02
type: audit-findings
status: observation-only (NO fixes applied this session — per §4.1 observation workflow)
venue: prod web app.icanbefitter.com (main @ 96fb118/bf8b1aa) + Supabase dedsavbjuwgarrhphgnl
account: test7@gmail.com (e34b04a9-3d43-445a-9377-685da6a6e810) — PRO (referral_trial → 2026-07-03), onboarded
method: HYBRID — static contract map of ALL ~165 user actions (4 code-verification subagents, reconciled against docs/architecture/functionality-flow.md + docs/sot_registry.yaml, code = source of truth) + live-drive of a representative subset on test7 (Claude-in-Chrome), each live write proven cross-surface via Supabase MCP.
---

# Comprehensive functional audit — 2026-07-02

> **This is a findings list, not a fix.** Per the observation workflow (§4.1), all issues below
> are gathered for the founder to prioritize. Fixes land in a **separate reviewed batch**
> (diagnose-doc + behavioral regression test + ×2 review scaled to blast-radius, per §4.12),
> which then produces the closure YAML (§4.2). No code was changed in this session.

## Scope caveat (read first)

The 4 static-verification subagents read the **working-directory branch `opt-h-restore-marker`**
(base `5533efd`), which is *behind* `main`. The **live prod web app = `main`** (`96fb118` OBS-6
account-switch fix + `bf8b1aa` C3 single-call restore). Therefore:
- The **auth-token seam** (`authUserIdTokenProvider`) and **restore path**
  (`restoreFromCloudForUser` single-call) differ between the audited code and the live app. Both
  are already shipped + reviewed + live-verified this session — treat as known-good on `main`.
- **Every other write contract** (nutrition / workout / water / weight / custom food+exercise /
  templates / coach tools / profile) is **branch-identical** → all findings below are valid for
  the live app.
- Kill-switch names from memory `disable_single_call_restore` / `disable_live_auth_token_read`
  exist on `main` (live), not on the audited branch. All `disable_*` flags default **fix-ACTIVE**
  when absent (prod default) → the live app runs with fixes ON.

## Executive summary

| Severity | Count | Nature |
|---|---|---|
| **P0** | 0 | No data-corruption / crash / security defect found. |
| **P1** | 2 | `pauseRange` bypasses sync fan-out; **coach dual-confirm double-logs a workout** (live). |
| **P2** | ~14 | Doc/SoT drift + coverage gaps + **coach food-log false "✓ Logged" on failure** + **same-slot meal OVERWRITE/data-loss (NUT-02, code-derived)**; **Profile `settings_screen` unreachable**. |
| **P3** | 2 | Cosmetic / low-risk (water `glasses` not incremented; `daily_steps` no SoT; coach `created_at` IST-as-UTC nit). |
| **NEEDS RE-TEST** | 1 | **Food-logging-via-coach failed 2/2 live** (queuing error → model-unreachable); likely transient Gemini/backend — re-test to confirm the path works. |
| **KNOWN** | 2 | Phone-OTP (Twilio unwired); native-only surfaces degrade on web (by design). |

> **Live-drive addendum (2026-07-02, after founder follow-up "did you check Profile + coach logging?"):** the Coach page and the full Profile surface were then driven live on test7. See the **Coach + Profile live addendum** section below — it adds the P1 coach double-log, the food-log failure + false-success P2, and the Profile settings_screen-unreachable P2.

The app is **substantially healthy**. The AI-coach tool surface is byte-exact to the charter
(20 tools, 9 FREE / 11 PRO, the 4 derive-only prunes confirmed absent). All 15 cross-cutting
invariants (XC-01..15) are enforced in code. Every founder-priority write reaches the **correct
table** with the **correct values** — the issues are one functional bypass (P1) and a cluster of
documentation/coverage drift (P2) where the code is correct but under-pinned.

---

## NOT WORKING (defects a user can hit)

### P1 — `pauseRange` (AI-coach "pause my plan") skips sync fan-out + provider invalidation
- **Where:** `lib/core/services/workout_schedule_write_service.dart:120,140` (verified by reading the code).
- **What:** the method aliases `final box = _hive.workoutBox;` then `await box.put(key, map)` with
  `status='paused'`. Its siblings `markCompleted` (L77) and `markSkipped` (L92) route through
  `WorkoutWriteService.upsertScheduled(...)` — which fans out to cloud (`syncWorkoutData`),
  invalidates the calendar/today/plan providers, and takes the per-key mutex. `pauseRange` does
  **none** of that. The class's own header comment (L6-9) lists `pauseRange` as one of the
  mutations that "calls into WorkoutWriteService for each Hive mutation" — it doesn't.
- **Reachable:** live AI-coach path — `pausePlan` tool → `tool_dispatcher.dart` → `pauseRange`.
- **Impact:** a user who tells the coach "pause my plan for N days" gets the pause written to local
  Hive but (a) **not pushed to cloud that tick** → lost on reinstall-before-next-sync, and (b) the
  Train calendar / Today card **won't refresh** to show "paused" until a manual rebuild. (The pause
  does eventually reach cloud when the next workout-domain write fires `syncWorkoutData`, so it's a
  window/staleness bug, not permanent loss in the common case.)
- **Why the gate misses it:** `workout_schedule_service_uses_write_service_test.dart` counts direct
  puts with regex `\bworkoutBox\.put\(`; `pauseRange` uses the `box` alias, invisible to the regex
  → the `== 4` direct-put assertion passes despite a 5th uncounted put.
- **Fix direction (later batch):** route `pauseRange` through `upsertScheduled` per day (like its
  siblings) + broaden the gate regex to catch aliased `box.put`. Add
  `test/contracts/pause_range_routes_through_write_service_test.dart` (behavioral).

### P3 — Water `glasses` column not incremented (cosmetic)
- **Where:** cloud `water_logs.glasses` stayed `0` after a live "250 ML GLASS" tap (total_ml=250 correct).
- **Impact:** none functional — `total_ml` is the SoT for hydration and the target math uses ml. The
  `glasses` column is a stale/unused denormalization. Flagged for a maintainer to either populate or drop it.

---

## NEEDS FOCUS (feature works; contract unpinned or mis-documented — drift risk)

### P2 — add-custom-food has no SoT registry concept + no regression test (FOUNDER PRIORITY)
- **Live result:** PASS — created "AuditFood0702" via Nutrition › ADD CUSTOM; cloud
  `user_custom_foods` row written immediately (v5-UUID id, `onConflict:'id'`, values exact,
  `submitted_to_db=false`). The feature **works end-to-end**.
- **Gap:** `grep custom_food docs/sot_registry.yaml` → only inside `community_review_queue`
  (the cross-user *read* concept). There is **no custom-food write concept** and **no
  `custom_food` writer→reader contract test**. Charter NUT-11's cited verify
  (`sync_fanout_contract_test`) doesn't reference custom foods. → a future table rename or
  writer/reader drift would pass every gate silently. Register the concept + add a behavioral test.

### P2 — create-custom-exercise: two writers, two key formulas, SoT names the wrong canonical one
- Live UI sheet `create_custom_exercise_sheet.dart:91` does a direct `customBox.put('custom_exercise_<ms>')`
  + `syncCustomItemsNow()`; the repository path uses `WorkoutWriteService.upsertCustomExercise`
  (`custom_exercise_<v5uuid>`). Both write the same prefix. SoT `custom_exercises_mutations` (L4717)
  + `lib/features/train/CLAUDE.md:62` name `upsertCustomExercise` canonical, but the **primary UI
  path** uses the direct sheet write (no mutex, no telemetry pair). Correct box + correct table
  (`user_custom_exercises`) — the SoT doc is inconsistent with the live writer, and the two key
  formulas differ. (The direct write is intentionally pinned by `custom_exercise_writer_to_reader_test`.)

### P2 — SoT/CLAUDE.md document a stale `exlog_*` key formula
- `sot_registry.yaml:139` (+1276/2560) + `train/CLAUDE.md:57` show
  `exlog_..._${exerciseName.hashCode...}`; the live code (`workout_write_service.dart:1030`) uses
  **UUID-v5-over-lowercased-name** (H-16 deliberately moved off `.hashCode` for cross-platform
  stability). Any future writer built from the registry would reproduce the abandoned unstable formula.

### P2 — SoT `workout_schedule_service_routes_through_write_service` cites stale line numbers
- Entry (L4377-4446) cites `workout_schedule_service.dart` line numbers; that file is now a ~270-line
  `@Deprecated` re-export shim. Real callsites live in `swap_service` / `template_service` /
  `workout_schedule_write_service`. Aggregate routing is correct; the per-callsite citations are stale.

### P2 — charter/CLAUDE.md name nutrition methods that don't exist (`saveMeal`, `deleteWithUndo`, `logWater`)
- Charter NUT-13/14/15 + `nutrition/CLAUDE.md:36-37` + `core/CLAUDE.md:44` reference
  `NutritionWriteService.saveMeal` / `deleteWithUndo` and `HealthWriteService.logWater` — none exist.
  Real methods: `saveMealPreset` / `saveMealAsTemplate`, `deleteLog(allowUndo)` + `restoreLastDeleted`,
  and `HealthWriteService.setWaterMl` (the real water writer). NUT-14's cited reader
  `food_log_list_section.dart` doesn't exist. Doc drift (code is correct).

### P2 — `NutritionWriteService.logWater` is dead code (latent trap)
- `nutrition_write_service.dart:392` `logWater` writes `water_$date` to `nutritionBox`, has **zero
  callers**, and no sync helper reads that key. The real water writer is `HealthWriteService.setWaterMl`
  (`water_ml_<istDate>` → `water_logs`). A future caller of the dead method would create water rows
  that never sync. Delete it.

### P2 — Terms acceptance has no SoT concept + dead `TermsModal`
- Writer `sign_in_screen.dart:625` stamps `userBox` `terms_accepted_at`/`terms_version` → projected to
  `users` (auth_session_bootstrapper). `TermsModal.maybeShow` has **zero call sites** (dead). A
  DPDP-compliance cloud field has no registry entry → drift undetected. Behavior is wired + correct.

### P2 — Charter PROF-03 cites `syncOnboarding()`; real method is `syncProfileNow()`
- `grep syncOnboarding lib/` → only `profile/CLAUDE.md:38`. Real: `syncProfileNow` (`sync_profile.dart:19`).
  The charter's stated invalidation set also differs from the actual set in `edit_profile_screen.dart:1643-1656`.
  Doc drift (edit reaches cloud). Efficiency note: edit-profile fires `syncProfileNow` up to 3× per save (idempotent, wasteful).

### P2 — Notifications inbox has no standalone SoT concept
- `notification_inbox_service.dart:69` `record` → `notifications_inbox` via `syncNotificationsInboxEntry`;
  registry references it only inside `restore_completeness`. A real WriteService-shaped write path with no
  own writer/reader concept + test. (Charter PROF-18 admits "needs test".)

### P2 — `health_sync_enabled` written to SHARED configBox (not user-scoped)
- `profile_provider.dart:518` `configBox.put('health_sync_enabled')`; not in the `user_scoped_hive_keys`
  shared-key allowlist (L2041). Could leak a prior owner's toggle across a fast account-switch before
  restore corrects it. Likely acceptable as a device-level preference, but not reasoned in the allowlist —
  flag for an explicit maintainer decision.

### P3 — `daily_steps` has no SoT concept (low risk)
- Table exists (`id,user_id,date,steps,source`) + is synced (`_syncStepsLogs`) + restored
  (`_restoreStepsLogs`), but has no standalone SoT entry. Steps are **import-only** (Health Connect /
  Fit, native), so writer/reader drift is unlikely. Expected, not dangerous.

---

## CONFIRMED-OK (verified this session)

- **Account-switch → Home populates** (OBS-6 a7f2e1): live-verified a 3rd time (test5→test7, no reload).
- **PRO gating:** test7 `subscriptions` = `referral_trial/active/ends 2026-07-03`; the "PRO expires in
  1 day / RENEW" banner renders correctly; no paywall encountered on PRO surfaces.
- **Water logging** (NUT-15): live → cloud `water_logs` (total_ml=250, IST date, onConflict user_id,date).
- **Water target** (NUT-16): 3125 ml = 75kg×35 + 500 (4 training days), matches the formula + UI.
- **Custom food** (NUT-11, FOUNDER PRIORITY): live → `user_custom_foods`, correct values, immediate sync.
- **AI-coach tool surface** (COACH-06/08): EXACTLY 20 tools (`registry.ts ALL_TOOLS`), 9 FREE / 11 PRO,
  the 4 derive-only prunes (`logPR`/`markWorkoutComplete`/`adjustCaloricTarget`/`prelog`) absent.
- **Cross-cutting invariants XC-01..15:** all enforced (sync fan-out, restore completeness, natural-key
  onConflict on all 8 tables, IST date keys, rank monotonic guard, `kIsWeb` web-degradation seams).
- **Community double-vote guard:** `community_reviews` has `UNIQUE(reviewer_id,item_type,item_id)` + PK +
  CHECK(vote/item_type) + FK reviewer_id→users ON DELETE SET NULL (DPDP). Not a gap.
- **Single-writer invariants:** WorkoutWriteService sole writer of `exlog_/wlog_`; WorkoutScheduleWriteService
  routes 8/9 schedule mutations through `upsertScheduled` (the exception is the P1 above); nutrition `nlog_`
  sole-writer + counters increment at API-call site (not save).

---

## KNOWN (cited, not re-reported as new)

- **Phone OTP** (AUTH-04): non-functional in prod — Twilio account created but never wired to Supabase
  Auth. Code path is fully wired; only the backend connection is missing. Email + Google OAuth work.
  (Founder example #1 — confirmed as a known-broken item, not a new finding.)
- **Native-only surfaces degrade on web (by design, XC-15):** health sync = gated dead-end on web;
  camera scan-meal + photo/video upload use a web file-picker (behaviour differs from native); native
  share (PDF/receipt). Android-specific behaviour needs the APK/device pass.

---

## Coverage — what was driven vs verified vs deferred

- **Live-driven on test7 (cross-surface verified):** water +250ml → `water_logs`; custom food → `user_custom_foods`.
  Both proven Hive→cloud with exact values. Establishes the write→sync pipeline is live and correct on prod.
- **Static-verified (code = SoT, 4 subagents + spot-checks):** all ~165 user actions across the 8 surfaces;
  the founder-priority custom exercise / template / schedule write paths (correct box + table + onConflict +
  immediate sync confirmed in code).
- **Not live-completed (friction/budget; static-verified instead):** live custom-exercise + template-save +
  assign-to-date drives were opened but not completed (nested-modal + render-lag friction on CanvasKit web);
  their contracts are confirmed in code. AI-coach `pauseRange` live repro not run (would mutate the 28
  scheduled_workouts) — the P1 is confirmed by reading the code, not by a live mutation.
- **Can't-drive-live (noted, verified statically):** phase unlock (needs weeks), rank promotions (needs weeks),
  plan-expiry card (day 29), 8 cron triggers (server), Phone-OTP (known-broken), Google OAuth (founder skip),
  payment (real money), delete-account (irreversible).
- **Tooling note:** Flutter CanvasKit web IS drivable for both taps and text-entry (`type` works; screenshots
  lag ~1 render so take a settling screenshot before concluding a field is empty). `read_page` exposes only
  the focused field's DOM input; `form_input(ref)` also works.

## Coach + Profile live addendum (2026-07-02)

Driven live on test7 (prod web) after the founder asked whether the Coach page and Profile options were actually exercised. They had NOT been in the first pass (static-only). This pass drove them live.

### Coach page — logging via chat

- **P1 — coach dual confirm cards DOUBLE-LOG a workout.** "log 3 sets of bench press at 60kg for 10 reps" →
  the coach emitted `logSet` and rendered **two independent confirm affordances**: a "Workout ready to log · CONFIRM
  · LOG WORKOUT / DISCARD" card AND a separate "LOG SET · APPLY / DISMISS" card. Confirming BOTH (natural — they look
  like two pending actions) **doubled the log**: `workout_log_exercises` 1→2 rows, `workout_log_sets` 3→6, same
  `workout_log_id` — bench press recorded as 6 sets / 60 reps instead of 3 / 30. Data-integrity defect. The COACH-08
  intent TTL + concurrent-edit guard should have prevented this. Fix: one confirm affordance per intent, or make the
  second APPLY idempotent against an already-committed intent.
- **CONFIRMED-OK — coach workout logging (single confirm).** The first confirm wrote correctly: `workout_log_exercises`
  (Bench Press, 60kg, one `workout_log_id`) + `workout_log_sets` (3 per-set rows, 10 reps @ 60kg) + `workout_logs`
  ("Chat Workout", date 2026-07-02 IST). COACH-05/08 reviewable-intent UX confirmed (not auto-applied).
- **CONFIRMED-OK — COACH-06 derive-only completion.** The coach `logSet` on a scheduled day flipped today's (Thu, LEGS)
  `scheduled_workouts` status `planned → completed` — no separate `markWorkoutComplete` tool. (Reverted in cleanup.)
- **P2 — coach FOOD-log shows a false "✓ Logged" card on FAILURE.** "log 2 rotis and dal for lunch" failed **twice**
  (attempt 1: coach text "queuing error for that log. Try again."; attempt 2: "I had trouble reaching the model. Try
  again in a moment.") — and `nutrition_logs`/`nutrition_log_items` stayed **0** (nothing logged, correctly). BUT a green
  **"✓ Logged" card rendered on BOTH failures** — a false-success indicator contradicting the error text. COACH-14 wants
  errors mapped to actionable copy; the text does that, the card lies. Reproducible P2.
- **NEEDS RE-TEST — food-logging-via-coach failed 2/2 live.** Both attempts errored (queuing error, then model-
  unreachable) while the workout `logSet` succeeded ~10 min earlier. Likely a transient shared-Gemini / `food-text-
  analysis` EF / ai-proxy hiccup (or the intent-queue rattled by the prior double-apply), NOT a confirmed app bug — but
  the food path could not be shown working live. Re-test in a fresh session (and on the APK) to confirm it works at all.
- **P3 (IST nit)** — `workout_logs.created_at` was stamped `19:08 UTC` vs the exercises' `13:38 UTC` (a +5:30 skew = IST
  wall-clock written into a UTC column). `created_at` audit field only; the `date` column is correct.

### Profile page — full live inventory (all options reachable from the Profile tab, top→bottom)

1. **Profile completeness card (81%)** + `ADD session duration` + `ADD body fat %` (write prompts → `user_profile`).
2. **Daily Goals ring** (Workout / Meals / Water / Weight) — read-only tracker.
3. **Badges (4/15)** — read-only.
4. **Your Journey** (Phase 1 — Foundation, Week 2 of 4, goal 78kg) — read-only.
5. **Body Stats + EDIT** → Edit Profile.
6. **Reports / milestones** (Weekly AI Report is PRO → `generate-weekly-report` EF; Progress Comparison → `user_stat_snapshots`, "Take Snapshot Now" = INSERT).
7. **Progress Photos** (PRO) → `progress_photos` + Storage bucket; capture = INSERT (cap 5/day PRO).
8. **SHARE & GROW:** Invite Friends (→ `referral_codes` lazy-create), Submissions (read + Community Review vote → `community_reviews` INSERT, UNIQUE-guarded), Rate App (Play Store).
9. **SETTINGS:** Edit Profile (→ `ProfileWriteService` → `user_profile`), Notifications (5/5 enabled).
10. **Export data as JSON** (DPDP export).
11. **AVYA:** AVYA's Promise, icanbefitter.com, **@icanbefitter (Instagram — external link)**.
12. **SUBSCRIPTION** — live-confirmed **"PRO · REFERRAL_TRIAL · Everything unlocked · EXPIRES 3 JUL 2026"**, no paywall (PRO gating correct). MANAGE SUBSCRIPTION → support sheet.
13. **SIGN OUT.**

- **CONFIRMED-OK:** every Profile section renders for the PRO account with no paywall; the surface is fully reachable.
- **P2 — `settings_screen.dart` (route `/profile/settings`) is registered but NOT linked** from the Profile tab (its rows
  are presentation-only stubs with no `onTap`), so it's effectively dead/unreachable. Confirm intended vs a missing link.
- Full per-option DB-effect + verify-SQL + safe-boundary map: `tasks/wla233fst.output` (workflow live-test matrix).

## Round-2 exhaustive live pass (2026-07-02, "test everything, fix together")

Continued live-driving the untested surfaces on test7. All cross-surface-verified vs cloud.

- **Weight log (Home):** PASS ✓ — `weight_logs` new row date 2026-07-02, `weight_kg=76.5`. Health write did NOT re-sync the stale local workout.
- **UI AI-text meal log (Nutrition › LUNCH › AI):** PASS ✓ — "2 rotis and dal" → `food-text-analysis` EF returned "Roti and Dal 355 kcal" (2 items) → SAVE → `nutrition_logs` (lunch, total_calories=355, protein=16, fiber=11) + 2 `nutrition_log_items`. **NUT-06 confirmed** — totals summed from items (220+135=355, 7+9=16, 5+6=11), not top-level. **This proves the `food-text-analysis` EF is healthy**, so the coach food-log failure was in the **coach chat pipeline (ai-proxy / intent-queue)**, not food analysis.
- **Nutrition read (macro ring):** PASS ✓ — after the meal log, the ring reads 355 consumed / 16 protein / 11 fiber (matches the nlog) + "On track to hit 78kg by Aug 26" projection (NUT-03). BMR 1508 / TDEE 2501 / TARGET 2914 kcal + macros 135P/411C/81F are **consistent across Home, Nutrition, and Diet-Plan** (ONB-08 calc consistency).
- **Diet plan generate + save (Nutrition › DIET PLAN):** PASS ✓ — generated locally (no AI), SAVE → `saved_diet_plans` row (plan_json 3126 chars) synced (NUT-17/19). **"SHARE AS PDF"** is offered in the post-save snackbar (PDF export present).
- **Edit-log surface (Train › EDIT LOG, TRAIN-13):** renders the single edit sheet ("Review sets", JUL 02) with all sets editable — visually confirmed the P1 double-log as **6 sets × 60kg × 10** (should be 3). Did not save (would re-sync the doubled log).
- **PR detection (derive-only):** PASS ✓ — after the coach logSet, Train shows "YOUR STATS · BENCH PRESS · 60 kg · First logged!" — a PR was derived from the logged set (COACH-06 derive-only PR, no `logPR` tool).
- **Local-vs-cloud divergence (offline-first, expected):** Home/Train still show the coach workout (streak 1, today ✓DONE, 6-set bench PR) because the cloud DELETE didn't touch local Hive. These re-sync to cloud only on a **workout-domain** write (a health/nutrition write did not re-push them). Reconcile by clearing site-data / sign-out-in. Handled in the final sweep.

- **Food-search log (Nutrition › + LOG FOOD › SEARCH):** PASS ✓ — searched "banana" (local DB, no Gemini), tapped result → logged to the current time-slot `snacks` (107 kcal, 1 item). Cross-surface confirmed (`nutrition_logs` snacks:107 + 1 item). NUT-06 further confirmed. **LOG FOOD has 5 tabs: AI / SCAN / CART / BAR / SEARCH** (Cart-auditor + Barcode surfaces; both native-only camera per the matrix — can't drive on web).
- **P2 (code-derived, verify in fix batch) — same-slot meal OVERWRITE / data-loss risk (NUT-02):** `nutrition_logs` onConflict is `user_id,date,meal_type`, but the Hive key is item-hash-based (`nlog_<istDate>_<slot>_<v5(items)[:8]>`). So logging a **2nd different meal into the same slot+day** overwrites the single cloud row while Hive keeps both → on reinstall/restore the 1st meal is LOST and totals diverge (Hive shows both, cloud shows one). The #1 recurring writer/reader/sync class. (Not triggered live — my 2nd food went to a different slot; flagged from code.)
- **CONFIRMED — local-dirty re-sync is real + material:** after I deleted the water + a coach row from cloud, a later Nutrition write re-fired `syncNutritionData` and **re-pushed the local water + coach interaction back to cloud** (workout artifacts did NOT re-push — different sync domain). So **cloud cleanup is not durable while the browser's local Hive holds test artifacts** — the only durable reset is clearing site-data / sign-out-in (local restores from clean cloud).

**Exhaustive contract-level matrix (every remaining action):** two workflows produced a full per-action map — Nutrition NUT-01..~13 (incl. scan/cart/barcode/saved-meal/re-log/delete-with-undo/water-override/urine), Train (active-workout per logging_type, swap, shorten, copy-week, assign-template, week-preview, deploy-phase), Home (calendar/receipt/streak/PR/weight-chart), remaining Coach tools (swap/createExercise/shorten/generateHotel + read tools + destructive plan tools with reverts), and Profile writes (edit-profile, take-snapshot, progress-photo, weekly-report, community-vote) — each with tap-path, expected cloud table+cols, verify SQL, cleanup, and safe boundary. Saved verbatim at `tasks/wla233fst.output` (Profile+Coach) and `tasks/w6frqsqyb.output` (Nutrition+Train+Home+Coach). These are the contract-level coverage for the surfaces not individually clicked; the runtime-bug-likely ones were live-driven above (double-log, false-success, food-search, meal-log, diet-plan, weight) or flagged (NUT-02 overwrite, pauseRange).

## Cleanup record

- Rows created this session (all live-drive writes): `water_logs` (250ml, 2026-07-02); `user_custom_foods`
  (AuditFood0702); `user_custom_exercises` (AuditExercise0702); `workout_templates` (AuditTmpl0702) +
  `template_exercises`; coach workout log (`workout_log_exercises` ×2 after double-log + `workout_log_sets` ×6 +
  `workout_logs` "Chat Workout"); 3 `ai_coach_interactions` (1 workout + 2 food attempts); and today's
  `scheduled_workouts` status flipped `planned→completed` by the coach logSet.
- **ALL deleted / reverted; cloud re-verified 0 residual.** Final state: custom_foods=0, custom_exercises=0,
  workout_templates=0, template_exercises=0, water_logs=0, workout_log_*=0, nutrition_logs=0; today's schedule
  reverted to `planned` (completed count=0); ai_coach_interactions back to baseline **2**. Baseline intact:
  scheduled_workouts=28, weight_logs=1, rank_promotions=1, user_daily_snapshots=4; `referral_trial` sub untouched.
  (Template deleted in-app via its trash + confirm dialog; everything else via Supabase MCP DELETE, FK-safe.)
- **Local-Hive caveat:** because the app is offline-first, several test artifacts still live in THIS browser's local
  Hive (customBox AuditFood0702 + AuditExercise0702; today's workout marked done in the Daily-Goals ring; the doubled
  bench-press exlog). Cloud is clean, but a local→cloud sync (`syncCustomItemsNow` / `syncWorkoutData`) could re-push
  them. **Definitive fix: clear site-data for app.icanbefitter.com on this browser (or sign out/in) — local then
  restores from the clean cloud.** A fresh session on another device is unaffected. Harmless tagged test data on a
  test account regardless.
- **Round-2 cleanup (2026-07-02):** additional test writes (weight 76.5, UI meal "Roti and Dal" lunch + Banana snacks,
  saved diet plan) were deleted; cloud re-verified to baseline (nutrition_logs=0, weight_logs=1, saved_diet_plans=0,
  water_logs=0, coach=2, workout=0/0, scheduled=28/0-completed). **NOTE — the re-sync caveat is now CONFIRMED, not
  theoretical:** during round-2 a Nutrition write re-pushed the previously-deleted water + a coach interaction back to
  cloud (I re-deleted them). So the final cloud-clean state holds **only if no further writes happen on this dirty
  local session** — the founder should clear site-data / sign-out-in on this browser to make it durable.
- **DURABLE CLEANUP DONE (2026-07-02):** signed test7 out in-app (Profile › Sign Out › confirm → routed to Welcome).
  Session closed → no further writes can re-sync. Post-sign-out cloud verify = **exact pre-audit baseline**:
  nutrition_logs=0, nlog_items=0, weight_logs=1 (Jun-26), saved_diet_plans=0, water_logs=0, workout_log_exercises/
  sets/logs=0, custom_foods=0, custom_exercises=0, workout_templates=0, scheduled_workouts=28 (0 completed),
  ai_coach_interactions=2, user_daily_snapshots=4, referral_trial sub intact. Nothing re-synced during sign-out. On
  the next login test7 restores from this clean cloud.

## Recommended next steps (separate reviewed batch — NOT this session)

1. **P1 fixes (workout-domain):** (a) **coach dual-confirm double-log** — one confirm affordance per tool intent (or
   idempotent second APPLY); regression test that a single `logSet` intent writes exactly once. (b) `pauseRange` — route
   through `upsertScheduled` + broaden the aliased-`box.put` gate regex + behavioral test. (account-tier → ×2 review + B-pass.)
1a. **P2 (coach error UX):** the food-log "✓ Logged" card must NOT render when the tool call failed — gate the success
   card on the actual `ToolResult` status; re-test food-logging-via-coach (NEEDS RE-TEST — failed 2/2 live, likely transient).
2. **P2 SoT/coverage:** register `custom_food` + `notifications_inbox` concepts with behavioral tests;
   correct the stale `exlog_` key formula, the `syncOnboarding`/`saveMeal`/`deleteWithUndo`/`logWater`
   name drift, and the stale line-refs; decide on `health_sync_enabled` scoping; delete dead
   `NutritionWriteService.logWater` + dead `TermsModal`.
3. **APK/device pass** (already gated): confirms native-only surfaces + the founder-priority write paths
   live on Android; ship C3 single-call restore + OBS-6 to Android.
