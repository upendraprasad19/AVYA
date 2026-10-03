---
bug_id: c2d8e5
date: 2026-09-28
batch: day-swapper-sync-load (Hermes E-pass remediation, finding h4F3, lens L37)
status: fixed
blast_radius: account
symptom: |
  Hermes seat h4 (L37, legacy shapes) found that the day-swap engine's
  `DaySwapRules.isRest` counted a row as rest only when `type == 'rest'`.
  It missed the legacy rest hybrid (`status: 'rest'` + a workout type + no
  exercises), which this same batch treats as rest everywhere else: the
  restore-merge normalizer and the one-time `ScheduleHybridRepairMigrator`
  both key on `PlanIntegrityReconciler.isRestHybrid`. A hybrid that arrives
  after the migrator's per-user flag is set sits un-normalized until the next
  restore or reconcile. In that window `restRunWarning` counted it as a
  workout day and could miss the "this swap makes 3+ rest days in a row"
  warning (spec §5.6). The day-swap copy's "Rest day" label had the same
  blind spot.
concept: day_swap_engine
sot_registry_entry: day_swap_engine
writers:
  - { file: lib/core/services/day_swap/day_swap_rules.dart, method_or_widget: "isRestHybrid — the ONE hybrid predicate, moved here", line: 124 }
readers:
  - { file: lib/core/services/day_swap/day_swap_rules.dart, method_or_widget: "isRest (now includes hybrids) → restRunWarning", line: 115 }
  - { file: lib/core/services/day_swap/day_swap_rules.dart, method_or_widget: "restRunWarning before/after", line: 240 }
  - { file: lib/core/services/plan_integrity_reconciler.dart, method_or_widget: "isRestHybrid — delegates, used by _normalizeHybrid and the repair migrator", line: 162 }
hive_key_prefix: "workoutBox schedule_<date> (read only)"
hive_key_formula: not_applicable — unchanged
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: "test/services/day_swap/day_swap_rules_test.dart ('a legacy rest hybrid counts as a rest day' + its mirror) and test/services/schedule_hybrid_repair_migrator_test.dart (the migrator still honours the moved predicate)"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — pure predicate over rows already read under the session guard
forbidden_patterns_checked:
  - "importing plan_integrity_reconciler.dart from day_swap_rules.dart — rejected: the reconciler already imports day_swap_rules.dart, so that would make an import cycle. The predicate body moved into DaySwapRules and the reconciler's name delegates to it, so there is still exactly one definition."
  - "also changing weekly_calendar.dart's `isRest = type == 'rest'` — checked, not needed: every local writer of `status: 'rest'` (regenerate_plan_planner.dart:456 and workout_schedule_read_service.dart :322 / :503 / :589) also sets `type: 'rest'`, and a swap moves `status` together with `type` as content (DaySwapRules.identityKeys excludes both), so no current writer creates a hybrid. Hybrids come only from legacy data (the migrator repairs those once) and cloud restores (both restore paths normalize them at write time). The swap engine is the only reader that runs INSIDE the window and warns on it, which is why it was the one fixed."
proposed_fix: |
  `isRestHybrid`'s body moved from PlanIntegrityReconciler into
  DaySwapRules (same code), and PlanIntegrityReconciler.isRestHybrid now
  delegates to it. `DaySwapRules.isRest` became
  `row != null && (row['type'] == 'rest' || isRestHybrid(row))`.
regression_test_planned: |
  day_swap_rules_test.dart has two new tests.
  (1) A week with a hybrid on Tuesday and rest on Wednesday: swapping
  Thu(workout) with Fri(rest) must warn with [tue, wed, thu].
  (2) The mirror: status rest WITH exercises is not rest; null is not rest;
  a plain type-rest row is rest.
  The first fixture used `type: 'push'`, which is NOT a workout type here
  (only 'workout' and 'custom_template' are,
  PlanEngineFlags.isRestDayConsideringLogged). The positive test failed on
  that, and the mirror passed for the wrong reason. Both fixtures were
  corrected to `type: 'workout'` before any mutation run (code-review
  lens 8, asserted fixture value).
  MUTATED AND RUN (rule 21):
  (1) `isRest` reverted to type-only (`|| false`). Exactly 1 test went red,
  the hybrid test (`Expected: not null`).
  (2) `isRestHybrid` made to ignore exercises (`(hasExercises || true)`).
  3 tests went red: the new mirror test and two
  schedule_hybrid_repair_migrator_test.dart tests. That shows the migrator
  still runs the moved predicate.
  Both were restored, and a `grep` for the mutant tokens found 0.
impact_analysis: |
  The 3-rest-day warning and the "Rest day" label now agree with the rest
  of the batch about hybrid rows. Nothing is written: this is a read-side
  predicate change only. Behaviour for ordinary rows is identical.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "day_swap_rules.dart:115 / :124, plan_integrity_reconciler.dart:162. flutter analyze lib/ has no warnings or errors." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "writers of status 'rest' enumerated by grep; all four set type 'rest' as well." }
---

## Summary

The swap engine's rest check ignored the legacy rest hybrid, so a swap could
build 3+ rest days in a row without the warning. The one hybrid predicate now
lives in `DaySwapRules`, the reconciler delegates to it, and `isRest` uses it.
Two tests cover it: one positive and one mirror. Mutation proved both halves:
the old `isRest` reddened the positive test, and an exercises-blind predicate
reddened the mirror and two migrator tests.
