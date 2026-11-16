---
bug_id: 7c4e2a
date: 2026-11-16
batch: generator-step4
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  OI-53's last two ship-dark flags, volume titration (W2.7) and plateau escalation (W3.5, the +1 set and the
  rotation), were measured switched on over a simulated history before the flip (576 profiles: Build / Cut / Maintain x
  3-6 days x 3 levels x 4 tiers x 30-90 minutes; scenarios progress, decline, flat; main 85bdcbbe). Neither pushed any
  group past its weekly range (0 group-weeks over the ceiling), but titration broke 2A's lead-first rule and d65's
  floor: an accessory passed its day's lead + 1 on 451 / 149 / 325 days (progress / decline / flat), a -1 took a set
  off the day's lead on 831 decline days and left 1,538 new 1-set rows. And with `disable_readiness` set, old green
  check-ins still allowed a +1 (`_recovered()` had no readiness gate).
concept: volume_titration
sot_registry_entry: volume_titration
contract_test_path: test/contracts/volume_titration_behavioral_test.dart
related_bugs: [d4a7e2, b3f1d8, e9b3d7, 675d02]
recurrence: |
  The class "a set writer that runs after the allocator predates an invariant the allocator now keeps". d4a7e2 (Unit
  2A, the lead-first allocator) recorded titration and plateau as "not re-capped (both OFF by default)" in the plan
  engine CLAUDE.md; b3f1d8 (Unit 2B, the day floor) created the 2-set seats a titration -1 took to 1; e9b3d7 (Unit
  2C-b) is the precedent of deciding titration's relation to a new allocator rule (it never takes the allowance);
  675d02 (Unit 3A) gave titration the goal band it reads. No earlier fix of this exact defect existed: both flags were
  OFF, so the carve-out was stated, not shipped. Bug-history lookup (CLAUDE.md 4.1.5): docs/diagnoses grep for
  volume_titration, applyToWeeks, plateau_escalation, mergePlateauSetDeltas, "re-capped"; every hit read.
writers:
  - { file: lib/shared/repositories/plan_engine/volume_titration.dart, method_or_widget: "applyToWeeks: leadFirst argument (null reads disable_lead_first)", line: 183 }
  - { file: lib/shared/repositories/plan_engine/volume_titration.dart, method_or_widget: "_titrateWeekBudgeted: the day's lead (openerOf over budgeted rows), T3 hasSets", line: 230 }
  - { file: lib/shared/repositories/plan_engine/volume_titration.dart, method_or_widget: "_titrateWeekBudgeted: T2 candidate order (most sets, latest day, latest slot)", line: 257 }
  - { file: lib/shared/repositories/plan_engine/volume_titration.dart, method_or_widget: "_titrateWeekBudgeted: T1 lead + 1 check on a +1", line: 278 }
  - { file: lib/shared/repositories/plan_engine/volume_titration.dart, method_or_widget: "_titrateWeekBudgeted: T2 never below 2 and the lead's R2 guard", line: 283 }
  - { file: lib/shared/repositories/plan_engine/volume_titration.dart, method_or_widget: "_recovered: T4 readinessEnabled", line: 119 }
  - { file: lib/shared/repositories/plan_engine/plan_engine_flags.dart, method_or_widget: "volumeTitrationEnabled (disable_volume_titration, default ON)", line: 355 }
  - { file: lib/shared/repositories/plan_engine/plan_engine_flags.dart, method_or_widget: "plateauEscalationEnabled (disable_plateau_escalation, default ON)", line: 482 }
  - { file: lib/features/dev/dev_panel_screen.dart, method_or_widget: "_toggleKillSwitch (the two dev-panel toggles)", line: 367 }
readers:
  - { file: lib/shared/repositories/plan_engine/plan_generator.dart, method_or_widget: "generateV4 Stage 4.5: resolveDeltas + mergePlateauSetDeltas + applyToWeeks (unchanged code; d83 comments only)", line: 379 }
  - { file: lib/shared/repositories/plan_engine/plateau_scan.dart, method_or_widget: "plateauedGroups / plateauedExerciseNames read plateauEscalationEnabled", line: 82 }
  - { file: lib/shared/repositories/plan_engine/sequencing_engine.dart, method_or_widget: "openerOf (the lead; never reads sets)", line: 62 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "the fresh-advance caller passes applyVolumeTitration / applyPlateauEscalation (pins == null)", line: 731 }
  - { file: lib/shared/services/pro_phase_advance.dart, method_or_widget: "the second fresh-advance caller (pins == null)", line: 888 }
