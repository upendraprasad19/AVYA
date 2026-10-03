---
bug_id: b2e6c4
date: 2026-07-27
batch: gate-input-family
status: fixed
blast_radius: platform
symptom: >
  The catastrophic-tier review gate was satisfied by an untracked file. It hashed
  the staged diff but checked the working tree for the review, so a
  docs/reviews/<hash>-review.md that was never git-added passed the gate and
  never entered history.
concept: code_review_pass_enforcement
sot_registry_entry: not_applicable
writers: scripts/check_code_review_pass_exists.dart:105 stagedDiffHash (hash), :190-226 (artifact check)
readers: scripts/pre-commit.sh gate loop — this is the one content gate that blocks a local commit
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/contracts/review_gate_staged_content_not_working_tree_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >
  File(path).existsSync() on an artifact whose name derives from the index;
  readAsStringSync() of a review file rather than its staged blob
proposed_fix: >
  Read the review through _stagedFileExists / _stagedFileContent — helpers
  already present in the same file for this exact class — and compute the
  staged-diff hash with docs/reviews excluded so staging the review cannot
  rename the file it satisfies.
regression_test_planned: >
  Three cases appended to the existing staged-vs-working-tree contract test:
  untracked review fails, staged review passes without renaming, staged review
  with a non-accepted verdict still fails.
touched_layers_checked:
  - { tier: 1_client_code, status: not_applicable, evidence: "no lib/ change — pre-commit enforcement tooling only" }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive surface" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema change" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no data touched" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no SQL migration; the test fixture writes a throwaway migration inside an isolated temp repo only" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function changed" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "local pre-commit gate only; no external service" }
  - { tier: 12_client_server_contract, status: fixed_in_this_batch, evidence: "three e2e cases in isolated git repos with scrubbed GIT_* env exercise the real gate against a staged SECURITY DEFINER migration — untracked review FAILS, staged review PASSES, staged-but-rejected review FAILS; the middle case is the proof the hash no longer moves when the review is staged" }
impact_analysis: >
  This is the only gate that blocks a local commit on review acceptance at
  catastrophic tier. Three untracked docs/reviews/*-review.md files were sitting
  in the working tree when the asymmetry was found, so the loophole was
  reachable in exactly the state the repo was already in. Fix can only add
  failures; the accompanying hash change means historical review filenames no
  longer match, which is harmless because the gate only evaluates the commit in
  progress.
---

# A review file could satisfy the gate without ever entering history

## What was wrong

`scripts/check_code_review_pass_exists.dart` blocks a catastrophic-tier commit
unless `docs/reviews/<staged-diff-hash>-review.md` exists with
`verdict: accepted`. Two halves of that sentence read from different places:

- the hash came from `git diff --cached` — the **index**
- the file was checked with `File(...).existsSync()` — the **working tree**

So an untracked review file satisfied the gate. And because it was untracked it
contributed nothing to the staged diff, the hash it was named after never moved,
and nothing about the commit recorded that a review had happened. Three untracked
`docs/reviews/*-review.md` files were present in the working tree when this was
found.

## The part worth keeping

The file already knew this lesson. `_stagedFileExists` / `_stagedFileContent`
sit at lines 84-93 with a comment describing precisely this class — written when
round-2 review found that `contentForcesCatastrophic` was reading the working
tree. The fix was applied to the SECURITY DEFINER content check and **not** to
the review artifact the gate is actually gating on.

The same defect, in the same file, one level up, surviving the fix for its own
sibling. That is the general shape to watch: fixing an instance is not fixing the
class, and the second instance is usually in the code that was open on screen.

## Why the hash had to change too

Reading the staged blob is not enough on its own — it creates a circle. Staging
the review changes the staged diff, which changes the hash, which renames the
file the gate is looking for. So the hash is now computed over
`git diff --cached -- . ':(exclude)docs/reviews'`.

The test named *"a STAGED accepted review satisfies it, and staging does not
rename it"* is the one that proves the circle is actually broken; without the
exclusion it would fail with the gate demanding a differently-named file.

## Cost

Historical review filenames no longer match the new hash. That is harmless: the
gate only ever evaluates the commit in progress, and past commits are not
re-gated. Recorded here so nobody later reads a stale filename as a bug.
