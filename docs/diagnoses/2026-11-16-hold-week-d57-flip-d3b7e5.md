---
bug_id: d3b7e5
date: 2026-11-16
batch: generator-step3d
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  OI-175 (generator step 3D, Unit 3D-b; founder d57 and d80). "Keep training Phase 1" (the expired card and the
  graduation screen) still ran the old redoWeek4 for every user: a copy of the TRAILING deload week, with plan_end
  extended from wherever it was, so it could land on any weekday. The correct Monday-aligned holdWeek (Peak, Peak,
  Peak, Deload) sat behind the ship-dark flag enable_hold_weeks, default OFF. Tracing the hold writer for the flip
  found four defects in holdWeek itself:
  (a) a second tap wrote the NEXT hold early, after expiry and before it (a graduation tap on the Thursday of
      week 4 wrote H1 for next week, a second tap H2 the week after);
  (b) a crash-partial hold (rows written, plan_end never moved) counted as a hold, so a retry a week later wrote H2
      and the orphan rows stayed in H1;
  (c) a completed day on a target date was overwritten by the Peak copy, losing a template day or coach log the
      user trained;
  (d) every row write's result was ignored and plan_end moved anyway.
  A display defect sat on top of these: during a hold two chips were gold (W4 and the current H chip; FOB-6's first
  sentence).
concept: hold_week_materialization
sot_registry_entry: workout_schedule_write_path
contract_test_path: test/contracts/hold_week_d57_behavioral_test.dart
related_bugs: [d7f3a9, c8b3f2, a3f8d1, f4c8e1, d5b8f3, b6e1f4, e7c4a2, b9d4c2, d7f3b2, c4e8b1]
recurrence: |
  A recurrence of the hold-week class (writers and readers that disagree about which rows are a hold).
  - Prior instances: d7f3a9 (the mechanic), c8b3f2 (stale week, locked-chip tick), a3f8d1 (streak identity),
    f4c8e1 (the identity clamp), d5b8f3 (the raw stamp), b6e1f4 (the coach's "week 4", FOB-3), e7c4a2 (the
    reconciler never heals holds), b9d4c2 (hold days dilute phase completion), d7f3b2 (regen content cycling) and
    c4e8b1 (FOB-4, the server copy, Unit 3D-a, merged first).
  - The known-good fix is applied again: ONE read rule every hold reader shares.
  - The new rule is that a hold row counts only while `plan_start <= date <= plan_end` (the covered rule). The guard,
    the next ordinal, the chips, the identity, the coach block, the reconciler and the streak all read it through
    `_holdDatesByOrdinal` / `holdOrdinalForDate`.
  - Bug-history lookup (CLAUDE.md 4.1.5): grep of docs/diagnoses for "redoWeek4", "holdWeek", "hold_ordinal",
    "enable_hold_weeks", "is_hold", "double tap" and "plan_end" (token and concept). The hits are the ten above, plus
    passing mentions in OI-189 (plan_end bound) and OI-166 (regen) diagnoses.
writers:
  - { file: lib/core/services/workout_schedule_write_service.dart, method_or_widget: "holdWeek -> HoldWeekOutcome; _holdWeekLocked: the double-tap guard, the orphan clear, the completed keep, the failed-write stop; the one push after the mutex", line: 231 }
  - { file: lib/core/services/workout_schedule_write_service.dart, method_or_widget: "_clearOrphanHoldRows (found in the build: orphans in the gap would join the next hold)", line: 412 }
  - { file: lib/features/train/widgets/keep_training_phase1_action.dart, method_or_widget: "runFreeTierRepeatWrite (no flag, no redoWeek4) / keepTrainingPhase1 (refresh through the captured container)", line: 25 }
  - { file: lib/features/train/widgets/plan_expired_card.dart, method_or_widget: "_handleHoldWeek: one snackbar per outcome; phase_1_cycle_repeat_started only on written", line: 59 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "SelectedWeek / SelectedWeekNotifier (picked)", line: 1171 }
readers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "_holdDatesByOrdinal (the covered rule; walks box.keys), latestCoveredHoldDate, maxCoveredHoldOrdinalBefore, holdOrdinalForDate, activeHoldWeeks / activeHoldOrdinalFor (no gate)", line: 1175 }
  - { file: lib/features/train/widgets/week_selector.dart, method_or_widget: "weekChipLit + the current group's holdingToday; _WeekChip.isLit", line: 1025 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "holdStatusProvider (through activeHold*)", line: 1120 }
