---
bug_id: e7240a
date: 2026-10-22
batch: cardio-duration-distance (OI-389 Batch 1a; closes OI-380, OI-382)
status: fixed_in_code
tier: l_fix
blast_radius: account
symptom: >-
  A cardio exercise logged in the active workout (e.g. "Running (Treadmill)" 30 MIN 4 KM) was stored with 0 minutes
  and no km: `_normalizeSetsByLoggingType` zeroed `durationSec` for every non-`timed` type (the a4c7d1 else-branch) and
  `ExerciseSet` had no distance field, so `completeWorkout` dropped the KM box. The Train row then read "0 min" or a
  restored row "30 min · 0.0 km"; a distance exercise (Farmers Carry) read "N sets · 0 reps · X kg" (OI-380); a
  negative or absurd duration / km was accepted (OI-382); a cardio PR of 1800 s showed "1800 km" on StatsGrid; and
  "12.5" typed in the MIN box saved no minutes at all (`int.tryParse`).
concept: hive_field_name_exlog — a cardio / distance set's duration (seconds) and km survive every writer and every reader resolves them through WorkoutReadService.
sot_registry_entry: hive_field_name_exlog
writers:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "fieldsClearedFor (the one type table; cardio keeps duration + km + weight, clears reps only when the set carries its own field)", line: 93 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "logExercise: resolve type (library → hint → stored cardio/distance → shape) → normalise both sides → dedup → merge → distance_km = Σ per-set when > 0; bounds via setBoundViolation", line: 135 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "editLog: per-set bounds after the sets_detail translation; distance_km recomputed when the prior or edited sets carry km", line: 1239 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "moveExerciseLogs collision: each side via perSetList; km = merged per-set sum, else the two sides' aggregateDistanceKm; stale sets_detail removed", line: 1005 }
  - { file: lib/core/services/write_result.dart, method_or_widget: "ExerciseSet.distanceKm, canonicalKm, copyWith(clearDuration/clearDistance), toMap/fromMap, isDuplicateWithin", line: 108 }
  - { file: lib/features/train/services/log_exercise_logic.dart, method_or_widget: "cardioMinutesToSeconds / secondsToMinutesInput / exerciseSetFromInput / validateSetInputs bounds", line: 39 }
  - { file: lib/features/train/screens/active_workout/exercise_card.dart, method_or_widget: "_valuesOf (cardio minutes → seconds at capture) and _durationBoxText (restore writes minutes)", line: 700 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "completeWorkout: exerciseSetFromInput + loggingTypeHint", line: 2234 }
  - { file: lib/features/train/widgets/edit_workout_log_sheet.dart, method_or_widget: "editSheetUpdatesFor (decimal minutes, km guard twins, malformed minutes refused) and _save (failure copy, stays open)", line: 992 }
  - { file: lib/core/services/auth_session_bootstrapper.dart, method_or_widget: "healedExlog (in-place, fieldsClearedFor; footprint unchanged)", line: 1193 }
readers:
  - { file: lib/core/services/workout_read_service.dart, method_or_widget: "aggregateDistanceKm (per-set sum, else top level, rounded 0.001)", line: 254 }
  - { file: lib/features/train/utils/exercise_log_detail.dart, method_or_widget: "exerciseLogDetail (Train expanded row)", line: 12 }
  - { file: lib/core/utils/cardio_format.dart, method_or_widget: "formatSetDuration / formatDistance / cardioDistanceDetail (chips, preview, receipt, PR)", line: 16 }
  - { file: lib/features/train/widgets/week_selector.dart, method_or_widget: "weekExerciseLineDetail", line: 829 }
  - { file: lib/features/train/widgets/workout_receipt_card.dart, method_or_widget: "fromActiveWorkout / fromExerciseLogs / exerciseDetail", line: 187 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: "loadAllExercisePRs (one unit per exercise) + ExercisePR.unit / formattedValue", line: 852 }
  - { file: lib/features/train/widgets/stats_grid.dart, method_or_widget: "_loadPRs fallback renders pr.formattedValue", line: 163 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "graduationTopPrs (kg by value first, then by date)", line: 2619 }
