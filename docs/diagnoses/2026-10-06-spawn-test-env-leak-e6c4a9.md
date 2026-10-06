---
bug_id: e6c4a9
date: 2026-10-06
batch: spawn-tests-env-and-stderr (PR 1 of 2)
status: fixed
tier: m_fix
blast_radius: feature
symptom: >-
  `test/scripts/contract_sweep_e2e_test.dart` FAILED 5 of its 7 tests (`PathNotFoundException ... argv.txt`,
  `Expected: <1> Actual: <0>`) whenever the pre-push contract sweep selected it, and the sweep selects it on every push that
  changes `docs/sot_registry.yaml` (`scripts/contract_sweep_lib.dart:41-43`), so every registry-touching push printed
  `WARN: flutter test exit 1`. The sweep (`scripts/contract_sweep.dart:31`) runs its own `flutter test` with
  `CONTRACT_SWEEP_NESTED=1`, the test builds every child environment from the parent minus `GIT_*`, `GITHUB_*` and `PUSH_BEFORE`
  only, so the runner UNDER TEST inherited the recursion guard and exited "nested" before spawning its stub flutter. Reproduced
  2026-10-05: `CONTRACT_SWEEP_NESTED=1` exported gives 2 passed / 5 failed; with no `CONTRACT_SWEEP_*` set, 7 of 7. The same
  per-file, hand-copied filter existed in about 35 more spawn tests, and about half of the 126 spawn sites inherit the WHOLE
  parent environment; and about two thirds of the 552 exit-code assertions on those spawns cannot print the child's stderr.
concept: not_applicable — test-fixture and test-support environment hermeticity; no Hive/cloud writer-reader contract and no entry of docs/sot_registry.yaml covers it (grep over the registry finds none, c3f8e1 recorded the same).
sot_registry_entry: not_applicable — no writer/reader pair, Hive key or cloud table is involved.
writers:
  - { file: scripts/contract_sweep.dart, method_or_widget: "main(): the sweep's own `flutter test` spawn sets CONTRACT_SWEEP_NESTED=1 (the recursion guard), and the sweep selects test/scripts/contract_sweep_e2e_test.dart", line: 31 }
  - { file: test/scripts/contract_sweep_e2e_test.dart, method_or_widget: "_env(): the child environment = the parent minus GIT_*, GITHUB_*, PUSH_BEFORE (a hand-copied, narrower list than the canonical scrub)", line: 66 }
