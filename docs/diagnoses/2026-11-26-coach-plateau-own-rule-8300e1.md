---
bug_id: 8300e1
date: 2026-11-26
batch: pr-card-unify
status: fixed
tier: full
blast_radius: account
symptom: |
  Found while removing Train's key-lift reader (83e031), confirmed by code reading: the coach's plateau insight ("Bench Press plateau detected: 40kg for 12+ weeks") used its own rule. It gated on loadKeyLiftPRs (substring names: Front / Goblet Squat counted as "Squat"), compared only the heaviest WEIGHT in the last 42 days with the one before (so 40 kg x 6 -> 40 kg x 8 read as a plateau), used the device-local clock, and always said 12 weeks (weeksStuck was the length of a 12-entry list). The plan engine already had a careful plateau definition (plateau_scan.dart).
concept: plateau_escalation
sot_registry_entry: plateau_escalation
writers:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "WorkoutWriteService.logExercise writes the exlog_* rows (unchanged)", line: 135 }
readers:
  - { file: lib/features/ai_coach/services/pattern_detector.dart, method_or_widget: "PatternDetector._plateauDetector (rewritten onto the shared scan)", line: 143 }
  - { file: lib/shared/repositories/plan_engine/plateau_scan.dart, method_or_widget: "PlateauScan.plateauedGroups / plateauedExerciseNames (now thin maps over flatCompoundLifts)", line: 80 }
hive_key_prefix: "exlog_, readiness_ (read only, unchanged)"
hive_key_formula: "n/a (no key change)"
sync_methods: []
restore_methods: []
cloud_table: "none"
cloud_columns: ["none"]
contract_test_path: test/contracts/coach_plateau_insight_behavioral_test.dart
ist_handling: ["window and recency cutoffs: istDateStr(nowWall().subtract(...)) compared lexically with IST day strings; the old detector used device-local DateTime.now()"]
provider_invalidations: ["none (PatternDetector is not a provider)"]
telemetry_op_types:
  success: ["none"]
  failure: ["none (PatternDetector._tryAdd swallows a detector failure, unchanged)"]
cross_account_guard: "Unchanged: reads the session's workoutBox / healthBox through HiveService, as before."
forbidden_patterns_checked:
  - { pattern: "a second plateau rule (weight-only, substring names) outside PlateauScan", absent: true }
  - { pattern: "a constant weeks count in the plateau copy", absent: true }
proposed_fix: |
  Plan docs/plans/pr-card-unify.md (founder D4, D5, D7). PlateauScan.flatCompoundLifts({recentWithinDays}) is the ONE scan (best-set Epley e1RM per session, >= 3 sessions over >= 28 days inside 63, within 5 %, compound by exact name), returning FlatLift; plateauedGroups / plateauedExerciseNames keep their gates and map over it; fatiguePresent() public. The coach: readinessEnabled && fatiguePresent -> none; flatCompoundLifts(recentWithinDays: 14); longest span, ties by name; "<name>: no real progress over your last N weeks (est. 1RM ~X kg). Time to adjust!" (N = span ~/ 7, 4..9; X to 0.5 kg). Deleted orphan WorkoutRepository.getExtendedWeeklyWorkoutCounts (its only caller was the old weeks line).
regression_test_planned: |
  test/contracts/coach_plateau_insight_behavioral_test.dart (real Hive, pinned clock, the real exercise library): a flat bench with its exact text; reps rising -> none; exact names (flat Dumbbell Bench named, rising Barbell Bench not); per lift; a decline -> none; bodyweight / timed -> none; readiness fatigue -> none and readiness OFF -> the insight; 2 sessions / a 21-day span -> none; recency 14 counts, 15 does not; 40 days -> 5 weeks, 49 -> 7; longest span and tie-break, also end to end; 0.5 kg rounding; sessions outside 63 days ignored. Plan engine unchanged: plateau_scan_test, plateau_escalation_behavioral_test, plateau_rotation_behavioral_test green untouched.
mutation_proof: |
  Applied by script (count confirmed), run, reverted; no compile errors; one red each unless stated. C1 the fatigue gate removed. C2 the readiness flag ignored. C3 the span floor 28 -> 21. C4 recency 14 -> 15. C5 recency exclusive. C6 recency dropped. C7 weeks a constant. C8 weeks rounded. C9 the first lift picked unsorted. C10 no tie-break. C11 no 0.5 kg rounding (2 red). C12 the window 63 -> 90.
impact_analysis: |
  The coach's plateau insight fires less often (reps count, exact names, >= 4 weeks, trained in the last 14 days) and names any compound lift, not only four. The plan engine's plateau outputs are unchanged (same gates, same loop, Set outputs). No write, sync or schema change.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "pattern_detector.dart _plateauDetector, plateau_scan.dart flatCompoundLifts / FlatLift / fatiguePresent, workout_repository.dart orphan removed. Whole-project analyze: no warning or error." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "The behavioral test writes exlog_* and readiness_* rows into the real session boxes and reads the insight through PatternDetector.analyze." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Client-only: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Client-only." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "Client-only." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function reads the insight text or the plateau_<id> pattern ids (grep of supabase/); the plateau-alert function is separate." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Client-only." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Client-only." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Client-only." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Client-only." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Client-only." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "pattern_ids reach the AI snapshot as data only; no server code matches them." }
recurrence: "Not a recurrence of a prior diagnose. Same class as the e1RM extraction rationale in e1rm_history.dart (three hand-rolled copies of one rule, the writer/reader drift class 2.1) and 83e031 (a second reader of one concept); fix shape the same: one function, every caller through it."
related_bugs: [83e031, cb1ab1]
---

# 8300e1 - the coach judged plateaus by its own rule

## What happened
The coach's plateau insight looked only at weight, matched names by substring, used the device clock and always said "12+ weeks".

## The fix
It now uses the plan engine's e1RM plateau scan, with founder D7: only a lift trained in the last 14 days, "over your last N weeks".

## Not established
- Not yet seen on a device; founder check after the merge.
- spanDays parses IST day strings with DateTime.parse (device-local); in a DST zone a span can read a day short. Pre-existing plan-engine maths, unchanged.
