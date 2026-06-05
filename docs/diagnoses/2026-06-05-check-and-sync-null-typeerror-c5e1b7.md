---
bug_id: c5e1b7
date: 2026-06-05
batch: cloud-sync-fixes
status: fixed
blast_radius: feature
symptom: >
  Recurring "_TypeError: Null check operator used on a null value" on the
  check_and_sync path (op_types check_and_sync / sync_service_if_2) in the live
  telemetry of the founder's account (d7a67a37), firing on app boot.
concept: check_and_sync_null_safety
sot_registry_entry: not_applicable
writers: not_applicable
readers: not_applicable
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: checkAndSync
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/contracts/cloud_sync_fixes_2026_06_05_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: check_and_sync
cross_account_guard: relevant — the race is a cross-user reset nulling the completer
forbidden_patterns_checked:
  - "_healthSyncCompleter!.complete() — the bare null-check operator throws when a concurrent user-switch (_resetForNewUser) nulls the field; replaced with a null-safe local guard. Pinned by cloud_sync_fixes_2026_06_05_test.dart."
proposed_fix: >
  In SyncService.checkAndSync (sync_service.dart:527) replace the bare
  `_healthSyncCompleter!.complete()` with a null-safe guard: read the field into
  a local, check non-null + !isCompleted, then complete — the same pattern
  already used by the cross-user reset path (line ~144).
regression_test_planned: >
  test/contracts/cloud_sync_fixes_2026_06_05_test.dart forbids
  `_healthSyncCompleter!.complete()` and requires the guarded local pattern.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "checkAndSync completes the health completer null-safe; flutter analyze clean" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "live telemetry shows _TypeError on check_and_sync; the guarded path can no longer throw on the cross-user reset race" }
impact_analysis: >
  Feature blast radius — the throw was caught by checkAndSync's outer try and did
  not crash the app, but it aborted the rest of that sync pass (restore / full
  sync / snapshot push), delaying cloud catch-up on boot when a user-switch
  raced. Fix is a localized null-safety change.
---

# _TypeError on check_and_sync (health-sync completer)

## What happened
`SyncService.checkAndSync` threw `_TypeError: Null check operator used on a null
value` on boot (op_type check_and_sync), aborting the rest of the sync pass.

## Root cause
`_healthSyncCompleter = Completer()` is created early in checkAndSync; a
concurrent user-switch (`_resetForNewUser`) nulls it; the later bare
`_healthSyncCompleter!.complete()` then throws.

## Fix
Read the field into a local + guard null / isCompleted before completing — the
same pattern the reset path already uses.

## Verification
`cloud_sync_fixes_2026_06_05_test.dart` forbids the bare `!` + requires the
guard; analyze clean. Confirm on +33 that the _TypeError stops.

## See also
- `lib/core/services/sync_service.dart` `checkAndSync`
