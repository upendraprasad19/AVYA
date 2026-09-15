---
bug_id: b7e4c2
date: 2026-07-27
batch: git-safety-merge-blindspot
status: fixed
blast_radius: platform
symptom: >-
  The two tests guarding the raw-`git commit` block fail whenever a conflicted
  merge is in progress — which is precisely when the pre-commit hook runs the
  full suite. Any integration merge with a conflict is blocked by two failures
  that describe a guard working correctly.
concept: git_safety_hook_contract
recurrence: >-
  Second instance of the ambient-git-state class. The first was
  feedback_mistake_git_hook_env_leak (a test's own temp repo defeated by an
  inherited GIT_DIR); this reaches the same failure by a different route — the
  test names the LIVE repo as the hook's cwd, so the repo's in-progress-merge
  refs decide the assertion. Both fixes are in this commit: the neutral cwd
  closes this route, the env scrub closes the original one.
related_bugs: f0c2d5
sot_registry_entry: git_safety_hook_contract
writers:
  - { file: scripts/git_safety_hook.dart, method: main_merge_exemption, line: 139 }
readers:
  - { file: test/contracts/git_safety_hook_integration_test.dart, method_or_widget: payload, line: 106 }
hive_key_prefix: n/a — developer tooling, no app state
hive_key_formula: n/a — developer tooling, no app state
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/git_safety_hook_integration_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "test asserts a deny path against the live repo's cwd", absent_after_fix: true }
  - { pattern: "spawned git subprocess inherits GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE", absent_after_fix: true }
proposed_fix: >-
  Point every deny-path assertion at a neutral temp directory instead of the
  live repo, scrub GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE from the spawned hook's
  environment so an inherited value cannot override that cwd, and add the
  missing positive test that the merge exemption itself works.
regression_test_planned:
  - test/contracts/git_safety_hook_integration_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "test file corrected; flutter analyze clean; 9/9 pass" }
  - { tier: 2_hive, status: not_applicable, evidence: "developer tooling, no local state" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no database involvement" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no database involvement" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service" }
  - { tier: 12_client_server_contract, status: verified, evidence: "the PreToolUse JSON wire contract is unchanged; only the test's cwd and env change" }
impact_analysis: >-
  No user-facing impact — this is developer tooling. The cost is to process
  integrity, and it is not small. A conflicted integration merge triggers the
  pre-commit full suite, which then reports two failures in the guard that
  blocks raw `git commit`. The guard is in fact working correctly; the test is
  asking the wrong question. The natural response to a red suite during a merge
  is `--no-verify`, which is exactly the reflex CLAUDE.md §4.3 and
  feedback_mistake_no_verify_reflex exist to prevent — so the defect's most
  likely consequence was to erode the discipline it was written to protect. It
  also left the merge exemption itself with no deliberate test: its only
  "coverage" was silently flipping two deny assertions to failures, which reads
  as a broken guard rather than as proof the exemption works.
---

# The raw-commit guard's test was blind exactly when a merge was in progress

## What was wrong

`scripts/git_safety_hook.dart:139` exempts raw `git commit` while
`MERGE_HEAD` / `CHERRY_PICK_HEAD` / `REVERT_HEAD` exists. That exemption is
correct and load-bearing: resolving a merge conflict *requires* a raw
`git commit`, and `safe_commit.sh` cannot stand in for it.

The integration test named the **live repo** as the hook's cwd:

```dart
'cwd': repoRoot,          // repoRoot = Directory.current.path
```

So the assertion `expect(result.exitCode, 2)` was really asking "is a merge in
progress right now?" — a question about ambient repo state, not about the hook.

## How it surfaced

During the `cron-secret-auth` merge on 2026-07-27. The merge conflicted on the
auto-generated `docs/diagnoses/INDEX.md`; resolving a conflict means the commit
goes through `pre-commit`, which runs the **full suite** on a merge commit. Two
tests failed:

```
raw git commit is denied (exit 2)   Expected: <2>  Actual: <0>
multi-line raw git commit is denied (F2 regression, at the wire level)
```

Both correct-by-the-hook, both wrong-by-the-test.

This had never fired before because a **clean** `--no-ff` merge does not run the
local pre-commit hook at all (§4.12.3). Only a *conflicted* merge reaches it.
The test was added 2026-07-19 and this is the first conflicted merge since.

## The second failure route

Fixing the cwd alone would not have been enough. Git exports `GIT_DIR` to its
own hooks, and `GIT_DIR` overrides **both** `workingDirectory:` and
`git -C <path>`. Under `pre-commit`, the hook subprocess inherits it, so
`_gitOk(cwd, ['rev-parse', '--verify', 'MERGE_HEAD'])` would resolve against the
real repo no matter which cwd the payload named.

That is the same class as `feedback_mistake_git_hook_env_leak`, reached from the
other direction — there an inherited `GIT_DIR` defeated a test's own temp repo;
here it would have defeated the neutral cwd. Both are closed here.

## The fix

1. **Neutral cwd.** Deny-path payloads point at a fresh temp directory with no
   merge in progress. `payload()` defaults to it; a test opts into the live repo
   only when it is genuinely about repo state.
2. **Scrubbed environment.** `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` are
   removed from the spawned hook's environment, case-insensitively — Windows env
   keys are case-insensitive but `Map.from(Platform.environment)` yields a
   case-sensitive copy, so a literal `.remove('GIT_DIR')` could miss `Git_Dir`.
3. **The missing positive test.** A new case builds a temp repo, writes
   `MERGE_HEAD`, asserts the simulation took (so it cannot pass vacuously), and
   requires the hook to **allow** the raw commit. The exemption now has
   deliberate coverage instead of being inferred from two failures.

## Verification

The decisive check is the one the old test could not survive: `MERGE_HEAD` was
written into this worktree's git dir, making a merge genuinely in progress, and
the suite re-run.

| Condition | Old test | Fixed test |
|---|---|---|
| No merge in progress | pass | 9/9 pass |
| **Merge in progress** | **2 failures** | **9/9 pass** |

`flutter analyze` on the file: no issues. `MERGE_HEAD` removed afterwards and
absence re-verified.
