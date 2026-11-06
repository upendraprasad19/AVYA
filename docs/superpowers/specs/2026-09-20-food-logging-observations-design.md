# Design — Food Logging & Nutrition UX Observations Batch

- **Date:** 2026-09-20
- **Branch:** `claude/food-logging-observations-126ab3`
- **Status:** drafted from founder brainstorm (decisions locked live in chat) — awaiting founder review of this doc
- **Origin:** founder manual testing session, 8 raw observations across Nutrition/Diet Plan/cold-start (obs 3 was submitted with no content and is dropped — nothing to investigate)
- **Blast-radius (expected):** `account` — Part G touches `ai-proxy`/`_shared/gemini.ts` (an Edge Function on the CLAUDE.md §4.3 always-≥account list) → ×2 plan review + B-pass required before `--no-ff` merge. Parts A-F are individually `feature`-tier but ship in the same batch/branch.

## Problem statements (verified against source + live Supabase logs, file:line cited)

1. **No retag.** A logged meal can't be moved to a different slot (breakfast→lunch etc.); the Edit Macros sheet (`nutrition_screen.dart:948-1060`) only edits macros. The Hive key embeds `meal_type` (`nutrition_write_service.dart:787-795`, `nlog_<date>_<mealType>_<hash>`) and the cloud natural key is `(user_id, date, meal_type)` (`sync_nutrition.dart:274`) — a prior bug (diagnose `c9f2a7`) shows a key/field mismatch here causes a Postgres FK violation (23503). A naive field-only update would reintroduce that class.
2. **Diet-plan slots look logged.** `todays_meals_card.dart` distinguishes populated (`:117-334`, solid border/background) from planned-only (`:366-376`, dashed border) slots by border style alone; the food-name text itself renders at the same weight as a real log.
3. **Scan Meal "failed" instantly.** `scan_meal_section.dart:282-283` calls `ImagePicker().pickImage(source: source)` with no `imageQuality`/`maxWidth`. `ai-proxy/index.ts:517-518` rejects any base64 payload >7.5M chars (≈5.6MB decoded) with an immediate `400`, before ever calling Gemini. Confirmed live: 5× `400` on `ai-proxy` at 2026-09-19T16:38-16:39 UTC (22:08-22:09 IST), matching the founder's screenshot exactly. **Same bug exists in `cart_auditor_section.dart:170-171`** (identical `pickImage` call, same server-side cap, same 20/day shared budget) — same root cause, fixed together, not deferred.
4. **"AI is offline (502)" on food-text analysis.** Confirmed via live Supabase logs (`function_logs`, 2026-09-20T04:01 UTC = 09:31 IST, exact timestamp match to the founder's screenshot): both `gemini-2.5-flash` AND its fallback `gemini-2.5-flash-lite` returned `HTTP 429 "You exceeded your current quota, please check your plan and billing details"` simultaneously. **Still recurring as of 04:14 UTC today** (35 min before this write-up) — an ongoing quota condition, not a one-off. `gemini.ts:260-311` (`_callOnce`) collapses every Gemini failure mode (429 quota, 400/403 billing/key, safety block, genuine 5xx, timeout) into an identical `{content:null}`, and `index.ts:435-442`/`:599-601` turn that into a synthetic `502` — the real reason is logged to the ephemeral Edge Function console (`gemini.ts:266-268`) and never persisted or surfaced.
5. **Two log-food sheets, two different tab sets — confirmed drift, not a design decision.** `LogFoodSheet` (5 tabs: AI/Scan/Cart/Barcode/Search, `log_food_sheet.dart`) was built 2026-04-26; `LogToSlotSheet` (3 tabs: AI/Scan/Search, `log_to_slot_sheet.dart`) was built 2 days earlier and never touched again (single commit in `git log`). No comment, diagnose-doc, or commit message anywhere argues Cart/Barcode shouldn't apply per-slot.
6. **Cold start >10s.** Not a regression (no relevant commits in 2 weeks; the known fire-and-forget paths from diagnose `7ad0c7` are still correctly unawaited). Real, additive cost: splash has a built-in 3s floor / 12s ceiling (`splash_screen.dart:111-115`), then the returning-user fast path in `restoring_screen.dart` still blocking-awaits `HiveUserSession.openForUser`, which opens **7 user-scoped Hive boxes sequentially** (`hive_user_session.dart:178-190`) — unlike the 5 shared boxes, already parallelized (`hive_service.dart:82`).
7. **Diet Plan screen shows a blank spinner behind a "Saved Diet Plan Found" dialog.** `diet_plan_screen.dart:40-68`: the saved plan is read synchronously from local Hive (no `await` anywhere in the chain) and then gated behind a dialog instead of rendered. The screen's AppBar **already has persistent Regenerate (`:498-502`, refresh icon → `_generateFreshPlan()`) and Save (`:514-520`, → `_savePlan()`) actions** — the dialog is redundant with UI that already exists.

## Founder decisions (locked in brainstorm)

| # | Decision | Choice |
|---|---|---|
| 1 | Obs 1 retag UX | Add a meal-slot selector into the existing Edit Macros sheet (not a separate long-press action) |
| 2 | Obs 5 sheet fix | Consolidate into one shared widget — retire `LogToSlotSheet` |
| 3 | Obs 8 diet plan | Show the saved plan immediately, no modal, using the existing toolbar Regenerate/Save actions |
| 4 | Obs 2/6 error handling | Fix the scan-image bug outright. For Gemini failures: user-facing message stays generic; add persisted telemetry; **admin gets a Telegram alert with the exact reason + a suggested fix** |

## Part A — Nutrition log retagging (obs 1)

**Write path.** Add `NutritionWriteService.moveMealLog({required String logKey, required String newMealType, Map<String, dynamic>? macroUpdates})`, mirroring the existing precedent `WorkoutWriteService.moveExerciseLogs` (`workout_write_service.dart:728-854`): compute the new key via the canonical `computeLogKey` helper (`nutrition_write_service.dart:786-795`) with `newMealType` substituted, read the existing Hive row, apply `macroUpdates` if present, write it under the new key, delete the old key. **Verified against the existing `deleteLog` (`:362-439`)/`editLog` (`:292-352`) precedent: neither issues an explicit cloud delete — both just mutate Hive and call the general `unawaited(SyncService.instance.syncNutritionData())` fan-out**, which upserts by natural key `(user_id, date, meal_type)` (`sync_nutrition.dart:296-314`, `id` deliberately omitted per diagnose `c9f2a7` so no PK-rewrite/FK risk exists for the NEW slot's upsert). So `moveMealLog` follows the SAME pattern — rekey locally, call the existing sync fan-out — and inherits the SAME accepted residual `moveExerciseLogs` already documents explicitly (local-only; the vacated old-slot cloud row is not tombstoned). Document this identically in `moveMealLog`'s doc comment (mirroring `workout_write_service.dart:722-727`'s wording) rather than inventing a stronger cloud-consistency guarantee than every other write path in this file already provides. Add this concept to `docs/sot_registry.yaml` as `nutrition_log_retag` with its own `behavioral_test_path`.

**UI.** Edit Macros sheet (`nutrition_screen.dart:948-1060`) gains a segmented meal-type selector (Breakfast/Lunch/Dinner/Snack) alongside the macro fields, defaulted to the log's current slot. SAVE checks whether the slot changed: unchanged → existing `editLog` path (macros only, no rekey). Changed → single `moveMealLog(logKey, newMealType, macroUpdates: {...five fields...})` call that rekeys AND applies any macro edits atomically in one write — never two separate writes for one SAVE tap.

**Test:** `test/contracts/nutrition_log_retag_writer_to_reader_test.dart` — move a log, assert old key gone, new key holds it under new `meal_type`, `TodaysMealsCard` groups it under the new slot, cloud upsert targets the new natural key.

## Part B — Diet-plan slot visual distinction (obs 7)

Strengthen `_EmptySlotCard`'s planned-hint rendering (`todays_meals_card.dart:418-447`) beyond the dashed border: add a small "SUGGESTED" chip (mirroring the visual vocabulary Train already uses for state, `day_card.dart:43-116`, rather than inventing a new one) and render the planned food-name/kcal text visibly dimmer/lighter weight than a real logged item's text, so the two are not confusable at a glance. No data-model change — purely `todays_meals_card.dart`.

## Part C — Log-food sheet consolidation (obs 5)

Retire `log_to_slot_sheet.dart`. Extend `LogFoodSheet` (`log_food_sheet.dart`) with an optional `lockedSlot` parameter: when present, the sheet title becomes "LOG TO {SLOT}" and any successful log call passes that slot through instead of leaving it unset. **All 5 tabs (AI/Scan/Cart/Barcode/Search) become available from both entry points** — the investigation found no recorded reason Cart/Barcode don't make sense per-slot, so the default on consolidation is parity, not re-deciding which tabs belong where. `nutrition_screen.dart:294-295`'s `onLogSlot` callback switches from `LogToSlotSheet.show` to `showLogFoodSheet(context, initial: LogFoodMode.ai, lockedSlot: slot)`.

**Test:** widget test asserting both entry points render from the same `LogFoodSheet` class with the same 5-tab set; `LogToSlotSheet` deleted, not left as dead code.

## Part D — Diet Plan screen: remove blocking modal (obs 8)

`diet_plan_screen.dart:49-68` (`_generatePlan`): when `getSavedDietPlan()` returns non-null, call `_loadSavedPlan(savedPlan)` directly instead of `_showLoadSavedPlanDialog(savedPlan)`. Delete `_showLoadSavedPlanDialog` (`:300-349`) entirely — it becomes dead code once nothing calls it. The existing AppBar Regenerate (`:498-502`) and Save (`:514-520`) icons already satisfy "user can regenerate/save" with no dialog needed. First-time users with no saved plan still fall through to `_generateFreshPlan()` exactly as today.

**Test:** widget test — with a saved plan in Hive, `DietPlanScreen` renders the plan content on the first frame with no dialog present.

## Part E — Cold-start Hive box-open parallelization (obs 4)

`hive_user_session.dart:178-190`: change the sequential `for` loop opening the 7 user-scoped boxes to `Future.wait(...)`, mirroring the existing parallel pattern already used for the 5 shared boxes (`hive_service.dart:77-82`). Low-risk, additive — no box has a documented ordering dependency on another (confirm during implementation by reading each box's adapter registration; if one genuinely depends on another being open first, exclude only that one from the `Future.wait` and note why inline). Splash's 3s floor / 12s ceiling (`splash_screen.dart:111-115`) is left as-is — it looks like a deliberate branding/animation minimum, not a bug; flag to founder if that's wrong.

**Test:** extend or add a startup-timing contract test asserting the 7 user-scoped boxes open concurrently (e.g. assert wall-clock ≈ max(box-open times) not sum).

## Part F — Fix scan/cart image size (obs 2)

`scan_meal_section.dart:282-283` and `cart_auditor_section.dart:170-171`: add `imageQuality` (e.g. 85) and `maxWidth`/`maxHeight` (e.g. 1600px) to both `pickImage()` calls, so a full-res camera photo is downscaled client-side before base64 encoding — keeping it well under ai-proxy's ~5.6MB decoded cap. Also add `ErrorTelemetry.recordNonFatal` to `ScanMealNotifier.scanImage`'s catch block (`nutrition_provider.dart:1421-1426`), which today has **zero** client-side telemetry on failure — the gap the investigation found while explaining why this bug went undiagnosed for a while.

**Test:** unit test asserting `pickImage` is invoked with a `maxWidth`/`imageQuality` constraint (source-grep-class, presence-only — pair with the existing manual-QA smoke test since `ImagePicker` itself isn't mockable at the byte-size level cheaply); the telemetry addition gets a behavioral test via the existing fault-injection seam pattern (`ai_breakdown_notifier_save_meal_telemetry_test.dart` is the precedent to mirror).

## Part G — Gemini failure classification + admin Telegram alert (obs 6, server-side)

**Capture the real reason.** In `_shared/gemini.ts`'s `_callOnce`/`geminiChat`, thread the last-attempt's real HTTP status + a truncated error body up through the return value instead of collapsing to `{content:null}` alone (e.g. `{content:null, lastError:{status, message}}`).

**On terminal failure** (all models in `ai-proxy`'s attempt list exhausted — today's synthetic-502 case, both in `food_text_analysis` at `index.ts:435-442` and `scan_meal`/`cart_auditor` at `:599-601`): insert a row into the existing `public.alerts` table (schema already live: `source, severity, summary, context_json, suggested_action` — `076_alert_detection_crons.sql:14-25`) with:
- `source = 'ai_proxy_gemini_exhausted'`
- `summary` = the captured real status + message (e.g. `"gemini-2.5-flash + gemini-2.5-flash-lite both HTTP 429: quota exceeded"`)
- `suggested_action` classified by status: 429 → "Check Gemini quota/billing on the Google Cloud project owning GEMINI_API_KEY — a recharge doesn't always attach to the right project or raise RPM limits"; 401/403 → "Check the GEMINI_API_KEY secret is valid"; 5xx/timeout → "Likely a transient Gemini-side outage — no action needed unless it persists"
- `severity = 'critical'` **only if** no unresolved `critical` alert with the same `source` exists in the last 30 minutes (a lightweight dedup query before insert) — otherwise `severity = 'warn'` (still visible in the founder's existing daily digest, just doesn't re-ping Telegram for every request in a quota storm)

This reuses the **existing** `trg_dispatch_critical_alert_notify` trigger (`133_alert_critical_notify_trigger.sql`) and `alert-critical-notify` function unchanged — no new Telegram wiring, no new secrets. Client-facing error message is unchanged (`nutrition_provider.dart:852-854`, `scan_meal_section.dart`'s generic string) — this is a server-only, additive change.

**Test:** `supabase/functions/ai-proxy/index_test.ts` (Deno) — a terminal Gemini failure inserts exactly one `alerts` row with the classified `suggested_action`; a second terminal failure within the dedup window inserts `severity='warn'` not `'critical'`; `deno check --node-modules-dir=none` before commit.

## Error handling

All new UI surfaces (retag selector, consolidated log sheet) follow the existing loading/error/empty pattern (§4.4 rule 13) already established by their host screens — no new empty/error vocabulary introduced.

## Testing & verification

- Every part lands with a behavioral regression test per CLAUDE.md §4.4 rule 21 (mutation-proven where a new gate-shaped guard is added — Part G's dedup check is the one candidate).
- Diagnose-docs per rule 22 for the two genuine *bugs* (Part F image-size, Part D modal) — Parts A/B/C/E are feature/consolidation work, not bug fixes, so they don't need a diagnose-doc but do need SoT registry entries where a new writer/reader contract is created (Part A).
- `flutter analyze` + targeted `flutter test` during dev; `deno check` for Part G before commit; pre-push (≥account, since Part G touches `ai-proxy`) runs the full suite.
- Part G needs the standard live-deploy authorization (§4.3) — separate from merge approval — before `ai-proxy` is redeployed.

## Sequencing

1. Part F (scan/cart image fix) — smallest, most clearly a bug, no dependencies.
2. Part D (diet plan modal removal) — small, independent.
3. Part B (visual distinction) — small, independent, same file family as Part A.
4. Part A (retag) — touches `NutritionWriteService` + sync; do after B since both touch `todays_meals_card.dart`.
5. Part C (sheet consolidation) — independent of A/B, touches `nutrition_screen.dart`'s slot callback which Part A's UI also touches (Edit Macros sheet is separate from the log-food sheet, so low collision risk, but sequence after A to avoid two people/passes touching `nutrition_screen.dart` simultaneously).
6. Part E (box-open parallelization) — independent, different feature area (auth/splash).
7. Part G (Gemini alerting) — server-side, independent of all client work; do last since it needs its own ×2 review + B-pass + live-deploy approval, and is the only part that changes the batch's blast-radius to `account`.
8. End of batch: ×2 plan review + B-pass (triggered by Part G), `--no-ff` merge to main, founder-authorized `ai-proxy` redeploy.

## Explicitly out of scope

- Splash's 3s floor / 12s ceiling timing — left as-is (looks intentional); revisit only if founder says otherwise after seeing Part E's improvement.
- Investigating *why* the Gemini project is hitting 429 quota (billing account linkage, RPM tier) — that's a founder-side Google Cloud/AI Studio action, not a code fix; Part G's alert is designed to make that diagnosis fast next time, not to fix the quota itself.
- A second Gemini API key/project as an automatic failover — not requested; would be a separate scope decision if the quota issue recurs after the founder checks their billing.
- Retagging a log to a different **date** (only meal-slot retag was requested).
