# Agent 7 Findings — Clusters 8, 9, 10, 13, 15

**Date:** 2026-05-16

## Cluster 10 — Telemetry & observability

### F10.1 — 🚨 CONFIRMED_BUG: `AppConstants.appVersion` hardcoded `'1.0.0+23'`, three APKs behind
- **Evidence:** `lib/core/constants/app_constants.dart:99`. Live SQL: `client_errors` last 30d shows 358 rows tagged `'1.0.0+23'` (latest 2026-05-15 04:10) but pubspec is at `1.0.0+26` (commit `300ccc6`).
- **Why:** APKs +24/+25/+26 shipped without bumping the constant. `ErrorTelemetry._currentClientVersion` (`error_telemetry.dart:279`) + `SyncService._currentClientVersion` (`sync_service.dart:285`) both read it. Every recent telemetry row mis-labelled.
- **Class:** "manually kept in sync" with no CI gate. CLAUDE.md fix-table P2-A claims `/build-apk` bumps both — clearly false.
- **Remediation:** Add `scripts/check_app_version_matches_pubspec.dart` build gate. Or parse pubspec at startup via `package_info_plus`.

### F10.2 — `0.0.0+release` 381 historical rows — PASS (pre-fix residue)
All dated 2026-05-06..2026-05-12 (before P2-A landed). Optional cleanup: `UPDATE ... SET client_version='1.0.0+23-legacy'`.

