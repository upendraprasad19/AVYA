# Drift-Fix Batch — Design Spec

**Date:** 2026-05-24
**Branch:** `claude/frosty-bardeen-cce54b` (base `2b09544`)
**Origin:** First-run output of `writer-reader-drift-detector` agent (ECC adoption B1) on workout + nutrition domains, 2026-05-24.
**Founder direction:** "everything including structural. brainstorm. make a plan." — locks scope to all 9 findings including 2 schema migrations.

---

## Goal

Close every drift finding surfaced by the agent's first run against the workout and nutrition domains, in a single commit, with regression coverage for the bug class (writer/reader field drift — 7+ instances since Test #6, per [[feedback_writer_reader_field_drift_recurring]]).

## Approach

**Approach C — single mega-commit** (founder-selected). All 9 fixes + 1 schema migration + Gate 23 + regression tests land in one commit. Trade-off accepted: waives [[feedback_gates_before_refactor]] for this batch since the 9 findings are mostly mechanical and pre-commit hook (~8 min) only runs once instead of 3+ times. Gate-before-refactor rule still applies to future structural batches.

## Standing principles applied

- [[feedback_no_deferrals]] — every finding closed in this batch, no `terminal_state: deferred`.
- [[feedback_writer_reader_field_drift_recurring]] — every fix ships behavioral/contract test pinning the writer↔reader contract, not just source-grep presence checks.
- [[feedback_use_ist_throughout]] — F1 nutrition P0 is the next surface for the recurring IST drift bug class.
- [[feedback_audit_closure_yaml_required]] — closure tally appended to `docs/audit/2026_05_24_drift_fix_closures.yaml`.

---

## Scope — 9 findings

### Nutrition domain (4)

#### F1 P0 — `NutritionWriteService.computeLogKey` doesn't use `istDateStr()`

**File:** `lib/core/services/nutrition_write_service.dart:87-88` + `:739-740` (canonical computeLogKey).
**Current shape:**
```dart
final dateKey = '${istDate.year}-${istDate.month.toString().padLeft(2, '0')}-${istDate.day.toString().padLeft(2, '0')}';
```
**Problem:** Parameter NAME `istDate` asserts caller pre-shifts to IST, but 7 callers pass raw `DateTime.now()` (device-local). On devices in non-IST timezones (founder traveling, future non-India users), a meal logged at IST 00:30 from a UTC-tz device produces a Hive key with **yesterday's** date. Readers (`_getMealsToday`, `TodaysMealsCard`) use `istDateStr(DateTime.now())` correctly → meal vanishes from "Today's Meals."
**Fix:** Replace hand-assembly with `istDateStr(date)` from `lib/core/utils/ist_date.dart`. Both sites (line 87-88 inline build inside `logMeal` AND line 739-740 inside `computeLogKey`).
**Regression test:** `test/contracts/nutrition_write_service_ist_anchored_test.dart` — given UTC `DateTime(2026, 5, 24, 22, 0)` (which is IST 2026-05-25 03:30) as the `date` arg, asserts Hive key contains `nlog_2026-05-25_*` not `nlog_2026-05-24_*`.

#### F2 P1 — Gate 23: `nlog_*` canonical writer enforcement

