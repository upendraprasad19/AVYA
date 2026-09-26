---
title: Partial UNIQUE index as ON CONFLICT arbiter (42P10 trap)
category: bug-classes
source_memory: feedback_partial_unique_arbiter_trap.md
last_reviewed: 2026-05-28
---

# Partial UNIQUE index as ON CONFLICT arbiter (42P10 trap)

## The class

PostgREST `ON CONFLICT` arbiter resolution requires a UNIQUE constraint OR a UNIQUE index whose definition the planner can MATCH against the inferred conflict target.

For a **partial** unique index like:

```sql
CREATE UNIQUE INDEX ... WHERE (col_a IS NOT NULL AND col_b IS NOT NULL AND col_c IS NOT NULL)
```

the planner must STATICALLY prove the partial predicate from the inserted row's schema-level invariants. If even one arbiter column is **nullable** in the table definition, the planner CANNOT prove the predicate (it doesn't know at plan time the row's values are non-null). It rejects the partial index → falls back to looking for a non-partial UNIQUE → finds none → raises:

```
42P10: there is no unique or exclusion constraint matching the ON CONFLICT specification
```

## How to detect

- Local fixtures populate every column → green tests, ships fine.
- In production, real-world data with nullable arbiter columns triggers 42P10 on every upsert.
- `client_errors` fills with `42P10` rows; downstream tables (children of the failing parent) accumulate zero new rows for days.
- A live-shape `INSERT ... ON CONFLICT` inside `BEGIN ... ROLLBACK` reproduces the error.

## Prevention

1. **Any commit that adds or changes an `onConflict:` argument** triggers a live-arbiter check. Run `INSERT ... ON CONFLICT (<the new columns>) DO UPDATE` inside `BEGIN ... ROLLBACK` against the live schema. If it returns 42P10, the fix is wrong before it ships.

2. **The check is automated.** `test/sql/onconflict_live_arbiter.sql` + `scripts/check_onconflict_live_arbiter.dart` are the gate. Wire into `/build-apk` Gate set.

3. **Schema design rule:** if a table has a `(col_a, col_b, col_c)` UNIQUE that's intended to be the writer's natural key, those 3 columns MUST be `NOT NULL` and the index MUST be non-partial. Partial unique indexes are for "subset of rows must be unique" scenarios — NOT for arbiter use.

4. **Audit-time checklist** — when an audit recommends changing `onConflict` from `'id'` to natural-key columns, verify:
   - (a) Index exists with those columns.
   - (b) Index is non-partial OR all arbiter columns are NOT NULL.
   - (c) A live `INSERT ... ON CONFLICT` succeeds in a rollback transaction.

5. **Belt-and-suspenders client guard:** skip the upsert + emit telemetry if any natural-key column is null in the payload.

## Instances

Verified live on the fitness-app project:

- `workout_logs.date` NULLABLE, `exercise_name` NULLABLE → 42P10.
- `workout_log_exercises.workout_log_id` NULLABLE → 42P10.
- `nutrition_logs.meal_type` NULLABLE → 42P10.
- `workout_log_sets` all 4 columns NOT NULL → OK (non-partial index there too).

47 `client_errors` rows accumulated in 60 seconds; zero exercise rows reached cloud across 48 hours.

## Canonical recovery path

- Migration: backfill NULL columns with writer-contract-aligned defaults → `ALTER COLUMN ... SET NOT NULL` → `DROP INDEX` partial → `CREATE UNIQUE INDEX` non-partial.
- Client guard: skip + telemetry if natural-key column null.
- Live-arbiter script in `scripts/` as a permanent gate.

## References

- This is a sub-class of writer/reader drift, at the writer-to-DB-target layer.
- Debugging skill: `.claude/skills/debugging/SKILL.md` § "Bug class catalog".
- Related: [`writer-reader-drift.md`](writer-reader-drift.md), [`live-verification.md`](../audit/live-verification.md).