### F10.3 — 89 `PostgrestException 42P10` rows (pre-fix residue) + generic op_types — MIXED
- 31 `upsert_exercise_log` + 29 `upsert_workout_log` + 15 `sync_service_catch_5` + 14 `sync_service_for`. All before 2026-05-15 04:10 (Test #16 migration 064 fix). Last 6h: 0 rows. Class fix is working.
- **BUT:** op_types `sync_service_catch_5` / `sync_service_for` are themselves a discipline violation — useless for triage.
- **Remediation:** Source-grep gate banning numbered catch-block op_types.

### F10.4 — FRAMEWORK_GAP: HIGH_PRIORITY_OP_TYPES client/server drift
- Client (`error_telemetry.dart:78-106`): 17 entries
- Server (`log-client-error/index.ts:117-145`): 18 entries (extra `unique_violation`)
- No contract test compares the two.
- **Remediation:** `test/contracts/high_priority_op_types_parity_test.dart`.

### F10.5 — FRAMEWORK_GAP: No cron-execution telemetry
- `cron.job_run_details.status='succeeded'` means "pg_net dispatched POST", NOT "Edge Function responded 2xx". Test #16 P1-D's `pr-detection` 401-storm was invisible until founder noticed.
- **Remediation:** New `cron_call_log` table; per-cron Edge Function INSERTs status at top of handler. 401s emit `cron_auth_failure_<fn>` to `client_errors`.

## Cluster 8 — Subscription gates

### F8.1 — 🚨 CONFIRMED_BUG: 5+ feature constants have zero `gate()` callsites
- Grep `\.gate\(` → 9 callsites covering only 6 distinct features (`featureCartAuditorPro`, `featureAiTextLogPro`, `featureScanMealPro`, `featureWeeklyAiReport` ×2, `featureProgressPhotos`, `featurePhases2To12` ×2, literal `'ai_body_composition'`).
- Constants without ANY gate:
  - `featurePhotoAnalysis` — CLAUDE.md §14 says PRO. **No client gate → potential silent free-tier bypass.** Needs widget audit.
  - `featurePredictionMonthly` — "fresh prediction every month" is PRO. Likely bug if re-trigger path exists for free users.
  - `featureMorningAlertPro` — server-only enforcement in `morning-alert` Edge Function. Acceptable.
  - `featureAiCoachUnlimited` — server-only enforcement in `ai-proxy`. Acceptable.
  - `featureAdaptiveWorkouts` — Phase 2 future. Acceptable.
  - `featureVoiceNotes` — free since Test #9 F13. Should be `@Deprecated`.
  - `featureActiveWorkoutMode` — free since Test #2 Q6. Already `@Deprecated`.
  - `featureDietPlanPdf` — FREE per CLAUDE.md §14. Should be deleted.
- **Remediation:** `scripts/check_gate_coverage.dart` + `test/contracts/gate_coverage_test.dart`.

### F8.2 — `_highValueFeatures` set correct — PASS

### F8.3 — POTENTIAL_BUG: inline `if (isPro)` checks in 9 widget locations
- `ai_coach_provider.dart:1011,1020`, `ai_coach_screen.dart:244,606`, `weekly_report_card.dart:112`, `edit_profile_screen.dart:1820`, `notification_settings_screen.dart:259`, `profile_screen.dart:508,1418`.
- Some are acceptable (constructor-prop reads when caller is reactive); some are the exact shape that bit Test #12 PRO-upgrade-unlock.
- **Remediation:** Per-callsite audit in Phase E.

### F8.4 — Payment idempotency intact — PASS (5-min replay window + 20/10-min rate limit + sanitized errors).

## Cluster 9 — Cron + Edge Function ops

### F9.1 — 🚨 FRAMEWORK_GAP: `_shared/cron_auth.ts` does NOT exist; auth inlined per-function with brittle env-equality
- **Evidence:** `ls supabase/functions/_shared/` shows no `cron_auth.ts`. Each cron function inlines:
```ts
const isServiceRole = !!serviceRoleKey && token === serviceRoleKey;
```
- Exactly the drift-fragile shape Test #16 P1-D flagged. Vault rotation = silent 401 storm.
- Currently: Vault row populated (length 219, created 2026-05-12 08:04). 17 cron jobs report `succeeded` last 24h — but `succeeded` is dispatch, not HTTP-200.
- **Remediation:** Create `_shared/cron_auth.ts` that decodes JWT signature + verifies `role` claim. Replace inline env-equality in every cron Edge Function.

### F9.2 — NEEDS_INVESTIGATION: `weekly_recap_ready_sunday` has `last_run=null` despite `active=true`
- Last Sunday was 2026-05-10; cron should have fired. Investigate whether it never registered properly or `cron.job_run_details` doesn't capture Sunday-only schedules.

### F9.3 — Edge Function error-shape contract compliance — PASS (4 spot-checks confirmed).

## Cluster 13 — Type consistency

### F13.1 — 4 high-priority columns type-correct — PASS
- `user_profile.injuries` → `text[]` ✓
- `user_profile.preferred_workout_time` → `text` ✓
- `users.terms_accepted_at` → `timestamptz` ✓
- `nutrition_logs.total_fiber` → `numeric` ✓
- Broader 46-table type matrix → defer to Agent 3.

## Cluster 15 — Discipline-gate pass

### F15.1 — Pre-commit hook installed — PASS (shared via parent gitdir, 1113 bytes).
### F15.2 — Diagnose-doc discipline holding — PASS (9 `^fix:` commits since 2026-05-13, 15 `closes-diagnose:` references, 112 docs in `docs/diagnoses/`).
### F15.3 — `docs/skipped-discipline.md` exists with 2 waivers (both SQL-only migrations, 2026-05-11) — PASS.
### F15.4 — FRAMEWORK_GAP: 12 `scripts/check_*.dart` exist; some need adding or renaming for Phase E framework deliverables.

## Class-level red flags (cross-cluster)

1. **AppVersion manual + uncovered** (F10.1) — 3 APK ships failed. Fix: pubspec-parser build gate.
2. **Cron auth brittle env-equality** (F9.1) — 4th instance of the class. Fix: JWT decode in shared module.
3. **Generic op_types in client_errors** (F10.3) — defeat triage. Fix: gate banning numbered catch labels.
4. **HIGH_PRIORITY_OP_TYPES drift** (F10.4) — Edge Function deploy gap. Fix: parity test.
5. **5+ feature constants without gate()** (F8.1) — 2 candidates are bugs, 2 are dead. Fix: gate-coverage gate.
6. **No cron-execution telemetry** (F10.5) — 401 storms invisible. Fix: cron_call_log table.

## Out-of-scope handoffs
- Cluster 4 (Agent 3): 46-table type matrix.
- Cluster 11 (Agent 6): per-callsite audit of 9 `if (isPro)` widget reads (F8.3).
- Cluster 5 (Agent 4): investigate Sunday cron F9.2.
