---
bug_id: 9b1621
date: 2026-10-21
batch: build-pin-and-test-closeout
status: fixed
blast_radius: feature
related_bugs: [2026-09-27-alert-threshold-test-windows-path-separator-d4a7c1.md, 2026-09-30-migration-ledger-057-forward-slash-windows-path-d4e7c2.md]
recurrence: >
  THIRD instance of the class "a test compares a FileSystemEntity.path string to a '/'-literal":
  d4a7c1 (2026-09-27, alert-threshold test) and d4e7c2 (2026-09-30, migration-ledger 057 test).
  The class is invisible to CI by construction, because CI runs on Linux where `.path` uses '/'.
  It surfaces only in a full suite on the founder's Windows machine. The fix applied is the
  known-good one from those instances: normalise with `.replaceAll('\\', '/')`, the idiom already
  used inline across test/contracts (e.g. age_floor_pickers_test.dart:86,
  applied_migrations_parity_test.dart:55).
symptom: >
  The local full suite (`flutter test --exclude-tags golden`, TZ=Asia/Kolkata) on Windows, run
  during the swap-move batch (PR #140), failed three contract tests with Expected/Actual
  differing only by path separator, e.g. Expected ['lib/shared/services/pro_phase_advance.dart:2']
  vs Actual ['lib\\shared\\services\\pro_phase_advance.dart:2']. All three are green in CI on main.
concept: >
  Each test walks a directory with `Directory(...).listSync(recursive: true)` and builds an
  expectation string or an equality check from `f.path`, then compares it to a literal written
  with '/'. On Windows `File.path` is backslash-separated, so (a) an equality skip
  (`f.path == _registryPath`) never matches and the registry file is reported as its own
  offender, and (b) string lists differ only in separators.
sot_registry_entry: not_applicable
sot_registry_note: >
  Test-only defect in three tests' own plumbing. There is no writer/reader pair, Hive key or cloud
  column.
writers:
  - { file: test/contracts/body_measurement_sites_derivation_test.dart, method_or_widget: "LIB-WIDE walk: `path` built from f.path, compared to _registryPath", line: 116 }
  - { file: test/contracts/clean_orphan_media_pro_recheck_test.dart, method_or_widget: "exactly ONE .remove( -- hit string built from f.path", line: 198 }
  - { file: test/contracts/lapse_gap_policy_writer_to_reader_test.dart, method_or_widget: "resetFreezesAfterGap callers -- caller string built from e.path", line: 28 }
readers:
  - { file: test/contracts/body_measurement_sites_derivation_test.dart, method_or_widget: "expect(offenders, isEmpty) vs _registryPath '/'-literal", line: 116 }
  - { file: test/contracts/clean_orphan_media_pro_recheck_test.dart, method_or_widget: "expect(hits, ['$_cleanDir/logic.ts x1'])", line: 200 }
  - { file: test/contracts/lapse_gap_policy_writer_to_reader_test.dart, method_or_widget: "expect(callers, ['lib/shared/services/pro_phase_advance.dart:2'])", line: 30 }
hive_key_prefix: null
hive_key_formula: "not_applicable -- no Hive involvement."
sync_methods: not_applicable — test-only code.
restore_methods: not_applicable — nothing is restored.
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/lapse_gap_policy_writer_to_reader_test.dart
ist_handling:
  - { file: test/contracts/lapse_gap_policy_writer_to_reader_test.dart, line: 28, fn: "not_applicable -- a path separator, no date." }
provider_invalidations: none — no client state.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  not_applicable — only the tests' own path strings change; what each test asserts about lib/ or
  supabase/functions/ is unchanged.
forbidden_patterns_checked: >
  - Copied the neighbour idiom `.path.replaceAll('\\', '/')` rather than inventing a helper (a
    second idiom). The assertion literals were NOT loosened.
  - A gate was considered and dropped by measurement on main 37c7498e. Broad scan,
    `git grep -n -E '\.path\b' 37c7498e -- 'test/*.dart' 'test/**/*.dart' | grep -cE
    "['\"][^'\"]*/[^'\"]*['\"]"`, gives 438 lines, almost all correct (`'${dir.path}/x'` is a
    valid path on Windows). Narrow scan, `git grep -n -E "\.path\.(contains|endsWith|startsWith)\('[^']*/|\.path =="`
    over the same paths, gives 23 lines; it mixes URI `.path` (correct on every OS) with file
    paths, and none of them fails today (the Windows full suite after the fix is 10,124/0).
    Telling "build a path" or "a URI path" from "compare a file path" needs type information a
    line gate does not have. This class therefore has NO automated guard: CI is Linux, so only a
    Windows full suite catches it.
proposed_fix: >
  Normalise each walked path with `.replaceAll(r'\', '/')` before it is compared or reported.
  Shipped in 81c17820 (PR #140); this doc is filed retroactively in batch
  build-pin-and-test-closeout, with a bug-class entry in .claude/skills/debugging/bug-classes.md.
regression_test_planned:
  - test/contracts/body_measurement_sites_derivation_test.dart
  - test/contracts/clean_orphan_media_pro_recheck_test.dart
  - test/contracts/lapse_gap_policy_writer_to_reader_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "Three test files normalised in 81c17820; re-proven on main 37c7498e by mutation (3/3 red with the fix reverted, 30/30 green restored)." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive box." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No rows." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "clean_orphan_media test only READS supabase/functions/clean-orphan-media; no function changed." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "None." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "None." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "None." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "None." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "None." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "None." }
impact_analysis: >
  Product impact zero; CI impact zero (Linux). The local Windows full suite, the only place this
  class shows, reported three false reds, which cost a diagnosis cycle and could mask a real red
  among them.
mutation_evidence: >
  On main 37c7498e: reverted the three normalisations with literal-string perl substitutions,
  confirmed APPLIED via `git diff -U0` (3 lines changed, the exact `.replaceAll` removed in each).
  `flutter test` on the three files: 27 passed, 3 failed — exactly the three tests named in the
  symptom. Restored from file backups; `git diff --stat` empty; 30/30 green.
  Near-miss recorded: the first mutation attempt used sed patterns that did NOT match, so it
  changed nothing and "All tests passed" proved nothing. A `grep -c` that counted 0 remaining
  normalisations looked like confirmation but was the same mismatched pattern. `git diff` before
  the run caught it. Confirm a mutation by the diff, not by a grep written with the same pattern.
---

# 9b1621 — Windows backslash paths in three contract tests (3rd instance of the class)

## What happened
The Windows full suite during PR #140 reported three contract-test failures that CI never shows.
Each test compared `File.path` (backslashes on Windows) with a `/`-literal. They were fixed in
`81c17820` by normalising `\` to `/`. The fix carried no diagnose-doc because it rode in a `feat`
commit. This doc closes that gap.

## Why it recurs
CI is Linux-only, so nothing in the pipeline that gates `main` can see this class. It shows only
on a Windows full-suite run. The debugging skill now carries the tell (see bug-classes.md) so the
next author normalises at write time.
