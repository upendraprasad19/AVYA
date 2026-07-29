---
bug_id: d7a3f9
date: 2026-07-29
batch: ci-gate-skip-fix
status: fixed
blast_radius: platform
symptom: >
  CI's Audit Gates job failed on 96c6fac2 — the enforcement-infra merge commit
  that had already landed on main — with "Gate failed: check_closes_oi_cited.dart".
  The same commit's local pre-commit hook and full local pre-push `flutter test`
  suite had both passed. check_closes_oi_cited.dart requires a
  <commit-msg-file> argument; CI's "Run all check_*.dart gates" step is a
  second, independently hand-maintained copy of the same
  `for GATE in scripts/check_*.dart` loop + case-skip pattern used in
  scripts/pre-commit.sh, and the enforcement-infra batch had added the
  skip-list entry to only one of the two copies.
concept: gate_fail_closed_discipline
sot_registry_entry: not_applicable
writers: >
  .github/workflows/test.yml "Run all check_*.dart gates" step (the loop that
  bare-invokes every unskipped scripts/check_*.dart file with zero arguments);
  scripts/check_gate_scripts_wired.dart _allowList and its dynamic-wiring
  inference (Gate 33 — the check whose entire job is to catch a gate that
  is not wired into both surfaces)
readers: >
  every push to main (CI enforcement blocks the merge from reading as clean);
  every agent or founder who reads a Gate-33 PASS as "every check_*.dart gate
  is correctly wired everywhere" — it was not
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/contracts/gate_wiring_args_required_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >
  a case-skip list needed by an args-required gate, maintained by hand in two
  independent files with nothing checking they agree; a "wired" classifier
  that infers loop-coverage from ABSENCE-from-a-skip-list rather than
  requiring explicit presence in an allowlist for scripts that crash on bare
  invocation
proposed_fix: >
  Add check_closes_oi_cited.dart to .github/workflows/test.yml's case-skip
  block (stops the crash — mirrors the 12 other entries already skip-listed
  there for analogous "requires special context" reasons). Add it to
  check_gate_scripts_wired.dart's _allowList with a reason (removes it from
  the flawed dynamic-wiring inference entirely, closing Gate 33's blind spot
  for this specific script rather than leaving Gate 33 to keep inferring
  "covered" from its absence).
regression_test_planned: >
  test/contracts/gate_wiring_args_required_test.dart — 3 assertions. Two
  confirmed (by extracting the actual 96c6fac2 git blob before writing this
  doc) to fail against the real pre-fix content of test.yml and
  check_gate_scripts_wired.dart; the third (pre-commit.sh) was already true
  and is pinned against future regression.
touched_layers_checked:
  - { tier: 1_client_code, status: not_applicable, evidence: "no lib/ change — CI/gate tooling only" }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive surface" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema change" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no data touched" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service" }
  - { tier: 12_client_server_contract, status: fixed_in_this_batch, evidence: "Extracted the real 96c6fac2 blobs for test.yml and check_gate_scripts_wired.dart and confirmed zero occurrences of check_closes_oi_cited.dart pre-fix (the genuine negative control, not an assumed one). Extracted the exact `run: |` step from the fixed test.yml and executed it for real (not simulated) against the full scripts/ directory: it now prints `[skip allow-list] check_closes_oi_cited.dart` and continues, matching the 12 other already-working skip-listed gates, instead of crashing. dart run scripts/check_gate_scripts_wired.dart re-run: PASS. bash -n syntax check on the extracted workflow step: OK. 3/3 new contract tests green." }
impact_analysis: >
  CI/gate tooling only; no product code. The fix can only ADD a required skip,
  never remove enforcement. Residual, stated rather than hidden: a FUTURE
  args-required check_*.dart gate still depends on a human remembering to add
  it to _allowList and to both case-skip blocks — that reliance is not new,
  it is the same one every other _allowList entry already carries, and
  eliminating it structurally (e.g. a script tagged with its own
  argument-arity, read by both surfaces from one place) is a separate,
  larger change deliberately not bundled into this P0 fix.
---

# CI's own "is this wired everywhere" gate passed on the commit that broke CI

## What happened

`96c6fac2` — the enforcement-infra merge — passed local pre-commit, passed the
full local pre-push `flutter test` suite, and landed on `main`. CI's Audit
Gates job then failed:

```
Usage: dart run scripts/check_closes_oi_cited.dart <commit-msg-file>
::error::Gate failed: check_closes_oi_cited.dart
```