hive_key_prefix: "workoutBox schedule_<date> (is_hold, hold_ordinal, week = 4 + n; status / content kept on a completed target); MigratedKey plan_end_date; configBox['enable_hold_weeks'] is now an inert key with no reader"
hive_key_formula: "a hold row counts iff plan_start <= date <= plan_end (dates only, inclusive); next n = 1 + max covered ordinal dated before the hold's Monday"
sync_methods:
  - "SyncService.pushWorkoutPlanForSyncDomain once after holdWeek's mutex, only on written (pinned by oi189_plan_end_bound_behavioral_test); the schedule push sends week_number <- entry['week'] (unchanged)"
restore_methods:
  - "plan_json merge (unchanged). A plan_end moved back by a stale-cloud re-anchor makes restored hold rows past it uncovered; sweepNonCompletedRowsPastPlanEnd deletes such rows on the next generation (stated in the plan, round 3 A-F3)"
cloud_table: scheduled_workouts
cloud_columns:
  - scheduled_workouts.week_number
  - user_progress.plan_json
ist_handling:
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "_holdWindowEnd: plan_end's DATE fields (no toLocal; a Z string keeps its UTC date, both sides of the Sunday pinned, round 4 F7); the hold's Monday comes from normalizeToMonday(nowWall()) as before", line: 1165 }
provider_invalidations:
  - "keepTrainingPhase1 on written: currentPlanProvider, selectedWeekProvider, todayWorkoutProvider through ProviderScope.containerOf captured before the await (round 3 B-F2, round 4 F1 / F2)"
  - "PlanExpiredCard callers unchanged: onRedoComplete invalidates (home: todayWorkoutProvider + currentPlanProvider; train: currentPlanProvider + selectedWeekProvider), now only on written"
telemetry_op_types:
  success: [hold_week_started, phase_1_cycle_repeat_started]
  failure: [hold_week_durability_push]
cross_account_guard: "Hive reads and writes go through the user-scoped workoutBox wrappers and WorkoutWriteService.upsertScheduled; no new cloud write. The refresh uses the container of the tapped screen, not another user's."
forbidden_patterns_checked:
  - { pattern: "a reader of enable_hold_weeks / PlanEngineFlags.holdWeeksEnabled / redoWeek4 in lib (grep: history comments only)", absent: true }
  - { pattern: "a second hold written in the same week (double tap after and before expiry)", absent: true }
  - { pattern: "an uncovered hold row counted by any hold reader (orphans, earlier phases, rows past plan_end)", absent: true }
  - { pattern: "a completed target day overwritten by the Peak copy", absent: true }
  - { pattern: "plan_end moved after a failed row write", absent: true }
  - { pattern: "a W chip gold during a hold the user did not pick", absent: true }
proposed_fix: |
  Plan docs/plans/2026-11-16-generator-step3d-hold-weeks.md (rev 5; rounds 1-3 on the combined plan, round 4 on
  3D-b, converged; split under section 4.12.1 with the server half, Unit 3D-a, merged first).
  - The flag and redoWeek4 are deleted, so runFreeTierRepeatWrite always calls holdWeek and returns its
    HoldWeekOutcome.
  - The covered rule gives every hold reader an upper bound.
  - holdWeek returns alreadyHolding when a covered hold is dated this week or later. It clears orphans in the gap
    (found in the build), keeps a completed target row with the three hold stamps, and stops on a failed row write
    before plan_end moves. It pushes once, only on written.
  - The callers show one message per outcome; the graduation path refreshes its providers.
  - The marker: SelectedWeek {week, picked}, and weekChipLit lights the default W chip only when no hold is today.
regression_test_planned: |
  test/contracts/hold_week_d57_behavioral_test.dart (22: the double tap after and before expiry, H1's Sunday, the
  Monday after H1, H3 after H2, the clock set back, crash-partial same week and a week later, orphans planned and
  completed, earlier-phase holds, a failed third row and its retry, completed target Monday and today, a planned
  target, noPlan, inFlight, the read cost; the covered rule with a time of day and both Z strings);
  test/features/train/hold_week_callers_test.dart (6, the expired card and the graduation path on real Hive);
  test/features/train/week_selector_hold_marker_test.dart (9, the weekChipLit table, the real strip during a hold,
  the card words); the 15 rewritten hold test files (OFF groups deleted).
