---
bug_id: d0b7e4
date: 2026-11-28
batch: oi348-landing3c
status: fixed
tier: m_fix
blast_radius: platform
symptom: |
  On the founder's Windows machine (India time) the merge of origin/main into oi348-landing3c was blocked twice by the pre-commit regression catalog: two tests in test/contracts/coach_meal_items_card_behavioral_test.dart expected a "Breakfast" log and got "Snacks". The same file passes when run directly. A third failure in the same runs (nutrition_history_writer_to_reader_test.dart, "730 days" frame budget, 723 ms against 400 ms) is a timing assertion, not this bug: it passed in a targeted run with the same TZ and when run alone. Under PR #349 the same pin cost two founder-approved hook skips (memory note reference_windows_tz_env_breaks_dart_local_time.md).
concept: pre_commit_regression_catalog_child_environment
sot_registry_entry: none
writers:
  - { file: scripts/regression_catalog_lib.dart, method_or_widget: "catalogChildEnvironment wrote TZ=Asia/Kolkata on every platform (before this fix)", line: 245 }
  - { file: scripts/contract_sweep.dart, method_or_widget: "_spawnEnv wrote the same literal TZ for the pre-push sweep's flutter test child (before this fix)", line: 29 }
readers:
  - { file: test/contracts/coach_meal_items_card_behavioral_test.dart, method_or_widget: "meal type chosen from the local hour", line: 1 }
hive_key_prefix: none
hive_key_formula: "not applicable: no stored value changes meaning"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/scripts/regression_catalog_lib_test.dart
ist_handling:
  - { file: scripts/regression_catalog_lib.dart, line: 222, fn: applySuiteZone }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "not applicable: no user data."
forbidden_patterns_checked:
  - { pattern: "a second literal TZ rule in scripts/contract_sweep.dart", absent: true }
  - { pattern: "--no-verify as the way round the failing walk", absent: true }
proposed_fix: |
  One shared rule, applySuiteZone in scripts/regression_catalog_lib.dart, used by both spawners. Off Windows it pins TZ=Asia/Kolkata, as before (OI-459: the VPS is UTC). On Windows it removes every spelling of TZ, so the child runs in the machine's own zone. catalogChildEnvironment takes isWindows (default Platform.isWindows) so both branches are tested on every platform.
regression_test_planned: |
  test/scripts/regression_catalog_lib_test.dart: the off-Windows group (now with isWindows false); the new Windows group (no TZ key for any parent or spelling; the scrub still applies; the default follows the machine; Windows only, a real Dart child under the catalog env reads the same offset as a child with no TZ). test/contracts/contract_sweep_wired_test.dart: the sweep takes the shared rule and holds no TZ literal (presence only).
mutation_proof: |
  Rule 21, run on Windows 2026-11-28. Five mutants, each confirmed applied (exactly one match), none a compile error, file restored byte for byte after each. M1 Windows branch pins TZ again (the old bug): 3 red, the real-child test among them. M2 removal case-sensitive: 1 red. M3 default platform "not Windows": 2 red. M4 off-Windows pin lost: 2 red. M5 sweep writes its own literal pin: 1 red. These counts are Windows results; SECOND ROUND below covers the B-pass folds. On Linux the default-platform behaviour test cannot see M3 (a default of false equals the real value there), so a source pin on the default stands in for it. SECOND ROUND (B-pass folds, four mutants, same method): N1 sweep back to the old literal pin, N2 a double-quoted pin added after the shared call, N3 no zone rule in the sweep: 2 red each (the source pin and the behaviour test through the real spawn). N4 default platform false: 3 red (the source pin among them).