readers:
  - { file: scripts/contract_sweep.dart, method_or_widget: "the runner: `CONTRACT_SWEEP_NESTED` makes it exit 0 'nested' (and CONTRACT_SWEEP_SKIP before it)", line: 68 }
  - { file: scripts/regression_catalog_lib.dart, method_or_widget: "scrubbedChildEnvironment: the ONE canonical scrub, which the sweep test did not use", line: 121 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/contracts/spawn_env_manifest_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — no user data.
forbidden_patterns_checked:
  - "adding CONTRACT_SWEEP_NESTED to the sweep test's own filter — rejected: it is the NTH hand-copied list (4f2a9e, c3f8e1, d81f3c, d9e4b1 each added names to one list and the next variable was missed); class 2.53 names the pattern (the Nth fix to one file, each a wider guess at the same heuristic)."
  - "an ALLOW-list (child sees only PATH, HOME ...) — rejected: the founder also runs these tests on Windows (SystemRoot, PATHEXT, COMSPEC, the Flutter/Dart cache variables) and this VPS cannot verify that, so an allow-list would trade a known gap for an unverifiable break at 126 sites."
  - "`SUPABASE_` as a prefix — rejected (class 2.56's rule: never widen an exact name to a prefix; Supabase owns that namespace). Six exact names are stripped instead."
  - "a hand-picked 'env_readers' lookup as the completeness check — rejected twice in plan review: a lookup is not a census. The check is a DERIVED two-way scan with floors and anchors."
  - "stripping `DART_BIN_OVERRIDE` in the canonical scrub — rejected: the merge walk's `flutter test` child contains tests that read it from their own process environment to find dart (12 files); the HELPER removes it from spawned children instead (two-level rule)."
  - "a baseline or ratchet list for the other 50 files — rejected: PR 2 migrates them and the strict guards arrive hard from their first commit."
proposed_fix: >-
  (1) `scripts/regression_catalog_lib.dart`: the canonical scrub is extended from three families to EVERY environment variable the
  repo's scripts read as a control switch, escape hatch, secret or build input (8 prefix families, 13 exact names, 1 external
  reader), exported as constants plus one predicate `isChildControlVariable` that the helper's guard shares. (2)
  `test/helpers/spawn.dart`: the one way a test spawns a child. `hermeticEnvironment` (scrub, then the helper's default removal of
  `DART_BIN_OVERRIDE`, then `remove`, then `extra` last; a control variable in `extra` throws unless declared in
  `allowControl`), `runSpawn` / `runSpawnAsync` (always `includeParentEnvironment: false`, spawn, THEN report, then return),
  `startSpawn` + `reportSpawn` for the `Process.start` sites, `spawnDiag`, `defaultSpawnReport` (printOnFailure inside a test, a
  print only for a FAILED child outside one), `dartBin`. (3) `test/helpers/spawn_env_scan.dart` + `test/contracts/
  spawn_env_manifest_test.dart`: completeness is DERIVED (seven scan arms), classified by hand, checked two-way (found ⊆
  classified, classified ⊆ found, the STRIPPED set equals what the scrub removes), with floors, per-arm anchors, allow-lists for
  what a scan cannot resolve, and the recursion-guard pin. (4) The two incident files are migrated: `contract_sweep_e2e_test.dart`
  (with the poisoned-parent regression through the helper's parent seam) and `sot_registry_citations_test.dart` (its `gateDiag` /
  `report` wiring becomes the shared one); `gate_e2e_env_hermetic_test.dart` is repointed. (5) OI-311 files the unexplained
  exit-254 flake on the board. The other 50 spawn test files and the strict site guards are PR 2 (its own plan and reviews).
regression_test_planned:
  - "test/scripts/contract_sweep_e2e_test.dart: 7 tests + the poisoned-parent regression + a seam pin = 9; run with `CONTRACT_SWEEP_NESTED=1` exported: 9 passed (it was 2 passed / 5 failed). test/contracts/spawn_helper_test.dart (27 tests), test/contracts/spawn_env_manifest_test.dart (30 tests), test/scripts/regression_catalog_lib_test.dart (20, +3 new groups' worth for the extended scrub), test/contracts/sot_registry_citations_test.dart (31), test/contracts/gate_e2e_env_hermetic_test.dart (13). Full suite after the last edit: `TZ=Asia/Kolkata flutter test --exclude-tags golden`: 7796 passed, 9 skipped, 0 failed."
