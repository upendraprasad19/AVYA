---
bug_id: a6c3e9
date: 2026-10-21
batch: build-pin-and-test-closeout
status: fixed
blast_radius: account
related_bugs: []
recurrence: >
  First recorded instance of the class "a floating version selector in a third-party dependency
  tree (a plugin's `+`, a POM's LATEST)". Recorded as debugging bug class 2.112.
symptom: >
  main CI run 39618403587 (merge of PR #140, 37c7498e) failed Build Check (APK) at
  `:razorpay_flutter:compileDebugJavaWithJavac`: "Could not find any matches for
  com.razorpay:checkout:1.6.+ as no versions of com.razorpay:checkout are available". A re-run of
  the same commit passed. That merge changed no android/ or pubspec file, and the same job had
  passed on the PR head minutes earlier.
concept: >
  The Razorpay Android SDK reaches the app through two floating selectors we do not own.
  (1) razorpay_flutter 1.4.5 (pubspec.lock:1266, pubspec.yaml:43 `^1.4.5`) declares
  `api 'com.razorpay:checkout:1.6.+'` in its own android/build.gradle (line 37 in the pub cache;
  1.4.1 and 1.4.7 are identical). (2) checkout-1.6.41.pom declares
  `com.razorpay:standard-core` at `<version>LATEST</version>`, which Gradle treats as
  latest.integration. Each floating selector makes Gradle fetch that module's version listing
  (maven-metadata.xml) on every resolution; when a listing comes back empty, the build fails. The
  second selector also floats the SHIPPED SDK. standard-core 1.7.20 (with core 1.0.20) was
  published 2026-10-14, and every build since then resolved it. Every built AAB (+46 on
  2026-09-23, +47 on 2026-09-24, +48 on 2026-10-01, per backups/built_versioncodes.json) predates
  it and used 1.7.19 / 1.0.19: the local Gradle cache directories for those two versions date
  from 2026-09-23 10:58 IST, minutes before +46 was built (05:38Z).
sot_registry_entry: not_applicable
sot_registry_note: >
  Build configuration. No writer/reader pair of app data, no Hive key, no cloud column.
writers:
  - { file: pubspec.lock, method_or_widget: "razorpay_flutter 1.4.5 -- its android/build.gradle (pub cache, line 37) declares checkout 1.6.+", line: 1266 }
  - { file: android/build.gradle.kts, method_or_widget: "pinnedAndroidDependencies -- the fix: checkout 1.6.41, standard-core 1.7.19", line: 26 }
readers:
  - { file: android/build.gradle.kts, method_or_widget: "subprojects configurations.configureEach resolutionStrategy.eachDependency useVersion -- applied to every subproject, including :razorpay_flutter", line: 35 }
hive_key_prefix: null
hive_key_formula: "not_applicable -- no Hive involvement."
sync_methods: not_applicable — build configuration.
restore_methods: not_applicable — build configuration.
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/android_dynamic_dependency_pin_test.dart
ist_handling:
  - { file: android/build.gradle.kts, line: 26, fn: "not_applicable -- dependency versions, no dates." }
provider_invalidations: none — no client state.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  not_applicable — the payment SDK bytes for checkout are unchanged (1.6.41 before and after);
  standard-core goes back from the floating 1.7.20 to the 1.7.19 every built AAB used.
forbidden_patterns_checked: >
  - `useVersion` in `eachDependency` rewrites the selector before resolution, so no listing is
    fetched. `force(...)` was not used; the zero-listing measurement below is the deciding proof.
  - Not fixed by bumping the plugin: razorpay_flutter 1.4.7 declares the same `1.6.+`.
  - core needs no pin: standard-core-1.7.19.pom declares core at the static 1.0.19.
  - Release build: android/app/proguard-rules.pro has no Razorpay rules, and checkout's bytes are
    unchanged, so R8 output for checkout is unaffected.
  - Whole-app scope, measured: `./gradlew :app:dependencies --configuration prodDebugRuntimeClasspath
    --refresh-dependencies --debug` after the fix. The only dynamic selectors left are RANGES WITH
    A PREFERRED VERSION (`{require [a, b]; prefer x}`), e.g. androidx.work:work-runtime
    [2.1.0, 2.8.99] prefer 2.8.1, firebase-messaging [23.0.8, 24.0.99] prefer 24.0.0 -> 25.0.2,
    androidx browser, cardview and test libraries. They still fetch listings from Google Maven, but
    the result is decided by `prefer` or by a higher version another locked dependency requires, so
    the shipped bytes do not float with a new upstream release. They are deliberately NOT pinned: a
    pin would override a legitimately higher version a future plugin requires, a silent runtime
    break worse than a listing-fetch failure. Only the truly floating `+` and LATEST selectors are
    pinned.
proposed_fix: >
  android/build.gradle.kts: a `pinnedAndroidDependencies` map (checkout 1.6.41, standard-core
  1.7.19) applied via `subprojects { configurations.configureEach { resolutionStrategy.eachDependency
  { ... useVersion(it); because(...) } } }`, declared above the existing
  `evaluationDependsOn(":app")`. Bumping either is a deliberate change with a device payment test;
  the contract test makes a plugin bump fail with the re-audit recipe.
regression_test_planned:
  - test/contracts/android_dynamic_dependency_pin_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "android/build.gradle.kts pin; Gradle before/after with --refresh-dependencies --debug: razorpay maven-metadata.xml references 79 -> 0, standard-core 1.7.20 -> 1.7.19, core 1.0.20 -> 1.0.19, checkout 1.6.41 both." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive change." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "None." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "None." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "None." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "None." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "None." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "None." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No key material; RAZORPAY_KEY_ID handling unchanged." }
  - { tier: 11, name: external_services, status: verified, evidence: "Maven Central metadata read 2026-10-21: checkout latest 1.6.41 (2024-08-12); standard-core latest 1.7.20 (2026-10-14); 1.7.19 and core 1.0.19 POMs served (HTTP 200)." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "The checkout flow and its server contract are unchanged." }
