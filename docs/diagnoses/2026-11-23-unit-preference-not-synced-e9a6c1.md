---
bug_id: e9a6c1
date: 2026-11-23
batch: oi348-walk-fixes Landing 2 (B9)
status: fixed
tier: full
blast_radius: platform
symptom: |
  OI-348 walk A3 (AAB 1.0.0+50, 2026-11-22): the phone's body-measurement sheet was set to inches; the same account on the web opened the sheet in centimetres. The values themselves are stored in cm and were right. Live 2026-11-23: no unit column on any table (information_schema). Reading the code also showed the Profile Units switch lived in the SHARED device box (configBox['units_metric']), so a second account on the same device inherited the first account's choice.
concept: unit_preference_sync
sot_registry_entry: unit_preference_sync
writers:
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: "setUnitsMetric: profile units_system via ProfileWriteService.patchProfileWith (owner captured at call start, no write without a profile); was configBox['units_metric']", line: 1119 }
  - { file: lib/features/profile/providers/body_measurements_provider.dart, method_or_widget: "MeasurementWriteNotifier.save: profile measurement_unit under the same shouldRememberUnit gate, owner captured, no stub, a failed unit write is caught (B-pass F1); was MigratedKey body_measurement_sheet_unit", line: 140 }
  - { file: lib/core/services/units_pref_adopter.dart, method_or_widget: "UnitsPrefAdopter.runIfNeeded: one-time per device, copies the legacy device value into a profile without units_system, after a SETTLED restore; deletes the device key; flag units_metric_to_profile_v1_done in migrationBox; a sign-up stub is not a profile (B-pass F4)", line: 73 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_syncUserProfile payload - ...unitPrefsPushEntries(p, enabled: UnitPrefFlags.pushEnabled) (valid values only, absent stays absent)", line: 250 }
readers:
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: "getUnitsMetric: profile units_system (only 'imperial' is imperial), else the legacy device key until the adopter ran; TOTAL (throw -> metric + units_pref_read_failed)", line: 1097 }
  - { file: lib/features/profile/providers/body_measurements_provider.dart, method_or_widget: "lastUnitInches: profile measurement_unit, else the legacy per-user key; preferredInches (sheet + Progress card)", line: 168 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_restoreUserProfile (per-key merge) - cloud non-null wins per key, cloud null never wipes (unchanged; carries the two new keys)", line: 773 }
  - { file: lib/features/profile/screens/profile/screen.dart, method_or_widget: "_isMetric seeded once; _onUnitsChanged (no snap-back); invalidateOnBackgroundRestore re-seeds it on the restore tick, except while a tap's write is pending (the write's completion re-seeds; B-pass F3)", line: 131 }
  - { file: lib/features/ai_coach/widgets/diff_preview/switch_goal_diff.dart, method_or_widget: "coach goal-change preview: was a RAW configBox['units_metric'] read; now getUnitsMetric()", line: 78 }
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "initState unit (getUnitsMetric, unchanged call)", line: 228 }
hive_key_prefix: "userBox['profile'] keys units_system, measurement_unit (new); configBox units_metric and userBox body_measurement_sheet_unit become legacy fallbacks; migrationBox units_metric_to_profile_v1_done (new)"
hive_key_formula: "n/a (fixed keys)"
sync_methods: [_syncUserProfile]
restore_methods: [_restoreUserProfile]
cloud_table: user_profile
cloud_columns: [units_system, measurement_unit]
contract_test_path: test/contracts/unit_preference_sync_writer_to_reader_test.dart
ist_handling: ["none: no date logic"]
provider_invalidations: ["Profile Units row: userProfileProvider after the write; the restore tick re-seeds the screen's _isMetric (HiveTabScaffoldMixin.invalidateOnBackgroundRestore)"]
telemetry_op_types:
  success: [units_pref_adopted]
  failure: [units_pref_read_failed, profile_units_write_failed, measurement_unit_write_failed, bg_heal_units_pref_adopter, restoring_units_pref_adopter]
cross_account_guard: "Both writers capture HiveUserSession.currentOwnerFullId first (null -> no write) and pass stillOwner to patchProfileWith (checked inside the lock). The values are per-user profile fields now; the device-wide key is read only until the adopter ran."
forbidden_patterns_checked:
  - { pattern: "a configBox['units_metric'] write anywhere in lib/", absent: true }
  - { pattern: "a raw configBox.get('units_metric') outside UserRepository.getUnitsMetric and UnitsPrefAdopter", absent: true }
  - { pattern: "a profile stub created by a unit write (patchProfile on a missing profile)", absent: true }
  - { pattern: "UnitsPrefAdopter called from _ensureLocalUser (never runs at a persisted-session launch)", absent: true }
  - { pattern: "a build-time re-read of _isMetric on the Profile screen (snap-back)", absent: true }
