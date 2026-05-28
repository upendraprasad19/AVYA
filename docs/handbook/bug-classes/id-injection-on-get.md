---
title: Hive box.get returns the value map — inject id from the key
category: bug-classes
source_memory: feedback_id_must_be_injected_on_get.md
last_reviewed: 2026-05-28
---

# Hive box.get returns the value map — inject id from the key

## The class

When a Hive read path consumes a `box.get(key)` value and surfaces it to UI/consumers, the Hive KEY is NOT part of the returned map. Most consumers want both — the key (for edits / deletions / cache invalidation) AND the value fields.

If the reader doesn't inject the key as `id`, downstream filters like `log['id'] is String` strip every row silently.

## How to detect

- Edit sheet shows "No entries" / "No exercise logs for this day" even though entries exist.
- Downstream filter on `log['id']` returns empty.
- Hive inspector confirms the rows are there; the repository is dropping the id during the cast.

## Prevention

Every repository method that returns Map values from a Hive read MUST inject the Hive key as `id`:

```dart
for (final id in index) {
  final raw = box.get(id);
  if (raw is Map) {
    final m = Map<String, dynamic>.from(raw);
    m['id'] = id;       // MANDATORY
    logs.add(m);
  }
}
```

Applies to ALL `box.get` reads that surface to consumers. Exceptions (e.g. AI snapshot iterating `box.toMap()` directly + using the key inline) document themselves via the iteration shape.

### Forbidden patterns

- `Map<String, dynamic>.from(raw)` immediately added to a returned list without `m['id'] = key` first.
- Reader filters like `where(log['id'] is String)` when the writer doesn't set the field AND no intermediate layer injects it.

### Recommended gate

A pre-commit / Gate-N check that scans `lib/**/*_repository.dart` for `box.get(...)` patterns inside methods returning `List<Map<...>>`. Require either:

1. The returned map has `m['id'] = ...` assigned within 5 lines, OR
2. The method body comments document why the key is intentionally dropped.

Until that gate exists, every PR touching a repository read path must include a contract test asserting `id` is on the returned map. Template: `test/contracts/edit_log_id_injection_test.dart`.

## Instances

`WorkoutRepository.getExerciseLogsForDate` walked `exercise_log_index_<date>`, called `_hive.workoutBox.get(id)`, and returned the value maps directly:

```dart
// PRE-FIX — id LOST in the cast:
final raw = _hive.workoutBox.get(id);
if (raw is Map) {
  logs.add(Map<String, dynamic>.from(raw));   // <-- id not on map
}
```

`EditWorkoutLogSheet._loadRows` then did `logs.where((log) => log['id'] is String)` → every row stripped → "No exercise logs for this day." Bug latent since the WriteService rewrite; surfaced on first Edit-sheet use.

This is the third Hive-field-name-contract drift instance in close succession:

1. `set_number` / `sets_completed` rename broke receipt rendering.
2. EditWorkoutLogSheet save wrote `sets_completed` while WriteService wrote `set_number`.
3. `id` never injected on returned map; Edit sheet filter strips every row.

## References

- Related: [`writer-reader-drift.md`](writer-reader-drift.md), [`sot-audit-required.md`](sot-audit-required.md).
