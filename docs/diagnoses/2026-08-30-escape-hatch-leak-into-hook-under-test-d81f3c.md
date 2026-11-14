---
bug_id: d81f3c
date: 2026-08-30
batch: allow-raw-git-scrub
status: fixed
blast_radius: feature
symptom: >-
  `test/contracts/git_safety_hook_integration_test.dart` fails 3 deny assertions
  ("raw git commit is denied", "raw git push is denied", "--no-verify is denied")
  whenever the operator has `ALLOW_RAW_GIT=1` exported in the shell — which is
  exactly the shell state produced by legitimately using the documented escape
  hatch. Observed 2026-08-30 during the `oi150-phase-merge` integration merge:
  the merge-commit regression-catalog walk reported the failures, and the
  obvious reading is "the guard is broken, bypass it with --no-verify". Both
  halves were in fact behaving exactly as designed — the hook was correctly
  honouring a hatch it should never have been handed.
concept: git_hook_env_leak
sot_registry_entry: not_applicable
writers:
  - "scripts/regression_catalog_lib.dart:88-95 (pre-fix) — `scrubbedChildEnvironment`
     removed `GIT_*`, `GITHUB_*` and `PUSH_BEFORE` only. This is the WRITER of the
     `flutter test` child's environment on a merge commit
     (scripts/check_regression_catalog.dart passes it with
     `includeParentEnvironment: false`). Neither hatch was in the removal set, so
     both passed through to every test in the walk."
  - "test/contracts/git_safety_hook_integration_test.dart:82-88 (pre-fix) — its OWN
     `scrubbedEnv()` helper, a SECOND and narrower copy of the same idea: it removed
     `git_dir`, `git_work_tree`, `git_index_file` and nothing else. This is the
     WRITER of the hook subprocess's environment, and it leaked both hatches even
     when the walk above was not involved at all."
  - "the operator — `ALLOW_RAW_GIT=1` / `FOUNDER_APPROVED_NO_VERIFY=1` are set BY
     HAND per CLAUDE.md 4.3, and are most likely to be set immediately before the
     integration merge that runs this gate."
readers:
  - "scripts/git_safety_hook.dart:126-127 — `env['FOUNDER_APPROVED_NO_VERIFY'] == '1'`
     and `env['ALLOW_RAW_GIT'] == '1'`. These are the ONLY two environment reads in
     the hook (verified: `grep -n \"env\\[\" scripts/git_safety_hook.dart` returns
     exactly these plus the `Platform.environment` binding at :111). Each turns a
     DENY into an ALLOW."
  - "test/contracts/git_safety_hook_integration_test.dart — asserts exit code 2
     (deny) for raw commit / raw push / --no-verify. Under the leak the hook exits
     0 and the assertions fail, so the leak INVERTS the test rather than merely
     misdirecting it."
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/scripts/regression_catalog_lib_test.dart, test/contracts/git_safety_hook_integration_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >-
  Confirmed the two hatches are read NOWHERE else in the tree that a scrub would
  need to cover: `grep -rn "ALLOW_RAW_GIT\|FOUNDER_APPROVED_NO_VERIFY" scripts/ test/`
  returns only git_safety_hook.dart (the two live reads), git_safety_lib.dart
  (doc comments), and git_safety_lib_test.dart (pure string-input tests that spawn
  no subprocess — `grep -c 'Process\.run\|Process\.start'` = 0). Of the four files
  that name `git_safety_hook.dart`, only the integration test actually SPAWNS it;
  batch_close_hook_e2e_test.dart and safe_merge_test.dart mention it in comments
  and spawn other things. So the affected spawner set is exactly the two writers
  above, and the other 11 helpers in gate_e2e_env_hermetic_test.dart's `_helpers`
  list do not need the hatch scrub — none of them reaches a consumer of it.
proposed_fix: >-
  Add both hatches to the canonical `scrubbedChildEnvironment`, and COLLAPSE the
  integration test's private `scrubbedEnv()` into a delegation to it, so there is
  one list rather than two that must agree. Matching by exact name (`==`), not
  prefix — unlike `GIT_`/`GITHUB_` these are complete variable names, and
  `startsWith` would silently eat unrelated vars such as `ALLOW_RAW_GIT_LEGACY`.
  Delegation was verified safe before adopting it: the canonical scrub also strips
  `GITHUB_*`, which would change what the test exercises in CI if the hook had a
  CI branch — it has none, per the `env[` enumeration in `readers:` above.
  `runHook` gains an optional `parentEnv` seam because Dart cannot mutate its own
  `Platform.environment`; without it the leak is unreachable from a test and could
  only ever be caught in production again.
regression_test_planned: >-
  test/scripts/regression_catalog_lib_test.dart — three unit cases on the real
  function: both hatches removed, removed case-insensitively, and vars merely
  CONTAINING a hatch name preserved (the mirror of the exact-match choice).
  test/contracts/git_safety_hook_integration_test.dart — two BEHAVIORAL cases that
  spawn the real hook with a synthetic parent env carrying each hatch and assert
  the deny still holds. The fixture reproduces a state the real workflow actually
  produces: it is precisely the shell state of the 2026-08-30 merge.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "27/27 green across test/scripts/regression_catalog_lib_test.dart and test/contracts/git_safety_hook_integration_test.dart (22 pre-existing + 5 new). No lib/ surface touched — build/test tooling only, ships in no APK." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "The contract here is the PreToolUse hook WIRE contract, verified by real subprocess. Two new behavioral tests spawn scripts/git_safety_hook.dart with a synthetic parent env carrying each hatch and assert exit 2 (deny) still holds. MUTATION-PROVEN on both legs: restoring the pre-fix 3-pattern predicate in scrubbedChildEnvironment reddens 5 tests (applied-check: 0 occurrences of ALLOW_RAW_GIT in the predicate region before running); reverting ONLY the delegation while leaving the canonical scrub fixed reddens 2 (applied-check: 0 calls to scrubbedChildEnvironment(parent, 1 const leaky). The second mutation is the load-bearing one — it proves the two seams were independently broken, so fixing only the canonical function would have left the direct-run leak live. Consumer set enumerated rather than assumed: grep -n 'env\\[' scripts/git_safety_hook.dart returns exactly the two hatch reads plus the Platform.environment binding, so no CI branch exists and delegating (which also strips GITHUB_*) changes nothing the test exercises." }
