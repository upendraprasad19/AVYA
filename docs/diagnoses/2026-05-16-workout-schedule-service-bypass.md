---
bug_id: 2026-05-16-workout-schedule-service-bypass
date: 2026-05-16
batch: APK Test #16.2 / Phase E (audit 2026-05-16) — E.6
status: fixed
regression_test: test/contracts/workout_schedule_service_uses_write_service_test.dart
symptom: >-
  `WorkoutScheduleService` had 13 direct `workoutBox.put` callsites — every
  schedule mutation (template assignment, swap exercise, shorten day, mark
  completed/skipped/travel, copy week, restore displaced) silently bypassed
  the canonical `WorkoutWriteService`. Concrete failures observed:
---

## Symptom

`WorkoutScheduleService` had 13 direct `workoutBox.put` callsites — every schedule mutation (template assignment, swap exercise, shorten day, mark completed/skipped/travel, copy week, restore displaced) silently bypassed the canonical `WorkoutWriteService`. Concrete failures observed:

- **AI coach stale schedule context.** A user assigned a custom template to today, but the AI coach kept referencing the old plan-generator workout for ~10 seconds (the next `pushSnapshot` fire from a different mutation). Test #15.3 / Bug 4b traced one slice of this.
- **No mutex.** Two near-simultaneous schedule edits (rare but possible if a user taps + AI tool fires concurrently) could race-overwrite.
- **No provider invalidation.** Calendar / today card / week selector served stale data after schedule changes until the next `ref.invalidate` from an unrelated cause.

Class fix per CLAUDE.md §15 allowed-writers list — `WorkoutScheduleService` was NOT on the list.

## Root cause

`WorkoutScheduleService` predates `WorkoutWriteService`. When Test #6 introduced the WriteService pattern for `exlog_*` (exercise logs), nobody migrated `schedule_*` writes. They stayed as direct `_hive.workoutBox.put(...)` calls. Each subsequent feature (Test #11 schedule completions, Test #12 swap, Test #15 templates) added MORE direct writes without questioning the pattern.

Audit Agent 6 (cluster 11) found 13 such sites: L249, L419, L728, L855, L866, L1170, L1313, L1441, L1526, L1606, L1616, L1683, L1865 (pre-fix line numbers).

## Fix

Founder approved Option A: refactor schedule mutations through `WorkoutWriteService.upsertScheduled` (already exists at `workout_write_service.dart:409`).

Categorized the 13 callsites:

**9 schedule writes → `WorkoutWriteService.instance.upsertScheduled(date, entry, source: WriteSource.schedSwap)`:**
1. `markCompleted` — completion status + duration_seconds stamp
2. `markSkipped` — skip status
3. `activateTravelMode` — bulk travel status per day in range
4. `swapExerciseInDay` — swap one exercise within a scheduled day
5. `shortenDay` — drop exercises to hit a time budget
6. `assignTemplateToDate` — assign a custom template to a date
7. `unscheduleTemplateFromDate` — restore the displaced auto-plan entry
8. `_copyWeek4ToWeekN` (target) — week-rollover copy
9. `_copyWeekFromPlan` (dest) — manual copy-week

The WriteService internally handles:
- Per-IST-date mutex (`_acquireLock(dateStr)`).
- Stamping `date`, `source`, `updated_at_ms` on the output map.
- `unawaited(SyncService.instance.syncWorkoutData())` + `pushSnapshot()`.
- Optional provider invalidation hook (callers may also invalidate directly).

**3 non-schedule writes — kept direct + added explicit `unawaited(SyncService.instance.syncWorkoutData())` fan-out:**
- `_planKey` upserts in `generateInitialPlan` + `generateAndScheduleFromDate` — these write the *global* plan state, not a per-date schedule entry. `upsertScheduled` doesn't fit (its key derivation is `scheduleKey(date)`).
- Template metadata `last_used_at` stamp — writes to `templateId` key, not a schedule key.

`WorkoutScheduleService` is now an explicitly-allowed direct writer for these 3 surfaces (will document in CLAUDE.md §15 as part of E.15 doc updates).

**1 internal backup write — kept direct, no fan-out needed:**
- `displacedKey` backup in `assignTemplateToDate`. This is internal rollback state that never reaches cloud (the sibling restore path at `unscheduleTemplateFromDate` is what produces the cloud-visible mutation).

## Verification

- New contract test: `test/contracts/workout_schedule_service_uses_write_service_test.dart` (4 sub-tests).
  - `file imports WorkoutWriteService + SyncService` ✓
  - `direct workoutBox.put count is bounded to known non-schedule sites` (exactly 4) ✓
  - `all schedule mutations route through WorkoutWriteService.upsertScheduled` (≥9) ✓
  - `non-schedule direct puts have explicit fan-out adjacent` (≥3 unawaited SyncService calls) ✓
- All 4/4 PASS via `flutter test`.
- Compile clean: `flutter analyze lib/core/services/workout_schedule_service.dart` → 0 issues post-fix (had 1 unused-var warning from a removed `targetKey` local; cleaned).

## Follow-ups

- Manual smoke test post-batch: assign template → days/week change → copy week → confirm calendar + today card + AI coach all see fresh state within seconds (not just on next mutation).
- `WriteSource.schedSwap` is now used broadly (not just for swap operations). Reasonable — the source field is a debug/telemetry hint, not a strict per-action enum. Could split if analytics need finer granularity later.
- Pre-Test-#13 `WorkoutRepository.logSetWithPrRescan` shim is still in the codebase — not in this batch's scope. Phase E.5.1 closed the AI-coach callsite; remaining callers to be swept in a future batch.

## Class lesson

When introducing a new canonical writer pattern (Test #6's WriteService), audit the ENTIRE class hierarchy for sibling write callsites that should migrate. The repo-pattern grep is fast and surfaces the drift before it ships. Codified as future build-gate: `scripts/check_writeservice_only.dart` (E.13 deliverable) will enforce "no direct `<box>.put` outside the allowed-writers list" going forward.
