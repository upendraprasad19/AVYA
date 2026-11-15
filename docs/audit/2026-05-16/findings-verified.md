# Phase D · Verified Findings — Mega-Checkpoint Synthesis

**Date:** 2026-05-16 · **Agents complete:** 6 of 7 (Agent 3 DB-column NULL matrix still running)
**Verification status:** every finding below re-read by main thread per `feedback_audit_findings_require_live_verification.md`.

## Top-line summary

| Category | Count | Notes |
|---|---:|---|
| 🚨 CONFIRMED_BUG | 13 | Fix in same batch per `feedback_no_deferrals.md` |
| FRAMEWORK_GAP | 11 | New permanent gates / contract tests |
| NEEDS_DECISION | 4 | Founder approval required |
| DEAD_SCHEMA_CANDIDATE | 4 | Drop or keep — founder decides |
| FALSE_ALARM | 1 | Drop (`onInvalidate` callback null) |
| LOW_USAGE_NOT_BUG | 6 | Reframed from Agent 4 (sync wired; tables empty due to 4 test users) |

## 🚨 CONFIRMED BUGS — proceed without per-item approval

### Writer/reader drift class (4 instances — 8th–11th overall)

1. **F6-2 · `logPR` AI coach tool bypasses `WorkoutWriteService`**
   - File: `lib/features/ai_coach/services/tool_dispatcher.dart:349`
   - Currently calls `WorkoutRepository.logSetWithPrRescan` (legacy, was rogue formula closed in Test #16.1)
   - Fix: route through `WorkoutWriteService.logExercise([ExerciseSet(weightKg, reps)])`. Move PR rescan inside the WriteService.

2. **F11-C11-2 / F12-C12-3 · `WorkoutScheduleService` 13 direct `workoutBox.put` callsites + 0 sync + 0 invalidations**
   - File: `lib/core/services/workout_schedule_service.dart` L248, L412, L717, L844, L855, L1159, L1302, L1430, L1515, L1595, L1605, L1669, L1851
   - Schedule mutations (generate plan, copy week, reschedule, assign template, days/week change) write Hive directly with no sync fan-out + no provider invalidation.
   - Fix: route through `WorkoutWriteService.upsertScheduled` (already exists L427) OR add `WorkoutScheduleService` to the allowed-writers list in CLAUDE.md §15 + ensure every put fires sync + invalidations.
   - **Severity:** HIGH — AI coach sees stale schedule data after every template assignment.

3. **F2-R2 (reframed) · sleep_log direct healthBox write uses device-local date, not IST**
   - File: `lib/features/profile/providers/profile_provider.dart:497`
   - Date computed as `now.year-now.month-now.day` (device-local). `feedback_use_ist_throughout.md` requires `istDateStr(DateTime.now())`.
   - At IST 00:00–05:30, key becomes prev-day UTC → IST sleep readers miss it.
   - Same class as Test #12 / Task A-1 `formatDateKey` IST fix.

4. **F8.3 sub-bug · inline `if (isPro)` widget reads (9 sites)**
   - Files: `ai_coach_provider.dart:1011,1020`, `ai_coach_screen.dart:244,606`, `weekly_report_card.dart:112`, `edit_profile_screen.dart:1820`, `notification_settings_screen.dart:259`, `profile_screen.dart:508,1418`
   - Some are constructor-prop reads (acceptable IF caller is reactive); some are the exact shape that bit Test #12 PRO-upgrade-unlock.
   - Fix: replace each with `ref.watch(subscriptionInfoProvider).isPro` per Test #12 C-2 pattern.

### AI architecture (3 instances)

5. **F6-3 · `model_used='pending'` 8 stuck rows + fire-and-forget UPDATE**
   - File: `supabase/functions/ai-proxy/index.ts:319-329`
   - UPDATE uses `.then((r) => {if(r.error) console.error})` — no await, no telemetry. 8 stuck rows in 2 weeks.
   - Fix: `await` the UPDATE + promote any error to `log-client-error` telemetry. One-shot SQL backfill: `UPDATE ai_coach_interactions SET model_used='unknown_legacy' WHERE model_used='pending' AND ai_response IS NOT NULL AND created_at < now() - interval '24h'`.

6. **F6-4 · Cross-channel duplicate pairs still accumulating (Test #16.1 incomplete)**
   - 8 dupe pairs (`food_text_analysis` + `in_app_orphan`) across 2026-05-11 → 2026-05-15.
   - Server-side 60s dedup at `ai-proxy:222-254` only covers intra-channel.
   - Client orphan upsert at `sync_coach.dart:91` writes via separate code path.
   - Fix (preferred): in `sync_coach.dart`, before orphan upsert, SELECT for `channel='app'` row with matching user+message within 5min. Skip on hit.

### Discipline / telemetry (3 instances)

7. **F10.1 · `AppConstants.appVersion` hardcoded `'1.0.0+23'`, 3 APKs behind**
   - File: `lib/core/constants/app_constants.dart:99`
   - 358 telemetry rows from APK +24/+25/+26 mis-labelled as `+23`.
   - Fix: bump constant to `'1.0.0+26'` immediately + add build gate to detect drift.

8. **F8.1 sub-bug · `featurePhotoAnalysis` no client `gate()` callsite**
   - CLAUDE.md §14 says photo upload PRO; no client enforcement. Potential silent free-tier bypass.
   - Fix: add `gate(featurePhotoAnalysis, ...)` at the photo upload site.

9. **F8.1 sub-bug · `featurePredictionMonthly` no client `gate()` callsite**
   - CLAUDE.md §14 says monthly prediction is PRO; no gate.
   - Fix: add `gate(featurePredictionMonthly, ...)` at the re-trigger path.

### Restore-completeness gaps (2 instances)

10. **F4-S2 · `referral_codes` has no restore method**
    - On cross-device login, founder's generated referral codes vanish from Hive (Phase A: 0 rows in cloud table — but founder did generate codes during Test #2; possibly also a write path issue, verify in Phase E).
    - Fix: add `_restoreReferralCodes` in `sync_restore_completeness.dart`.

11. **F4-S2 · `referral_redemptions` has no restore method**
    - Paired with referral_codes. Same fix shape.

### Documentation drift (2 instances)

12. **F6-1 · CLAUDE.md §11 tool count outdated: claims 20, registry has 24**
    - Tier split also wrong: claims "6 FREE / 20 PRO", actually "11 FREE / 13 PRO".
    - Fix: update CLAUDE.md §11 to 24 tools + correct tier split + add `exercise` family.

13. **F5-S1 (reframed) · `backups/applied_migrations.json` parity**
    - JSON has 71 entries, disk has 72 files, live `schema_migrations` has 61 timestamp-format entries.
    - Mixed numbering convention split during the project's history.
    - Fix: regenerate `applied_migrations.json` from live `schema_migrations` as ground truth. Document the numbering convention switch.

## FRAMEWORK_GAPs — proceed without per-item approval

14. **F-A · Health domain has no `WriteService`** — Workout + Nutrition gated; Health (sleep/weight/measurements) writes directly. Create `HealthWriteService` OR formally document exemption.
15. **F3-A · `undo_*` Hive keys undocumented** — add SoT registry entry + `undo_stash_lifetime_test.dart`.
16. **F3-B · `custom_exercise_*` contract test missing** — add `custom_exercise_writer_to_reader_test.dart`.
17. **F3-C · MigratedKey contracts undefined** — add `migrated_key_contracts_test.dart` covering 7+ MigratedKey concepts.
18. **F10.4 · HIGH_PRIORITY_OP_TYPES drift** (client 17 / server 18) — add `high_priority_op_types_parity_test.dart`.
19. **F10.5 · No cron-execution telemetry** — add `cron_call_log` table + per-cron Edge Function status INSERT. Surfaces F9.1 401 storms early.
20. **F9.1 · `_shared/cron_auth.ts` does not exist** — auth inlined per-function with brittle env-equality. Create shared module + JWT signature/role decode.
21. **F10.3 · Generic op_types** (`sync_service_catch_5`, `sync_service_for`) defeat triage — add gate banning numbered catch-block op_types.
22. **F-B · LOW_USAGE tables lack success telemetry** — add `upsert_<table>_success` op_type emission to `_syncSavedMeals`, `_syncSleepLogs`, `_syncMeasurements`, `_syncSavedDietPlan`, `_syncCustomFoods`. Distinguish "feature not used" from "sync silently failing".
23. **F8.1 · `check_gate_coverage.dart` + `gate_coverage_test.dart`** — every `featureXxx` constant must have ≥1 gate callsite OR `@Deprecated` annotation OR be on the server-only-enforcement allowlist.
24. **New gates per audit plan** — `check_naming_conventions.dart` (extend existing), `check_writeservice_only.dart`, `check_mutation_invalidation_set.dart`, `check_ai_tool_dispatcher_coverage.dart`, `audit_discipline_history.dart`.

## NEEDS_DECISION — founder questions

### NEEDS_DECISION 1 — Legacy widgets in active use
`RankChip` + `RankInsignia` are documented as "slated for removal" in CLAUDE.md §9, but 5+ live callsites remain (`profile_screen`, `profile_identity`, `rank_chip_full_width`, `train_screen`, `phase_roadmap_screen`).
- **Option A:** Migrate all callsites to `WardRankPill` / `WardRankInsignia` + delete legacy files this batch.
- **Option B:** Drop "slated for removal" claim from CLAUDE.md §9; widgets stay.

### NEEDS_DECISION 2 — `MySubmissionsScreen` legacy route
Two screens at `/profile/my-submissions` (legacy) and `/profile/submissions` (canonical tabbed). Legacy route retained for "deep-link safety" since Test #1.
- **Option A:** Delete legacy now (1 release cycle has passed).
- **Option B:** Keep one more cycle.

### NEEDS_DECISION 3 — `WorkoutScheduleService` fix shape
Direct workoutBox writes + zero sync is the bug (F11-C11-2). Two fix shapes:
- **Option A (recommended):** Refactor — route all schedule mutations through `WorkoutWriteService.upsertScheduled` (already exists L427). Cleaner long-term; risk = one large refactor PR.
- **Option B:** Add `WorkoutScheduleService` to allowed-writers list in CLAUDE.md §15 + add `unawaited(syncWorkoutData())` + invalidation batch after every put. Lower risk; more callsites to maintain.

### NEEDS_DECISION 4 — `HealthWriteService` introduction
F-A: Health domain has no WriteService. Same architectural asymmetry that caused Workout/Nutrition bugs pre-#6.
- **Option A:** Build `HealthWriteService` (sleep + weight + measurements + steps) this batch. Mirrors Workout/Nutrition pattern. ~250 LoC.
- **Option B:** Document the asymmetry as intentional in CLAUDE.md §15. Add contract tests for current direct writes.

## DEAD_SCHEMA_CANDIDATES — founder decides keep/drop

### DEAD 1 — `featureActiveWorkoutMode` constant — RECOMMEND DELETE
Already `@Deprecated`; 0 gate callsites; active workout is free since Test #2 Q6.

### DEAD 2 — `featureVoiceNotes` constant — RECOMMEND DELETE
Free since Test #9 F13 (CLAUDE.md §14); should be `@Deprecated` or deleted.

### DEAD 3 — `featureDietPlanPdf` constant — RECOMMEND DELETE
FREE per CLAUDE.md §14. Constant has no gate callsites.

### DEAD 4 — `UserRepository.softDeleteAccount` method — RECOMMEND DELETE
0 callsites; hard-delete via `delete-account` Edge Function is canonical (Test #11 H1).

## FALSE ALARM (drop)

- **F12-C7-1 · `WorkoutWriteService.onInvalidate` callback null** — Verified: optional nullable callback by design; callers invalidate manually if not wired. Comment at `conversational_log_handler.dart:256-260` documents intent.

## LOW_USAGE (not bugs) — Agent 4's RED FLAG zero-row tables reframed

Phase C verification showed sync IS wired at the mutation sites for all 5 tables Agent 4 flagged:
- `user_saved_meals` ← `NutritionWriteService.saveMealPreset:541` fires sync
- `user_custom_foods` ← `nutrition_provider.dart:1252` + `workout_repository.dart:1483` fire sync
- `sleep_logs` ← `profile_provider.dart:507` fires sync (separate from F2-R2 IST drift)
- `body_measurements` ← `conversational_log_handler.dart:153` fires sync
- `saved_diet_plans` ← `diet_plan_screen.dart:231` fires sync

`client_errors` shows ZERO failure rows for upsert_* op_types on any of these tables. Most likely: 4 test users haven't exercised these manual-only low-traffic features.

Framework gap 22 (success-path telemetry) closes the diagnostic gap so we can distinguish empty-because-unused from empty-because-broken in future audits.

## Phase E execution plan (preview)

Will be expanded after Phase D founder approval + Agent 3 DB column matrix lands.

**Branch:** `audit/2026-05-16-comprehensive`

**Commit grouping** (per-cluster, reviewable):
1. Bump `AppConstants.appVersion` → +27 + add gate (F10.1)
2. AI Coach: `logPR` tool through WriteService + ai-proxy await UPDATE + cross-channel dedup + tool count docs (F6-2, F6-3, F6-4, F6-1)
3. `WorkoutScheduleService` refactor or wire (F11-C11-2) — depends on NEEDS_DECISION 3
4. `HealthWriteService` introduction or asymmetry doc (F-A) — depends on NEEDS_DECISION 4
5. Sleep log IST drift fix (F2-R2)
6. Gate coverage: featurePhotoAnalysis + featurePredictionMonthly + delete 3 dead constants (F8.1)
7. Inline `if (isPro)` → reactive `ref.watch` (F8.3) per-callsite
8. Restore-completeness: `_restoreReferralCodes` + `_restoreReferralRedemptions` (F4-S2)
9. Framework: 8 new gate scripts + 6 new contract tests (FRAMEWORK_GAPs 14–24)
10. Doc updates: CLAUDE.md §11 + §9 (legacy) + naming + SoT registry (F6-1 + NEEDS_DECISION 1)
11. Telemetry: success-path emission for low-usage syncs (F-B) + cron_call_log (F10.5) + cron_auth.ts (F9.1) + ban generic op_types (F10.3) + HIGH_PRIORITY parity (F10.4)
12. `applied_migrations.json` regenerate from live (F5-S1)
13. SQL backfill for `model_used='pending'` historical rows
14. Run full test suite + new contract tests + new scripts. Target ≥1700 pass / 0 fail.
15. `/build-apk` → APK +27.

Estimated: 3–4 days post-Phase-D approval.