hive_key_prefix: exlog_
hive_key_formula: "WorkoutWriteService.exlogKey(date, exerciseName) (unchanged)"
sync_methods: ["SyncService._syncExerciseLogs (unchanged: summary distance_km = top level; per-set from _resolvePerSetList)"]
restore_methods: ["sync_workout.dart _restoreExerciseLogs (unchanged)"]
cloud_table: workout_log_exercises, workout_log_sets
cloud_columns: [distance_km, duration_seconds, duration_secs]
contract_test_path: test/contracts/cardio_duration_distance_writer_to_reader_test.dart
ist_handling: ["unchanged: exlogKey / istDateStr"]
provider_invalidations: ["edit sheet _save invalidates the full batch on success AND on a partial failure (T30)"]
telemetry_op_types:
  success: ["none new"]
  failure: ["none new: a refused write returns WriteResult.invalid(code) and the UI shows copy, never the raw code in release"]
cross_account_guard: "unchanged: every writer goes through the user-scoped workoutBox"
forbidden_patterns_checked:
  - "canonicalising km <= 0 in the ExerciseSet constructor — REJECTED: validation must read the RAW value so a negative km is refused, not silently dropped (round 5 A P3-4); canonicalised in fromMap, the normaliser and exerciseSetFromInput instead"
  - "a restore-shape lift in logExercise — REJECTED (round 4 A P1-1): it collapses multi-set rows; the re-log reset of a restore-shaped row is OI-393"
  - "making the boot heal live — REJECTED for 1a (round 4 B P2-2): no kill switch; OI-394"
  - "value-semantics sweep (§4.1.5.3) over supabase/functions, re-run 2026-10-22: weekly-report selects duration_seconds but does not use it; pr-detection is weight-only; getPRTimeline now passes non-zero cardio duration_seconds / distance_km to the model; createCustomExercise only lists the type names; no server code branches on logging_type cardio or distance. Verdict: verified clean"
  - "a bare log['distance_km'] read in a reader — gated by test/contracts/no_top_level_distance_km_reads_test.dart"
proposed_fix: >-
  See the plan docs/plans/cardio-duration-distance.md rev 12 (U1–U8). One type table (fieldsClearedFor) shared by the
  normaliser, exerciseSetFromInput and the heal; ExerciseSet carries km; logExercise resolves the type over existing ∪
  incoming (library → slot hint → stored cardio/distance → shape), normalises both sides before dedup, and writes
  distance_km = Σ per-set only when > 0; bounds 0..21600 s and 0..300 km in logExercise, editLog (per set, after the
  sets_detail translation) and validateSetInputs; decimal minutes at capture (D2, founder 2026-10-22); every reader
  through WorkoutReadService.aggregateDistanceKm and the formatter pair; PRs carry their unit.
regression_test_planned:
  - "test/contracts/cardio_duration_distance_writer_to_reader_test.dart (T1-T4b, T6, T8 pure legs, T9, T10, T10b, T16a/c, T18, T19 a-g, T20, T23-T26, T28b/c, T29-T32)"
  - "test/contracts/cardio_complete_workout_behavioral_test.dart (T5, T28, T28c through completeWorkout)"
  - "test/features/train/log_exercise/log_exercise_card_test.dart group T32b (12.5 through the real card)"
  - "test/features/train/edit_sheet_cardio_test.dart (T8 rendered legs, T20, T30)"
  - "test/sync/cardio_move_merge_push_behavioral_test.dart (T19 payload legs)"
  - "test/widgets/ward_set_chips_test.dart (T4b/T11/T29 chips), test/features/train/stats_grid_cardio_pr_test.dart (T16b)"
  - "test/contracts/no_top_level_distance_km_reads_test.dart (gate)"
mutation_proof: >-
  71 mutants (plan §4 M1-M73; the four snapshot mutants M13, M35, M61, M71 were added after founder D4 = yes on
  2026-10-23), each
  applied by an exact-match replace (refused on 0 or >1 anchor matches; confirmed by count), run against the test
  files it names, and restored in a finally (lib/ byte-compared to a pre-run copy afterwards). 71 of 71 red. One
  survivor on the first run, M46 (the sheet pops on failure): the sheet was mounted as the app's home route, which
  cannot pop; the harness now pushes it as a route and M46 reddens 2 tests. Reddened counts: M1 10, M2 5, M3 7, M66 2, M67 1, M68 3, M69 2, M70 1, M72 3, M73 1, M4 1, M5 1, M8 1, M9 1, M10 4, M11 1, M12 1, M17 1, M18 1, M19 1, M20 1, M21 4, M22 4, M23 1, M24 1, M25 2, M26 3, M27 1, M28 2, M56 2, M57 1, M58 3, M62 2, M39b 1, M39c 2, M59 1, M60 2, M29 2, M30 1, M31 1, M31b 1, M63 1, M64 1, M32 1, M33 3, M34 1, M36 1, M37 2, M49 1, M50 1, M51 1, M52 1, M53 2, M65 1, M54 1, M55 1, M38 1, M39 1, M40 1, M41 1, M42 1, M43 1, M44 2, M45 2, M47 1, M48 1, M46 2. D4 (test/contracts/snapshot_cardio_fields_test.dart, 11 tests): M13 1, M35 7, M61 4, M71 3; second B-pass (docs/reviews, reviewed at c1e011414e0b) fixes: MF1a (distance weight back to sets[] only) 1, MF1b (sets count back to sets[] length) 1, MF2 (switch read as != null) 1.
  Runner and results: session scratchpad mut/run.py, mut/results.json. Self-attested.
