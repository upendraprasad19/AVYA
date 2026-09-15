---
bug_id: c0e3a5
date: 2026-05-17
batch: open-issues OI-03 (snapshot contract enforcement)
status: fixed
symptom: |
  No live symptom — preventive infrastructure. OI-07 built the snapshot
  contract manifest. OI-03 is the gate that ENFORCES the manifest. F3-1.1
  (`coach_notes` vs `coaching_notes`) was the cross-system reader drift
  class instance that motivated this; that bug class is the recurring
  one across 5+ APK iterations. Without the gate, the next writer-side
  rename can silently break cron-function personalisation again.
concept: snapshot_contract_enforcement
sot_registry_entry: ai_snapshot_building
writers:
  - { file: scripts/check_snapshot_contract.dart, method: main, line: 28 }
readers:
  - { file: test/contracts/snapshot_contract_gate_test.dart, method: gate subprocess test, line: 21 }
hive_key_prefix: ""
hive_key_formula: "snapshot_contract.yaml keys[].key (top-level snapshot JSON field names)"
sync_methods: []
restore_methods: []
cloud_table: user_daily_snapshots
cloud_columns: [snapshot_json]
contract_test_path: test/contracts/snapshot_contract_gate_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "gate runs on source files — no user-scoped state"
forbidden_patterns_checked:
  - { pattern: "snap.<key>", absent_outside_canonical: true }
proposed_fix: |
  New gate script `scripts/check_snapshot_contract.dart` enforces the
  contract documented at `docs/snapshot_contract.yaml`. Two checks:

  (1) Writer-emit verification — every `key` listed in the contract's
      `keys:` array MUST appear as `'<key>':` in `buildAiContext` or
      its helper-returned maps. Catches a writer-side rename that
      silently breaks the contract.

  (2) Reader-read verification — every `readers:` entry citing
      `{fn, file, line}` MUST contain a `snap.<key>` /
      `snapshot.<key>` / `snap['<key>']` read at the cited line ±15
      lines of slack. Catches a reader being removed without a
      corresponding manifest update.

  Contract test `test/contracts/snapshot_contract_gate_test.dart`
  runs the gate as a subprocess and asserts exit 0.

  Tolerant matching:
  - Reader probe accepts `snap`, `snapshot`, `snap_json`, `snapshotJson`
    as root identifier (cron functions use varied aliases).
  - Reader probe accepts dot-access (`snap.foo`) AND bracket-access
    (`snap['foo']`).
  - ±15 line slack window so manifest doesn't require pixel-perfect
    line numbers (refactors will commonly shift readers by 1-3
    lines).

  Deferred (Phase 3, when a real drift surfaces): catch a NEW reader
  added to an Edge Function that references a key NOT in the
  contract. Requires parsing Edge Function source for all snapshot
  field accesses.
regression_test_planned:
  - test/contracts/snapshot_contract_gate_test.dart
---
# Body

## Why this gate matters

The recurring writer/reader drift class has surfaced in 5+ APK
iterations. F3-1.1 (`coach_notes` vs `coaching_notes` on 2026-05-16)
was the most recent instance — client emitted `coaching_notes`, cloud
column was `coach_notes`, no enforcement caught it for weeks. The
manual fix added one upward-sync method; without the gate, the next
field rename will cause the same class of silent break.

This gate plus OI-07's manifest are the structural class-killer for
cross-system snapshot drift.

## Architecture

```
docs/snapshot_contract.yaml
  ├─ writer: {file, method, line}     (single source of truth)
  ├─ keys: [...]                       (every emitted field)
  │   ├─ key: <name>
  │   ├─ type: scalar | list | map
  │   ├─ writer_line: <int>
  │   ├─ readers: [...]                (Edge Functions that read it)
  │   └─ prompt_passthrough: <bool>    (consumed via ai-proxy stringify)
  └─ orphan_readers: [...]             (debt list — fixed in OI-07-FOLLOWUP)

scripts/check_snapshot_contract.dart
  Phase 1: every key in YAML → must appear in writer source
  Phase 2: every reader citation → must read the key within ±15 lines
```

## Verification

```
$ dart run scripts/check_snapshot_contract.dart
check_snapshot_contract: 52 keys checked, 1 reader citations checked.
OK: snapshot contract check passed.
$ flutter test test/contracts/snapshot_contract_gate_test.dart
All tests passed! (4 cases)
```

## Why ±15 line slack

Manifest line numbers drift by 1-3 on any refactor. A zero-slack
gate would require the manifest to be updated on every minor edit
to any of 13+ Edge Functions, generating false-positive noise that
masks real drift signal. ±15 lines is wide enough to absorb routine
refactors and narrow enough to catch real renames.

## Closing

closes-oi: OI-03
