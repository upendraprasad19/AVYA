---
bug_id: e4a7c1
date: 2026-07-26
batch: ci-speed
status: shipped
symptom: |
  Two merges to main in quick succession: the second push cancels the first
  push's still-running workflow. The `plan-review-record` job — the ONLY place
  the §4.12 keystone gate executes — therefore never runs for the first commit,
  even though that commit DID land on main. The gate reports nothing and CI
  shows a cancelled (not failed) run, so a >=account merge with no converged
  plan-review record can reach main entirely un-gated.
concept: ci_concurrency_cancels_keystone_gate
sot_registry_entry: null
writers:
  - { file: .github/workflows/test.yml, method_or_widget: "top-level concurrency.cancel-in-progress", line: 19 }
readers:
  - { file: .github/workflows/test.yml, method_or_widget: "plan-review-record job (the run cancellation kills)", line: 169 }
  - { file: scripts/check_plan_review_record_exists.dart, method_or_widget: "main() — never invoked when the run is cancelled", line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/ci_workflow_concurrency_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "cancel-in-progress applied unconditionally to refs/heads/main", absent: true, after_fix: true, note: "The expression now excludes main by ref. Asserted semantically (not by string match) in ci_workflow_concurrency_test.dart, which evaluates the expression for refs/heads/main and expects false." }
  - { pattern: "PR runs left uncancellable (runner waste from over-correcting)", absent: true, after_fix: true, note: "refs/pull/N/merge is unique per PR, so the != comparison leaves PR cancellation fully intact; pinned by the 'a PR push is still cancelled' case." }
proposed_fix: |
  Change `.github/workflows/test.yml` concurrency from the unconditional

    cancel-in-progress: true

  to a ref-conditional

    cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}

  main pushes are never cancelled, so every merge commit's plan-review-record
  job runs to a conclusion. PR pushes keep cancellation because
  refs/pull/N/merge is already unique per PR, so superseding a stale PR run
  remains safe and free.
regression_test_planned:
  - test/contracts/ci_workflow_concurrency_test.dart (new — behavioral; parses the workflow and EVALUATES the expression for main / PR / feature refs rather than string-matching it)
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "Fix in .github/workflows/test.yml:19 plus a new behavioral contract test that runs in the standard `flutter test test/` suite. 5/5 pass with the fix; revert-and-rerun against the HEAD workflow gives 4 failures / 1 pass, and the single pass is the PR-cancellation case that was already correct under `true` — so the test does not overclaim." }
  - { tier: 2, layer: hive, status: not_applicable, evidence: "No Hive read/write — CI configuration only." }
  - { tier: 3, layer: postgres_schema, status: not_applicable, evidence: "No schema change." }
  - { tier: 6, layer: edge_function, status: not_applicable, evidence: "No Edge Function touched or redeployed." }
  - { tier: 7, layer: cron, status: not_applicable, evidence: "No cron job involved; this is a push-triggered GitHub Actions workflow." }
  - { tier: 11, layer: external_services, status: verified, evidence: "GitHub Actions is the external system. Verified against live run 30168462713 (`gh run view --json jobs`): all 7 jobs share one run, so cancelling that run cancels plan-review-record with it. Expression form confirmed valid in a `concurrency` block against GitHub's documented example `cancel-in-progress: ${{ !contains(github.ref, 'release/') }}`." }
impact_analysis: |
  Strictly widens gate coverage; it cannot cause a missed failure. The change
  only makes FEWER runs get cancelled, so every check that runs today still
  runs, and some that were previously killed now complete. Worst case is a
  small increase in concurrent runners when two merges land within minutes of
  each other — which is the intended trade: a completed keystone-gate run is
  worth more than a saved runner-minute.

  Discovered while measuring CI wall-clock for the ci-speed batch, not from a
  user-visible failure. No evidence was found that a merge has actually slipped
  through un-gated this way; the defect is that nothing would have revealed it
  if one had, because a cancelled run reads as neither pass nor fail.
blast_radius: feature
---

# A cancelled `main` run silently skips the §4.12 keystone gate

## Symptom

`.github/workflows/test.yml` declared:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

Every push to `main` produces the same concurrency group —
`Test & Analyze-refs/heads/main` — because `github.ref` is identical for all of
them. So a second merge cancels the first merge's in-flight run.

That run is the only place `plan-review-record` executes
(`.github/workflows/test.yml:169`, gated
`if: github.event_name == 'push' && github.ref == 'refs/heads/main'`). Cancel
the run and the gate never evaluates the commit — which has already landed.

## Why this is worse than a normal skipped check

A cancelled run concludes `cancelled`, not `failure`. Nothing turns red. The
§4.12 keystone gate is the repo's single structural enforcement point for
plan-quality on a `>=account` merge, and it disarms itself precisely under the
condition it exists to catch: merges landing fast, one after another.

## Root cause

`github.ref` is not unique per commit — it is the branch ref. For PRs it is
`refs/pull/N/merge`, which *is* unique per PR, so cancellation there behaves as
intended. The blanket `true` applied PR-shaped semantics to a branch where the
ref is shared by every push.

## Fix

```yaml
cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}
```

## Regression test

`test/contracts/ci_workflow_concurrency_test.dart` strips YAML comments, reads
the declared value, and **evaluates** it for three refs rather than matching its
text — so an equivalent rewrite still passes and an inverted one fails:

| ref | expected |
|---|---|
| `refs/heads/main` | not cancelled |
| `refs/pull/14/merge` | cancelled |
| `refs/heads/some-feature` | cancelled |

Comment-stripping is load-bearing, not cosmetic: the explanatory comments this
batch added to `test.yml` themselves contain the literal strings
`cancel-in-progress` and `needs:`, so an unstripped grep would false-pass
against a comment (`feedback_source_grep_strip_comments_first`).

The evaluator throws on an expression form it cannot parse rather than
defaulting — a test that quietly passes on syntax it does not understand is the
false confidence this file exists to prevent
(`feedback_source_grep_false_confidence`).
