---
title: Use IST timezone throughout
category: conventions
source_memory: feedback_use_ist_throughout.md
last_reviewed: 2026-05-28
---

# Use IST timezone throughout

## The rule

All user-facing date/time displays AND date-key computations must use **IST (UTC+5:30)** — NOT the device's local zone or UTC.

Applies to (non-exhaustive):

- Hive date-keyed entries: `schedule_<date>`, `exlog_<date>_<hash>`, `nlog_<date>_*`.
- Cloud `date`-typed columns: `nutrition_logs.date`, `scheduled_workouts.date`, `weight_logs.date`.
- Daily counter resets: `last_daily_reset`, `UsageCounterService.checkAndResetCounters`.
- Streak windows, calendar boundaries, AI snapshot "meals today" / "workouts this week".

## Why

The project's user base is in India and tests in IST. A nutrition log created at 00:16 IST (Apr 30 18:46 UTC) gets filtered out by `WHERE date = CURRENT_DATE` queries that resolved to Apr 30 in UTC. The same "the database thinks it's yesterday" bug surfaces in any calendar / daily-counter / streak-window / AI-snapshot boundary. Single-timezone consistency eliminates the entire class.

## How to apply

- **Hive date keys**: derive `<date>` from `DateTime.now().toIst().toIso8601String().substring(0, 10)`.
- **Cloud sync writes**: write `date` columns from the IST-derived value, not from device-local or UTC.
- **Server-side `CURRENT_DATE` queries** against `nutrition_logs.date` etc.: use `(NOW() AT TIME ZONE 'Asia/Kolkata')::date` to match what the client wrote.
- **`created_at` columns stored as `timestamptz`** are fine as-is; only DATE-typed columns need IST normalization.
- **Counter resets** compare against IST date, not local-timezone date.

## Helpers

- Client: `lib/core/utils/ist_date.dart`.
- Edge Function: `supabase/functions/_shared/ist_date.ts`.

## Sweep discipline

IST sweeps are recurring; the first pass always misses 2-3 sites. Run an exhaustive grep + second-pass audit when touching this domain:

```bash
grep -rn "DateTime.now\(\)" lib/ --include="*.dart"
grep -rn "CURRENT_DATE\|now\(\)" supabase/ --include="*.sql"
```

## References

- CLAUDE.md §4.5 (IST throughout for date keys + cloud `date` columns + counter resets).
- Related: [`sot-audit-required.md`](../bug-classes/sot-audit-required.md), [`writer-reader-drift.md`](../bug-classes/writer-reader-drift.md).
