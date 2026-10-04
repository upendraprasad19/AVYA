---
bug_id: d4a7e1
date: 2026-10-04
batch: swap-title-and-launch-refresh
status: fixed
blast_radius: account
symptom: |
  Founder-reported (2026-10-01, day-swap report): after swapping Oct 1 and
  Oct 2 on the web and completing the swapped workout there (log "PULL +
  CORE"), the Android phone's Train row title for Oct 1 stayed "Push + Core"
  (and the Home Today widget showed the old name) while the completed card,
  receipt and calendar view showed the correct workout. A completed
  non-template schedule row keeps the content it had when it completed: the
  restore merge returns a local completed row unchanged and the status
  overlay never writes a title for a non-template row, while the completed-day
  surfaces read the performed log.
concept: workout_completion_status
sot_registry_entry: |
  workout_completion_status (docs/sot_registry.yaml:3414) — adds a writer row
  for CompletedTitleHealer, the only writer that changes the title of an
  already-completed row. behavioral_test_path of the concept is unchanged
  (test/contracts/sync_schedule_completion_payload_hash_index_writer_to_reader_test.dart);
  the new test is cited in the writer row.
writers:
  - { file: lib/core/services/plan_integrity_reconciler.dart, method_or_widget: "mergeScheduleEntry - returns a local completed row unchanged (the freeze)", line: 105 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreScheduledWorkouts - spreads ...existingMap; title only from a cloud template", line: 2589 }
  - { file: lib/core/services/completed_title_healer.dart, method_or_widget: "CompletedTitleHealer.run - the fix: row title := its own wlog name", line: 65 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "restoreFromCloudForUser wrapper + restoreFromCloud tail - the hooks", line: 1858 }
readers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "Train week rows - name from the schedule row", line: 841 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "todayWorkoutProvider -> Home Today widget", line: 521 }
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: "Home Today card title - reads the schedule ROW (the receipt / View Card read the logs)", line: 854 }
hive_key_prefix: "schedule_ and wlog_ (workoutBox)"
hive_key_formula: "'schedule_${istDateStr(date)}' / 'wlog_${istDateStr(date)}' (WorkoutWriteService.scheduleKey / wlogKey)"
sync_methods:
  - "_syncScheduleCompletions copies the ROW's workout_name (sync_workout.dart:685): follows at the next normal sync; not changed"
restore_methods:
  - "restoreFromCloudForUser (multi-step + single-call)"
  - "restoreFromCloud (no-local-logs path)"
  - "_restoreWorkoutLogs / _restoreScheduledWorkouts / mergeScheduleBundleIntoHive (unchanged writers the heal runs after)"
cloud_table: null
cloud_columns:
  - null
contract_test_path: test/contracts/completed_title_follows_log_test.dart
ist_handling:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "scheduleKey / wlogKey -> istDateStr (unchanged)", line: 1524 }
provider_invalidations:
  - "none added - the existing heal_after_restore bump (restoreCompletedTick) refreshes the tabs after the heal on the background branch; restoreCompletedTick is deliberately NOT bumped by the heal (it gates streak decay)"
telemetry_op_types:
  success:
    - completed_title_healed
  failure:
    - completed_title_heal_skipped
cross_account_guard: "The heal reads and writes only the CURRENT user's boxes, takes a fresh HiveService.instance.workoutBox per row, and swallows the ownership/StateError an account switch raises (returns 0, never a restore failure). It uses no cloud data."
forbidden_patterns_checked:
  - { pattern: "restoreCompletedTick bumped by the heal", absent: true }
  - { pattern: "heal inside heal_after_restore.dart (UI part file, one branch, success only)", absent: true }
  - { pattern: "wlog workout_name 'Workout' / 'Chat Workout' copied onto a row", absent: true }
proposed_fix: |
  A local-only pass, CompletedTitleHealer.run(), run after a SUCCEEDED full
  restore at the one public entry (restoreFromCloudForUser wrapper) and at
  the tail of restoreFromCloud. For each completed, non-template, non-logged
  schedule row whose wlog_<date> is a real workout_log (source !=
  cloud_restore_completion) with a non-placeholder name differing from the
  row's ignoring case/whitespace, set ONLY workout_name to the log's name.
  Kill switch disable_completed_title_heal. Placeholder names are one shared
  constant (kPlaceholderWorkoutNames) so the chat handler's writer and the
  heal cannot drift.
