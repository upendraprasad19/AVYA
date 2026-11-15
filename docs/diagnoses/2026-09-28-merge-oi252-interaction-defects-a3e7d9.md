---
bug_id: a3e7d9
date: 2026-09-28
batch: day-swapper-sync-load (merge of origin/main 7cb4eb78, merge-resolution review F1-F4)
status: fixed
blast_radius: platform
symptom: |
  A context-blind review of the merge of origin/main into this branch
  (OI-252 stable template ids, B2a-2b telemetry dedup) found four defects
  where the two lines of work met. None was a conflict git reported.
  F1: sync_nutrition.dart's nlog item catch paired a recordNonFatal with a
  _reportSyncFailure but lacked `skipServerPost: true`, so one failure made
  two log-client-error requests. The sweep test that exists to catch exactly
  this paired calls within a 300-character window, and a 583-character
  comment sat between the two calls, so the test was green.
  F2: in _syncScheduledWorkouts, a row whose template is not on this phone
  (Case 2) still OMITTED template_id. That was right before OI-252, when the
  cloud id needed a name lookup against the local row. Now the id is inside
  the key. After a day swap on this phone, the omitted key left the cloud
  row linked to the PRE-swap template.
  F3: _restoreWorkoutPlan's whole-bundle skip requires every bundled
  schedule key to exist locally. OI-252 filters ghost days (deleted template)
  out of the merge, so they are never written. An account with one ghost day
  never got the skip again, and paid the full merge plus a deleted-template
  query on every launch.
  F4: when the cloud says a day is rest and no template resolves,
  _restoreScheduledWorkouts types the row rest (b6e1c8), but the
  `...existingMap` spread kept the old workout's template_id, name and
  exercises. The next push sent that template_id with a rest status, and
  another device's restore built a custom_template row with status rest,
  which is the b6e1c8 hybrid again. Same area: the completed-row carve-out
  covered only `cloud planned`, so an unpushed local completion was demoted
  by a cloud rest row (spec I6), which a cross-device swap can now produce.
concept: sync_fanout_workout_domain
sot_registry_entry: sync_fanout_workout_domain
writers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_syncScheduledWorkouts Case 2 (F2)", line: 2089 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreScheduledWorkouts completed carve-out + rest-content strip (F4)", line: 2343 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreScheduledWorkouts merged row put (F4)", line: 2568 }
  - { file: lib/core/services/sync/sync_nutrition.dart, method_or_widget: "_syncNutritionLogs nlog item catch (F1)", line: 387 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreWorkoutPlan bundledRowAccountedFor → skipPlanMerge (F3)", line: 1355 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreScheduledWorkouts template resolve (reads the pushed template_id on another device)", line: 2238 }
  - { file: test/sync/sync_telemetry_test.dart, method_or_widget: "H-42 telemetry-pair sweep (F1 test scope)", line: 260 }
hive_key_prefix: "workoutBox schedule_<date>, tmpl_<uuid>"
hive_key_formula: not_applicable — unchanged
sync_methods: [_syncScheduledWorkouts, _syncNutritionLogs]
restore_methods: [_restoreWorkoutPlan, _restoreScheduledWorkouts]
cloud_table: scheduled_workouts
cloud_columns: [template_id, status]
contract_test_path: "test/contracts/sync_scheduled_payload_hash_index_writer_to_reader_test.dart (case 2a/2b, F2); test/sync/restore_plan_merge_skip_test.dart (ghost-day skip + mirror, F3); test/sync/restore_rest_row_content_test.dart (F4, 4 tests); test/sync/sync_telemetry_test.dart (block-scoped pairing, F1); test/sync/sched_template_fk_recovery_test.dart (repointed to OI-252)"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [upsert_scheduled_workout, scheduled_workout_fk_recovered]
cross_account_guard: not_applicable — no new reads or writes across accounts; every path runs under the existing session guard
recurrence:
  - "b6e1c8 (rest restored as a no-exercise workout): F4 is the same hybrid, re-created by a different route (a stale template_id pushed with a rest status)."
  - "feedback_mistake_guard_without_its_mirror: F3's presence check guarded 'a locally deleted row' and missed the mirror 'a row the merge itself never writes'."
  - "feedback_green_check_input_set_width: F1's sweep test was green because its input window (300 chars) was narrower than the code it judged."
