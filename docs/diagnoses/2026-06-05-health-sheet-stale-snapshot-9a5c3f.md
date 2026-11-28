---
bug_id: 9a5c3f
date: 2026-06-05
batch: apk-obs-2026-06-05
status: fixed
blast_radius: feature
symptom: >
  Profile → Health sync: after tapping CONNECT for Health Connect, the sheet
  still showed "Tap to enable / CONNECT" (disconnected). Only after navigating
  away and back did it show "Connected".
concept: biometric_sync_state
sot_registry_entry: biometric_sync_state
writers: >
  lib/features/profile/providers/profile_provider.dart BiometricNotifier.toggleSync
  (requests permissions → syncToHive → writes configBox['health_sync_enabled'] →
  ref.invalidateSelf()) — unchanged behaviour.
readers: >
  lib/features/profile/screens/profile/health_sync_sheet.dart — the bottom sheet
  now wraps BiometricSyncCard in a Consumer that ref.watch(biometricProvider) and
  awaits toggleSync, instead of rendering a captured BiometricData snapshot.
hive_key_prefix: not_applicable (configBox['health_sync_enabled'] flag + healthBox reads)
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable (Health Connect → local healthBox)
cloud_columns: not_applicable
contract_test_path: test/contracts/biometric_sync_state_test.dart
ist_handling: >
  Bonus fix in the same provider — BiometricNotifier.build read today's health
  data with a device-LOCAL todayStr; switched to istDateStr(now) to match
  HealthWriteService's IST date keys.
provider_invalidations:
  - biometricProvider (invalidateSelf inside toggleSync; the sheet now watches it)
telemetry_op_types: not_applicable
cross_account_guard: not_applicable (biometricProvider watches authUserIdTokenProvider already)
forbidden_patterns_checked:
  - "The health sheet rendering a captured BiometricData snapshot instead of ref.watch(biometricProvider) — now wrapped in a Consumer that watches the provider; pinned by test/contracts/biometric_sync_state_test.dart."
proposed_fix: >
  Wrap BiometricSyncCard in a Consumer whose builder does
  ref.watch(biometricProvider), so toggleSync's invalidateSelf() rebuilds the card
  in place. Change the toggle handler to await toggleSync (so a denied permission
  can't flip the UI). Switch the biometric build's todayStr to istDateStr.
regression_test_planned: >
  test/contracts/biometric_sync_state_test.dart (comment-stripped source-grep):
  the sheet uses Consumer + ref.watch(biometricProvider) (not a snapshot), awaits
  toggleSync (the pre-fix unawaited call is gone), toggleSync still calls
  invalidateSelf, and the biometric build keys by istDateStr.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "Consumer wrap + await + IST; flutter analyze clean on health_sync_sheet's library screen.dart + profile_provider.dart; biometric_sync_state_test 5/5 green" }
impact_analysis: >
  Feature blast radius — Health-sync UI reactivity. The root cause is the
  "renders a captured snapshot instead of watching the provider" anti-pattern
  (a new red flag for the debugging skill). Once the sheet watches the provider,
  Riverpod guarantees the in-place rebuild. The IST fix removes an early-morning
  health-date mismatch. Found via the founder's APK image 4.
---

# Health Connect shows "Connect" after connecting (stale snapshot)

## What happened
The Health-sync sheet kept showing "Tap to enable" after a successful connect;
only a remount showed "Connected".

## Root cause
The bottom sheet rendered a CAPTURED `BiometricData` snapshot passed into
`_showHealthSyncSheet(b)` — it did NOT `ref.watch(biometricProvider)`. So
`toggleSync`'s `invalidateSelf()` rebuilt the provider, but the open sheet never
re-read it.

## Fix
Wrap the card in a `Consumer` that `ref.watch(biometricProvider)` + `await`
`toggleSync`. (Bonus: the biometric build now keys today's health data by
`istDateStr`, was device-local.)

## Verification
`flutter analyze` clean; `biometric_sync_state_test.dart` (watch-not-snapshot +
await + invalidateSelf + IST).

## See also
- `lib/features/profile/screens/profile/health_sync_sheet.dart`
- New debugging red flag: "renders a captured snapshot instead of watching the provider".