**Mirror:** Gate 17 (`scripts/check_exlog_key_canonical.dart` — shipped Test #16.1, allowlist enforcement for `exlog_*`).
**New script:** `scripts/check_nlog_key_canonical.dart`.
**Allowlist (sole sites permitted to construct `nlog_*` string literals):**
1. `lib/core/services/nutrition_write_service.dart` (canonical `computeLogKey`).
2. `lib/core/services/sync_service.dart` (`_nlogKeyForRestore` documented restore mirror — takes raw cloud maps, not typed `List<FoodItem>`).
3. `lib/core/services/nlog_key_migrator.dart` (migration mirror).
**Failure mode:** Source-grep finds any other file with literal `'nlog_'` followed by `${` or `+ ` (string assembly pattern).
**Wired into:** `/build-apk` skill's gate list (Gate 23).
**Regression test:** `test/contracts/nlog_key_canonical_test.dart` — asserts exactly 3 allowlisted files match the pattern; none elsewhere in `lib/`.

#### F3 P2 — Cloud `nutrition_log_items` dead fallback reads

**File:** `lib/core/services/sync/sync_nutrition.dart:172-174`.
**Current shape:**
```dart
'food_name': item['name'] ?? item['food_name'] ?? '',
'quantity_g': item['serving_g'] ?? item['quantity_g'],
```
**Problem:** Writer (`FoodItem.toMap` at `nutrition_write_source.dart:62-70`) emits exactly `{name, quantity_g, calories, protein, carbs, fat, fiber}` — never `food_name` or `serving_g`. The fallback reads are pre-2026 legacy paths with no live producer.
**Fix:** Drop the fallbacks → cleaner code, single canonical key per field:
```dart
'food_name': item['name'] ?? '',
'quantity_g': item['quantity_g'],
```
**Regression test:** None (dead-code removal; covered by existing per-item sync round-trip tests in `test/contracts/nutrition_write_to_read_contract_test.dart`).

#### F4 P2 — Add `nutrition_log_items.fiber` column

**Migration:** `068b_drift_fix_batch.sql` (combined with F4 workout — see below).
**SQL fragment:**
```sql
ALTER TABLE public.nutrition_log_items
  ADD COLUMN IF NOT EXISTS fiber NUMERIC DEFAULT 0;
COMMENT ON COLUMN public.nutrition_log_items.fiber IS
  'Per-item fiber (g). Populated by NutritionWriteService→sync_nutrition projection. Added 2026-05-24 (drift-fix F4).';
```
**Client write change:** `lib/core/services/sync/sync_nutrition.dart:169-179` per-item projection adds `'fiber': item['fiber'] ?? 0`.
**Backfill source:** None (no pre-existing data outside Hive; legacy rows stay 0 — same precedent as `nutrition_logs.total_fiber` from migration 034 per CLAUDE.md §7 column-type notes).
**Regression test:** `test/contracts/nutrition_log_items_fiber_projection_test.dart` — source-grep `sync_nutrition.dart` for the `'fiber':` key in the per-item projection block.
**`backups/applied_migrations.json` update:** Pair-update per [[feedback_migration_apply_record_pair.md]].

### Workout domain (5)

#### F1 P1 — AI snapshot reports SUM reps as "PR reps"

**File:** `lib/features/ai_coach/repositories/ai_coach_repository.dart:1939`.
**Current shape:** Reads `log['reps_completed']` (semantic = SUM across sets per WriteService contract) and surfaces it under PR record as `'reps': N`.
**Problem:** A 5-set workout at 100kg × 10 reps each surfaces as "PR: 100kg × 50 reps" in AI snapshot.
**Fix (founder-locked: PR-set reps semantic):**
```dart
final sets = (log['sets'] as List?) ?? [];
int? prSetReps;
if (sets.isNotEmpty) {
  final prWeight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
  // Find the set whose weight matches PR weight (max across sets per WriteService contract).
  for (final s in sets) {
    if (s is Map) {
      final w = (s['weight_kg'] as num?)?.toDouble() ?? 0;
      if (w == prWeight) {
        prSetReps = (s['reps'] as num?)?.toInt();
        break;
      }
    }
  }
}
// Fall through to legacy rows lacking sets[]
prSetReps ??= (log['reps_completed'] as num?)?.toInt();
```
**Regression test:** `test/ai_coach/pr_snapshot_uses_pr_set_reps_test.dart` — given exlog `{weight_kg: 100, reps_completed: 28, sets: [{w:60,r:10},{w:80,r:8},{w:100,r:5},{w:100,r:5}]}`, asserts PR snapshot reports `reps: 5` (PR-set reps), never `reps: 28` (SUM). Plus legacy-row fallthrough case (no `sets[]` → reads `reps_completed`).

#### F2 P1 — Drop top-level `duration_seconds` dead reads

**Files:**
- `lib/features/train/widgets/workout_receipt_card.dart:368` — reads `log['duration_seconds']`.
- `lib/features/train/screens/train_screen.dart` — multiple sites read `log['duration_seconds']`.

**Problem:** Writer (`WorkoutWriteService` exlog map at `:166-179`) does NOT emit `duration_seconds` at top level. Per-set duration lives at `sets[].duration_sec` only. All these reads silently return 0 for modern rows.
**Fix (founder-locked: drop reads, use `WorkoutReadService.bestPerSetDuration` everywhere):**
- Replace every `log['duration_seconds']` read in receipt + train_screen with `WorkoutReadService.bestPerSetDuration(log) ?? 0`.
- The cloud projection at `sync_workout.dart:250` (which DOES compute aggregate sum) is unchanged — cloud column stays for downstream analytics; client-side derivation routes through `bestPerSetDuration`.

**Regression test:** `test/contracts/no_top_level_duration_seconds_reads_test.dart` — source-grep `lib/features/train/widgets/workout_receipt_card.dart` + `lib/features/train/screens/train_screen.dart` for `log['duration_seconds']` / `log["duration_seconds"]` patterns (strip comments first per [[feedback_source_grep_strip_comments_first.md]]). Fails if any non-comment match exists.

#### F3 P2 — Drop `notes: log['id']` dead stuffing

**File:** `lib/core/services/sync/sync_workout.dart:133`.
**Current shape:**
```dart
'notes': log['id'],  // store local ID for reference
```
**Problem:** `log['id']` is never set by `WorkoutWriteService`; the field is null for all post-Test-#6 authored rows. The comment "store local ID for reference" is dead intent. No production reader.
**Fix:** Remove the line. Cloud column `notes` stays NULL (always was effectively).
**Regression test:** Source-grep test in `test/contracts/cloud_workout_logs_no_notes_stuffing_test.dart` — fails if `'notes': log[` appears in `sync_workout.dart`.

#### F4 P2 — Rename cloud `workout_logs.exercise_name` → `workout_name`

**Migration:** `068b_drift_fix_batch.sql` (atomic rename per founder choice — sole tester, controls all installs).
**SQL fragment:**
```sql
ALTER TABLE public.workout_logs RENAME COLUMN exercise_name TO workout_name;
COMMENT ON COLUMN public.workout_logs.workout_name IS
  'Workout session name (e.g. "Push A"). Renamed from exercise_name 2026-05-24 (drift-fix F4) — the value was always a session label, never a per-exercise identifier. Per-exercise data lives in workout_log_exercises.';
```
**Client write changes:**
- `lib/core/services/sync/sync_workout.dart:129` — `'exercise_name': wlogName` → `'workout_name': wlogName`.
- `_syncWorkoutLogs` `onConflict` param: confirm if `'user_id,date,exercise_name'` constraint name needs migration — **needs live verification** (see "Pre-flight verification" section).
**Client read changes:** None expected — no production reader of cloud `workout_logs.exercise_name` outside the weekly-report Edge Function (which reads it as a session label). That function must be updated and redeployed in the same batch.
**Edge Function deploy:** `weekly-report` (and any other readers found in pre-flight grep of `supabase/functions/`) — redeploy with `workout_name` reads.
**Critical UNIQUE constraint:** Per CLAUDE.md §7, `workout_logs` has unique on `(user_id, date, exercise_name)` (one of the partial unique indexes flagged in Test #16 / OI-42). Migration must drop+recreate this constraint with new column name. SQL fragment:
```sql
ALTER TABLE public.workout_logs DROP CONSTRAINT IF EXISTS workout_logs_user_id_date_exercise_name_key;
-- After RENAME, recreate:
ALTER TABLE public.workout_logs ADD CONSTRAINT workout_logs_user_id_date_workout_name_key UNIQUE (user_id, date, workout_name);
```
**Regression test:** `test/contracts/cloud_workout_logs_uses_workout_name_test.dart` — source-grep `sync_workout.dart` projection block for `'workout_name':`, fails if `'exercise_name':` still appears in `workout_logs` upsert.
**`backups/applied_migrations.json` update:** Pair per [[feedback_migration_apply_record_pair.md]].

#### F5 P2 — Delete `workout_repository.logSetWithPrRescan`

**File:** `lib/features/train/repositories/workout_repository.dart:1114` (method declaration only).
**Pre-flight grep (already verified):** Zero active callers in `lib/` outside the declaration itself. References in `lib/core/services/exlog_key_migrator.dart`, `write_result.dart`, `tool_dispatcher.dart` are doc comments. Test files reference for absence-assertion.
**Fix:** Delete lines 1114-1205 (method body, ~91 lines). Adjust any imports if needed.
**Regression test:** Existing `test/contracts/tool_dispatcher_log_pr_uses_writeservice_test.dart` already pins that dispatcher doesn't call this method. Add `test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart` — source-grep `lib/features/train/repositories/workout_repository.dart` fails if `Future<String> logSetWithPrRescan(` reappears.

---

## Migration 068 — combined

**File:** `supabase/migrations/068b_drift_fix_batch.sql`.
**Content:**
```sql
-- Migration 068 — drift-fix batch (2026-05-24)
-- Source: docs/superpowers/specs/2026-05-24-drift-fix-batch-design.md
-- F4 workout: rename workout_logs.exercise_name → workout_name
-- F4 nutrition: add nutrition_log_items.fiber

BEGIN;

-- ============================================================================
-- F4 workout — rename column + recreate unique constraint
-- ============================================================================
ALTER TABLE public.workout_logs DROP CONSTRAINT IF EXISTS workout_logs_user_id_date_exercise_name_key;
ALTER TABLE public.workout_logs RENAME COLUMN exercise_name TO workout_name;
ALTER TABLE public.workout_logs ADD CONSTRAINT workout_logs_user_id_date_workout_name_key UNIQUE (user_id, date, workout_name);
COMMENT ON COLUMN public.workout_logs.workout_name IS
  'Workout session name (e.g. "Push A"). Renamed from exercise_name 2026-05-24 (drift-fix F4) — the value was always a session label, never a per-exercise identifier. Per-exercise data lives in workout_log_exercises.';

-- ============================================================================
-- F4 nutrition — add fiber column
-- ============================================================================
ALTER TABLE public.nutrition_log_items
  ADD COLUMN IF NOT EXISTS fiber NUMERIC DEFAULT 0;
COMMENT ON COLUMN public.nutrition_log_items.fiber IS
  'Per-item fiber (g). Populated by NutritionWriteService→sync_nutrition projection. Added 2026-05-24 (drift-fix F4). Legacy rows default 0 — no backfill source (no fiber column existed pre-migration).';

COMMIT;
```

**Apply via:** `mcp__ba7b5e8e__apply_migration` (per CLAUDE.md §2a — MCP only for fitness app project).
**Backup:** Both `supabase/migrations/068b_drift_fix_batch.sql` (source) AND `backups/applied_migrations.json` entry (live-applied marker) updated in the same commit per [[feedback_migration_apply_record_pair.md]].

---

## Pre-flight verification (must run before writing migration)

These are not yet verified in this brainstorm — implementer agent must verify in T0:

1. **Exact constraint name for `workout_logs` unique** — query live: `SELECT conname FROM pg_constraint WHERE conrelid = 'public.workout_logs'::regclass AND contype = 'u';`. The `DROP CONSTRAINT IF EXISTS workout_logs_user_id_date_exercise_name_key` above is a guess based on Postgres naming convention; real name may differ.
2. **Other readers of `workout_logs.exercise_name`** — grep `supabase/functions/` for `exercise_name` joined with `workout_logs`. Likely callers: `weekly-report`, `morning-alert`, `rolling-context`, `compute-coach-signals`. All identified callers redeploy with `workout_name`.
3. **F5 grep already done (above)** — zero active callers confirmed.

---

## Test coverage summary

| Finding | Test path | Type |
|---|---|---|
| Nutrition F1 P0 | `test/contracts/nutrition_write_service_ist_anchored_test.dart` | Behavioral (Hive write → key inspection) |
| Nutrition F2 P1 | `test/contracts/nlog_key_canonical_test.dart` + `scripts/check_nlog_key_canonical.dart` | Source-grep + Gate 23 |
| Nutrition F3 P2 | Covered by existing `nutrition_write_to_read_contract_test.dart` | (no new test) |
| Nutrition F4 P2 | `test/contracts/nutrition_log_items_fiber_projection_test.dart` | Source-grep |
| Workout F1 P1 | `test/ai_coach/pr_snapshot_uses_pr_set_reps_test.dart` | Behavioral |
| Workout F2 P1 | `test/contracts/no_top_level_duration_seconds_reads_test.dart` | Source-grep (comment-stripped) |
| Workout F3 P2 | `test/contracts/cloud_workout_logs_no_notes_stuffing_test.dart` | Source-grep |
| Workout F4 P2 | `test/contracts/cloud_workout_logs_uses_workout_name_test.dart` | Source-grep |
| Workout F5 P2 | `test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart` | Source-grep |

All source-grep tests strip `/* ... */` + `// ...` comments first (per [[feedback_source_grep_strip_comments_first.md]]).

## Gate 23 wiring

- New script: `scripts/check_nlog_key_canonical.dart`.
- Wire into `/build-apk` skill's gate list at the same insertion point as Gate 17.
- Document in CLAUDE.md §6 (rule 22 references the gate list).

---

## Out of scope (deferred to future batches with explicit rationale)

None. All 9 findings + 2 schema migrations close in this batch.

The agent's report also flagged:
- **Nutrition F4 P2 deeper option**: Could add `nutrition_log_items.fiber` AND backfill from a future per-item analytics rebuild. This batch ships the additive column only; backfill remains 0 for legacy rows. Founder may revisit when per-item fiber analytics becomes a product need.
- **Workout F4 P2 cloud reader updates**: Edge Functions reading `workout_logs.exercise_name` redeploy as part of this batch. Any function NOT discovered in pre-flight grep that subsequently fails will surface in `client_errors` + cron telemetry — fix in a hotfix commit if found.

---

## Closure tracking

**Closure YAML:** `docs/audit/2026_05_24_drift_fix_closures.yaml`.
**Format:** Per [[feedback_audit_closure_yaml_required]] + [[feedback_closure_yaml_per_finding_discipline]].
**Schema:**
```yaml
batch: 2026-05-24-drift-fix
total_findings: 9
closed_count: 9
findings:
  - id: nutrition-F1
    severity: P0
    terminal_state: closed_in_commit
    commit_sha: <SHA>
    test_path: test/contracts/nutrition_write_service_ist_anchored_test.dart
  # ... (8 more entries with same shape)
```

---

## Discipline gate compliance

- **Rule 21 (regression test required):** 8 of 9 findings ship behavioral or source-grep tests (F3 nutrition covered by existing test). ✅
- **Rule 22 (diagnose-doc required for `fix:` commits):** Single mega-commit will be `fix(drift): close 9 drift-fix-batch findings (closes-diagnose: 524d12)`. Diagnose doc at `docs/diagnoses/2026-05-24-drift-fix-batch-524d12.md` summarizes the 9-finding closure as one logical event.
- **Pre-commit hook:** Passes `flutter analyze` + `flutter test`. ~8 min.
- **Migration pair-update:** `supabase/migrations/068b_drift_fix_batch.sql` + `backups/applied_migrations.json` in same commit. ✅
- **No `--no-verify`:** Standard pre-commit run, no bypass. ✅

---

## Success criteria

1. Migration 068 applied live and visible in `list_migrations` MCP query.
2. All 9 contract tests pass on first run.
3. Pre-commit hook (`scripts/pre-commit.sh`) passes without `--no-verify`.
4. `dart run scripts/check_nlog_key_canonical.dart` exits 0.
5. Closure YAML `docs/audit/2026_05_24_drift_fix_closures.yaml` shows 9/9 closed.
6. Diagnose-doc `docs/diagnoses/2026-05-24-drift-fix-batch-524d12.md` passes `dart run scripts/validate_diagnose_doc.dart`.
7. Re-running the drift-detector agent against workout + nutrition domains surfaces ZERO findings.
8. Pushed to `origin/main` (after founder approval — APK build is a separate, explicit ask per [[feedback_apk_build_explicit_approval.md]]).