mutation_proof: >-
  108 first-round mutants over `test/helpers/spawn.dart`, `test/helpers/spawn_env_scan.dart`, the lists and predicate in
  `scripts/regression_catalog_lib.dart`, the manifest test's classification sets and the two migrated test files, each applied to
  a scratch copy of the worktree (copy, mutate, `grep -c` confirms the edit APPLIED, run the targeted test files, restore from the
  saved original, `cmp`). 98 reddened. 2 reported NOT-APPLIED because the match text occurred twice (M16a, S18); they were re-run
  with disambiguating context (M16a2, S18c, S18c2) and reddened. 8 stayed green and each is accounted for: 3 are intended controls
  (M1b, a no-op rewrite of the scrub line; R8-newspawn, an extra test that spawns THROUGH the helper, which must not redden;
  D9, a count floor lowered to 0, which no assertion can catch by construction because a floor is a human-set bound and the
  per-arm anchors and two-way equality still bind below it); 1 is equivalent on this platform (ST4: removing `runInShell: true`
  from a call whose command is a plain executable, behaviour identical on Linux, unverifiable on Windows); and 4 were REAL
  survivors that exposed a missing protection: M-ctlci (the `allowControl` comparison made case-sensitive: no test passed a
  lower-case declaration), D5 (the `EMAIL` external-reader set emptied: no test pinned it), S18b (the shell scan's comment-line
  skip removed) and S7b (the Dart scan's comment mask removed): no synthetic source fed a COMMENTED read to those arms. Each was
  closed by a new test in the same batch, and each mutant was re-run and reddened. The lists were mutated one entry at a time
  (every one of the 8 prefixes, 13 exact names and `EMAIL`, case-insensitivity, widening `SUPABASE_` to a prefix, dropping the
  scrub entirely): every one reddened the helper test AND the manifest's two-way equality. The poisoned-parent regression
  reddens against the old filter on the same injected parent.
impact_analysis: >-
  Test-support code plus one pure function in `scripts/`. The only product-adjacent behaviour change is the merge-commit walk's
  child `flutter test` (`scripts/check_regression_catalog.dart:64`): it now loses the control variables above and keeps
  `DART_BIN_OVERRIDE`; no test reads a stripped name as an input (the only literal process-environment read in `test/` is
  `DART_BIN_OVERRIDE`; `String.fromEnvironment` is compile-time). The walk runs only on a merge commit made through the local
  pre-commit hook and CI excludes it (`test.yml:244`), so a merge made through a GitHub PR never runs it: therefore
  `dart run scripts/check_regression_catalog.dart` was run EXPLICITLY, once with the operator variables exported and once
  without (`Regression catalog: 134 recent Dart tests all green`, exit 0 both times; operator variables exported:
  CONTRACT_SWEEP_NESTED, PRE_PUSH_FULL, ALLOW_MAIN_COMMIT, PRE_COMMIT_FULL, MINT_OI_REMOTE). The claim this fix makes is BOUNDED: every variable the repo's own scripts, `.claude/*.js` helpers
  and tests read from the process environment is classified and the control ones are removed from a spawned test's environment. It
  does NOT claim the child is hermetic: variables an external tool reads (git's `HOME` / `~/.gitconfig`, `XDG_*`) still flow unless
  a scenario removes or pins them (d9e4b1's own fix pins `GIT_CONFIG_GLOBAL`), and the manifest's external-reader list is hand-written
  (`EMAIL`). Not verifiable here: Windows (the helper keeps case-insensitive matching and removes only named variables and
  `DART_BIN_OVERRIDE`; its environment-equality test spawns Dart, not the MSYS `env`).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "no lib/ file changed" }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "no Hive access" }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "none" }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "none" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "no Edge Function changed" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "none" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "none" }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "none" }
  - { tier: 10, name: "Secrets / API keys", status: verified, evidence: "the scrub now also strips the secrets the repo's scripts read from the process environment (SUPABASE_ACCESS_TOKEN, SUPABASE_ACCESS_TOKEN_FITNESS, SUPABASE_SERVICE_ROLE_KEY, USDA_API_KEY) from a spawned test's child, so a developer's real token can no longer reach a fixture that runs a deploy or apply script; no secret is read, written or logged by this change" }
  - { tier: 12, name: "Client -> server contract (here: pre-push sweep -> test file)", status: fixed_in_this_batch, evidence: "the flagged spawn the sweep makes (CONTRACT_SWEEP_NESTED=1) no longer reaches the runner under test: contract_sweep_e2e_test.dart 9/9 with the flag exported (2 passed / 5 failed before); the poisoned-parent test fails against the old filter on the same injected parent (mutant SW3 and the M2 prefix mutants)" }
