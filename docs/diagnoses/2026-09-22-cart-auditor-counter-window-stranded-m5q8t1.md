---
bug_id: m5q8t1
date: 2026-09-22
batch: observation-batch-and-digest-redesign (post-push gate)
status: fixed
blast_radius: feature
symptom: |
  Full-suite pre-push run failed
  `test/features/nutrition/counter_increment_on_analyse_test.dart`: "Test #11
  M1 — counter at API-call site, not save site CartAuditorNotifier.analyseCart
  calls UsageCounterService.increment on success (Test #11 M2)" — Expected
  true, Actual false.
concept: cart_auditor_counter_increment_test_window
sot_registry_entry: not_applicable
writers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "CartAuditorNotifier.analyseCart", line: 1486 }
readers:
  - { file: test/features/nutrition/counter_increment_on_analyse_test.dart, method_or_widget: "'CartAuditorNotifier.analyseCart calls UsageCounterService.increment on success (Test #11 M2)' test", line: 137 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/features/nutrition/counter_increment_on_analyse_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — source-grep test over a local Dart file, no user data.
forbidden_patterns_checked:
  - "a fixed-length source.substring() window used to bound a method body for a source-grep assertion, sized from a stale character count"
proposed_fix: |
  Not a behavioral regression — `CartAuditorNotifier.analyseCart` still
  correctly calls `ref.read(usageCounterServiceProvider).increment(...)` on
  its success path, unchanged in placement or logic. The test itself uses a
  fixed `source.substring(analyseCartIdx, analyseCartIdx + 1000)` window to
  bound the method body before grepping it (unlike its sibling `logMeal`
  check earlier in the same file, which finds the next method definition
  dynamically). This batch's own A5/OI-226 fix (diagnose f7a2c9) added a new
  `throwBeforeAnalyseForTest` test seam and an `unawaited(ErrorTelemetry.
  logEvent(...))` call ahead of the increment call inside `analyseCart`,
  growing the method body enough that the actual `.increment` call — whose
  own token starts at character offset ~993 from the method's start — now
  straddles the fixed 1000-character cutoff, chopping the assertion's
  target text mid-token. Measured: the full method body is ~2253 characters.

  Fixed by widening the window to 2000 characters, matching the value its
  own sibling `scanImageBody` window already uses two tests above in the
  same file, comfortably clearing the current call site with headroom.
regression_test_planned:
  - test/features/nutrition/counter_increment_on_analyse_test.dart
impact_analysis: |
  Test-only change. No production code touched — `analyseCart`'s actual
  behavior (telemetry, test seam, and the counter increment itself) was
  already correct and already shipped in this batch; only the pre-existing
  test's own detection window was too narrow to see it after the method
  grew. Zero risk to the running app.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "flutter test test/features/nutrition/counter_increment_on_analyse_test.dart: 5/5 in the M1 group passed after fix (was 1 failure)." }
mutation_proven:
  mutated: "Reverted the window from analyseCartIdx + 2000 back to analyseCartIdx + 1000, confirmed applied by reading the file."
  result: "Ran flutter test test/features/nutrition/counter_increment_on_analyse_test.dart together with test/features/profile/delete_account_screen_test.dart (both mutated at once): RED — combined count showed exactly -2 failures, one per file, reproducing this exact original failure (Test #11 M2 assertion false). Restored the window to 2000; re-ran both files together: GREEN, 47/47 passed."
  confirmed_applied: "Read the file after the revert and after the restore to confirm the exact substring-window value each time."
---

## Summary

The pre-push full suite failed a pre-existing source-grep test asserting
`CartAuditorNotifier.analyseCart` increments the usage counter on success —
not because the increment was removed, but because this batch's own A5/OI-226
telemetry fix grew the method body past the test's fixed detection window.

## Root cause

`counter_increment_on_analyse_test.dart`'s `analyseCart` check bounds the
method body with a fixed `+ 1000` character offset rather than locating the
next method definition (as its own sibling `logMeal` check in the same file
already does more robustly). This batch's A5/OI-226 fix (diagnose f7a2c9)
added a test seam and a new telemetry call ahead of the pre-existing
`.increment(...)` call, pushing that call's token to straddle the fixed
cutoff. None of the batch's 4 review rounds re-ran this specific pre-existing
test file after that fix landed.

## Fix

Widened the window from 1000 to 2000 characters, matching the sibling
`scanImageBody` check's own established value in the same file. The full
method body measures ~2253 characters; 2000 clears the actual call site
(offset ~993) with comfortable headroom.

## Verification

- `flutter test test/features/nutrition/counter_increment_on_analyse_test.dart`:
  full M1 group green after the fix.
- Mutation proof: reverting the window to 1000 reproduces the original
  failure; restoring to 2000 returns to green.

## Files changed

- Modified: `test/features/nutrition/counter_increment_on_analyse_test.dart`
- Created: this diagnose-doc.
