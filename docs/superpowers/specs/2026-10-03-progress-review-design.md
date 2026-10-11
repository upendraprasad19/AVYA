# Design — Progress Review: a coach-owned, computed-numbers view of the user's journey

**Version:** v3.2 (2026-10-11 — status and OQ-L2a only, no design change: L1 and L2a have merged, this document lands on `main`) · v3.1 (2026-10-06 — founder decisions 5–10 recorded; no design change beyond them) · v3 (2026-10-04). v1 → round 1 (lenses A ground truth, B data/sync, C AI/safety, D process) → v2 → round 2 (R2-A ground truth, R2-B L3 mechanics, R2-C L1/L2/L4, R2-D process/policy) → **v3**. All eight reviews returned `needs-changes`; every finding is dispositioned in §10 (round 1) and §12 (round 2).
**Branch / worktree:** written on `coach-progress-review` (base `origin/main` `4fef03a7`); landed from `progress-review-spec-board` (base `main` `fdd89da6`). Code and live facts below are as of `4fef03a7` and 2026-10-03/04 unless a row says otherwise. Line numbers have moved since L1 and L2a merged; each landing plan re-verifies the ones it uses.
**What this document is:** the **umbrella design** for four landings (the optional fifth, effort capture, was declined — §8). It is NOT a landing plan. Each landing writes its own short plan citing this document, and that plan gets its own §4.12 ×2 review + record. The umbrella rounds do not count toward any landing record's `review_rounds` (§9).
**OIs:** L1 = OI-296, OI-307, OI-308 (+ OI-312, OI-313, OI-218, OI-269 found while planning, §9) · L2 = OI-297, OI-304 (sibling pushes, latent: OI-332) · L3 = OI-299, OI-300, OI-306 · L4 = OI-210 · decided, kept open by the founder: OI-298 (§8), OI-305 (§7) · gate on L3's migration apply: OI-310 (privacy policy).
**Status:** umbrella design; the landing order was approved by the founder on 2026-10-06. **L1 merged:** L1a-1 (PR #92; migration 155 applied live 2026-10-07), L1a-2 (PR #96), L1a-3 (PR #97), L1b (PR #93; five Edge Functions deployed 2026-10-09). **L2a merged:** PR #99, 2026-10-11. **Not started:** L2b (sheet, flag, entry points), L3, L4. The checks still open on the board and in the closure ledgers (device checks, deploy checks) are founder-owned.
**Blast radius:** every landing is at least `platform` (`blast_radius.yaml:54-63,421`); L3's migration is `catastrophic` by filename (§3). Each landing classifies its real diff with `scripts/blast_radius_from_diff.dart` (fails open on paths that do not exist yet — write first, then classify).
**Format:** the founder's 7-section Feature Spec Template (`SPEC_TEMPLATE_BRAINSTORM.md`, untracked in the shared main folder; its hook is undeployed) + this repo's spec header.

---

## Founder decisions on record

| # | Decision | Exact source |
|---|---|---|
| 1 | "The forecast is then no longer a separate feature. It becomes the coach's job, backed by computed numbers." | founder: "correct" (2026-10-03). HOW (retirements, copy, timing) is this document's **proposal** — L4, OQ-L4a/b. |
| 2 | Measurement scope A: the four existing sites (waist, chest, hips, arms); no cloud schema change for measurements. | founder: "A" |
| 3 | Measurement entry: one sheet + Home "due" prompt + link in the Weight sheet + Progress Comparison + a chat chip that opens the sheet + a skippable week-1 baseline prompt; not PRO-gated. | founder: "go" (surfaces corrected in L2 to ones that actually render) |
| 4 | Update the plan and run a second review before deciding the split, effort capture and young users. | founder, 2026-10-04 |
| 5 | OQ-S: four landings in order L1 → L2 → L3 → L4; start the L1 plan. | founder: "1. yes" (2026-10-06) |
| 6 | OQ-E: effort capture (RIR) left out — "RIR will become too intimidating for beginners"; kept as an OI (OI-298) to pick up later. No L5. | founder (2026-10-06) |
| 7 | OQ-Y: keep the current age rules (status quo, option C). | founder: "keep things as they are now" (2026-10-06) |
| 8 | OQ-L3a: free = one lifetime review, PRO = one per IST month; `getAthleteState` free. | founder: "ok" (2026-10-06) |
| 9 | OQ-L4a: paywall copy "Monthly Progress Review"; OQ-L4b: server stops serving old-APK predictions after the flip APK reaches most active users (threshold set by the founder at that time). | founder: "yes to both" (2026-10-06) |
| 10 | OQ-L3d (consent): founder asked the coordinator to check. Finding: the app's policy links point at the blog's newsletter policy, which describes no app data at all (OI-310). The L3 migration apply waits on OI-310. | founder: "not sure can you check" (2026-10-06) |

**Still open for the founder (§11):** mixed-device measurement guard (OQ-L2a), safety thresholds (OQ-L3b, at L3 plan time), retention (OQ-L3c), the app privacy policy (OQ-L3d → OI-310), names (OQ-N).

Carried constraints (readiness spec `2026-09-01-…-design.md` §2): **#1** the post-workout completion screen takes no data collection; **#6** no new evening push.

---

## Section 0 — Discovery pass (confirmed facts)

Code facts verified at `4fef03a7` by the coordinator and the round-2 reviewers. Live facts are the coordinator's read-only SELECTs (2026-10-03/04).

| # | Fact | Evidence |
|---|---|---|
| F1 | Coach history tools: `getProgressSummary`, `getExerciseHistory` (PRO), `getPromotionStatus`, `getPRTimeline`, `getNutritionHistory`; tool loop ≤ 3 rounds. | `tool-loop.ts:70`; `ai.md:47-55` |
| F2 | Unpaged reads: `getProgressSummary` 5 selects in `Promise.all` (`:55-91`); `getNutritionHistory` logs ordered by non-unique `date` (`:106-114`) + items `.in("log_id", ids)` unchunked (`:123-126`; ~100-uuid URL limit per `paged_fetch.ts:74-81`; no range cap in the schema `:160-179`, so a ~30+ day per_day call fails); `getPromotionStatus` 365-day `workout_logs` (`:160-168`); `getPRTimeline` `.limit(50)` (`:75`); `getExerciseHistory` (`:49`). | file:line |
| F3 | PostgREST returns at most 1,000 rows per request with HTTP 200 and no signal; `.range()` cannot raise it; correct reads page on a unique order (`paged_fetch.ts:1-31`). | file |
| F4 | Live scale: 42 users; `workout_log_sets` 553 (heaviest user 513); `body_measurements` 0; `sleep_logs` 0; `workout_logs.rpe` non-null 0; longest span 153 days. The cap is latent today. | SQL |
| F5 | Measurement entry is chat-only (`<ICBF_LOG>` → `conversational_log_handler.dart:154-170` → `HealthWriteService.logMeasurement` `:209`, its only caller). No measurement reader in `HealthReadService`. | file:line |
| F6 | The four-site list is hard-coded in 8 places (`conversational_log_handler.dart:158`, `ai_coach_provider.dart:1616`, `ai_snapshot_builder.dart:1622`, `sync_service.dart:2470`, `sync_health.dart:278-281`, `ai-proxy/index.ts:983`, `ai-media-proxy/index.ts:735`, DDL `004`). Other vocabularies: `044_user_stat_snapshots.sql:24` (`arms_l/arms_r/thighs_*`); a Telegram writer (`sync_service.dart:2477-2480`). | file:line |
| F7 | **(corrected in v3)** Push sends all four sites AND `notes`, nulls included (`sync_health.dart:276-283`). **Restore** skips dates already in Hive (`:508`). **Pull** (`sync_service.dart:2452-2482`, last-24h rows) fills only locally-null sites; a local non-null wins. So: a device pushing nulls blanks other devices' cloud values; a same-day edit on device B never reaches device A's Hive; A re-pushing can overwrite B's newer value. | file:line |
| F8 | Weight entry: Home quick action → `WeightLogSheet` (`home_screen.dart:675-680`). | file:line |
| F9 | No effort data (`workout_write_service.dart:563` forwards `rpe` only if given; nothing gives it). No warm-up flag writer. | file:line; SQL |
| F10 | Exercise identity is the display name. `workout_log_id` is one deterministic id **per IST day** (`wlog_<istDate>`, `sync_workout.dart:279`), not per session; text in `workout_log_exercises`, uuid in `workout_log_sets`. Library names are unique live (292 of 292, case-insensitive) but have no unique constraint; custom exercises are unique on `(user_id, lower(name))` (`057:35-36`). Soft-delete exists only on `workout_log_exercises`; deleted rows carry a suffixed `exercise_id`. | SQL; file |
| F11 | `nutrition_logs` unique per `(user_id,date,meal_type)`, per-meal totals. `nutrition_log_items` has no `user_id`/`date` column. | file; `live_schema_columns.json:253-265` |
| F12 | No server record of goal changes (OI-306): `goal_changed_at` Hive-only (`tool_dispatcher.dart:1298`); `primary_goal_updated_at` one reader (`ai_snapshot_builder.dart:1605`), no writer; 0 of 292 `user_daily_snapshots` rows non-null. | grep; SQL |
| F13 | Profile Predictions = `PredictionService._regenerate` → `AiService.predict` (`ai_service.dart:422-431`) → `ai-proxy` `type:"prediction"` (`index.ts:778`) → Gemini; 3 per IST day on `prediction_daily`. `future-prediction` has no caller (OI-210). | file |
| F14 | Five forecast computations: LLM text; `future-prediction`; `reports_screen.dart` `_buildProjectionCallout` (`:816-880`); `journey_timeline.dart` (`:40-63`); `BmrCalculator.projectGoalDate` (`bmr_calculator.dart:258`, shown at `nutrition_screen.dart:545`, `nutrition_targets.dart:19`, `pace_detail_sheet.dart:11`). | file:line |
| F15 | Prediction surface: the minimum inventory is in L4; L4 also runs a full `git grep -i predict` inventory. | grep |
| F16 | Home mounts `_buildStreakWarning`, `_buildExpiryBanner`, `_buildRepeatNudge` (`home_screen.dart:468-470`). `InsightCard`/`DeepAnalysisCard` are never instantiated (OI-304). | grep |
| F17 | Quick-prompt chips call `_sendMessage` (`quick_prompts.dart:26`, a `part` file) and render only when `messages.length <= 1` (`ai_coach/screen.dart:505`); `contextualPromptsProvider` is `Provider<List<String>>` (`ai_coach_provider.dart:1440`). | file:line |
| F18 | `usage_counters` / `refund_quota` / `DIGEST_KEYS` do not fit this feature (nightly 7-day cleanup; refund only for chat-family channels; set-equality test). `weekly-report` consumes after insert, PRO unmetered (`index.ts:690-725`). | live; file |
| F19 | `asPrincipalMessage` is identity (`sanitize_for_prompt.ts:331-333`); tool results go back raw (`tool-loop.ts:532`); `byName` ignores tier (`registry.ts:97-100`) but execution re-checks tier (`tool-loop.ts:420`) and capability (`:446-458`) — a real hook. `CAPTAIN_MANUAL` is shared with `weekly-report` (`weekly-report/index.ts:5,446`); `captain_manual.ts:373-384` says forecast tools come "in a future batch". | file:line |
| F20 | `privateMode` is never set (0 of 42); all `coach_memory` consent rows `v1`. | file; SQL |
| F21 | DOB pickers: onboarding floor 10 (`identity_screen.dart:82`; lowered from 13 after a user could not enter his son's 2019 DOB, `:77-81`), Edit Profile 13 (`edit_profile_screen.dart:676`). Live: 0 under 18, youngest 24; one profile has no DOB. | file; SQL |
| F22 | `gate()` deprecated → `gateAndVerify`. `prediction_monthly` is in `allProFeatures` (`subscription_service.dart:103`) with no gate call. New Hive keys must join `UserConfigMigrator.userScopedKeys`. `units_metric` is device-level `configBox`. | file:line |
| F23 | MEV 8 / MRV 20 are private constants in `volume_titration.dart:45-46` (plan_engine — not importable). | file |
| F24 | **Duplicate live summary rows (OI-307):** summary `set_number` = set count and is in the conflict key (`sync_workout.dart:379,481-484`; `082:34`), so a set-count change after sync leaves a second live row. Live: 44 groups / 99 rows / 1 user. Readers without dedupe include all four `workout_log_exercises` tools, `weekly-report:217`, `i-see-you-callout:230`, `pr-detection:88`. | file; SQL |
| F25 | **Exercise-log `completed_at` is the last-write time**, not the workout day: exlogs carry `updated_at_ms` (`workout_write_service.dart:207-220`), `editLog` re-stamps it (`:1136`), sync resolves `completed_at` from it (`sync_workout.dart:592-597`). The true day is the `wlog_<istDate>` id. | file:line |
| F26 | **Triple-counted volume (OI-308):** `getExerciseHistory.ts:88,95` = weight × reps × sets; `reps` is cumulative (`getProgressSummary.ts:114-123`). UTC day slicing also at `getExerciseHistory.ts:42,90`, `getPRTimeline.ts:77,78,114`, `getPromotionStatus.ts:136`, `getProgressSummary.ts:29,38`. | file:line |
| F27 | **No force-update mechanism** exists (no min-version check in `lib/` or `supabase/functions/`): a server change reaches every installed APK at once. | grep |
| F28 | `GeminiResult` does not expose `finishReason` on success (`gemini.ts:295-330,600-605`). One `geminiChat` pass = primary + fallback at 40 s each; the retry deadline is checked only between passes (`:367-447`). | file:line |
| F29 | Experience: `setDetectedExperience` (`user_repository.dart:649`) has no caller; the live source is `user_progress.detected_experience_level` (`weekly-recalc/index.ts:380`); the snapshot alias defaults to `'beginner'` (`ai_snapshot_builder.dart:123`). The set logger has no "exercise complete" event (`active_workout/exercise_card.dart:640-650,716-721`). | file:line |
| F30 | The founder digest still meters `prediction_daily` (`founder_digest_content.ts:42,100,287`), pinned by `founder_digest_caps_mirror_test.dart:376`, `founder_digest_content_test.ts:308-317`, `founder-digest/index_test.ts:1216-1231`. | file:line |

---

## Section 1 — Problem & goal

**User:** the Avya user (22–35, India), free and PRO.

**Problem.** A user six months in asks the coach for an overall verdict and gets a partial — and partly wrong — one: (1) the coach's history tools carry live correctness bugs (silent 1,000-row cap, duplicate summary rows, triple-counted volume, edit-time and UTC day boundaries — F2, F24–F26); (2) body-change and effort data is not collected; (3) nothing computes a multi-month picture, so a thinking-off model assembles raw rows; (4) the forecast is an ungrounded LLM guess, and four other forecast computations disagree.

**Goal.** Fix the reads (L1); collect measurements (L2); compute a deterministic **athlete state** and **findings**, and let the model *word* them without ever writing a number (L3); one honest forecast (L4).

**Measurable outcome.** For a user with ≥ 90 days of logs, one tap yields a review in which no number was written by the model (mechanically enforced, L3.4). Tracked after launch (targets set by the founder after 30 days): users with ≥ 2 measurement entries ≥ 14 days apart (today 0); reviews per 30 days; template-fallback share.

---

## Section 2 — Non-goals / guardrails

- Effort capture — founder decision (§8); the athlete state reports `effort: "not_collected"` until then.
- Wearable HRV/RHR; photo analysis; body-fat estimation.
- Deleting measurements: `upstream_blocked` on OI-280's tombstones; a same-day re-entry overwrites the edited sites.
- Goal-change segmentation of the review (OI-306 adds the writer in L3; segmentation is not designed here).
- Any new push; any collection on the post-workout screen; changes to the readiness sheet, chat model or chat caps.
- `weekly-report` behaviour is unchanged **except** the shared `CAPTAIN_MANUAL` text, edited in the L3 tool-flip commit and pinned there by a weekly-report prompt test (F19).
- Must not touch: `plan_generator.dart`, `plan_engine/**` (constants mirrored by value + a text-reading parity test, F23); payment, `delete-account`, `admin-*`.
- ADR-0012: every new tool is read-only.

---

## Section 3 — Data model

| Landing | Schema / live data change |
|---|---|
| L1 | OI-307: either (a) the sync tombstones the superseded summary row in the same sync (no schema change), or (b) a migration re-keys the summary row on `(user_id, workout_log_id, exercise_id)`. The L1 plan picks one with evidence. Either way a **live dedupe** of the 44 existing groups (a live write; its own founder go). |
| L2 | none (decision 2). OQ-L2a records the founder's call on a server-side merge guard. |
| L3 | `progress_reviews` table + `athlete_state_rows()` function in a migration named `NNN_progress_reviews_rls.sql` (the `*_rls.sql` glob makes it `catastrophic`, so hermes + rollback are gate-enforced). Applied live **only after** the L3 plan converges ×2, the drafted migration file passes B-pass + hermes, and OI-310 (an app privacy policy covering health data and AI processing) is published; then before L3's code commit (Gate 14, `check_schema_column_refs.dart`). |
| L4 | none. |

```sql
-- L3 sketch (final DDL in the L3 plan; number via scripts/mint_migration.sh; rollback documented).
create table public.progress_reviews (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.users(id) on delete cascade,  -- erased with the account
  period_key    text not null,            -- 'free_lifetime' | 'pro_YYYY-MM' (IST month)
  status        text not null check (status in ('pending','ready')),
  attempt_id    uuid not null,            -- ownership token; set on insert and on take-over
  attempts      smallint not null default 1,   -- cap per period (L3.6)
  window_from   date, window_to date,
  goal_at_review text,                    -- FitnessGoals token
  state_json    jsonb, findings_json jsonb,
  review_json   jsonb,                    -- items {finding_id, text-with-placeholders}; values typed + unit-tagged
  forecast_json jsonb,
  source        text check (source in ('model','template')),
  model_used    text, tokens_used integer,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (user_id, period_key)            -- the quota
);
-- RLS: SELECT own rows WHERE status='ready'. No client INSERT/UPDATE/DELETE.

-- Read-only aggregation. SECURITY INVOKER, search_path pinned,
-- REVOKE EXECUTE FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO service_role (migration 130 precedent).
-- Every subquery filtered by p_user. Returns one jsonb (no 1,000-row cap). Domains:
--  weight (daily), measurements; workout days by IST day taken from workout_log_id ('wlog_<date>');
--  per-day per-exercise best set + set count from workout_log_sets, live-ness by EXISTS on a live
--  workout_log_exercises row (semi-join, never a row-multiplying join — F24);
--  exercise→muscles via exercise_library (one row per lower(name)) else user_custom_exercises (user_id, lower(name));
--  scheduled_workouts (non-rest, non-paused) for adherence; nutrition_logs per-day totals (never items);
--  sleep/steps/water/readiness per day; user_profile (date_of_birth, height_cm, target_weight_kg,
--  daily_calories, protein_grams, primary_goal); user_progress.detected_experience_level.
create function public.athlete_state_rows(p_user uuid, p_from date, p_to date) returns jsonb ...;
```

**Client (Hive, userBox via `MigratedKey`, all added to `userScopedKeys`):** `progress_review_latest`, `measurement_due_dismissed_at`, `measurement_baseline_skipped`. They live in userBox; the `measurement_` scans at `ai_snapshot_builder.dart:1614` and `sync_health.dart:267` read healthBox only — the glossary gets a note.

---

## Section 4 — Landings

### L1 — Coach history correctness (OI-296, OI-307, OI-308)
A live bug-fix landing: ≥ 4 defects ⇒ `docs/audit/<branch>.closure.yaml` (Gate 40); a diagnose-doc per defect; OI-308 takes the FULL template (recurrence of APK Test #12.6).
1. **Paging:** each long read pages with `.range()` at ≤ 1,000 rows ordered by a unique key (`date, id`), up to N pages; `truncated: true` only when the last allowed page is full. Count-only needs use `count: 'exact', head: true`. `getNutritionHistory` item ids are chunked (≤ 100 per request). Measured latency recorded in the plan against each tool's `maxLatencyMs`.
2. **Day = the workout day:** exercise rows are bucketed by the `wlog_<istDate>` id (fallback IST(`completed_at`)); every UTC slice in F26 replaced with `_shared/ist_date.ts`.
3. **Duplicates:** readers dedupe summary rows per `(workout_log_id, exercise_id)`; the writer stops creating them (§3 L1 row); the live dedupe runs with its own go. The L1 plan measures each server reader in F24 and fixes every one that counts or sums summary rows.
4. **Volume:** `getExerciseHistory` volume = weight × cumulative reps (OI-308).
5. `getNutritionHistory` no longer reads items for `aggregation: "total"`.
6. Tool `description` strings stay byte-identical (a description change would be an AI-prompt change under §4.6).
Ripple (repoint, never loosen): `get_progress_summary_parallel_queries_test.dart:38-72`, `get_progress_summary_math_test.dart`, `unit_c_read_hardening_test.ts:88-98`, `get_nutrition_history_tool_test.dart:33-37`, `sync_onconflict_natural_key_test.dart`. Fixtures: > 1,000 rows; two live summary rows for one (log, exercise); delete-then-re-log same day; an old log edited today; 00:15 IST; a 60-day per_day nutrition range. Every new test mutation-proven.

### L2 — Measurement entry (OI-297, OI-304)
- **L2a — merge-safe push, ungated (bug fix) — MERGED 2026-10-11 (PR #99; plan `docs/plans/coach-measurement-entry-l2a.md`):** omit null sites **and** null `notes` from the payload — a correctness fix to the existing writer, shipped without the UI flag so every new APK stops blanking values. Residual, recorded in OI-297: old APKs and the out-of-repo Telegram writer still send nulls, and a same-day edit does not reach a device that already holds the date (F7). OQ-L2a records the founder's call on a server-side guard.
- **UI flag:** `enable_body_measurements` (`configBox`, default OFF); getter in a platform-tier file (or a `blast_radius.yaml` rule) so the flip commit is gate-graded; a dev-panel writer per `dev_panel_screen.dart:256-378`; logged in `docs/ship_dark_pending_review.yaml`. The flip removes the OFF branch (§4.6.4).
- **Site registry:** `kBodyMeasurementSites` + TS twin; the 8 sites derive from it; parity test against `live_schema_columns.json` and the payload.
- **Writer/reader:** `HealthWriteService.logMeasurements(date, editedSites, source)` writes **only sites the user edited** (last values are hints, never prefilled into the save); `HealthReadService.measurementHistory()`; a provider that watches `authUserIdTokenProvider`, added to `user_scoped_provider_rebuilds_on_auth_change_test.dart`. SoT registry entries with `behavioral_test_path`; the stale `health_write_service` reader (`BiometricNotifier`, `sot_registry.yaml:6599-6601`) corrected.
- **Sheet:** four optional fields, unit from `units_metric` (stored in cm), guide line per site, registry bounds, inch-confusion prompt, save confirmation with change since last entry (NUT-12 precedent).
- **Entry points (flag ON):** `_buildMeasurementDue` in Home's mounted banner stack after `_buildRepeatNudge`; "Measurements due · Add" in `WeightLogSheet`; Progress Comparison "Add measurements" + deltas, with `snapshotManual` receiving the latest measurements (`arms` → `arms_l`/`arms_r`) so the two readers on that screen agree; in chat, an **action chip** in its own slot above the input while measurements are due (the existing chip row renders only on an empty chat, F17), opening the sheet without `_sendMessage` — existing string chips unchanged (test); week-1 baseline prompt in the banner slot.
- **Due state:** due ≥ 28 IST days after the last entry; first prompt from tenure day 7; one dismissal silences all surfaces for 7 days. Copy through `psychology-pass-fitness` + Wardroom soul.
- **Delivery:** L2 ships as **L2a** (the push and the registry, above, merged) and **L2b** (everything else in this section, behind the flag; its own plan and ×2 review). The L2a plan §0 carries the L2b obligations; OQ-L2a must be decided before the L2b flag flips.
- **OI-304:** the banner does not use `PatternDetector`; L2 also mounts or deletes the dead `InsightCard`/`DeepAnalysisCard` and corrects `ai_coach/CLAUDE.md:41` + `ai-coach-detail.md:45`.

### L3 — Athlete state + Progress Review (OI-299, OI-300, OI-306)
**L3.1 Athlete state.** Pure TS `_shared/athlete_state/` over the single `athlete_state_rows` result (§3 domains). Sections: weight trend (smoothed, kg/wk, %BW/wk); measurements; training (workout days vs scheduled; key lifts = top-5 by frequency with best-set e1RM trend + `stalled`; **logged** sets per muscle per week + `unmapped_share`); nutrition (per-day totals vs targets, protein g/kg, logged days); recovery; per-section `coverage` + `confidence`; `effort: "not_collected"`; `caveats` (`nutrition_deletes_unverified` until OI-281). Landmarks mirrored with a Dart test that reads `volume_titration.dart` text.
**L3.2 Findings.** Closed, versioned catalogue of codes; each finding has a unique `id`, `code`, `kind`, typed `values` (number + unit + sign) and `evidence`; each code has a template sentence, so the template review is complete without a model.
**L3.3 Safety (template-only, no forecast):** `minor` (age < 18), `age_unknown` (no DOB), `underweight_now` (needs height — **missing height ⇒ `safety_unknown`**, template-only), `underweight_target` (missing target ⇒ stated as not computable), `rapid_loss`, `very_low_intake`. Thresholds proposed with cited sources by the L3 plan author and approved by the founder (OQ-L3b). A standing doctor line covers pregnancy, conditions and medication.
**L3.4 Model as editor.** Input: findings (ids, codes, kinds, evidence labels) — no raw rows, no free text. Output JSON: `headline` (must reference a finding id, else templated), `wins[]`, `watchouts[]`, `next_4_weeks[]`, each `{finding_id, text}`. `text` may use only `{{value_name}}` placeholders **of its own finding**. Validator: schema-parse; ids exist and kinds match; no digit; no word from a closed, versioned list (English + Hinglish magnitudes, multipliers, fractions, ordinals, percent — e.g. double, twice, half, dozen, dugna, aadha, teen, paanch); length caps. One retry only if the time budget allows, else template. No `finishReason` dependency (F28) — parse + validator decide.
**L3.5 Sanitisation.** Allowlisted tokens only (goal, injuries via their vocabularies); exercise names through `sanitizeIdentifier` + cap, serialised with `sanitizeJsonForPrompt` inside `fenceAsData`; no `coach_memory` text. Same on the tool result. Injection test via a custom exercise name.
**L3.6 Edge Function `progress-review`** (`verify_jwt=true`, e8a1c3 auth; the request carries only `units`, enum-validated).
- auth → tier → **eligibility probe** (insufficient ⇒ 200 `insufficient_data` + named gaps; nothing reserved) → **reserve** (insert `pending` + new `attempt_id`; on unique conflict: `ready` ⇒ return it; fresh `pending` ⇒ 202; stale `pending` ⇒ atomic take-over `UPDATE … SET attempt_id=new, attempts=attempts+1 WHERE id=? AND status='pending' AND updated_at < cutoff AND attempts < 3`) → RPC → state → findings → safety → (template | model + validator) → `UPDATE … SET status='ready' WHERE id=? AND attempt_id=mine AND status='pending'` (0 rows ⇒ ownership lost, result discarded).
- **Hard internal deadline 110 s**; stale cutoff ≥ 2× the platform wall-clock limit (cited live in the L3 plan). Model: `MODEL_PRO`, thinking on, 4096 tokens, 40 s per call.
- **Gemini exhaustion ⇒** delete the reservation (`WHERE attempt_id=mine`) and return 503 "try later" — an outage never burns a free user's only review; `reportGeminiExhaustion`. The template is used only for safety flags and validator rejection. 3 attempts in one period ⇒ template.
- Client: 202 ⇒ bounded polling (fixed attempts), then a clear "still working, check back" state. Telemetry: codes and counts only.
- The retention job (OQ-L3c) also deletes `pending` rows older than the cutoff (month-rollover orphans).
**L3.7 Window and units.** The review always covers the whole history with `last_90d` sub-sections (no per-request window, so the one-per-period row cannot conflict with a different window). Units are rendered on the client from typed values + `units_metric`.
**L3.8 Tool `getAthleteState({window})`.** Read-only; reuses a review's `state_json` only when the window matches and it was computed the same IST day, else computes fresh. Gated at offer time and at execution (the `tool-loop.ts:420/446` hook). Its Captain Manual guidance and the `CAPTAIN_MANUAL` correction ship in the **tool's own flip commit** (separate from the review flip), with the weekly-report prompt pin (§2).
**L3.9 Flags.** Server code constants `PROGRESS_REVIEW_ENABLED`, `ATHLETE_STATE_TOOL_ENABLED` (false); env `DISABLE_*=true` can only turn off. Client `enable_progress_review` (default OFF, dev-panel writer, platform-tier getter). Each flip is a commit with full ×2 + B-pass, logged in `ship_dark_pending_review.yaml`.
**L3.10 Client.** `progressReviewProvider` (Hive-first `progress_review_latest`; owner-at-start guard + in-flight clear on account change — precedent `prediction_service.dart:112,132,166`; watches `authUserIdTokenProvider`); `ProgressReviewCard` under `WeeklyReportCard`; `/profile/progress-review`; `gateAndVerify` with a first-review-free branch; the new feature key added to `allProFeatures`; skeleton / error-retry / empty states.
**L3.11 OI-306.** Edit Profile, onboarding and the coach tool all write one goal-change timestamp, synced; the zero-writer field and its reader are removed.

### L4 — One forecast (OI-210), in three parts
**L4-build (dark):** the observed-trend forecast = one TS function in the athlete state + a Dart twin with shared golden cases, replacing the `reports_screen.dart` and `journey_timeline.dart` math; `projectGoalDate` stays as the labelled plan projection; client prediction surfaces hidden behind `enable_progress_review` with OFF-identity tests (Profile, onboarding, paywall).
**L4-flip (client, with the L3 review flip):** deletes the client prediction path (inventory below + a full `git grep -i predict` over `lib test supabase docs .claude`), swaps the paywall copy (OQ-L4a), removes the OFF-identity tests. Keeps `detectAndStripJsonShapedReply` (chat uses it at `ai_coach_provider.dart:286,318,698,951,1031`).
**L4-server (its own founder go, OQ-L4b):** after flip-APK adoption is measured, `ai-proxy` `type:"prediction"` becomes a stub returning `200 {reply: <founder-approved retirement copy>, actions: []}`, tested against `_regenerate` and the onboarding path (an old APK shows the copy; no chat fall-through; no quota). The same commit removes `prediction_daily` from `DIGEST_KEYS` and the kill-switch rows with their pins (F30), and deletes the `future-prediction` code (removing the deployed function is a further go).
**Inventory (minimum):** `prediction_service.dart`; `AiService.predict` (`ai_service.dart:414-470`); `ai_coach/widgets/prediction_card.dart` incl. the PROF-17 share sheet (`:286`); `profile/screens/profile/prediction_card.dart`; `profile_content.dart:299-335`; `profile/screen.dart:61-62,130,165`; `edit_profile_screen.dart:2110-2127`; `ai_coach_provider.dart:1311-1434` (prediction parts only); `onboarding_provider.dart:724,776-828`; `day_rollover_service.dart:283`; `journey_timeline.dart:218-223`; `user_config_migrator.dart:70-76`; `app_constants.dart:26,65`; `subscription_service.dart:103`; `paywall_sheet.dart:149-150`; `paywall_sheet_phase_variant.dart:41`; `wardroom_copy.dart:266`; `prediction_handler.ts` + test; `prediction_quota_switch.ts` (move `envSwitchOn` first); docs `functionality-flow.md` HOME-19 + PROF-17, `lib/features/home/CLAUDE.md:67`, `functions-detail.md:158`, `supabase/functions/CLAUDE.md:147`, `snapshot_contract.yaml:663-679`, `sot_registry.yaml:3272,7659,12424-12443`; tests `prediction_sanitiser`, `prediction_refresh_outcome(_wiring)`, `prediction_attempt_gate`, `prediction_service_singleton_lifecycle`, `prediction_card_onboarding_copy`, `usage_quota_ledger_writer_to_reader_test.dart:262`, `quota_refund_wiring_test.dart:174-182`, `no_silent_debugprint_in_services_test.dart:59`, `voice_is_free_test`, `runbook_deploy_verify_jwt_test.dart:64`, `singleton_lifecycle_registry_test.dart:148`, `reports_section_consolidated_test.dart:12`, `profile_screen_layout_test.dart:101`; tooling `.claude/deploy_via_api.js:440,756`, `emit_payload.js:32`; comment-only mentions listed by the L4 grep.

---

## Section 5 — Edge cases (each a named test in its landing)

L1: > 1,000 rows; duplicate summary rows; delete-then-re-log; old log edited today; IST midnight; long per_day nutrition range. · L2: mixed fleet (a flag-OFF device or old APK pushes nulls — the recorded residual); untouched hint fields never saved; same-day re-entry overwrites only edited sites; units; account switch. · L3: insufficient data (no reservation); concurrent first requests (unique conflict ⇒ 202); slow worker vs take-over (`attempt_id`); Gemini outage (reservation released, 503); validator rejection (retry if budget, else template); attempts cap; month-rollover orphan (retention cleanup); missing DOB / height / target; minor; injection string; tool called while disabled; RPC for user A never returns user B rows; `authenticated` cannot execute the RPC. · L4: old APK before the server stub (unchanged); old APK after the stub (shows the retirement copy, spends nothing); flag OFF identity.

---

## Section 6 — Acceptance criteria (headline)

1. **L1:** every §5-L1 fixture yields correct, IST-day, deleted-free, de-duplicated counts and volume; `truncated` appears only at the page cap; the live dedupe leaves one live row per group.
2. **L2:** the push never sends a null site or null notes; a saved sheet writes only edited sites and fires one fan-out; flag OFF ⇒ no new UI; the parity test fails on a missing site.
3. **L3 numbers:** for every golden persona no digit or listed number-word appears outside a placeholder; adversarial goldens (wrong-finding placeholder, sign flip, each banned word class) are rejected, then templated.
4. **L3 ledger:** a second request in the same period ⇒ the existing review, no model call; two workers ⇒ exactly one `ready` write; an outage ⇒ no row left, period not burned.
5. **L3 safety & isolation:** any safety flag ⇒ no model call; injection fenced; the RPC returns only `p_user`'s rows; `authenticated` lacks EXECUTE; user B cannot read A's review.
6. **L4:** build: flag OFF byte-identical; flip: no client sends `type:"prediction"`; server stub: an old APK shows the copy and spends nothing; founder-digest mirror test green.

---

## Section 7 — Young users (founder + counsel; OI-305)

**Facts.** 0 live users under 18 (youngest 24). Sign-up allows age 10 (lowered from 13 after a user could not enter his son's 2019 DOB — option A reverses that decision) and Edit Profile 13. DPDP Act §9 + Rules 2025 (Rule 10): verifiable parental consent for under-18s; no tracking or behavioural monitoring of children; substantive obligations reported for 13 May 2027 (counsel to confirm). Supervised youth strength training is safe (NSCA, AAP); calorie restriction and weight-loss focus are discouraged for adolescents (AAP).

**Options.**
**Founder decision 2026-10-06: C (status quo).** The options considered:
- **A:** 18+ at sign-up and in Edit Profile; any existing under-18 profile gets no deficit target, no weight forecast (including `projectGoalDate`) and no AI review. Owner: an onboarding/auth landing under OI-305.
- **B:** 13–17 with verifiable parental consent and a reduced feature set (the same exclusions + no behavioural nudges) — substantial compliance work.
- **C (chosen):** status quo. Revisit before the DPDP children's-data obligations commence or when OI-310's policy is written, whichever is first (recorded in OI-305).

Independently, L3 treats `minor` and `age_unknown` as template-only with no forecast. A missing DOB removes nothing else (an adult without a DOB keeps their deficit).

---

## Section 8 — Effort capture (RIR/RPE) — founder decision 2026-10-06: OUT of this initiative (OI-298 kept open for later)

**What it is.** RIR = how many more reps you could have done; RPE = the same on 1–10. It tells a coach whether sets were hard enough and whether fatigue is building.
**The beginner problem.** Novices underestimate how close they are to failure by several reps (Steele et al.; Halperin et al. 2022 meta-analysis: ~1 rep on average, worse in novices). Beginners should not drive load from RIR until calibrated.
**Industry.** Hevy/Strong: optional per-set RPE, off by default, logging only. Fitbod: optional per-exercise RiR feeds its algorithm. JuggernautAI: RPE after key sets; the first block is calibration. RP Hypertrophy: plain-language per-muscle questions (pump, soreness, workload, joint pain), no jargon.
**Proposal if "in" (landing L5, own spec):** one optional per-exercise question **"How did that feel? Easy · Solid · Tough · Max"** (RIR ≥ 4 / 2–3 / 1 / 0) in the set logger, never on the post-workout screen. Trigger (defined in L5, since no event exists — F29): all of an exercise's sets checked, once per exercise per session, re-armed if sets are added. During the first 8–12 weeks (experience from `user_progress.detected_experience_level`, not the unwritten Hive key) the answer only shapes coaching language; rep performance stays the progression signal. Storage: one column on `workout_log_exercises` (+ sync, restore, OI-280 coordination).
**Decision:** out ("too intimidating for beginners"). OI-298 stays open on the board at the founder's request for later pickup, with this section as its design starting point. The athlete state reports `effort: "not_collected"`.

---

## Section 9 — Delivery structure (proposal; founder decides — OQ-S)

| Landing | OIs | Ships | Review |
|---|---|---|---|
| L1 | 296, 307, 308 (+ 312, 313, 218, 269 found while planning) | live bug fixes in three sub-landings: **L1a-1** server migration (`docs/plans/coach-history-correctness-sync.md`), **L1a-2** client restore/delete and workout-day keying (`docs/plans/coach-history-correctness-client.md`, after L1a-1's apply; its server day clamp was withdrawn in v6), **L1b** coach tools + server readers (`docs/plans/coach-history-correctness-tools.md`, independent of L1a). **L1a-3** exercise-log pass serialisation, bounded calls and restore fingerprints (`docs/plans/coach-history-correctness-sync-passes.md`, after L1a-2; split from L1a-2 after round 7). L1a was split after its third review round kept finding new P1s (§4.12.1). Every live apply and deploy needs its own go | each sub-landing: own plan, full ×2 + B-pass, closure ledger |
| L2 | 297, 304 | **L2a (merged, PR #99):** merge-safe push live + one site registry, no UI. **L2b:** UI dark behind `enable_body_measurements`; flip = own commit | each: own plan, full ×2 + B-pass |
| L3 | 299, 300, 306 | migration (catastrophic) after its gates; features dark; review flip and tool flip are separate commits | own plan, full ×2 + B-pass + hermes + rollback |
| L4 | 210 | build dark → client flip (with the L3 review flip) → server stub (own go) | own plan, full ×2 + B-pass per part |

- **Order:** L1 → L2 → L3 → L4. L2 and L3 are **not** parallel: both change `ai-proxy`, which is deployed only from post-merge `main`, so one landing's deploy cannot revert the other's.
- **Standalone value:** L1 and L2 each have it. L3 dark has none on its own; pushing it before its flip is the explicit founder scope call §4.3 requires (OQ-S).
- **Every landing plan** declares its execution mode (§4.12.7), gets its own ×2 rounds (these umbrella rounds do not count), prepends the brief preamble, names lenses, gives reviewers an exhaustive read-only command list (no scripts, no DB statements), and is preceded by the coordinator's full gate loop (§4.12.8) when it carries a diff. Every new test is mutation-proven. Live writes (migration apply, dedupe, every EF deploy, function deletion) each need their own founder go. The context-artifact budget is re-baselined in the commit that grows `OPEN_INDEX.md` (§5 row).

### Naming (§4.7)
"Athlete state", "findings", "Progress Review" (working title, OQ-N); avoid **digest** (founder digest), **muster**, *readiness*, *weekly report*. New terms are appended to `docs/naming_conventions.md`, plus the userBox-vs-healthBox note for `measurement_due_*`.

---

## Section 10 — Round-1 review log

The v2 table stands except where round 2 showed a disposition incomplete; those are re-dispositioned in §12. Summary of round-1 dispositions (A-1..A-16, B-1..B-18, C-1..C-14, D-1..D-18): quota → row ledger; probe before reserve; no refund path; idempotent row; sanitiser at the source; offer + execution gating; code-constant flags; placeholder-only numbers; template-only safety; privateMode claims removed; one RPC; fifth forecast; no goal segmentation; L1 widened; L2 flag; retirement sweep; line re-verification; name-based joins; live rows only; null-omitting push; per-landing tiering; live apply first; IST; old-APK stub; logged sets; per-day nutrition; Hive keys; Home banner stack; OI-298/OI-210 wording; action chip; reader added; `gateAndVerify`; one record per landing; shared due state.

---

## Section 11 — Open questions (founder unless noted)

| # | Question | Proposal |
|---|---|---|
| OQ-S | Four landings in the §9 order? | **Decided: yes** |
| OQ-E | Effort capture? | **Decided: out; OI-298 kept** |
| OQ-Y | Young users? | **Decided: status quo** |
| OQ-L2a | **Open — decide before the L2b flag flips** (not before L2b is built). After L2a two residuals remain: (1) old APKs and the out-of-repo Telegram writer still push nulls — only a server-side BEFORE UPDATE keep-old-on-NULL trigger (platform tier; revisits decision 2's "no schema change") can stop that; (2) a stale held value can overwrite a value another device corrected, because the push sends every held site — a client-side per-site pending set (the push sends only sites edited since the last confirmed upload) fixes that; or accept both. | Per-site pending set as its own small piece before the flag flips; the trigger only if the Telegram writer is shown to send blanks. The "0 rows" premise that made the residuals acceptable ends when real users enter measurements (OI-297, ledger row L2B-ENTRY) |
| OQ-L3a | Free: 1 lifetime review; PRO: 1 per IST month; `getAthleteState` free? | **Decided: yes / yes** |
| OQ-L3b | Safety thresholds | L3 plan author proposes with sources; founder approves |
| OQ-L3c | Retention | 24 months |
| OQ-L3d | Does consent cover a stored health state + findings sent to a model? | **Checked 2026-10-06: no — the linked policy covers no app data (OI-310).** Founder + counsel publish an app policy before the L3 migration apply |
| OQ-L4a | Paywall copy replacing "Monthly Prediction" | **Decided: "Monthly Progress Review"** |
| OQ-L4b | When the server stops serving predictions to old APKs | **Decided:** after the flip APK reaches most active users; the founder sets the threshold then |
| OQ-N | User-facing names | Psychology pass + Wardroom soul |

---

## Section 12 — Round-2 review log

| Finding(s) | Disposition in v3 |
|---|---|
| R2A-1, R2C C-2 (a budget cannot detect truncation) | L1.1 pages with `.range()`; `truncated` at the page cap. |
| R2A-2, R2B-1 (set join multiplies) | Verified live (44 groups) ⇒ OI-307 into L1; RPC uses EXISTS; F24. |
| R2A-3, R2C C-5 (F7 wrong; mixed fleet) | F7 corrected; null-omission ungated incl. `notes`; residual in OI-297 + OQ-L2a. |
| R2A-4, R2B-8 (RPC domains) | §3 lists every domain incl. schedule, profile, experience, maps via `lower(name)`. |
| R2A-5, R2D-2 (manual shared with weekly-report) | §2 amended; manual edit in the tool flip with a weekly-report pin (L3.8). |
| R2A-6, R2C C-10, R2D-9 (retirement list, digest keys) | L4 inventory + full grep; digest rows removed with the server stub (F30). |
| R2A-7, R2C C-11/C-12, R2D-1 (L4 sequencing, old APKs) | L4 split into build / client flip / server stub with its own go (F27, OQ-L4b); stub response pinned. |
| R2A-8, R2B-6 (window reuse) | No per-request review window (L3.7); tool reuse only for the same window + same IST day. |
| R2A-9, R2C C-4 (more UTC sites; triple count) | F26; L1.2; OI-308 into L1. |
| R2A-10, R2D-6 (OI board drift) | OI-296/298/299/305 reworded with v3. |
| R2A-11, R2B-7 (RPC isolation, EXECUTE) | REVOKE from PUBLIC too; AC5 RPC tests. |
| R2A-12 (SoT registry) | L2 entries + `BiometricNotifier` correction; L3 entries in its plan. |
| R2A citation rot | Cascade note no longer cites F17; F21 states the missing DOB; L3.10 guard lines corrected. |
| R2B-2 (no owner token) | `attempt_id` + conditional writes (§3, L3.6). |
| R2B-3 (wall clock) | 110 s internal deadline; cutoff ≥ 2× the limit, cited live; bounded polling. |
| R2B-4 (outage burns the period) | Exhaustion ⇒ release + 503; attempts cap. |
| R2B-5 (placeholder ambiguity, word list) | Finding ids; own-finding placeholders; typed signed values; closed English + Hinglish list; adversarial goldens. |
| R2B-9 (missing height/target) | `safety_unknown` / "not computable" (L3.3). |
| R2B-10 (units) | Client renders typed values with `units_metric` (L3.7). |
| R2B-11 (finishReason) | Dropped; parse + validator decide (F28). |
| R2B-12 (rollover orphans) | Retention job deletes stale pending rows. |
| R2C C-1 (`completed_at` = edit time) | F25; day from `wlog_<date>` in L1 and the RPC. |
| R2C C-3 (`.in()` URL length) | Chunked ids (L1.1). |
| R2C C-6 (prefill creates fake entries) | Hints only; only edited sites saved. |
| R2C C-7 (chip rarely visible) | Own slot above the input while due; string chips unchanged. |
| R2C C-8 (auth watch) | Provider watches `authUserIdTokenProvider` + the hand-listed test. |
| R2C C-9 (two disagreeing readers) | `snapshotManual` receives measurements. |
| R2C C-13 (L1 pins) | L1 ripple list. |
| R2C §4.6 caveat (tool descriptions) | L1.6: descriptions unchanged. |
| R2D-3 (flag protocol) | Platform-tier getters, dev-panel writers, ledger entries, flips delete the OFF branch. |
| R2D-4 (hermes, apply order) | `*_rls.sql` name; apply after convergence + B-pass + hermes + OQ-L3d/OQ-Y. |
| R2D-5 (Gate-40 states) | L1 closure ledger; OI-304 → L2, OI-306 → L3; OQ-L3b owner; §8 "out" = founder-declined close. |
| R2D-7 (§7 facts) | Reversal noted; `projectGoalDate` included; owner named; Edit Profile aligned. |
| R2D-8 (§8 hooks) | Real experience field; trigger defined in L5 (F29). |
| R2D-10 (parallel deploys) | L2 → L3 sequential; `ai-proxy` deployed from post-merge `main` only. |
| R2D-11 (umbrella vs landing) | Header + §9: own ×2 per landing; execution mode; OQ-S as the scope call. |
| R2D-12 (flip bundling) | Tool flip separate from the review flip. |
| R2D-13 (context budget) | Re-baselined in the committing batch (§9). |