mutation_evidence: >-
  Mutation 1 — restored the pre-fix three-pattern predicate in
  `scrubbedChildEnvironment` (the way a real regression re-enters: the old line
  back in place). Applied-check before running: the predicate region contained 0
  occurrences of `ALLOW_RAW_GIT`. Result: 5 tests RED (3 new unit + both new
  behavioral). Mutation 2 — reverted ONLY the delegation, restoring the
  integration test's private three-name list while leaving the canonical scrub
  fully fixed. Applied-check: 0 calls to `scrubbedChildEnvironment(parent`, 1
  `const leaky`. Result: 2 tests RED. Mutation 2 is the load-bearing one: it
  proves the two sites were independently broken, so the fix as originally scoped
  (canonical function only) would have left the second leak live. Both mutations
  restored from file backups, never `git checkout` — a git restore in a mutation
  chain reverted uncommitted work earlier in this same session.
impact_analysis: >-
  No user-facing impact — this is build/test tooling and ships in no APK. The cost
  is to the operator, and it is the expensive kind: the failure presents as a
  broken safety guard at the exact moment of an integration merge, and its most
  obvious remedy (`--no-verify`) is the one thing CLAUDE.md 4.3 says has no escape
  hatch. On 2026-08-30 it cost one merge cycle; the merge passed with the catalog
  reporting 64 recent tests green once the var was dropped from the parent shell.
  Second-order: because the leak only appears when a hatch is set, the tests are
  green for anyone who has not used one — so the defect is invisible in CI and to
  every clean-shell run, and surfaces only for the operator mid-merge.
related_bugs:
  - "4f2a9e (2026-08-13) — SAME FUNCTION. The fix that CREATED
     `scrubbedChildEnvironment`, for the `GIT_*` leak."
  - "c3f8e1 (2026-07-28) — the `GITHUB_EVENT_PATH` leak that added the `GITHUB_*`
     arm to the same predicate."
recurrence: >-
  Third instance of git_hook_env_leak, and the sharpest, because the previous fix
  is the one that missed it. 4f2a9e's own `readers:` list NAMES
  git_safety_hook_integration_test.dart as an affected consumer: it scrubbed the
  parent env FOR that file and never noticed the file carries its own narrower
  scrub for its own child. The generalisation it stopped one step short of is that
  the environment is not only written by MACHINES. `GIT_*` and `GITHUB_*` are
  enumerable by asking "what does the runner export?"; these two are set by a
  PERSON, which is a different question nobody asked. This is the
  feedback_mistake_guard_without_its_mirror class (instance 20): the guard was
  built for the failure its author had just hit, and the symmetric case — an
  operator-set var reaching a consumer that trusts it — was never enumerated. It
  is also the two-lists-that-must-agree drift class, which is why the fix collapses
  them rather than adding the same two names in two places.
---

# d81f3c — the escape hatch leaks into the hook whose refusals we assert

## One-line

`ALLOW_RAW_GIT=1` in the operator's shell reached `git_safety_hook.dart` through
two separate un-scrubbed seams, turning every DENY assertion in its integration
test into a failure — while both the hook and the test were behaving exactly as
written.

## Why it reads as a code regression

The failure mode is uniquely misleading. A leaked `GIT_DIR` makes a test operate
on the wrong repository, which produces weird, obviously-environmental errors. A
leaked `ALLOW_RAW_GIT` makes the code under test do the *right* thing for the
environment it was handed — it allows a raw commit, because it was told it had
permission. The test then fails on a correct behaviour, and the failure message
says the safety guard did not fire.

The remedy that suggests itself is `--no-verify`, which is the single bypass this
repo grants no hatch for. That is the real cost of this bug: not the merge cycle
it burned, but the direction it points a tired operator at 1am.

## The two seams

Either one alone reproduces the failure, which is why both had to be fixed and
why mutation 2 matters more than mutation 1:

1. **`regression_catalog_lib.dart:88`** — the merge-time route. The catalog walk
   spawns `flutter test`; the child inherited both hatches; one of the tests it
   runs is the integration test.
2. **`git_safety_hook_integration_test.dart:82`** — the direct route, and the
   likelier one. Anyone running `flutter test` in a shell where they have used the
   hatch hits this with the catalog walk nowhere in the picture.

## What was NOT changed, and why

The other 11 helpers registered in `gate_e2e_env_hermetic_test.dart`'s `_helpers`
list keep the three-literal contract unchanged. They spawn `retire_worktree`,
the gate-index builder, `pre-push.sh`, `pre-commit.sh` — none of which reads
either hatch. Adding the scrub there would be cargo-cult: the assertion would be
true and would protect nothing. The scrub belongs where a consumer exists, and
the consumer set is exactly one script.