impact_analysis: |
  Platform tier. Every free user who keeps training Phase I now gets the July hold design: a Monday-aligned week,
  Peak three times and then Deload, at flat loads, with H chips.
  - A tester device with is_hold rows from earlier dev toggling sees them now (pre-launch data).
  - A tester whose window redoWeek4 made ends on a non-Sunday gets the first hold inside that window (defect B,
    verified_clean, pre-launch).
  - The coach's HOLD WEEKS block is live (FOB-3). The Sunday push and weekly report name the hold: the 3D-a
    deploys went live 2026-11-16 (weekly-recap-ready v29, weekly-report v41).
  - The app is not live in any store.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "write / read services, the action, the expired card, the marker; flutter analyze --no-fatal-infos clean; mutations below" }
  - { layer: hive_local_state, status: verified, evidence: "real-Hive tests write and read schedule_<date> rows and plan_end_date (hold_week_d57_behavioral_test, hold_week_callers_test)" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no column or migration; week_number already exists and the server reads it (3D-a)" }
  - { layer: edge_function_code, status: verified, evidence: "no Edge Function change in 3D-b; FOB-3 live check: the deployed ai-proxy bundle carries HOLD WEEKS (closure ledger)" }
  - { layer: client_server_contract, status: verified, evidence: "holdWeek stamps week: 4 + n and the push sends it as week_number (sync_workout.dart:2350), the field the server's hold rule reads" }
---

# "Keep training Phase 1" is the Monday-aligned hold week (d57)

## Root cause

- **The flag.** `runFreeTierRepeatWrite` branched on `enable_hold_weeks` (default OFF) to `redoWeek4`, and every
  gated reader returned empty.
- **holdWeek's own defects**, each reached by its writer and read by the hold readers:
  - **Double tap.** `holdWeek` chose the Monday after `plan_end` whenever this Monday was not after it, so a second
    call after the first moved `plan_end` wrote the next hold.
  - **Orphans and ordinals.** `_nextHoldOrdinal` counted every `is_hold` row before the Monday, covered or not; the
    readers had no upper bound.
  - **Overwrite and ignored failures.** The copy loop overwrote any target row and ignored each `WriteResult`.
- **Two gold chips.** `_WeekChip` lit `w == selectedWeek` (the clamped default 4) while the H chip lit today's hold.

## Fix

See `proposed_fix`. The plan's section 2 has the design; round 4's P2 / P3 folds are listed in
`docs/plan-reviews/generator-step3d.md`.

## Mutations

Script `mutate_b.py` (session scratchpad): one mutant at a time, with nothing else compiling.
- **Applied:** the file content differed after each replacement.
- **Restored:** from a backup copy, with byte equality asserted.
- **Run:** against the named test file(s).
- **Not a compile error:** every red run below reports passing tests alongside the failures.

| # | Mutant | Tests | Result |
|---|---|---|---|
| M1 | the write gated on a flag again (returns noPlan) | callers | red, 3 of 6 |
| M2 | the double-tap guard removed | d57 | red, 5 of 22 |
| M3 | the guard keyed on this week only (pre-expiry double tap) | d57 | red, 3 |
| M4 | the completed keep removed | d57 | red, 2 |
| M5 | inFlight mapped to written | d57 | red, 1 |
| M6 | noPlan mapped to written | d57 + callers | red, 2 |
| M7 | the ordinal off by one | d57 | red, 11 |
| M8 | a failed row write still moves plan_end | d57 | red, 1 |
| M9 | the keep stamps week without is_hold | d57 | red, 2 |
| M10 | the orphan cleanup removed | d57 | red, 2 |
| M11 | the covered upper bound removed | d57 | red, 3 |
| M12 | the covered lower bound removed (earlier-phase holds) | d57 | red, 2 |
| M13 | the upper bound as `<` (the Sunday drops) | d57 | red, 2 |
| M14 | `_holdDatesByOrdinal` without the is_hold check | d57 | red, 11 |
| M15 | `_holdDatesByOrdinal` without the `schedule_` prefix check | d57 | green: EQUIVALENT |
| M16 | `weekChipLit` ignores picked | marker | red, 2 |
| M17 | `weekChipLit` ignores holdingToday | marker | red, 3 |
| M18 | holdingToday passed to a PRO group | marker | green: EQUIVALENT |
| M19 | the graduation refresh drops todayWorkoutProvider | callers | red, 1 |
| M20 | the graduation refresh drops currentPlanProvider | callers | red, 2 |
| M21 | the refresh through the tap-time `ref`, not the captured container | callers | red, 1 (the popped-screen test) |

The two green mutants are equivalent, measured rather than assumed:
- **M15.** The only other dated keys in workoutBox are `displaced_<date>`. Their key cut at the fixed 9-character
  `schedule_` offset is `_2026-07-06`, which `DateTime.tryParse` rejects, so no non-schedule row can enter the map.
  The check stays as the readable guard.
- **M18.** A PRO group's chips are W5-W12. The default selection is the clamped program week (1-4), so a PRO chip can
  only be lit by a tap (`picked` true), and the rule's hold arm (`holdingToday && !picked`) can never fire there.
  The `false` is kept for clarity, as the plan asks.

## B-pass (docs/reviews/generator-step3d-bpass.md)

Two fresh Sonnet seats on the committed diff of 543fa294 (CI green). Seat A (the services, 9 mutants of its own),
seat B (the UI, the callers, the records). Ten findings, all accepted; every fix below, with its regression test.

- **A-F2 (P2), the class widened in the fix.** A failed row write left every row written before it stamped
  `is_hold` / `hold_ordinal` / `week: 4 + n` with `plan_end` unmoved. The covered rule hides them from the hold
  family, but four raw readers do not apply it (writer `workout_schedule_write_service.dart` `_holdWeekLocked`;
  readers `workout_schedule_read_service.dart` `completedWeekNumbers` / `_withoutHoldRows` / `weekModeForRow` and
  `hold_week_labels.dart` `rowIsHold` on Home's card). Seat A named the completed-row case; a copied planned row is
  the same class. **Fix:** `_rollBackHoldRows` puts every touched target back, newest first (a prior row rewritten
  through the same write path, so its push corrects the cloud copy; a date with no prior row deleted). The cloud
  half of that delete is OI-174's (upsert-only push), recorded there with the new server reader (3D-a's hold rule).
- **A-F1 (P2).** The orphan gap's exclusive lower bound (it protects H(n-1)'s Sunday, the old `plan_end`) had no
  test: seat A's mutant M3 survived. The H1 -> H2 -> H3 test now pins both Sundays.