proposed_fix: |
  Plan docs/plans/oi348-walk-fixes-landing2.md (v4 CONVERGED, Unit B9; founder 2026-11-23: "Both": sync the Profile switch AND the sheet unit, per user).
  1. Migration 185: user_profile.units_system ('metric'|'imperial') and measurement_unit ('cm'|'in'), nullable, CHECK-constrained; applied before any build carrying the push keys ships.
  2. Both settings become profile-map fields written through patchProfileWith(stillOwner:), never creating a stub. One pure rule file, lib/core/utils/unit_prefs_rule.dart, for keys, values and readers.
  3. Push: unitPrefsPushEntries (valid values only; kill switch disable_unit_pref_sync, payload byte-identical when on).
  4. Restore: the existing per-key merge (cloud non-null wins). Conflict rule: the last pushed change wins at every device's next restore.
  5. UnitsPrefAdopter moves the legacy device value into the profile once per device, from BOTH post-restore heal paths (background: before the reckon whose tick bump is last; foreground: _ensureOwnershipBeforeHome), gated on restoreSettledForCurrentUser.
  6. Profile Units row: the switch moves at once and is never re-read in build; a restore tick re-seeds it.
  7. A reader the plan reviews did not list: goal_targets_preview.dart takes `metric` as a parameter only (its caller switch_goal_diff.dart was listed and is fixed); its doc comment and the provider comments that named units_metric are updated.
regression_test_planned: |
  test/contracts/unit_preference_sync_writer_to_reader_test.dart (27): pure rule; setter -> reader both ways; no profile / no owner -> no write; bad value -> metric; throwing read -> metric + event; legacy fallback and profile-wins; non-bool device value; measurement unit order and bad value; two accounts on one device (each its own value; before the adopter the second account sees the device value, after it metric); adopter: copied / only-if-absent / no device key / no profile / not settled / no owner / metric copy; source pins: the settled gate before the write, the helper's own try + caller reason, the bg call before the reckon, the fg call after openForUser, no call from auth_provider and exactly one caller file.
  test/sync/unit_preference_push_restore_test.dart (11): unitPrefsPushEntries both / neither / invalid / switch; the REAL profile push through the stub server (row carries both; absent sends neither; switch on = byte-identical row); the REAL _restoreUserProfile merge (cloud imperial + in -> readers follow; cloud NULL keeps local; a different cloud value wins; the switch does not stop a restore).
  test/profile/profile_units_row_test.dart (1 behavioural, the real ProfileScreen): a restore tick re-seeds the switch; a tap moves it at once and it stays while the write is held behind the profile lock (ProfileWriteService.debugHoldLockUntil), then the profile holds the new value.
  Repointed (never loosened): measurement_prompt_state_behavioral_test, measurement_save_unit_rule_test (the write is now the profile patch, two blocks in), measurement_write_batch_behavioral_test (+ a no-profile case), body_measurements_sheet_test (asserts the stored units_system), measurement_card_end_to_end_test, edit_profile_goal_target_test, edit_profile_target_impact_test.
mutation_proof: |
  Rule 21. scratchpad/mut_b9/all.sh (sed, grep -c of the mutated text, the test, restore by cp + cmp): 14 of 14 KILLED (push entries x2, the switch, the reader value check and its catch, both no-stub guards, adopter only-if-absent / no-profile-no-flag / absent-key-flag / settled gate, the build re-read snap-back, the restore re-seed, the bg call order). Detail in "Mutation results" below.
impact_analysis: |
  The units setting and the sheet's unit follow the user to every device and no longer leak between accounts on one device. Testing accounts only (CLAUDE.md section 1): an imperial device's value reaches the account that first completes a settled restore on it after the upgrade. Old builds (AAB +50) keep reading and writing the device key and never push the new fields; a value the new build pushes reaches an old build only through its own restore merge (which it ignores: it reads the device key). The profile push carries two more keys, only when set.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "unit_prefs_rule.dart, unit_pref_flags.dart, units_pref_adopter.dart, user_repository.dart, body_measurements_provider.dart, sync_profile.dart, profile screen + row, switch_goal_diff.dart, heal_after_restore.dart, restoring_screen.dart; flutter analyze lib/ clean (no warnings)." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "profile keys units_system / measurement_unit; legacy keys read as fallbacks; adopter flag in migrationBox (contract test)." }
  - { tier: 3, name: "Postgres schema", status: fixed_in_this_batch, evidence: "migration 185 adds two nullable CHECK-constrained columns; live had neither (information_schema 2026-11-23)." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "No existing data to migrate (columns new); NULL = never set." }
  - { tier: 5, name: "Migrations applied", status: fixed_in_this_batch, evidence: "185 applied 2026-11-24 after the founder go, cloud version 20261124012742; both columns read back from information_schema with their CHECK constraints; backups/applied_migrations.json and backups/live_schema_columns.json in the same commit." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function reads or writes the two columns." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "None." }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "user_profile own-row policies cover new columns (column-agnostic)." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "None." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "None." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "None." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The real profile push through the stub server carries both keys; the real restore merge brings them back (test/sync/unit_preference_push_restore_test.dart). Live end-to-end after the apply." }
