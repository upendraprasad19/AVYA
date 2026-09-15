---
title: Source-of-truth audit required on every bugfix
category: bug-classes
source_memory: feedback_source_of_truth_audit.md
last_reviewed: 2026-05-28
---

# Source-of-truth audit required on every bugfix

## The rule

Every bugfix / brainstorm involving data render or state mismatch starts by naming the writer(s) AND the reader(s) of the data, by file:line. The brainstorm/proposal MUST list both.

## How to detect

You're missing this discipline when the proposal:

- Names only the rendering widget ("the receipt shows wrong data").
- Proposes a fix that patches the reader without tracing upstream.
- Doesn't enumerate sibling renderers of the same data type.

## Prevention

When the user reports "X shows wrong/missing data", before proposing a fix:

1. **Name the writer(s).** Grep the field name across all `*.put` / `*.write` callsites. There are usually 2-4 writers (WriteService, EditSheet, restore-from-cloud, AI tool dispatcher). List them.

2. **Name the reader(s).** Grep the field name across all `box.get` / value-access callsites. List them.

3. **Audit field-name parity.** Do all writers use the same field name? Do readers' fallback chains cover all writers' field names?

4. **Pick the fix layer.**
   - If one writer drifts → fix at the writer (or normalize at the WriteService entry point).
   - If readers' fallback chain is wrong → fix at the readers, AND consider adding a max() / best-of merge instead of first-non-null.
   - If contract is genuinely ambiguous → write a `test/contracts/<x>_write_to_read_contract_test.dart` test pinning the agreed shape.

5. **State the fix at BOTH layers** in the proposal. Example:
   - "Writer side: `EditWorkoutLogSheet` should write `set_number` alongside `sets_completed`."
   - "Reader side: `workout_receipt_card.fromExerciseLogs` reads MAX of `set_number` and `sets_completed`."

## Don'ts

- **Don't ship a fix that only patches the reader.** The next writer drift will resurrect the bug at a different reader. Patch the writer if you can; patch BOTH if you can't (cheap defense in depth).

- **Don't ship a fix that only patches the writer for new data.** Existing rows in users' Hive still have the broken shape. Either backfill (migration) or make readers tolerant.

- **Anti-pattern:** "Receipt shows wrong data → patch receipt code → ship." Always trace upstream to the writer, even if the bug is visually in the reader.

## Renderer enumeration (extends the rule)

When patching a reader-side bug, GREP for every widget that renders the same data type. List them all in the proposal AND the commit message. Patch all of them in the same commit (or explicitly say which you're skipping and why).

### Concrete grep recipes by data type

| Data type | Grep |
|---|---|
| Exercise logs | `grep -rn "getExerciseLogsForDate\|exercise_log_index_\|fromExerciseLogs" lib/` |
| Nutrition logs | `grep -rn "nutritionBox\|nlog_\|foodLogProvider" lib/` |
| Subscription state | `grep -rn "subscriptionInfoProvider\|isPro\(\)\|MigratedKey.read.*isPro" lib/` |
| Workout schedule | `grep -rn "scheduleKey\|getScheduleForDate\|schedule_" lib/` |

Renderer enumeration belongs in the brainstorm proposal, not discovered after the fix lands and breaks for the user.

## Instances

- One bugfix patched the bottom-sheet renderer but missed the inline calendar-row renderer that consumed the same `WorkoutRepository.getExerciseLogsForDate`. One grep would have caught both. The same "0 sets · 26 reps · 85 kg" reappeared in the missed surface two batches later.

## References

- CLAUDE.md §4.1 (writer/reader drift is the default suspect class).
- Related: [`writer-reader-drift.md`](writer-reader-drift.md), [`id-injection-on-get.md`](id-injection-on-get.md), [`ist-throughout.md`](../conventions/ist-throughout.md).