- **A-F3 (P3).** Stale SoT `line_range`s: the seam entry (1007-1032 -> 1264-1288) and six read-service ranges whose
  bodies outran them, plus the write service (+42 lines) and `keepTrainingPhase1`. Recomputed from anchors.
- **A-F4.** An un-stamped completed orphan keeps `week: 4 + n`: no change, its date is before this week's Monday, so
  no current-week reader (today's card, the server's current-IST-week rule) sees it. Its local delete: OI-174.
- **B-F1 (P2).** Five caller arms had no test (graduation alreadyHolding / inFlight / noPlan / a throw; the card's
  failed / inFlight). Six new tests in `hold_week_callers_test.dart`.
- **B-F2 (P2).** OI-60 (the flag flip) was OPEN for a flag this batch deletes: archived (append-only) with the
  deploys; OI-188's defect 1 and OI-95's flag mention marked; OI-166's tail fixed (B-F3).
- **B-F4 / B-F6 (P3).** The `SelectedWeek` "no `==` on purpose" claim was not load-bearing (a tap on the default
  week changes `picked`): reworded. Two `use_build_context_synchronously` infos: an explicit `mounted` guard.
- **B-F5 (P3).** The graduation test could not see the `selectedWeekProvider` invalidation: it now picks W2 first.

Build trap: a `Completer` made in the `testWidgets` (fake-async) zone completes on a pump, so
`await tester.runAsync(() => future)` on work gated by it never returns (the first run of the new inFlight tests hung);
poll with the file's `waitFor`, which pumps.

| # | Mutant | Test | Result |
|---|---|---|---|
| MR1 | no `_rollBackHoldRows` call | d57 | red, 2 |
| MR2 | a no-prior date is not deleted | d57 | red, 1 |
| MR3 | a prior row is not rewritten (`WriteResult.fail`) | d57 | red, 1 |
| MR4 | the orphan gap includes `plan_end` (seat A's M3) | d57 | red, 1 |
| MC1 | graduation alreadyHolding stays put | callers | red, 1 |
| MC2 | graduation inFlight shows a snackbar | callers | red, 3 |
| MC3 | no `selectedWeekProvider` invalidation | callers | red, 1 |
| MC4 | a thrown write maps to inFlight | callers | red, 1 |
| MC5 | the card's inFlight shows a snackbar | callers | red, 1 |
| MC6 | the card's failed is silent | callers | red, 1 |

Each mutant was confirmed applied (`grep -c` = 1), reddened through a test failure (no compile error), and the file
was restored from a backup with its sha256 checked. Seat A's M1 / M2 (the double-tap comparison against the Monday vs
today, `isBefore` vs `isAfter`) stay green and are equivalent: a covered hold's last date is its Sunday, never a Monday.
