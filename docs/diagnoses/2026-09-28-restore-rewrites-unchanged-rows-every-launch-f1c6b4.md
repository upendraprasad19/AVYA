---
bug_id: f1c6b4
date: 2026-09-28
batch: day-swapper-sync-load (Hermes E-pass remediation, findings h7F1 + h7F2, lens L31)
status: fixed
blast_radius: platform
symptom: |
  Hermes seat h7 (L31, I/O cost) found three restore writers that run on
  every launch through `restoreLightweightAlways` (sync_service.dart:1508)
  and write Hive unconditionally, even when the cloud row matches what is
  already stored. `_restoreWorkoutTemplates` wrote every live template on
  every launch (its "F6 · Always refresh" comment dropped an old
  skip-if-present guard without adding a changed-check). `_restoreUserProgress`
  put `userBox['progress']` and `_restoreUserProfile` called
  `ProfileWriteService.updateProfile` on every launch with no comparison. A
  steady-state user with N templates paid N+2 Hive writes per cold start for
  no change. It is the same class this batch closed for the 17 push domains
  (SyncSkipIndex) and for the schedule bundle (L2), but it had not been
  applied to these three restore writers. The founder's standing directive
  for this batch is not to flood Supabase or I/O.
concept: restore-write-if-changed
sot_registry_entry: not_applicable — no writer/reader contract or field name changed; the same writers write the same values, only less often
writers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreWorkoutTemplates — template put", line: 1885 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_restoreUserProgress — userBox['progress'] put", line: 996 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_restoreUserProfile — ProfileWriteService.updateProfile (re-stamps updated_at)", line: 845 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreWorkoutTemplates — reads the stored template to compare", line: 1878 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_restoreUserProgress — existingMap vs result.merged", line: 991 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_restoreUserProfile — existingMap vs merged, updated_at excluded", line: 837 }
  - { file: lib/core/services/sync_flags.dart, method_or_widget: "restoreWriteIfChangedEnabled (kill switch disable_restore_write_if_changed)", line: 187 }
hive_key_prefix: "workoutBox template_<id>; userBox 'progress'; userBox 'profile'"
hive_key_formula: not_applicable — unchanged
sync_methods: []
restore_methods: [_restoreWorkoutTemplates, _restoreUserProgress, _restoreUserProfile]
cloud_table: not_applicable — no cloud read or write changed
cloud_columns: []
contract_test_path: "test/sync/restore_write_if_changed_test.dart (3 behavioural tests counting real Hive write events via box.watch)"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — all three writers already run under the per-user boxes; the comparison reads the same box it would have written
forbidden_patterns_checked:
  - "comparing with `==` on the maps — rejected: a jsonb round-trip reorders keys. SyncFingerprint.canonicalJson (sorted keys at every depth) is the primitive the push-side skip index and the L2 schedule skip already use."
  - "comparing the whole profile map including `updated_at` — rejected: ProfileWriteService.updateProfile re-stamps updated_at = istNow() on EVERY call, so the stored stamp never equals anything and the skip would never fire. Mutation 2 below proves the exclusion is load-bearing. Skipping cannot lose a real change: the only difference ignored is the one the write itself would have invented."
  - "skipping reportProgressDemotionsDeclined along with the progress write — rejected: a refused monotonic demotion is news whether or not anything was written."
  - "a fingerprint index (SyncSkipIndex) for these restores — rejected: the stored Hive value IS the comparison target, so a second index would be a second copy of the same fact that could drift."
proposed_fix: |
  Each of the three writers builds the value it would write, compares
  SyncFingerprint.canonicalJson of it with the stored value, and skips the
  write when they are equal. The profile comparison drops `updated_at` from
  both sides first. "Refresh templates from cloud" still holds: a template
  that differs in any field is written. Behind a new §4.6 kill switch,
  `configBox['disable_restore_write_if_changed']`
  (`SyncFlags.restoreWriteIfChangedEnabled`, opt-out polarity like the
  batch's other L-flags), which restores the unconditional write for all
  three. Two @visibleForTesting seams, `restoreUserProgressForTest` and
  `restoreUserProfileForTest`, mirror the existing
  `restoreWorkoutTemplatesForTest` and are added to the public-API snapshot.
regression_test_planned: |
  test/sync/restore_write_if_changed_test.dart has three tests, one per
  writer. Each counts the Hive write events on the exact key (`box.watch`)
  across four restores: the first write (1), an identical restore (0), a
  real change (1, with the new value asserted), and the kill switch on with
  an identical restore (1). The positive case means no test could pass if
  the restore never wrote at all.
  MUTATED AND RUN (rule 21):
  (1) `restoreWriteIfChangedEnabled` was forced false by changing the
  comparison to `== 'MUTANT'`, applied and confirmed with `grep -c` (1).
  All 3 tests went red, each on the identical-restore assertion
  (`Expected: <0> Actual: <1>`).
  (2) The profile `..remove('updated_at')` was changed to `..remove('MUTANT')`
  and confirmed applied. Exactly 1 test went red, the profile test, on the
  same assertion. The other 2 stayed green, so the file compiled.
  Both were restored; `git grep -c MUTANT -- lib` printed nothing. 49/49
  green across the new file, the public-API snapshot, the progress-monotonic
  behavioural test and the OI-252 template restore test.
impact_analysis: |
  A steady-state launch no longer writes N+2 identical Hive rows. Any real
  cloud change is still written, and the values written are the same as
  before. One visible difference: on an unchanged restore, the profile's
  local `updated_at` is no longer bumped to "now". Checked: no reader in
  lib/ reads the profile map's `updated_at` (a grep for `['updated_at']`
  finds only other maps), and `sync_profile.dart:785` records that the
  field is server-set and never pushed. So the stamp now means what its
  name says, the last real change. Provider invalidation is unaffected: ProfileWriteService
  never invalidated providers on this path (skipSync:true, no
  invalidation), and the restore flow's own post-restore invalidation still
  runs.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "sync_workout.dart:1878-1885, sync_profile.dart:837-845 and :991-996, sync_flags.dart:187. flutter analyze lib/ has no warnings or errors." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "write counts on workoutBox template_<id>, userBox progress and userBox profile, observed via box.watch in restore_write_if_changed_test.dart." }
  - { tier: 12, name: "Client → server contract", status: not_applicable, evidence: "no network read or write changed; the same injected rows produce the same stored values." }
---

## Summary

Three restore writers ran on every launch and rewrote unchanged Hive rows:
templates, the progress map, and the profile map. Each now compares the value
it would write with the stored one, using sorted-key canonical JSON, and
skips identical writes. The profile comparison ignores `updated_at`, because
the write itself would have re-stamped it. A new kill switch,
`disable_restore_write_if_changed`, restores the old unconditional write.
One test file counts the real write events for each writer. It was
mutation-proven twice: forcing the switch reddened all three tests, and
removing the `updated_at` exclusion reddened only the profile test.
