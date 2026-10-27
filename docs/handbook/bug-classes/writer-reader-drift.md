---
title: Writer/reader field-name or semantic drift
category: bug-classes
source_memory: feedback_writer_reader_field_drift_recurring.md
last_reviewed: 2026-05-28
---

# Writer/reader field-name or semantic drift

## The class

Every WriteService refactor or Hive contract change risks one of:

- The writer changes how a field is computed (e.g. `reps_completed` was per-set, becomes SUM).
- The writer renames a field (`sets_completed` → `set_number`, `duration_seconds` → `duration_sec`).
- The writer's source of truth changes entirely (e.g. AI snapshot should read logged `exlog_*`, not planned `schedule_<date>`).
- The reader is never updated.
- The contract test pins field PRESENCE but not SEMANTICS.

The bug surfaces only on specific code paths or after specific data shapes accumulate — sometimes weeks or months later.

## How to detect

Symptoms tend to look like:

- "Receipt shows 0 sets · 26 reps · 85 kg" (one field reading 0 while siblings populate).
- AI coach speaking nonsense numbers ("PR: 100kg × 50 reps") because the projection reads a SUM as per-set.
- Restored-from-cloud data renders incorrectly after a reinstall, even though fresh local writes look fine.
- Edit-sheet shows "No entries" even though entries exist (the sheet filtered on a field the reader never injected).

## Prevention

1. **Whenever a WriteService field is renamed, computed differently, or moved to a new SoT — in the SAME PR**, grep every consumer:

   ```bash
   grep -rn "<old_field_name>" lib/ --include="*.dart"
   grep -rn "<old_field_name>" supabase/functions/ --include="*.ts"
   ```

   Every match is a candidate consumer. Audit each; either update or document why it's safe to leave.

2. **Contract tests must pin SEMANTICS, not just PRESENCE.** Don't just `assert log['reps_completed'] != null`; assert `log['reps_completed'] == 85` (sum of `10+15+10+15+10+10+15`). If the field's meaning changes, the test must explicitly assert the new meaning.

3. **Legacy + canonical field names**: when introducing a new canonical alongside a legacy (e.g. `duration_sec` canonical, `duration_seconds` legacy), the deserializer MUST accept both. The contract test MUST cover both shapes. Otherwise restored data silently drops the field.

4. **SoT changes**: when the SoT itself changes (AI snapshot now reads logged not planned), grep ALL snapshot consumers (`_getTodayWorkout`, `_getYesterdayWorkout`, `_getThisWeekWorkouts`, `_getMealsToday`, etc.) and verify each one's SoT decision is intentional and consistent.

5. **The first reader you fix is usually NOT the only one.** Always look for siblings — co-located helpers (`lastSets` next to `_getLastPerformance`), parallel renderers (`workout_receipt_card` next to `train_screen`).

## Instances (≥15 distinct, since Test #6 WorkoutWriteService rewrite)

| Surface | Bug | Field/shape | Reader missed |
|---|---|---|---|
| Test #7 ship | "0 sets" on receipt | `set_number` ≠ `sets_completed` | `WorkoutReceiptData` |
| Test #8 | AI snapshot drops meals/exercises | `id`/`type` filters | `_getMealsToday`, `_getNutritionTrend7d`, `_getThisWeekWorkouts`, `_getPersonalRecords` |
| Test #12 | 0s timed display | summary-vs-per-set tier | `WardSetChips` |
| Test #12.5 | logging_type per-set strip | per-set normalization | `WorkoutWriteService` library lookup |
| Test #15.3 | Reps pre-fill 85 | `reps_completed` was SUM after Test #6 | `_getLastPerformance` |
| Test #15.3 | AI coach says 8 exercises | reader read schedule, not logs | `_getTodayWorkout` |
| Test #15.3 | Timed exercise 0s | `duration_seconds` legacy vs `duration_sec` canonical | `ExerciseSet.fromMap` |
| Hermes OI-36 | `deleteFoodLog` bypassed WriteService | direct Hive delete vs canonical writer | `NutritionProvider.deleteFoodLog` |
| Drift-fix nutrition F1 | `computeLogKey` not IST-anchored | `.year/.month/.day` hand-roll vs `istDateStr()` | `computeLogKey` + 3 sites |
| Drift-fix workout F1 | AI "PR: 100kg × 50 reps" nonsense | `reps_completed` is SUM but PR snapshot read per-set | `AiCoachRepository` PR projection |
| Drift-fix workout F2 | Receipts always show 0s | `log['duration_seconds']` top-level never emitted | 6 sites across 5 train files |

## When the rule applies

- Any commit that changes a Hive field name, type, or semantics.
- Any commit that changes which Hive key a reader reads from.
- Any commit that adds a new SoT helper superseding an existing one.
- Any commit that restores data shape (cloud → Hive) — restore must match what the local writer produces, or readers silently break post-reinstall.

## When the rule doesn't apply

- Pure UI tweaks (no data shape involved).
- New fields being ADDED (no existing readers to update).
- Renames within a single file where the only reader is co-located.

## References

- CLAUDE.md §4.1 (writer/reader drift is the default suspect class).
- CLAUDE.md §4.4 rule 21 (contract tests pin semantics, not just presence).
- Specialist subagent: `.claude/agents/writer-reader-drift-detector.md` (run per-domain at end of every batch).
- Gates: 17, 23, 42 (`scripts/check_sot_behavioral_test_paths.dart`).
- Related: [`sot-audit-required.md`](sot-audit-required.md), [`id-injection-on-get.md`](id-injection-on-get.md), [source-grep-limits](../testing/source-grep-limits.md).