hive_key_prefix: "configBox['disable_volume_titration'], configBox['disable_plateau_escalation']; reads exlog_* (workoutBox) and readiness_* (healthBox)"
hive_key_formula: "PlannedExercise.sets per week (workingSets on the deload week) -> WorkoutDay.toMap exercises[].sets"
sync_methods:
  - "SyncService plan push (user_progress.plan_json); set counts pass through untouched"
restore_methods:
  - "plan_json merge (unchanged); a stored plan is not rewritten, the rules apply at the next fresh PRO phase advance"
cloud_table: user_progress
cloud_columns:
  - plan_json
ist_handling:
  - { file: lib/shared/repositories/plan_engine/volume_titration.dart, method_or_widget: "resolveDeltas cutoff istDateStr(nowWall() - 35 days), unchanged", line: 61 }
provider_invalidations:
  - "none: generation only; Train and Home read the stored plan as before"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: generation writes through the existing plan writers (wrapUserScopedBox); the kill switches live in configBox like every PlanEngineFlags switch."
forbidden_patterns_checked:
  - { pattern: "a NEW non-focus row past its day's lead + 1 after titration / plateau (3,072 profile-scenarios)", absent: true }
  - { pattern: "a new 1-set row", absent: true }
  - { pattern: "a group-week over top(g) + the floor's seats past it", absent: true }
  - { pattern: "a day longer than OFF and over the plan audit's time bound", absent: true }
  - { pattern: "an output change with the opt-ins false, or with the kill switches set", absent: true }
  - { pattern: "a +1 from old readiness rows while disable_readiness is set", absent: true }
  - { pattern: "a code line of plan_generator.dart modified (rule 14; d83 waives comments only)", absent: true }
