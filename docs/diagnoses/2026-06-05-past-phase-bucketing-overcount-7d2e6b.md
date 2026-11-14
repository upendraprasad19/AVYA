---
bug_id: 7d2e6b
date: 2026-06-05
batch: apk-obs-2026-06-05
status: fixed
blast_radius: account
symptom: >
  pastPhaseBlocks() bucketed past schedule rows by 28-day CALENDAR windows. A
  single phase whose rows span >28 calendar days (gaps/overlaps) split across two
  buckets → over-count → the PhaseProgressReconciler could over-advance
  current_phase. The +12 clamp bounded only the catastrophic case, not a modest
  +1/+2 over-count.
concept: phase_blocks_bucketing
sot_registry_entry: phase_blocks_bucketing
writers: >
  lib/core/services/workout_schedule_read_service.dart generation methods
  (generateAndSchedule + generateAndScheduleFromDate) now stamp 'phase': phase on
  every schedule_* entry (the phase parameter was already in scope).
readers: >
  lib/core/services/workout_schedule_read_service.dart pastPhaseBlocks() now
  delegates to the pure bucketPastRows(rows): groups by the stamped 'phase' via
  carry-forward (an unstamped row inherits the nearest preceding stamped phase;
  leading unstamped rows take the first stamped phase) when ANY past row is
  stamped, else falls back to the proven 28-day calendar bucketing (B-pass F-2 —
  replaced an all-or-nothing `every` guard so one unstamped row can't collapse
  the dataset). Consumed by the week selector + PhaseProgressReconciler +
  phaseForDate (shared SoT).
hive_key_prefix: schedule_
hive_key_formula: not_applicable (adds a 'phase' field to the existing schedule_<istDate> rows)
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: scheduled_workouts
cloud_columns: not_applicable (phase is a local grouping aid; not a cloud column)
contract_test_path: test/contracts/past_phase_bucketing_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable (reads user-scoped workoutBox via existing guarded paths)
forbidden_patterns_checked:
  - "pastPhaseBlocks bucketing purely by 28-day calendar windows — now prefers explicit phase identity when stamped (bucketPastRows), pinned by test/contracts/past_phase_bucketing_test.dart."
proposed_fix: >
  Stamp an explicit 'phase' on schedule_* rows at generation time (the generators
  already receive the phase). Refactor pastPhaseBlocks into a pure, testable
  bucketPastRows: when ANY past row is stamped, group by phase identity with
  carry-forward (unstamped rows inherit the nearest preceding stamped phase) so
  one logical phase = one block regardless of calendar span; only when NO row is
  stamped fall back to 28-day bucketing. The fallback is intentional and correct
  for legacy data — the founder's duplicate-week residue stays ONE block under
  28-day (a naive week-reset inference would over-count it). The +12 clamp stays
  as a backstop.
regression_test_planned: >
  test/contracts/past_phase_bucketing_test.dart — bucketPastRows: one stamped
  phase spanning >28 days → ONE block; two stamped phases → two; legacy
  duplicate-week residue in one window → ONE block (founder case); a stamped
  dataset with one unstamped swap row → carry-forward keeps phase identity
  (B-pass F-2, still two blocks); fully-unstamped legacy → 28-day fallback; two
  legacy phases >28d apart → two; empty → none.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "phase stamp on 5 generation write-sites; pure bucketPastRows; flutter analyze clean; past_phase_bucketing_test 7/7 + reconciler + week-selector tests green" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "legacy (unstamped) rows fall back to 28-day → founder's existing data still resolves to one block (phase 2, not 3)" }
impact_analysis: >
  Account blast radius — the bucketing feeds the rank/phase reconciler. Forward-
  safe: new (stamped) data groups by phase identity; legacy data keeps the proven
  28-day behaviour (so no existing user is re-bucketed). The reconciler stays
  monotonic + clamped. The fix is the only robust solution (explicit stamping) —
  inference from week numbers cannot distinguish a duplicate phase from a legit
  gappy one. Carried-over follow-up F-B; founder said fold in.
---

# pastPhaseBlocks over-counted on gappy history (28-day window)

## What happened
A single phase spanning >28 calendar days split into two blocks → the reconciler
could over-advance `current_phase`.

## Root cause
`pastPhaseBlocks` bucketed purely by 28-day calendar windows from the earliest
row — a phase with gaps/overlaps crossed a window boundary.

## Fix
Stamp an explicit `phase` on schedule rows at generation (the generators already
have the phase). `pastPhaseBlocks` → pure `bucketPastRows`: group by phase
identity with carry-forward (an unstamped row inherits the nearest preceding
stamped phase) when ANY row is stamped — so a single swapped/legacy row can't
collapse the dataset (B-pass F-2); only when NO row is stamped fall back to
28-day (correct for the founder's legacy duplicate-week residue — week-reset
inference would over-count). `+12` clamp kept as backstop.

## Verification
`flutter analyze` clean; `past_phase_bucketing_test.dart` (7 cases); reconciler +
week-selector tests green.

## See also
- `lib/core/services/workout_schedule_read_service.dart` (bucketPastRows)
- Related: two-Phase-1 reconciler a3f8c1; receipt phase 6f1a2c (same SoT).
