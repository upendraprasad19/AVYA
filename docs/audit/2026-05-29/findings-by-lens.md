# Audit Findings by Lens — 2026-05-29 (window `3dc227c..HEAD`)

> Every REAL/PARTIAL finding below was verified by the MAIN thread (file:line read +
> live SQL via Supabase MCP) per L17 / `feedback_audit_findings_require_live_verification.md`.
> Subagent fan-out produced the candidates; main thread confirmed or rejected each.

## REAL findings

### EF-1 (P1) — `proactive-coach-promotion` writes to a nonexistent table → every rank promotion's celebration is inert
- **Lens:** L21 (EF semantic correctness) + L22 (schema-vs-payload parity)
- **File:** `supabase/functions/proactive-coach-promotion/index.ts:81-96`
- **Verified live:** `coach_interactions` table **does not exist** (`information_schema.tables` → only `ai_coach_interactions`, `coach_memory`, `rank_promotions`). The actual chat table `ai_coach_interactions` has columns `user_message, ai_response, model_used, channel, snapshot_id` — NOT the `role/content/metadata` this code inserts.
- **Effect:** `insertRes.error` is set on every call → function returns HTTP 500 at line 95 **before** `sendOneSignalPush` (line 100). Trigger `trg_dispatch_proactive_coach_promotion` (confirmed live on `rank_promotions`) fires correctly, so the path is exercised on every promotion — and fails. No congrats message persisted, **no push notification sent**. Directly defeats the promotion-celebration loop (founder's core concern).
- **Compounding (P2):** `logTelemetry` (line 242) inserts `{user_id, op_type, message, severity}` into `client_errors`, but that table's columns are `id, user_id, error_code, error_message, op_type, retry_count, client_version, platform, created_at` — **no `severity`, no `message`**. The failure telemetry ALSO silently fails (best-effort try/catch) → the breakage is invisible.
- **Compounding (P2):** `RANK_LABELS` (lines 40-52) uses codes `PO2/PO1/ENS/LTJG/LCDR/CDR/CAPT`; canonical ladder (`rank_ladder_data.dart:77-178`) is `SD2,SD1,LS,PO,CPO,MCPO,SubLt,Lt,LtCdr,Cdr,Capt`. 7 of 11 ranks fall through to the raw code in the AI prompt.
- **Blast tier:** platform (EF). Fix requires source change + byte-identical redeploy + smoke (`/edge-function-deploy-rollback`). Deployed version is v2 (matches git).

### DRIFT-1 (P2) — restore relabels every workout session to "Workout"
- **Lens:** L1 (writer/reader drift, restore path)
- **File:** `lib/core/services/sync/sync_workout.dart:537`
- **Verified:** migration `068b:22` renamed `workout_logs.exercise_name → workout_name`; the write side (lines 130-138) correctly upserts `workout_name` with `onConflict: user_id,date,workout_name`. But the RESTORE reader at line 537 still reads `map['exercise_name'] ?? 'Workout'`. Post-rename the cloud row has no `exercise_name`, so every restored session relabels to the literal `'Workout'`.
- **Effect:** on any restore (new device / reinstall / logout→login) all session labels ("Push A", "Pull B") become "Workout" — corrupts home history, receipt headers, AI snapshot. Per-exercise data (sets/reps in `workout_log_exercises`) is intact; lines 595/620 read a different, un-renamed table and are fine.
- **Fix:** read `map['workout_name']`; add a cloud→restore→Hive round-trip behavioral test (the new write-side test only pins the write).

## PARTIAL / known-gap (not new regressions in this window)

- **EF-2 (P2)** — `weekly-recalc/index.ts` has no in-function cron telemetry (OI-21 known gap, excluded by `cron_telemetry_adoption_test.dart`). Consequence: weekly-recalc failures never reach `cron_call_log`, so the new `alert_edge_function_health` cron (076/077) is blind to them.
- **EF-3 (P2, efficiency / L31)** — `evaluate-rank-promotions` and `weekly-recalc` both full-roster recompute every run with no skip-if-no-change predicate. Fine now; scales with user count. Pre-existing (documented Hermes-R2 #13 / code-review-2026-05-11).
- **NUT-1 (P2, L1)** — `nutrition_write_service.logWater` (line ~401) writes Hive key `water_<istDate>` in `nutritionBox`, but the canonical reader/sync use `water_ml_<istDate>` in `healthBox`. **Zero callers** (`grep .logWater(` → none); live path is `HealthWriteService.logWater`. Dormant drift, not a live break — remove or fix the dead method.

## FALSE ALARMS — verified clean (do not action)

- Rank monotonic guard (client `shouldPromote` rank_service.dart:61-66 + cron `evaluate-rank-promotions`): strict `>` ordinal, null→-1. **No demotion possible.** ✓
- `weekly-recalc` `total_workouts_done`: `Math.max(recomputed, existing)` — prevents the 3a7b9f Sunday-demotion class. ✓
- `workout_repository.dart` −287-line deletion (`logSetWithPrRescan`/`_recomputePrFlagsForExercise`): 0 live callers; PR rescan now in `WorkoutWriteService._rescanPrFor`. No orphaned reader. ✓
- `calculateCurrentStreak` / `currentStreak`: freeze-consume gated on `consume:true`; read path is side-effect-free. No L26 regression. ✓
- 076 alert crons: `client_errors.created_at`, `subscriptions.created_at`, `subscriptions.status`, `cron_call_log.http_status`, `cron_call_log.started_at` — **all exist live.** Only the original 076 edge-function-health cron had the column bug, already fixed by 077. ✓
- Migration 074 / `exercise_library`: **258 rows seeded live**, 074 present in migration history. `food_database` = 1431. L13 parity clean. ✓
- EF deploy parity: evaluate-rank-promotions v7, weekly-recalc v16, weekly-report v21, proactive-coach-promotion v2 — all match git. ✓
- nutrition IST anchoring + rank writer/reader field match: verified against `docs/sot_registry.yaml`. ✓

## Net
Two actionable bugs in the rank/restore journey: **EF-1 (P1, promotion celebration inert)** and **DRIFT-1 (P2, restore label corruption)**. Both directly on the founder's "start → promotions → phases over a year" path. The monotonic guards that were the headline concern are correct.