impact_analysis: >-
  Behaviour changes, each deliberate: cardio minutes and km are kept; a cardio / distance set keeps its weight and keeps
  reps unless it carries its own field; out-of-range duration / km are refused (the chat card shows its existing
  "Not saved" line for an over-long cardio draft); a stored set with a phantom field now dedups against a clean re-send
  (T24, the one behaviour change of the U3 order; no existing test depended on the old outcome); the edit sheet stays
  open on a refusal. Known limits recorded, not worse than today: a set logged on top of a restore-shaped row resets its
  totals, km included (OI-393; 0 such rows live); the merge's mixed shape loses the restore-shaped side's km (OI-393);
  the heal stays dead on disk rows (OI-394); editLog does not apply the type table (1b); the cloud per-set clamp at
  3600 s (OI-391). The coach snapshot now carries duration_min (one decimal) / distance_km for cardio and distance
  rows (D4, kill switch disable_snapshot_cardio_fields, default on). Pre-launch: 0 cardio / distance rows exist live.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "U1-U8 as listed in writers/readers; flutter analyze clean on lib/" }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "exlog_* sets[].distance_km + duration_sec kept; real-Hive contract tests" }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "workout_log_exercises.distance_km numeric(8,3) exists; no km CHECK; wls_duration_secs_realistic 0..3600 NOT VALID (OI-391 owns it). No migration in 1a" }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "0 cardio/distance rows ever, 0 rows with km, 0 restore-shaped live rows, 0 rows whose stored type differs from the library (read-only, plan §0)" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "no EF change (coach logCardio is OI-392)" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "none touched" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "none touched" }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "none touched" }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "none touched" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "none" }
  - { tier: 12, name: "Client -> server contract", status: fixed_in_this_batch, evidence: "the client now sends real cardio seconds and km (were 0 / absent); push code unchanged: summary distance_km is the stored top level (written only when > 0, so NULL not 0); per-set rows carry km; T19 payload legs through the stub server" }
recurrence: >-
  Recurrence of the writer/reader drift class: a4c7d1 (its else-branch zeroed every non-timed duration: the root cause
  here), 6e1b45 (a field dropped by a copy: W4's hand copies and the missing ExerciseSet field), d4e7c2 (two writers,
  different field subsets: the restore writer's top-level km vs logExercise's per-set km, reconciled now in one reader).
  e8f95e (type guessed from data shape) is adjacent: 1a adds the slot hint and the stored type before the shape guess.
  New finding: the boot heal (W11) has been dead on disk rows since it was written (lazy cast throws); recorded, live
  heal is OI-394.
related_bugs:
  - a4c7d1
  - e8f95e
  - 6e1b45
  - docs/diagnoses/2026-08-02-restored-exlog-aggregate-read-d4e7c2.md
---

## What was wrong

See `symptom`. Plan: `docs/plans/cardio-duration-distance.md` rev 12 (§1 writers W1–W15, readers; §2 history).
Review record: `docs/plan-reviews/cardio-duration-distance.md` (9 rounds, converged).

## Writer and reader

The one type table `fieldsClearedFor` (`workout_write_service.dart:93`) is read by the writer's normaliser, by
`exerciseSetFromInput` (the active workout and the receipt) and by the heal. Every reader of a row's km goes through
`WorkoutReadService.aggregateDistanceKm` (`workout_read_service.dart:254`) and prints through `cardio_format.dart`.

## The fix

See `proposed_fix`. Splits under §4.12.1 (closure ledger `docs/audit/cardio-duration-distance.closure.yaml`): 1b coach
paths (OI-389 stays open), OI-391 cloud cap, OI-392 coach `logCardio`, OI-393 restore-shaped totals reset, OI-394 live
heal.
