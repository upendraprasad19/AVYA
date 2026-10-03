# Phase C · Main-thread Verification Log — 2026-05-16

Per `feedback_audit_findings_require_live_verification.md`: every subagent finding gets re-read and re-confirmed by main thread before acting. False positives are expected (3 of 21 on 2026-05-12). Status codes:
- ✅ CONFIRMED — bug is real, fix in Phase E
- ❌ FALSE_ALARM — agent was wrong, drop the finding
- ⚠️ PARTIAL — bug real but agent's framing off; revise

## Verifications complete

### F2-R2 (Agent 1) — sleep_logs unregistered writer — ⚠️ PARTIAL
- **Confirmed:** `lib/features/profile/providers/profile_provider.dart:498` writes direct `healthBox.put('sleep_log_$todayStr', {...})` — no WriteService layer.
- **Refuted:** Agent 1 claimed sync isn't triggered. L507 actually does `unawaited(SyncService.instance.syncSleepNow())` + L508 `pushSnapshot()`. Agent missed those lines.
- **Real bug found during verification:** Date computed via `now.year-now.month-now.day` (device-local), NOT IST. `feedback_use_ist_throughout.md` requires `istDateStr(DateTime.now())`. At IST 00:00–05:30, a user logging sleep gets the wrong date key.
- **Status:** CONFIRMED_BUG class — F2-R2 reframed: not a WriteService bypass (sync is wired), but an IST drift in the date computation. Same bug class as Test #12 / Task A-1 `formatDateKey` IST fix.

### F12-C7-1 (Agent 6) — WorkoutWriteService.onInvalidate callback null — ❌ FALSE_ALARM
- Verified: `onInvalidate` is an optional nullable callback (L49). It's invoked at L196/198/386/388/etc only `if (ref != null && onInvalidate != null)`.
- `conversational_log_handler.dart:256-260` comment explicitly documents this as opt-in: callers that don't wire `onInvalidate` MUST invalidate manually.
- Edit-log path (Trace 2 PASS) confirms manual invalidation works.
- **Drop this finding.**

### F11-C11-2 / F12-C12-3 (Agent 6) — WorkoutScheduleService bypasses WriteService + has zero invalidations — ✅ CONFIRMED
- Verified 13 direct `workoutBox.put` callsites in `lib/core/services/workout_schedule_service.dart` (L248, L412, L717, L844, L855, L1159, L1302, L1430, L1515, L1595, L1605, L1669, L1851).
- Verified ZERO `SyncService.instance.sync` or `pushSnapshot` calls in the same file (grep returned no matches).
- **Confirmed bug:** Schedule mutations (generate plan, copy week, reschedule, assign template, days/week change) write Hive directly with no fan-out to cloud + no provider invalidation.
- **Severity:** HIGH. CLAUDE.md §15 explicitly lists allowed direct-writers — `WorkoutScheduleService` is NOT on the list.
- **Question for Phase D founder:** Should `WorkoutScheduleService` (a) be added to allowed-writers list with mandatory sync wiring per put, or (b) be refactored to call `WorkoutWriteService.upsertScheduled` which already exists at L427? Option (b) is cleaner but riskier. Founder picks.

### F5-S1 (Agent 4) — applied_migrations.json parity gap — ⚠️ PARTIAL
- Verified: `backups/applied_migrations.json` is missing "024" (line 24 jumps "023" → "025"). 71 entries.
- Disk has 72 files (sequential 001-068 + timestamp-format migrations 20260328000001+).
- Live `supabase_migrations.schema_migrations` has 61 entries — fewer than both disk and JSON.
- **Reframed bug:** Multiple mismatch — JSON vs disk + JSON vs live + disk vs live. Live uses timestamp format; JSON uses sequential. Naming convention split during the project's history.
- **Action item:** Phase E should normalize: pick one format (live tracks ground-truth) + regenerate `applied_migrations.json` from live. Migration 024 specifically: confirm it was applied to live (likely under a different version string) before deciding to backfill the JSON.