proposed_fix: |
  Plan docs/plans/2026-11-16-generator-step4-titration-plateau.md (v3.1, three review rounds, converged), founder d81 /
  d82 / d83. T1: a +1 on a row that is not its day's lead (SequencingEngine.openerOf over the week's budgeted rows) and
  credits no focus group needs current(row) <= current(lead), read at that moment (R5's rule). T2: a -1 takes rows at
  3+ sets whose groups stay above the band bottom, the most sets first, ties to the latest day then slot (d65), never
  below 2; the lead only when every other budgeted non-focus row of its day stays within its new sets + 1. T3: a
  stash-less deload row is skipped, a stash-less lead turns its day's lead checks off. T4: _recovered() returns false
  when readiness is switched off. T5: both features default ON behind kill switches (dev-panel toggles); the enable_
  keys are retired. applyToWeeks(leadFirst:) follows disable_lead_first.
regression_test_planned: |
  test/contracts/volume_titration_behavioral_test.dart (step 4 group: T1 x4, T2 x5, T3; the T4 and kill-switch /
  default-ON tests); test/plan_generator/titration_plateau_gate_test.dart (the simulated-history gate);
  test/plan_generator/goal_training_gate_test.dart (d81 live world); the re-derived session_set_budget_consumers_test,
  plateau_escalation / plateau_rotation behavioral tests.
impact_analysis: |
  Every fresh PRO phase advance from now on reads the user's history: a group whose main lifts rose (with 3+ recent
  green check-ins) can gain a set, a declining group loses one, a flat compound earns a set and is rotated next phase.
  Pre-launch, every account is a testing account (CLAUDE.md section 1). Costs measured on the build (section 3 of the
  plan): with T1 the progress scenario's +1s no longer lift a group over its band bottom (they went to non-lead rows);
  the d82 net on flat shrinks from 214 to 126 group-weeks; mixed histories end 17 group-weeks lower at the bottom.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "volume_titration.dart, plan_engine_flags.dart, plateau_scan.dart (comment), plan_generator.dart (comments, d83), dev_panel_screen.dart; flutter analyze clean; 16 rule mutants each reddened a test (below)" }
  - { layer: hive_local_state, status: verified, evidence: "configBox kill switches read through PlanEngineFlags (default-ON test, kill-switch tests, a stale enable_ key ignored); exlog_ / readiness_ read-only" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no cloud column, table or migration: set counts live inside plan_json, shape unchanged" }
  - { layer: edge_function_deploy, status: not_applicable, evidence: "supabase/functions reads neither key (grep)" }
  - { layer: client_server_contract, status: verified, evidence: "plan_json shape unchanged; the golden hashes unchanged (no golden persona opts in), run on the build" }
---

# Generator step 4: volume titration and plateau escalation switched on (OI-53)

## Root cause

- `VolumeTitration.applyToWeeks` was written before Unit 2A's lead-first rule and 2B's 2-set seats existed, and 2A
  explicitly left it un-capped while it was OFF ("Titration and plateau's +/-1 are not re-capped (both OFF by
  default)"). A +1 took the first matching row in slot order that fit the ledger, whatever the lead held; a -1 took the
  first matching row, which is the lead whenever the lead credits the group, and went to 1 set.
- `_recovered()` counted `readiness_*` rows with no `readinessEnabled` check (`PlateauScan` had it); the flag
  short-circuit was the only thing keeping old rows from counting after `disable_readiness`.

## Measured

Section 1 of the plan (main 85bdcbbe, `history_sim_dump_test.dart`, 576 profiles per scenario): over the ceiling
0 / 0 / 0; R2 / R5 new breaks 451 / 149 / 325 days; leads lowered 0 / 831 / 0; new 1-set rows 0 / 1,538 / 0. Every
history scenario carries `weakMuscles()` focus groups at phase >= 2 (`training_history_analyzer.dart:176`), so the
focus top (25) and the focus exemption apply in every advance.

On the build, `titration_plateau_gate_test.dart` (15 min 41 s locally; 3,072 profile-scenarios, OFF / IDENTITY /
KILLED / ON): every hard zero holds; IDENTITY and KILLED equal OFF everywhere; sore 3/6 and readiness-off change
nothing; plans changed progress 126, decline 373, flat 446, mixed 434, focus 41, sore 2/6 48; leads trimmed under the
guard 685 (decline); focus rows above lead + 1 that gained 48 (flat); groups with a plateau +1 and a titration -1
1,612 (mixed, each kept the -1); under-bottom group-weeks OFF -> ON: progress 8,942 -> 8,942, flat 9,956 -> 9,830
(d82 net), mixed 9,939 -> 9,956.

## Mutations

Each applied (count checked), the three test files run, the file restored from a backup copy (never git checkout):

| Mutant | Red tests |
|---|---|
| T1 check removed | 1 |
| T1 lead = slot 0 | 1 |
| T1 lead read at the start of the week | 1 |
| T1 focus exemption removed | 1 |
| T2 floor at 2 instead of 3 | 1 |
| T2 first-match instead of most sets | 6 |
| T2 cross-day tie earliest | 3 |
| T2 lead guard removed | 1 |
| T2 guard counts focus rows | 1 |
| T2 lead never a candidate | 7 |
| T3 null stash counted as 0 | 1 |
| T4 removed | 1 |
| `leadFirst` argument ignored | 1 |
| a +1 ignores `ledger.fits` | 9 |
| titration default OFF | 6 |
| plateau default OFF | 8 |

The gate's own pins were not mutated one by one (each run is 16 minutes); every rule above is pinned by a behavioral
test that reddened, and the gate's positive pins are exact counts that any stricter or looser rule moves.

## Founder decisions

d81 (Cut == Maintain 5 of 576 live accepted; the goal-training gate gains the live-world test), d82 (plateau ships
whole), d83 (rule-14 waiver: comments only in `plan_generator.dart`).

## B-pass (2026-11-17, `docs/reviews/generator-step4-bpass.md`)

Two fresh seats on 5c260f1b (CI green): 11 findings, 0 P0 / P1. Fixed in the B-pass commit: T2's lead guard counts
unbudgeted rows (R5 caps them too, A-F1); four tests for boundaries the flip makes live (the R2 equality, a flat e1RM
held not declining, the 40 % rule's 2 / 3 of 6, the quad-first credit), each proven by its mutant:

| Mutant | Red tests |
|---|---|
| R2 guard `>=` at equality | 1 |
| guard skips unbudgeted rows | 1 |
| flat e1RM read as a decline (`<=`) | 1 |
| 40 % rule `.floor()` | 1 |
| `creditedOf` -> `of` in `groupsOf` | 1 |

The gate's R2 check now also fails on a break that only got deeper (B-F5), and the history helper reads the library's
list-valued `exercise_type` (B-F6); the gate was re-run on the fixed tree (15 min 35 s): every hard zero holds and every pin is unchanged (no simulated plan puts an
unbudgeted row past the lead, so A-F1 is pinned by its behavioral test). Docs: the dev-panel comment says
debug build (OI-95), stale `enable_*` lines and the resolved ship-dark note corrected.
