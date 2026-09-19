---
bug_id: b2e9d3
date: 2026-06-13
batch: e2e-obs-fixes
status: fixed
blast_radius: account
symptom: >
  Web boot console (Obs#2, live web E2E): "[main] Firebase/Crashlytics init
  failed: Null check operator used on a null value". main() ran
  Firebase.initializeApp() + FirebaseCrashlytics.instance.* with NO kIsWeb
  guard. FirebaseCrashlytics has no web platform binding, so a null-check
  inside the plugin threw at boot on web. The try/catch logged it (boot did
  not hard-fail), but the fatal-error routing (FlutterError.onError /
  PlatformDispatcher.onError) was left half-wired and the failure surfaced in
  boot telemetry on every web load.
concept: platform_guarded_native_init
sot_registry_entry: not_applicable
contract_test_path: test/contracts/crashlytics_web_guard_test.dart
writers: >
  lib/main.dart — the Firebase + Crashlytics init block is now wrapped in
  `if (!kIsWeb) { ... }`.
readers: >
  FirebaseCrashlytics (Android/iOS only); the web build has no Crashlytics
  consumer and must not touch the binding.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: "not_applicable"
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - "Unguarded Firebase.initializeApp() + FirebaseCrashlytics.instance.* at boot — now gated behind if (!kIsWeb). Pinned by test/contracts/crashlytics_web_guard_test.dart."
proposed_fix: >
  Wrap the entire Firebase + Crashlytics init in `if (!kIsWeb)`. kIsWeb is
  already imported (flutter/foundation). The Android/iOS init + the
  FlutterError/PlatformDispatcher fatal routing are unchanged; web cleanly
  skips a binding it does not have.
regression_test_planned: >
  test/contracts/crashlytics_web_guard_test.dart — source-grep (comment-
  stripped): main.dart's Firebase.initializeApp + FirebaseCrashlytics init is
  inside an `if (!kIsWeb)` guard.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "main.dart init wrapped in if(!kIsWeb); flutter analyze clean; crashlytics_web_guard_test green" }
impact_analysis: >
  Account/boot blast radius, web-only impact. The crash was caught so it did
  not hard-fail boot, but it left a noisy boot error and meant the web build
  attempted (and failed) a binding it has no business touching — on the exact
  surface the founder is actively testing. Android/iOS Crashlytics is preserved
  exactly. Low severity, clean-boot correctness fix.
---

# Firebase/Crashlytics unguarded init crashes web boot (b2e9d3)

## What happened
`main()` initialised Firebase + Crashlytics unconditionally. Crashlytics has no
web binding, so on web a null-check inside the plugin threw
("Null check operator used on a null value"), logged by the surrounding catch.

## Fix
Wrap the whole block in `if (!kIsWeb)`. Android/iOS path unchanged; web skips it.

## See also
- lib/main.dart (the guarded init)
- test/contracts/crashlytics_web_guard_test.dart
