---
bug_id: 6f1a2c
date: 2026-06-05
batch: apk-obs-2026-06-05
status: fixed
blast_radius: feature
symptom: >
  The workout receipt / share card (Home "View Card", day-detail sheet, post-
  completion sheet — the shareable card with AVYA branding + QR) rendered a
  hardcoded "PHASE 1" subtitle even when the user was on Phase 2+. The Train
  screen showed the correct phase, so the receipt visibly disagreed.
concept: workout_receipt_rendering
sot_registry_entry: workout_receipt_rendering
writers: >
  WorkoutWriteService.logExercise (stamps exlog_* rows the receipt reads) —
  unchanged. The new phase resolver is
  WorkoutScheduleReadService.phaseForDate (reuses pastPhaseBlocks()).
readers: >
  lib/features/train/widgets/workout_receipt_card.dart
  (WorkoutReceiptData.fromExerciseLogs now resolves phase via
  WorkoutScheduleReadService.phaseForDate(date); fromActiveWorkout takes an
  optional phase). Callers: lib/features/home/screens/home_screen.dart "View
  Card"; lib/features/home/widgets/day_detail_sheet.dart; and
  lib/features/train/screens/active_workout/completion_sheet.dart (passes phase
  to the in-memory fallback).
hive_key_prefix: exlog_
hive_key_formula: not_applicable (no new key — receipt reads existing exlog_* rows)
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/contracts/receipt_phase_for_date_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable (display only; phaseForDate reads user-scoped progress through existing guarded paths)
forbidden_patterns_checked:
  - "WorkoutReceiptData.fromExerciseLogs constructing a receipt without resolving the phase — it now derives it via WorkoutScheduleReadService.phaseForDate(date); pinned by test/contracts/receipt_phase_for_date_test.dart."
proposed_fix: >
  Add WorkoutScheduleReadService.phaseForDate(date) — returns current_phase
  (UserRepository progress) for in-window dates, else the 1-based pastPhaseBlocks
  bucket index for historical dates (single bucketing SoT, no new reader). Thread
  it into the receipt: fromExerciseLogs (the canonical builder all three views
  use) computes it by default; fromActiveWorkout accepts an optional phase the
  completion fallback supplies. Pure helper phaseForDatePure is unit-tested.
regression_test_planned: >
  test/contracts/receipt_phase_for_date_test.dart — phaseForDatePure cases
  (in-window → current_phase; past dates → correct block index; null plan → 1)
  plus a comment-stripped wiring grep that fromExerciseLogs + the completion
  fallback resolve phase via phaseForDate (not the hardcoded default 1).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "phaseForDate added; receipt factories thread phase; flutter analyze clean on workout_schedule_read_service.dart + workout_receipt_card.dart + active_workout/screen.dart" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "receipt reads existing exlog_* rows; receipt_after_write_service + receipt_scoping + receipt_per_set_chips tests still green after the change" }
impact_analysis: >
  Feature blast radius — display only. Affects every user past Phase 1 viewing a
  workout receipt. phaseForDate is defensive (try/catch → 1 if Hive unavailable)
  so it can only correct the phase, never crash the receipt. Reuses the
  pastPhaseBlocks bucketing SoT so the receipt, week selector, and reconciler can
  never disagree on phase numbering. Found via the founder's APK image 1.
---

# Workout receipt card hardcoded "PHASE 1"

## What happened
The shareable workout receipt subtitle always read "PHASE 1" even on Phase 2+.

## Root cause
`WorkoutReceiptData.phase` defaulted to `1` and neither factory
(`fromExerciseLogs`, `fromActiveWorkout`) nor any caller ever supplied the real
phase — so `_buildTitle` rendered `'PHASE ${data.phase}'` = "PHASE 1".

## Fix
`WorkoutScheduleReadService.phaseForDate(date)` (reuses `pastPhaseBlocks()`).
`fromExerciseLogs` — the canonical builder all three receipt views read —
resolves the phase by default; the completion in-memory fallback passes it
explicitly. The pure `phaseForDatePure` is unit-tested.

## Verification
`flutter analyze` clean; `receipt_phase_for_date_test.dart` (pure cases +
wiring grep); existing receipt tests still green.

## See also
- `lib/core/services/workout_schedule_read_service.dart` (phaseForDate)
- `lib/features/train/widgets/workout_receipt_card.dart`
- Related: two-Phase-1 week-selector fix a3f8c1 (didn't cover the receipt).