impact_analysis: |
  scripts/ and test/ only. No lib/ change, no writer/reader contract, no registry range moves. Linux (VPS and CI): unchanged, the pin still applies. Windows: the merge-commit walk and the pre-push sweep now run in the machine's zone, as a plain flutter test does there. A Windows machine that is not on India time gets no pin; date-boundary tests can fail there, and CI stays the full-suite judge. The real-child test is Windows only, so CI on Linux does not run it; the pure Windows-branch tests do run there, and the default-platform wiring is held there only by a source pin. contract_sweep_e2e_test.dart checks the TZ the sweep's real spawn hands flutter on both platforms. On a Windows machine set to UTC the real-child test cannot tell the two behaviours apart.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "No lib/ file changed; the fix is in the git-hook tooling. Measured on Windows 11 (India time) with a Dart parent spawning a Dart child: no TZ gave offset 330 min; TZ=Asia/Kolkata gave 0 min; TZ=UTC gave 0 min; TZ=IST-5:30 gave 330 min. The zone name read India Standard Time in all four." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive contract changed." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Not involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No client/server contract touched." }
recurrence: "Recurrence, two pins. The sweep's dates from OI-220 (commit 029afa62, 2026-09-19) and was diagnosed on 2026-09-29 as OI-268 (open until this fix; the same class is cited by d4e7c2). The catalog's came with the fix for c44dfc (OI-459, 2026-11-04), which stated the pin had no effect on the Windows clone because Dart ignores TZ there; that was never measured and is wrong, and OI-268 already said so."
related_bugs: [c44dfc, d4e7c2]
---

# d0b7e4 - the pinned zone read as UTC on Windows

## What happened

The pre-commit hook walks the recent regression tests on a merge commit. It started `flutter test` with
`TZ=Asia/Kolkata`. On Windows, Dart's C runtime cannot read that name and used a zero offset, so the tests ran in
UTC on a machine that is on India time. Two tests that pick a meal type from the local hour then failed on a tree
where they pass when run directly.

A Git Bash check did not reproduce it: Git's `sh` drops a `TZ` value that contains a slash before a native Windows
program starts. The failure reproduced from PowerShell and from the gate itself, which sets the variable from inside
Dart.

The same bug had already been filed for the pre-push sweep as OI-268 (2026-09-29, measured on this machine). The
bug-history lookup for this fix first searched the board for the regression catalog only and missed it; the B-pass
found it.

## The fix

One rule for both places that start such a test run: pin India time off Windows, set no zone on Windows.

## End-to-end check

`dart run scripts/check_regression_catalog.dart` from PowerShell with `TZ=Asia/Kolkata` set in the parent, on the fix
(2026-11-28): 2009 passed, 4 skipped, 2 failed. The coach meal-card tests passed. The two failures were not this
bug: `dart_run_retry_test.dart` (setUpAll) needs `chmod`, which a PowerShell parent does not have on PATH (through
Git's `sh.exe` the file runs and skips its POSIX-only tests), and the 730-day frame-budget test (530 ms against 400).

## Not covered

- `scripts/pre-push.sh` and `scripts/run_full_suite.sh` also write `TZ=Asia/Kolkata`, from the shell. On this
  machine that value never arrives: measured 2026-11-28, from Git's `sh.exe` a native `cmd` child reports TZ not
  defined for `Asia/Kolkata` and for `a/b`, while `UTC` and `IST-5:30` do arrive. So those two scripts run in the
  machine's zone on Windows, which is what this fix does on purpose. Both are unchanged. (The `UTC` result says
  nothing about a value with a slash.)
- The 730-day speed test fails when the machine is loaded (723 ms against 400 ms in one blocked walk). It is not
  part of this fix; it is changed separately in diagnose 5e91a7.

## Added after PR #360's CI (head cd0711da)

The first version of this fix failed `test/contracts/spawn_sites_guard_test.dart` (rule G2) in unit shard 3: it
added a second whole-environment read to `contract_sweep_e2e_test.dart` and a first one to
`regression_catalog_lib_test.dart`. The five files first run locally for the fix did not include that guard, and
the guard and its allow-list are unchanged. Now the sweep test reads the environment in one place (`_parentWith`)
and the catalog test builds both environments through `hermeticEnvironment`. Run on Windows 2026-11-28: the
guard, those two files, `spawn_env_manifest_test.dart` and `spawn_helper_test.dart`: 122 passed, 1 skipped (POSIX
only). With `applySuiteZone`'s Windows branch disabled (grep count 1) the two rewritten files had 4 failures,
including both rewritten tests; the file was restored byte for byte (cmp).
