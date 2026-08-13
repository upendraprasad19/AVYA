---
bug_id: 4f2a9e
date: 2026-08-13
batch: supabase-http-fix
status: fixed
blast_radius: feature
symptom: >-
  The merge-commit regression-catalog walk fails with "at least one recent
  regression test FAILED" on tests that are green everywhere else. Observed while
  merging `supabase-http-fix`: 9 failures across
  test/contracts/git_safety_hook_integration_test.dart,
  review_gate_staged_content_not_working_tree_test.dart and
  blast_radius_content_rule_wired_all_scripts_test.dart, including
  `Expected: <0> / Actual: <254>`. The merge is blocked by a gate reporting
  failures that do not exist in the change under review.
concept: git_hook_env_leak
sot_registry_entry: not_applicable
writers:
  - "scripts/check_regression_catalog.dart:56-64 (pre-fix) — `Process.run('flutter',
     ['test', ...dartPaths], runInShell: true)` with NO `environment:` and no
     `includeParentEnvironment: false`. The child therefore inherits the full hook
     environment. This is the WRITER of the child's env."
  - "git itself — it exports GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE into every hook
     process. scripts/pre-commit.sh:341-346 invokes this gate from inside pre-commit,
     which runs on a merge commit, so those three are always set here."
readers:
  - "test/contracts/git_safety_hook_integration_test.dart — builds throwaway git repos
     and asserts subprocess exit codes. GIT_DIR overrides BOTH `workingDirectory:` and
     `-C <path>`, so every git call lands on the REAL repo instead of the fixture."
  - "test/contracts/review_gate_staged_content_not_working_tree_test.dart — same shape;
     it stages fixtures into what it believes is its own index."
  - "test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart — same."
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/scripts/regression_catalog_lib_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >-
  Grepped scripts/ for other `Process.run` / `Process.start` calls that spawn a child
  which itself touches git, without an environment filter. The gate-e2e test family
  already scrubs correctly (test/contracts/gate_e2e_env_hermetic_test.dart enforces it
  across 8 helpers). check_regression_catalog.dart was the outlier — it is the only
  gate that spawns a whole `flutter test` run, and the only one that runs exclusively
  from inside a hook. Stated as known-exposure, NOT a census.
proposed_fix: >-
  Hand the child a filtered environment: `scrubbedChildEnvironment(Platform.environment)`
  removing GIT_*, GITHUB_* and PUSH_BEFORE, with `includeParentEnvironment: false`.
  BOTH are required and that is the subtle half — passing `environment:` ALONE merges
  with the parent, so the scrubbed keys come straight back and the fix does nothing.
  PATH is preserved (the child still has to find `flutter`); the filter is a PREFIX
  match so an unrelated `MY_GIT_TOKEN` survives. GITHUB_*/PUSH_BEFORE are included to
  match the hermetic contract the gate-e2e family already shares — one affected file
  reads GITHUB_EVENT_PATH (diagnose c3f8e1).
regression_test_planned: >-
  test/scripts/regression_catalog_lib_test.dart — 5 pure tests over
  `scrubbedChildEnvironment` (removes the three git vars; removes GITHUB_*/PUSH_BEFORE;
  case-insensitive prefix; keeps unrelated vars INCLUDING ones merely containing "git";
  does not mutate the caller's map) plus 1 structural test pinning that the gate passes
  the scrub AND sets includeParentEnvironment: false.
  The structural one is LABELLED as structural: driving the gate end-to-end means
  standing up a throwaway Flutter project with its own docs/diagnoses/INDEX.md and
  running a real `flutter test` inside it — minutes per assertion. House pattern for
  I/O that cannot be driven cheaply: mutation-prove the pure decision, pin the wrapper
  structurally, and state the limit instead of implying coverage
  (feedback_mistake_guard_without_its_mirror).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "13/13 green in test/scripts/regression_catalog_lib_test.dart (7 pre-existing + 6 new). No lib/ surface touched — this is build tooling." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "A/B ISOLATION, run three ways. (1) Inside the hook during the merge: 9 failures. (2) The SAME three files standalone against the SAME mid-merge repo: 38/38 PASS. (3) Re-running git_safety_hook_integration_test.dart with GIT_DIR + GIT_INDEX_FILE exported reproduces the failures (6 pass / 3 fail). The variable is the environment, not the code under test. MUTATION-PROVEN 3 ways: dropping the GIT_ prefix clause reddens 3 tests; dropping includeParentEnvironment: false reddens 1; dropping the environment: argument reddens 1." }
impact_analysis: >-
  The gate manufactured FALSE FAILURES on every conflicted merge, and only on
  conflicted merges — a clean `--no-ff` merge never runs pre-commit, so the walk never
  fired. That is why it went unnoticed: it is invisible until a merge conflicts, and
  then it blocks the merge citing tests that are green.
  Severity is bounded — it produced false RED, never false green, so nothing shipped
  behind it. But it trains exactly the wrong reflex: the failures are unrelated to the
  change, the tests pass when you run them by hand, and the obvious next move is
  `--no-verify`, which CLAUDE.md rule 20 and feedback_mistake_no_verify_reflex ban. A
  gate that cries wolf on every conflicted merge is a gate that gets bypassed.
  Not established: whether any past merge was pushed through with --no-verify because
  of this. `docs/skipped-discipline.md` records no such waiver.
related_bugs:
  - "feedback_mistake_git_hook_env_leak — the same class, previously seen in TEST code
     (a test spawning its own repo inside pre-commit). This is the first instance in a
     GATE: the leak is one level up, in what the gate hands its child."
  - "diagnose c3f8e1 — GITHUB_EVENT_PATH leaking into gate e2e suites; why GITHUB_* is
     scrubbed here too rather than GIT_* alone."
recurrence: >-
  Nth instance of the git-hook env-leak class, and the first where the leaking party is
  a gate rather than a test. The lesson generalises one level: any process spawned from
  inside a git hook inherits GIT_DIR, so the question is not only "does MY code use
  workingDirectory correctly" but "does everything I SPAWN". The existing hermetic
  contract (test/contracts/gate_e2e_env_hermetic_test.dart) covers 8 test helpers by
  name and did not cover the gate that spawns them all.
---

# 4f2a9e — the regression-catalog walk leaks git's hook env into `flutter test`

## What happened

Merging `supabase-http-fix` into `main` hit a conflict (the append-only OI board), so
the merge was completed with `git commit` — which runs the `pre-commit` hook, which on
a merge commit runs `check_regression_catalog.dart`. That gate reported **9 failing
tests**, none of them related to the change being merged.

## Root cause

`check_regression_catalog.dart` spawns `flutter test` with no environment filter. Git
exports `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` into every hook, and those
override both `workingDirectory:` and `-C <path>`. The ~9 tests that build their own
throwaway git repos were therefore operating on the **real repository, mid-merge**.

## Evidence

| Run | Result |
|---|---|
| Inside the hook, during the merge | 9 failures |
| Same 3 files, standalone, same mid-merge repo | **38/38 pass** |
| Same file, standalone, with `GIT_DIR`/`GIT_INDEX_FILE` exported | failures reproduce |

## Fix

Hand the child a scrubbed environment, with `includeParentEnvironment: false` — both
halves are required, because `environment:` alone merges with the parent.

## Why it hid

The walk only runs on merge commits, and only *conflicted* merges run `pre-commit` at
all (a clean `--no-ff` merge does not). So the gate could be wrong for a long time
while firing rarely, and each time it fires it looks like the branch's fault.