### Agent 4 RED FLAG zero-row tables — ⚠️ AGENT 4 LARGELY WRONG, but tables still 0
- **Verified:** Sync IS wired at every claimed-missing mutation site:
  - `NutritionWriteService.saveMealPreset` L541 — fires `unawaited(SyncService.instance.syncNutritionData())` ✅
  - `nutrition_provider.dart:1252` (custom food) — fires `syncCustomItemsNow()` ✅
  - `workout_repository.dart:1483` (custom exercise) — fires `syncCustomItemsNow()` ✅
  - `diet_plan_screen.dart:231` — fires `syncSavedDietPlan(planData)` ✅
  - `conversational_log_handler.dart:153` (measurement) — fires `syncMeasurementsNow()` ✅
- **Refuted:** Agent 4's "missing fan-out trigger" diagnosis is WRONG.
- **Real status:** Sync is wired. So why are the tables empty?
- **Live telemetry check:** Queried `client_errors` for any `upsert_saved_meal`, `upsert_sleep_log`, `upsert_measurement`, `upsert_diet_plan`, `upsert_referral_*` op_types — **NONE exist** (last 30 days). Compare: `upsert_workout_log` has 94 occurrences, `upsert_nutrition_log` has 20.
- **Most likely root cause:** With only 4 test users + manual-only low-traffic features (save meal preset / log sleep manually / add body measurement / save diet plan / generate referral code), **users have not actually exercised these features.** Tables are 0 because feature usage is 0, not because sync is broken.
- **Hardening recommendation:** Even if not a bug, **add success-path telemetry** (`upsert_<table>_success` op_types written from sync methods) so we can distinguish "feature not used" from "sync silently failing" in future audits. This is a FRAMEWORK_GAP, not a CONFIRMED_BUG.
- **Phase E action items reframed:**
  1. ✅ Keep current sync wiring (already correct).
  2. NEW: Add success-path telemetry emission to sync methods.
  3. NEW: Add `_restoreReferralCodes` + `_restoreReferralRedemptions` per Agent 4's FRAMEWORK_GAP (still valid — cross-device restore IS missing for referrals).
  4. NEW: Verify by triggering one of these features manually + watching cloud table populate (smoke test).

### F6-2 (Agent 5) — `logPR` tool bypasses WorkoutWriteService — ✅ CONFIRMED
- Verified at `tool_dispatcher.dart:349`: `await WorkoutRepository.instance.logSetWithPrRescan(...)`. Sibling `log_set` at L312 correctly routes through `WorkoutWriteService.logExercise`.
- This is the 8th instance of the writer/reader drift class.
- Test #16.1 / Bug A closed the rogue-key bug but didn't move the caller through the canonical WriteService.
- **Phase E fix scope:** replace the call with `WorkoutWriteService.logExercise(date, name, [ExerciseSet(weightKg, reps, loggedAtMs: now)])`. Move PR rescan inside the WriteService.

### F6-3 (Agent 5) — `model_used=pending` fire-and-forget UPDATE — ✅ CONFIRMED
- Verified at `ai-proxy/index.ts:319-329`: `.update({...}).eq('id', reservationId).then((r) => {if(r.error) console.error})` — no await, no telemetry on failure.
- Comment at L309-311 acknowledges the trade-off ("Fire-and-forget so the HTTP response doesn't block on this final write"). 8 stuck rows over 2 weeks shows the trade-off is wrong.
- **Phase E fix:** `await` the UPDATE; promote any error to telemetry.

## Verifications pending

Only Agent 3 (DB columns × NULL counts) remains. Agent 7 confirmed broader 46-table type matrix is Agent 3 territory.

## Pattern emerging from 4-agent reports

**Recurring root cause:** drift between user-action mutation sites and the SoT-gated WriteService / Sync trigger layer. Same class as Tests #6→#16:
1. **F2-R2 / F14-D2 (Agents 1 + 4):** 8 zero-row cloud tables — sync methods exist but not fired from mutation sites. Fixed by 5–6 LoC additions (`unawaited(syncXxx())`).
2. **F11-C11-2 / F12-C12-3 (Agent 6):** `WorkoutScheduleService` 13 direct puts with no sync. Same class.
3. **F2-R3 (Agent 1):** WriteService asymmetry — Health domain (sleep, weight, measurements) has no WriteService gating Workout/Nutrition enforces.

**Implication:** Phase E should consider a `HealthWriteService` + audit-gating script that enforces "every mutation surface to the 3 user-scoped boxes goes through a WriteService" rather than fixing each gap individually.