regression_test_planned: |
  test/contracts/completed_title_follows_log_test.dart (26 tests, real Hive):
  founder fixture for both wlog sources; map-minus-title byte-identical;
  second run 0 writes; stale re-put re-healed; double-completed date follows
  the single slot; one test per guard (placeholder x2, synthetic source,
  template, planned, logged, no wlog, wrong wlog type, case-only, blank
  name); kill switch; closed box swallowed; hook decision (success only,
  restoreCompletedTick untouched, flag closed); placement parity over
  restoreFromCloudForUser + restoreFromCloud; placeholder-set scan of the
  markCompleted call sites.
  MUTATION PROOF (rule 21), each applied once, "applied" confirmed by an
  exact-match count of 1, file restored and byte-compared after every run:
  M1 drop status guard (+22 -1), M2 drop template guard (+22 -1), M3 drop
  logged guard (+22 -1), M4 drop synthetic-source guard (+22 -1), M5 drop
  placeholder check (+21 -2), M6 case-sensitive compare (+22 -1), M7 drop
  wlog-type guard (+22 -1), M8 drop flag check in the heal entry (+22 -1),
  M9 heal after a non-success (+22 -1), M10 drop the heal in the public
  entry (+22 -1), M11 drop the restoreFromCloud tail heal (+22 -1), M12 heal
  bumps restoreCompletedTick (+22 -1), M13 placeholder set loses 'workout'
  (+20 -3). Code-review rewrite of the two weak tests (placeholder-literal scan over
  the ENCLOSING function of each markCompleted caller + a caller census; a
  placement-parity test that pins the decision seam, the core's single
  caller, heal-after-Future.wait and the restore-entry census) was itself
  mutated: M14 a real-name literal in train_provider (+22 -1), M15 wrapper
  heals without the decision seam (+22 -1), M16 restoreFromCloud tail heal
  dropped (+22 -1), M17 chat handler stops naming kChatWorkoutName (+21 -2),
  M18 a new caller of restoreFromCloudForUser (+22 -1). An earlier M17 with a
  non-compiling replacement produced no test output and was NOT counted;
  it was redone with a compiling one. Every mutation reddened at least one test.
  The full suite (TZ=Asia/Kolkata) then caught two regressions the targeted
  runs could not: no_silent_debugprint_in_services_test (H-42: the healer's
  catch printed without telemetry; now also logs completed_title_heal_skipped
  with the error TYPE only) and sync_domain_interface_test (the restore/push
  helper-pair exhaustiveness guard saw the new _restoreFromCloudForUserCore;
  added to its restoreOnlyAllowlist beside FromCloudForUser, its parent).
  A second fresh-context review (ACCEPTED, no P0/P1) then found: P2 the
  wrapper's success-only condition survived negation (substring checks only);
  P3 guard-removal mutations were masked by the pass-level catch (a removed
  `is! Map` guard made the pass report 0 and the no-wlog test stay green);
  P3 the entry census asserted callers of the public restore must be
  restoring_screen (wrong: they are hooked by construction); P3 the
  check_writeservice_only allowlist entry was a no-op (the gate matches only
  a literal `workoutBox.put(`, the healer writes through a local alias) and
  would have silently allowed a future direct write, so it was REVERTED. The
  first review's "missing from the allowlist" finding was therefore not a
  real gate failure (the pre-commit loop had passed without it). Fixes: the
  wrapper test now matches the exact non-negated `if (...) { await heal; }`;
  three tests prove an earlier no-wlog row, a non-Map schedule value and a
  non-Map wlog never starve a later row; the census now pins the call sites
  of _restoreWorkoutLogs/_restoreScheduledWorkouts (6 in sync_service.dart,
  3 flag-gated ForSyncDomain in sync_workout.dart). Mutations: M19 wrapper
  negates the decision (+25 -1), M20 drop `log is! Map` (+24 -2), M21 drop
  `raw is! Map` (+25 -1), M22 a new restore-op call site (+25 -1); all
  applied once, all restored (git status clean of the mutated files). Fixture check: the
  founder fixture (completed "Push + Core", log "PULL + CORE") is the live
  case; 154 related existing tests across 18 files still pass.