recurrence: "RECURRENCE of class 2.56 (an inherited environment variable changes a spawned child): 4f2a9e (GIT_* into a nested flutter test), c3f8e1 (GITHUB_EVENT_PATH into a spawned gate), d81f3c (the operator hatches ALLOW_RAW_GIT / FOUNDER_APPROVED_NO_VERIFY; made scrubbedChildEnvironment the ONE canonical scrub), d9e4b1 (an ambient HOME and EMAIL reached a spawned git fixture, so a commit passed locally that CI refused). This is the fifth instance and the first where the leaked variable is the repo's OWN recursion guard set by its OWN tooling onto a child that then selects the test. Each earlier fix added names to one hand-copied list; the structural fix here is a shared helper plus a DERIVED two-way manifest. Also class 2.90 (a spawned-process test asserts only the exit code): the helper's single report choke point answers ledger rows C4, C5 and C7 of docs/audit/sot-gate-test-stderr.closure.yaml for the files migrated here; PR 2 answers them for the rest."
related_bugs:
  - 4f2a9e
  - c3f8e1
  - d81f3c
  - d9e4b1
  - a7f3d1
---

# Spawned tests inherited the repo's own control variables: the sweep's recursion guard switched off the runner it was testing

## What was wrong

The pre-push contract sweep (`scripts/contract_sweep.dart`) runs the contract tests a push touches with a nested `flutter test`,
and sets `CONTRACT_SWEEP_NESTED=1` on that spawn so a test that runs the real pre-push hook cannot recurse. One of the tests it
selects, whenever a push changes `docs/sot_registry.yaml`, is `contract_sweep_e2e_test.dart`, which runs the REAL sweep runner
against a fixture repository. That test built its child environments from the parent minus `GIT_*`, `GITHUB_*` and `PUSH_BEFORE`,
so the runner under test inherited the flag from the sweep that was running it, took its "nested" branch and exited before
spawning the stub `flutter`: 5 of the 7 tests failed, on every registry-touching push, as a warn-only `WARN: flutter test exit 1`.

It was the fifth time one defect has been fixed one variable at a time. The repo already had a "ONE canonical scrub"
(`scrubbedChildEnvironment`, `d81f3c`), and about 35 spawn tests still kept their own narrower copy; about half of the 126 spawn
sites inherited the whole parent environment; and the stderr half (class 2.90) was in the same state, because each of about 552
exit-code assertions hand-writes its own `reason:`.

## Writer and reader

