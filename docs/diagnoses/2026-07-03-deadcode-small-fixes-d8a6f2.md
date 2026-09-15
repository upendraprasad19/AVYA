---
bug_id: d8a6f2
date: 2026-07-03
batch: audit-fixwave-2026-07-02
status: fixed
blast_radius: platform
symptom: >
  Cluster of dead-code + small-correctness findings from the 2026-07-02 audit,
  fixed together in Units 6-7. (F14) NutritionWriteService.logWater wrote a
  `water_<date>` key to nutritionBox with ZERO callers and no sync reader — a
  latent trap (a future caller would create water rows that never reach cloud);
  the real writer is HealthWriteService.setWaterMl. (F15) TermsModal.maybeShow
  had zero call sites (the sign-in trigger was removed in the Test #4 / OBS-A
  batch) and the DPDP terms-acceptance write had no SoT concept. (F16)
  `health_sync_enabled` is written to the shared configBox and was not in the
  userScopedKeys allowlist, so a prior owner's toggle could survive a fast
  account switch. (F17) `template_exercises.prescribed_sets/reps` persisted NULL
  because the builder's saved exercise map omitted sets/reps (readers fall back
  to the exercise's default_sets, so benign at read time, but the cloud row was
  not self-describing). (F19) markCompleted stamped `completed_at` from device-
  local DateTime.now() (IST) into the timestamptz column — a +5:30 skew vs the
  exercises' UTC created_at. (F20) settings_screen (route /profile/settings) is
  functional but not linked from the Profile tab.
concept: audit_fixwave_small_fixes
sot_registry_entry: >
  Not a single concept — a cluster. F14 removed the dead logWater writer from the
  water_intake concept (setWaterMl is sole canonical). F15 registered a
  terms_acceptance concept. F16 documented health_sync_enabled in
  _intentionallyShared. No new writer/reader CONTRACT changed for F17/F19/F20.
writers: >
  F14: deleted NutritionWriteService.logWater (nutrition_write_service.dart).
  F16: profile_provider.dart writes configBox['health_sync_enabled'] (unchanged;
  documented device-level in user_config_migrator.dart _intentionallyShared).
  F17: sync_workout.dart _syncWorkoutTemplates now falls back to
  ex['default_sets']/['default_reps'] for prescribed_sets/reps. F19:
  workout_write_service.dart markCompleted stamps completed_at via .toUtc().