`check_closes_oi_cited.dart` is a commit-msg gate (added earlier in the same
enforcement-infra batch) that takes the proposed commit message file as a
required argument. `.github/workflows/test.yml`'s "Run all check_*.dart
gates" step bare-invokes every `scripts/check_*.dart` file that is not in its
own inline case-skip block — and that block did not have this entry.

This exact class of bug had already happened once, earlier in the same
batch, on the other surface: `scripts/pre-commit.sh` runs the identical
`for GATE in scripts/check_*.dart` + case-skip pattern, and its skip-list was
missing the entry too, caught locally when a commit attempt failed. The fix
at the time added the entry to `pre-commit.sh`. `.github/workflows/test.yml`
is a **second, separate, hand-maintained copy of the same loop** and was
never touched — the same bug, in the sibling file, still open.

## Why Gate 33 didn't catch it

`scripts/check_gate_scripts_wired.dart` exists specifically to assert every
`check_*.dart` script is wired into both `pre-commit.sh` and `test.yml`. It
reported `PASS: all 91 gate/validator scripts covered` on `96c6fac2` — the
exact commit that broke CI.

Its dynamic-wiring inference is:

```dart
final inWorkflow = workflowContent.contains(script) ||
    (workflowDynamic && !workflowCaseSkips.contains(script));
```

For `check_closes_oi_cited.dart`, `workflowContent.contains(script)` was
false (it wasn't skip-listed) and `workflowCaseSkips.contains(script)` was
also false — so `!workflowCaseSkips.contains(script)` was **true**, and the
script read as wired via the dynamic loop. The absence that broke CI is the
same absence that made Gate 33 call it covered. This is correct logic for a
gate that tolerates bare invocation; it is exactly backwards for one that
requires an argument and crashes without it.

Same shape as `a9f2c6` (this batch's own prior diagnose-doc): a check that
validates only what it can see, and reads an omission as health rather than
as something to classify and possibly fail on.

## The fix

Two edits, not one. Adding the skip-list line to `test.yml` alone stops this
specific crash but leaves Gate 33's inference bug in place — a future
args-required gate skip-listed in only one file would reproduce the exact
failure and Gate 33 would say PASS again. Adding
`check_closes_oi_cited.dart` to `check_gate_scripts_wired.dart`'s `_allowList`
removes it from the flawed inference path entirely, the same mechanism
already used for 14 other scripts that are legitimately not covered by naive
dynamic-loop presence.

Two divergences between the two skip-lists were checked and are NOT this bug:
`check_apk_release_signed.dart` (pre-commit-only) self-skips gracefully in CI
("SKIP — APK not found. Exit 0" — confirmed in the live CI log) rather than
crashing; `check_hooks_installed.dart` (workflow-only) is deliberately
CI-specific per its own `_allowList` reason (CI checkouts never run
`setup-hooks.sh`). Neither reproduces the args-required crash.

## Round-1 review: the fix reproduced its own bug class while shipping

Independent review of the first draft found the new test hand-copied Gate
33's private `_extractCaseSkips` instead of importing it — two
independently-maintained copies of the same parsing logic, the exact shape
this doc names as root cause, now inside the regression test meant to guard
against it. Fixed by extracting the function to a shared library, imported
by both `check_gate_scripts_wired.dart` and the test.

Naming that library `check_gate_scripts_wired_lib.dart` reproduced the bug
**one level deeper, live, during this fix's own development.** Gate 33 scans
every `scripts/check_*.dart` file as a gate the dynamic loops must invoke; a
`check_`-prefixed library with no `main()` matched that glob. Re-running
Gate 33 immediately after adding the file — a habit from writing this exact
fix, not a coincidence — showed its count had silently gone from 91 to 92,
and `dart run scripts/check_gate_scripts_wired_lib.dart` failed with
`Invoked Dart programs must have a 'main' function defined`. Had this
shipped, both `pre-commit.sh` and `test.yml` would have bare-invoked it and
crashed, for a third reason in the same family, introduced by the fix for
the first two.

Renamed to `gate_scripts_wired_lib.dart`, matching the naming already used
by every other pure script library in this repo (`bug_index_lib.dart`,
`worktree_guard_lib.dart`, `git_safety_lib.dart`,
`plan_review_record_lib.dart`) — none carry a gate-triggering prefix. Gate
33's count confirmed back to 91 after the rename.

The method note: verifying a fix against the failure it targets is not the
same as verifying the fix doesn't introduce a new one. Re-running the
relevant gate after *every* edit — not just at the end — is what caught
this before it reached a commit.