- Writer of the variable: `scripts/contract_sweep.dart:31` (the sweep's own `flutter test` spawn). Writer of the child
  environment: `test/scripts/contract_sweep_e2e_test.dart:66` (`_env()`), narrower than the canonical scrub at
  `scripts/regression_catalog_lib.dart:121`.
- Reader: `scripts/contract_sweep.dart:68` (and `:64` for the kill switch).
- The same writer/reader pair exists for every variable listed in the manifest: each name's reader is cited in the plan (1.5) and
  is derived by the scan on every run.

## The fix

See `proposed_fix` above and `docs/plans/spawn-tests-env-and-stderr.md` (v3, two independent review rounds, 27 findings, none
rejected). The three structural choices:

1. **One helper owns both halves.** The environment and the failure report are produced from ONE place, so an author cannot wire
   one and forget the other, and a future test gets both by routing through `runSpawn`.
2. **Completeness is derived, not remembered.** The manifest test scans every environment read in `scripts/*.dart|*.sh`,
   `.claude/*.js` and `test/**/*.dart` (seven arms), and fails in both directions: a new read must be classified by a human; a stale
   classification must go. The first prototype of the scan missed `ANDROID_DEVICE_ID` (an `echo` line looked like an assignment),
   which a plan-review round found; each hole it found is now an arm with a synthetic mutant. Running the scan on the real tree
   also found a name the plan missed: `USDA_API_KEY` (read in `.claude/build_food_db_v2.js`, a file `git grep` prints only as
   `Binary file .claude/build_food_db_v2.js matches`, with no lines, so the plan's reading of `git grep -n process.env -- .claude/*.js`
   saw only the two Supabase tokens). It is classified STRIPPED (a credential;
   no test spawns that script).
3. **The recursion guard moves from "inherited" to "declared".** Stripping `CONTRACT_SWEEP_NESTED` from a test child is the point
   of the fix, so a test that executes the real pre-push hook, or spawns the sweep runner itself, must declare its own guard
   (`CONTRACT_SWEEP_SKIP` as an environment entry, or `--flutter-bin`). The manifest pins it with a specified detector (a
   mention in a `reason:` string does not count: mutant R6 deleted the real declaration and the pin went red).

## Answers to the plan's implementation checkpoint (section 6 of the plan)

1. **The scan, run as the real test, reports 56 names plus `PWD`, not the plan's 55.** The extra name is `USDA_API_KEY`
   (`.claude/build_food_db_v2.js`; classified STRIPPED). The plan's "only the two Supabase tokens" came from reading
   `git grep -n process.env -- .claude/*.js`, which printed that file only as `Binary file ... matches` (no lines). Every arm's
   synthetic mutant reddens (S1-S6 and the shell/Dart/JS arm mutants of the mutation run above).
2. **The migrated files' child environments differ from before ONLY by the removals.** Measured with the real scrub against
   the old per-file filter (`GIT_*`, `GITHUB_*`, `PUSH_BEFORE`): on this session's environment (41 variables) the two children are
   IDENTICAL (nothing removed by the helper that the old filter kept, nothing kept that it removed); on the same environment plus the
   operator variables (`CONTRACT_SWEEP_NESTED`, `PRE_PUSH_FULL`, `ALLOW_MAIN_COMMIT`, `PRE_COMMIT_FULL`, `MINT_OI_REMOTE`, `EMAIL`
   and a `DART_BIN_OVERRIDE`) the helper removes exactly those seven and nothing else.
3. **`check_regression_catalog.dart` passes with and without the operator variables exported:** 134 recent Dart tests, exit 0, both
   runs (see `impact_analysis`).
4. **Every changed assertion of D5 is at least as strict as before.** `sot_registry_citations_test.dart`: the old
   `reports, hasLength(1)` and `reports.single` become a per-label check (exactly ONE gate report; exactly FOUR fixture-git reports,
   one per command, each under its own label) AND a total (`hasLength(1 + 4)`: nothing else spawns), so a fifth spawn or a missing
   report reddens where the old count of one would have read the wrong report; the content checks (`exit=`, `stdout=`, `endsWith('stderr=')`)
   now read the gate's own report by label. The old source-wiring pin on `runGateOn`'s body (`gateDiag` call after `Process.runSync`)
   is replaced by `runGateOn routes every spawn through the helper, and nothing else spawns` (every spawn in that body is a
   `runSpawn` call and no `Process.` call remains) plus the helper's behavioural tests of the report, because the report now comes
   from one choke point rather than a per-site call.
5. **Source-grep contracts and docs that cite text this PR moved:** `git grep` for `gateDiag`, `Process.runSync` in the migrated files
   and the old per-file filter text found only historical ledger and skill documents, which stay untouched (they describe the
   2026-10-04 state); no live test or gate greps the moved literals.
6. **The full suite after the LAST edit:** `TZ=Asia/Kolkata flutter test --exclude-tags golden` 7796 passed, 9 skipped, 0 failed. The
   serial pre-commit gate loop is run on the final stage (its result is in the commit log, not restated here).

## Prior art checked (§4.1.5)

`docs/diagnoses/INDEX.md` and `bug-classes.md` were grepped for the symptom, the concept and the files: 4f2a9e, c3f8e1, d81f3c and
d9e4b1 are the recurrence (cited in `related_bugs:`); a7f3d1 and the `sot-gate-test-stderr` ledger (class 2.90) are the reporting half;
the exit-254 flake itself is NOT explained here (OI-311).