recurrence: "Writer/reader drift family (a setting stored where no sync reader looks). Related: b5d2e8 (made the coach preview unit-aware by reading the raw device key, the reader fixed here), c4055a (the account-swap token rule the sheet unit relies on). Not a recurrence of a fixed bug."
related_bugs: [b5d2e8, c4055a]
---

# e9a6c1 - unit-preference-not-synced

## What happened
The Profile Units switch wrote `configBox['units_metric']`, one value per DEVICE, and the measurement sheet remembered its unit in a per-user Hive key. Nothing pushed either value, so another device of the same account showed its own default, and two accounts on one device shared one switch.

## The fix
Both are profile fields (`units_system`, `measurement_unit`), pushed by the profile push and restored by the profile merge. A one-time adopter moves the old device value into the profile after a settled restore. See the frontmatter.

## Mutation results
`scratchpad/mut_b9/all.sh`, 2026-11-23/24: 14 of 14 KILLED, each applied (grep -c >= 1) and restored by cp + cmp.
- U1 / U2: drop the `units_system` / `measurement_unit` push entry -> push test red (3 / 2 lines).
- U3: the switch ignored (`if (false)`) -> push test red.
- U4: reader value check `raw != 'imperial'` -> `raw == 'metric'` -> contract red (the 'feet' row).
- U5: reader catch narrowed to `on UnsupportedError` -> contract red (the throwing read).
- U6 / U7: the "no profile -> no write" guard removed in `setUnitsMetric` / the sheet save -> contract / batch test red.
- U8: adopter "only if absent" removed -> red. U9: no-profile sets the flag -> red. U10: absent device key sets no flag -> red. U14: the settled gate removed -> red.
- U11: the Units row reads `getUnitsMetric()` in build (snap-back) -> widget test red. U12: the restore re-seed removed -> widget test red.
- U13: the background adopter call placed after the reckon -> pin red.

## B-pass fix round (2026-11-24, docs/reviews/oi348-landing2-bpass.md, seat B9)
- F1 (P2): `MeasurementWriteNotifier.save` awaited `patchProfileWith`, which rethrows; the old device-key write never threw. A failed unit write after the measurement was saved escaped the sheet's tap (sheet stays open, a second tap saves the day again) and skipped the refresh. Now caught (`measurement_unit_write_failed`). Test: `measurement_write_batch_behavioral_test.dart` MIRROR (the failure injected into the real patch path through `ProfileWriteService.debugFailNextPatchWith`).
- F2 (P3): no test changed the owner WHILE a unit write waited on the profile lock. Added for all three writers (`setUnitsMetric`, the adopter, the sheet save): the write is refused, neither profile changes, the adopter keeps the key and sets no flag.
- F3 (P3): a restore tick while a tap's write was queued re-read the OLD stored value and flipped the switch back, and nothing re-seeded it after the write. The tick now skips the re-seed while a write is pending; the last pending write's completion re-seeds from the store. Test: `profile_units_row_test.dart` step 3.
- F4 (P3): the adopter treated the sign-up stub `{id, email, created_at}` as a profile and would push a near-empty `user_profile` row. It now needs real data (a goal or a height, the bootstrapper's own cloud test): a stub is `noProfile`, retried later.
- F5 (P3): stated below as a residual.
Mutations, all KILLED (applied, `grep -c` 1, restored by cp + cmp): MF1 the save catch rethrows (1 red); MF2a/b/c each `stillOwner` -> `() => true` (1 red each); MF4 `profileHasRealData` -> `isNotEmpty` (2 red); MF3 the in-flight skip removed (widget test red).

## Residual, stated
- Shared device, B-pass F5: when the FIRST account to finish a settled restore on a device already has `units_system` in its cloud profile, the adopter drops the device key; another account on that device that had set imperial on the old build then reads metric until it sets the switch once. Accepted: the old value was one per DEVICE (the bug itself), every account is a testing account (CLAUDE.md section 1), and keeping the key per account would need a per-account offer the old build never recorded.
- Before the adopter has run on a device (offline launch, failed or unsettled restore), a second account on it reads the device-wide value (the plan's bounded pre-adopter window).
- A toggle made offline and followed by a relaunch before it pushes is reverted by the launch restore (every profile field's posture; accepted in the plan).
- Old builds never push these fields; their device key stays theirs.