impact_analysis: |
  Changes one field (workout_name) on completed non-template rows, only when
  the device's own performed log names a different workout. Affected
  surfaces: Train row title, Home Today widget, week strip, the Home insight
  and day-detail sheet (these render the stored casing, often upper-case
  from Train - accepted, cosmetic), and the cloud completions name (follows
  at the next normal sync because _syncScheduleCompletions copies the row's
  name).
  Not changed: status, completion metadata, swap markers/stamps, exercises,
  workout_focus, type, week_*. A healed row's exercise list stays as it was
  (the completed card reads the logs). Template rows are excluded (the
  overlay owns their titles). A date completed twice under different names
  keeps the OLDEST cloud log in its single local slot (restore keeps the
  first by created_at); the heal follows that slot, i.e. what the card shows
  (OI-302 tracks whether restore should pick the newest).
  Residual, stated: which source the founder's phone's wlog_2026-10-01
  carries is unproven. If it is the synthetic cloud_restore_completion one
  (copied from the stale completions name) the heal will not fire there; the
  founder's device check settles it, and the optional live repair of the
  Oct 1/2 plan_json rows is the fallback. OI-284 therefore stays OPEN until
  that check. Not in this batch: OI-294 (a restore that never returns
  refreshes nothing; split out by plan round 2).
related_bugs:
  - d5a1e7
  - b6e1c8
  - a7d3f1
  - d9b2c5
  - c7e3a9
recurrence: |
  Recurrence of the completed-row / restore-merge family (a7d3f1/d9b2c5
  restore overwrite, b6e1c8 hybrid rows, debugging classes 2.30, 2.51,
  2.74). New class 2.85: a "completed is sacred" guard freezes the whole row
  though the row's TITLE has a different source of truth (the log) than its
  status. Companion lesson recorded: restoreCompletedTick also gates streak
  decay - a "refresh the UI" bump on it was rejected by plan review.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "completed_title_healer.dart + SyncService hooks + SyncFlags.completedTitleHealEnabled; flutter analyze clean on the touched files; 26 new tests green, 22 mutations all red." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Real Hive session in the test: only workout_name changes (map minus title byte-identical); wlog slot and every other key untouched." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Live SELECT-only 2026-10-04 (project dedsavbjuwgarrhphgnl, user d7a67a37): scheduled_workouts Oct 1/Oct 2 completed with template_id NULL on every row Sep 29-Oct 4; cloud plan_json Oct 1 = Pull + Core completed. scheduled_workouts has no title column (backups/live_schema_columns.json)." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Traced restoring_screen.dart:114/375 -> restoreFromCloudForUser (heal before _healAfterRestoreInBackground's bump); restoreFromCloud only from _restoreIfNeeded; no other production restore entry (round-2 review)." }
---

## Summary

A completed non-template schedule row kept its pre-swap title after a
cross-device restore, while the completed card showed the performed
workout. The row now follows its own performed log after a successful full
restore.

## Root cause

Writers: `mergeScheduleEntry` keeps a local completed row unchanged
(`plan_integrity_reconciler.dart:105-107`) and `_restoreScheduledWorkouts`
spreads `...existingMap` and writes a title only from a cloud template
(`sync_workout.dart:2562-2589`). Readers: the Train row and Home Today widget
read the schedule row; the completed card, receipt and calendar read
`wlog_<date>`. The status was right and the content was frozen at pre-swap.
How the phone reached "completed before the swap was merged" is unproven
(OI-293); the fix repairs the row whatever the order was.

## Fix

`CompletedTitleHealer.run()` after a succeeded `restoreFromCloudForUser` and
at the tail of `restoreFromCloud`; see `proposed_fix`.

## Related

Plan `docs/plans/swap-title-and-launch-refresh.md` v3 (rounds 1-2). Six
earlier rounds on `swap-cross-device-reconcile` (merged c7e3a9 only). Open on
the board: OI-284 (until the device check), OI-294, OI-295, OI-302.