related_bugs: [b6e1c8, d5a1e7, f4a8c2]
forbidden_patterns_checked:
  - "F3 alternative rejected: storing the ghost keys beside the fingerprint in the plan skip index. The index holds string values only, and the push side prunes row keys it does not know, so a second row key could be deleted under the skip. The local-only check needs no new state."
  - "F2 alternative rejected: always sending the key's id with no fallback. When the cloud lacks the template the FK rejects it on every pass; the 23503 fallback keeps the old omit-and-confirm outcome for that case."
  - "F4: the strip is unswitched, like the rest-type derivation it completes (spec sec 11 lists restore type derivation among the pure bug fixes); a kill switch would re-open the hybrid loop."
proposed_fix: |
  F1: add `skipServerPost: true` to the nlog item catch, and make the sweep
  test pair within the rest of the ENCLOSING BLOCK (brace matched) instead of
  a fixed 300 characters. The count moves 70 → 75: five pairs the window
  could not see, four already flagged and this one.
  F2: Case 2 sends the key's uuid; only a 23503 (the cloud lacks the
  template too) or a legacy key falls back to omitting template_id. Either
  way the row is confirmed.
  F3: a bundled row counts as present if it exists locally, OR its
  `tmpl_<uuid>` template key is absent locally, which is what a deleted
  template leaves. Residual, stated: a real row deleted locally whose
  template is also missing locally is not put back until the bundle changes.
  F4: a row typed rest with merged status rest drops template_id; if it
  replaced a workout it gets the canonical rest content (Rest Day /
  Recovery & mobility / no exercises). The completed carve-out now covers
  `cloud rest` as well as `cloud planned`.
  Also repointed: sched_template_fk_recovery_test.dart was written before
  the merge with legacy `tmpl_1` keys and a SELECT stub that answered one id
  for every name, so OI-252's migrator folded both templates into one key.
  It now uses uuid keys and models the loss as a 23503 on the schedule
  upsert (new SyncStubServer.writeFailers hook), which is how the real
  server signals it now.
regression_test_planned: |
  MUTATED AND RUN (rule 21), each restored by reverse string replace (not
  git checkout, which would have discarded uncommitted fixes in the same
  file) and re-checked green:
  F1: nlog `skipServerPost: true` removed → the sweep test red
  (`does not contain 'skipServerPost: true'`).
  FK repoint: the forced template re-push removed (`forceKeys: const {}`) →
  1 red (`Expected: ['Push A'] Actual: []`).
  F2: the key-id attempt disabled → 2 red (2a: template_id null; 2b: 1
  write instead of 2).
  F3: the ghost clause made always-false → 1 red (ghost test, 'New' instead
  of 'Old'); the template-presence check made always-true → 1 red (mirror).
  F4: the strip disabled → 2 red; the carve-out reverted to planned-only →
  1 red (the completed test).
  All reds were assertion failures on code that compiled.
impact_analysis: |
  F1 halves the telemetry requests for an nlog item failure. F2 keeps the
  cloud's template link right after a swap when the template is not on the
  phone. F3 restores the L2 skip for accounts holding a ghost day, removing
  one bundle merge and one deleted-template query per launch for them. F4
  stops a rest day from carrying a workout's template into the cloud, and
  stops a cloud rest row from demoting an unpushed completion.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "sync_workout.dart :1355, :2089, :2343, :2548; sync_nutrition.dart :387. flutter analyze lib/ clean." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "restore_rest_row_content_test.dart and restore_plan_merge_skip_test.dart assert the Hive rows the real merge writes." }
  - { tier: 12, name: "Client → server contract", status: verified, evidence: "case 2a/2b and the FK recovery test drive the real push against the local PostgREST stub and assert the scheduled_workouts payload." }
---

## Summary

Four defects sat where this branch met origin/main's OI-252 and telemetry
work. The merge review found them, and each is fixed with a test that was
mutation-proven: a missing `skipServerPost` hidden by a too-narrow sweep
window, a schedule push that dropped a known template id, a restore skip
that ghost days defeated for good, and a rest day that kept (and pushed) the
workout it replaced.