impact_analysis: >
  Build reliability: removes the two listing fetches that can fail a build when Maven returns an
  empty listing (CI Build Check, /build-apk, local). Shipped-bytes determinism: since 2026-10-14 an
  AAB built without this pin would have carried standard-core 1.7.20 / core 1.0.20, a payment SDK
  no build had been tested with. The pin returns to 1.7.19 / 1.0.19, which shipped in +46..+48.
  CI note: changing android/build.gradle.kts changes the setup-java gradle cache key
  (.github/workflows/test.yml), so the first CI run after the merge downloads cold. A network
  flake there is not this fix failing.
mutation_evidence: >
  Each mutation was confirmed applied by diff before the run, then restored from a file backup.
  (1) Removed the checkout entry from the pin map: "each floating coordinate is pinned to an exact
  version" red. (2) Pinned checkout to "1.6.+": the same test red. (3) Commented out `useVersion(it)`:
  "the pin map is applied to every subproject before resolution" red. (4) pubspec.lock
  razorpay_flutter 1.4.5 -> 1.4.7: "razorpay_flutter is still the audited version" red, with the
  re-audit recipe in the message. Restored: 3/3 green. Behavioural proof, outside flutter test:
  `./gradlew :razorpay_flutter:dependencies --configuration debugCompileClasspath
  --refresh-dependencies --debug`. Before the fix the log references
  com/razorpay/checkout/maven-metadata.xml 35 times and com/razorpay/standard-core/maven-metadata.xml
  44 times; after, 0 for any com/razorpay module.
---

# a6c3e9 — the Razorpay Android SDK floated on two dynamic versions

## What happened
`main` CI failed to build the APK because Gradle could not list `com.razorpay:checkout` versions,
which it needs to do because the plugin asks for `1.6.+`. Tracing it further showed a second,
quieter problem: checkout's POM asks for `standard-core` at `LATEST`. Since 2026-10-14 that has
silently meant a payment SDK release that no shipped build has used.

## Fix
Both coordinates are pinned in `android/build.gradle.kts`, to the versions every built AAB used.
Gradle now fetches no Razorpay version listing at all. A contract test keeps the pins exact, and
it fails with a re-audit recipe when `razorpay_flutter` changes.
