---
bug_id: c84e33
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase C (P2 process)
status: shipped
symptom: |
  `scripts/check_apk_size_within_bounds.dart` (Gate 13) silent-skipped
  with exit 0 when the APK artifact was missing. In a clean CI or
  wrong-order pipeline the gate green-checks without actually
  verifying anything.
concept: apk_size_gate_strict_mode
sot_registry_entry: subscription_payment_grace_window
writers:
  - { file: scripts/check_apk_size_within_bounds.dart, method: --release flag parse, line: 32 }
  - { file: scripts/check_apk_size_within_bounds.dart, method: missing-APK FAIL branch, line: 49 }
readers:
  - { file: test/contracts/phase_c_oi_closures_test.dart, method_or_widget: OI-33 group, line: 50 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/phase_c_oi_closures_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a — local build gate"
forbidden_patterns_checked:
  - { pattern: "missing-APK silent-skip in --release mode", absent: true }
proposed_fix: |
  Added `--release` flag. When set, missing APK at the expected path is
  FATAL (exit 1) instead of SKIP. Default behaviour unchanged so dry-run
  / pre-build invocations still work. Documented in the script header.
  `/build-apk` skill should pass `--release` after `flutter build apk`.
regression_test_planned:
  - test/contracts/phase_c_oi_closures_test.dart
---

# Bug c84e33 — APK size gate silent-skipped on missing artifact

closes-oi: OI-33

Gate-strictness lens (L24, new). Two-line fix: parse `--release` flag + branch into `exit(1)` instead of `exit(0)` when APK missing.