readers: >
  F14: water readers unchanged (they key off water_ml_ via setWaterMl). F15:
  auth_session_bootstrapper.hydrateFromCloud projects terms_accepted_at/version
  to the users cloud row. F17: schedule/active-workout readers already fell back
  to the exercise default_sets (that's why the NULL was benign) — now the cloud
  template_exercises row carries the prescription too. F20: settings_screen rows
  route to the real surfaces; the screen is reachable by its route only.
hive_key_prefix: "water_ (removed) / terms_ (F15) / n/a"
hive_key_formula: "n/a — dead-code removal + timestamp/scope/prescription corrections"
sync_methods: ["_syncWorkoutTemplates (F17 fallback)"]
restore_methods: ["auth_session_bootstrapper.hydrateFromCloud (F15 terms)"]
cloud_table: "users (F15 terms) + template_exercises (F17) + workout_logs (F19 completed_at)"
cloud_columns: ["terms_accepted_at", "terms_version", "prescribed_sets", "prescribed_reps", "completed_at"]
contract_test_path: test/contracts/terms_acceptance_writer_to_reader_test.dart
ist_handling: >
  F19 is the IST-relevant fix: completed_at (a timestamptz audit column) now uses
  .toUtc() before serialization. The IST `date` date-key columns are UNTOUCHED
  (§4.5 — they stay istDateStr). No other item touches date semantics.
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: true
forbidden_patterns_checked:
  - "Dead write method that keys a Hive box no sync helper reads (orphan rows that never sync). F14: logWater wrote water_<date> (nutritionBox) — no reader. Deleted."
  - "Dead widget retained after its only trigger was removed. F15: TermsModal (zero call sites). Deleted; its source-assertion tests removed; the live terms write registered as a SoT concept."
  - "Device-scoped preference written to shared configBox without a reasoned entry in the allowlist. F16: health_sync_enabled documented as an intentional device-level key (health is a device capability; no cross-user data leak)."
  - "A timestamptz audit column stamped with device-local (IST) wall-clock instead of UTC. F19: completed_at now .toUtc()."
proposed_fix: >
  F14: delete logWater + its dedicated test; repoint the water_logs contract test
  + the registry water_intake writer to setWaterMl. F15: delete terms_modal.dart;
  remove its source-assertion test groups (terms_skip_test, null_guard_test,
  provider_invalidation_test); register a terms_acceptance SoT concept + test.
  F16: add health_sync_enabled to _intentionallyShared with the device-capability
  rationale (no half-migration — reader stays on configBox). F17: at the
  template-exercise sync, fall back to default_sets/default_reps so the cloud row
  is self-describing (readers already fell back locally). F19: .toUtc() on
  completed_at (completed_at_ms epoch unchanged). F20: document settings_screen's
  registered-but-unlinked state (retained pending a product decision) — no
  behaviour change.
regression_test_planned: >
  terms_acceptance_writer_to_reader_test.dart (F15); water_logs_writer_to_reader_
  test.dart repointed to setWaterMl (F14); the SoT parity + Gate-42 gates pass
  after F14's registry ripple was fixed. F17/F19/F20 are small enough that the
  full suite + analyze are the coverage (F19's .toUtc() is a one-line narrowing;
  F17's fallback is additive; F20 is doc-only).
touched_layers_checked:
  - "client_code — status: fixed_in_this_batch — F14 delete logWater; F16 allowlist doc; F17 sync fallback; F19 .toUtc(); F20 doc-comment."
  - "hive_local — status: verified — F14 removal leaves setWaterMl as sole water writer; F15 terms write unchanged."
  - "client_to_server_contract — status: verified — F17 template_exercises now carries prescribed_* (additive); F19 completed_at is UTC; F15 terms project via bootstrapper — all confirmed by reading the code + SoT parity gate green."
impact_analysis: >
  All low-risk. F14/F15 remove dead code (no runtime behaviour). F16 is a
  documented decision (no code change to the write/read). F17 is additive (cloud
  rows gain a value they lacked; no reader regressed — they already fell back).
  F19 normalizes an audit timestamp to UTC (no date-key touched). F20 is doc-only.
  Platform-tier only because F17 edits a file under lib/core/services/sync/**; the
  change itself is a conditional fallback with no path that can drop data.
---

# d8a6f2 — dead-code + small-correctness cluster (F14/F15/F16/F17/F19/F20)

See YAML frontmatter. Fixed together in the audit-fixwave batch (Units 6-7).
None is user-facing behaviour change of consequence; grouped so the batch closes
every 2026-07-02 audit finding (§4.2 no-deferrals).

## Pre-commit gate reconciliation (F17)
F17's new fallback reads `ex['default_sets']`/`ex['default_reps']` on the exercise
sub-object inside `_syncWorkoutTemplates`. Gate 19 (`check_hive_map_field_drift`)
mis-attributed those to the `schedule_*`/`exlog_*` Hive maps (the file also walks
those prefixes), flagging them as drift. They are canonical **exercise-library**
field names (`user_custom_exercises.default_sets/default_reps` live) read only as a
prescription fallback — never emitted into those Hive maps. Resolved by adding
`default_sets`/`default_reps` to the gate's `_alwaysOk` set with the documented
rationale (these are safe anywhere as canonical exercise-default names, so the
global scope is appropriate — unlike the NUT-02 cloud-projection reads, which are
baseline-scoped in e5c4b9).
