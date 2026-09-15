---
bug_id: c9f1d3
date: 2026-07-27
batch: git-safety-merge-blindspot
status: fixed
blast_radius: platform
symptom: >-
  scripts/check_code_review_pass_exists.dart — the gate that decides whether a
  catastrophic-tier diff has an accepted review — was itself feature tier. A
  change to it cleared no review gate at all: no plan-review record, no B-pass,
  no independent round.
concept: blast_radius_registry_coverage
recurrence: >-
  Not a recurrence of a bug class, but a recurrence of a KNOWN-AND-STATED
  intent failing to be carried out. The 2026-07-19 sweep wrote the rule down in
  docs/blast_radius.yaml ("A change to the reviewer must not be exempt from
  review") and then missed the review-acceptance gate itself. Same shape as
  feedback_ist_sweep_gap — an exhaustive-sounding sweep leaving sites behind.
related_bugs: b7e4c2
sot_registry_entry: blast_radius_registry_coverage
writers:
  - { file: docs/blast_radius.yaml, method: paths_rule_check_code_review_pass_exists, line: 97 }
readers:
  - { file: scripts/check_code_review_pass_exists.dart, method_or_widget: parseRules, line: 28 }
  - { file: scripts/check_plan_review_record_exists.dart, method_or_widget: _parseRules, line: 72 }
  - { file: scripts/blast_radius_from_diff.dart, method_or_widget: main, line: 120 }
hive_key_prefix: n/a — repo governance metadata, no app state
hive_key_formula: n/a — repo governance metadata, no app state
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "a tier-engine script resolving to feature via the scripts/** catch-all", absent_after_fix: true }
proposed_fix: >-
  Add an exact-path platform rule for scripts/check_code_review_pass_exists.dart
  ahead of the scripts/** catch-all, and pin all three tier-engine scripts plus
  their shared library with a test that reads the registry rather than a
  hardcoded list, so the two cannot drift apart again.
regression_test_planned:
  - test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "registry rule added; test extended; 13/13 pass; negative control (rule removed) fails exactly the one assertion, exit 1" }
  - { tier: 2_hive, status: not_applicable, evidence: "repo governance metadata, no local state" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no database involvement" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no database involvement" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service" }
  - { tier: 12_client_server_contract, status: verified, evidence: "no runtime contract; classifier output re-verified positionally with controls after a stdin-path anomaly" }
impact_analysis: >-
  No user-facing impact. The exposure is that the one file deciding whether
  catastrophic content has an accepted review could be weakened — including
  silently, by an agent — with no review of its own. Nothing indicates that
  happened; this is a latent hole being closed, and the fix is one registry line
  plus a test. The wider consequence is on trust: docs/blast_radius.yaml states
  the intent in a comment, and a comment cannot enforce anything, which is why
  the fix pins the three tier-engine scripts by reading the registry rather than
  restating the list.
---

# The gate that decides "was this reviewed?" was exempt from review

## What was wrong

`docs/blast_radius.yaml` promotes the discipline-enforcement scripts to
`platform`, with an explicit rationale in the file:

> A change to the reviewer must not be exempt from review.

The sweep promoted `check_plan_review_record_exists.dart` and its library — and
missed `check_code_review_pass_exists.dart`, which is one word away in name and
is the *blocking local gate*. It fell through `scripts/** → feature`.

At feature tier, editing it requires no plan-review record, no B-pass and no
independent review round. `test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart`
had already named it in its own header as **"the most load-bearing one"** — and
still nothing pinned its tier.

## How it surfaced

Honestly: as a by-product of a **wrong** diagnosis of mine, which is why that
diagnosis is recorded rather than quietly dropped.

While merging `cron-secret-auth`, this gate blocked the merge. I concluded it
was "unsatisfiable by construction" — that the required filename derives from
the staged diff, so adding the review file would change the hash and rename the
file being sought — and wrote an exemption that stood the gate down whenever
`MERGE_HEAD` / `CHERRY_PICK_HEAD` / `REVERT_HEAD` existed.

**That premise was false.** `stagedDiffHash()`
(`check_code_review_pass_exists.dart:161`) hashes `git diff --cached`, the
*index*; but the artifact is read at `:236` with `File(...).existsSync()`, the
*working tree*. An unstaged review file satisfies the gate without moving the
hash. There is no circularity. (`git status` on main already showed five
untracked `docs/reviews/*-review.md` files — the answer was sitting in plain
sight.)

Adversarial review then showed the exemption was not merely unnecessary but
harmful: cherry-pick and revert produce **single-parent** commits, and the CI
keystone gate exits at `check_plan_review_record_exists.dart:142-145` when
`HEAD^2` is absent — so `git revert -n <any trivial commit>`, which needs no
conflict at all, would have walked catastrophic content past **both** gates.

The exemption and its test were reverted in full. The registry gap, found while
computing that change's own blast radius, is real and is what this doc closes.
Retained lesson: `memory/feedback_mistake_claimed_gate_unsatisfiable.md`.

## The fix

One rule, placed ahead of the `scripts/**` catch-all (first match wins):

```yaml
- { glob: "scripts/check_code_review_pass_exists.dart", tier: platform }
```

The test reads the registry and resolves each path through the same
first-match-wins order the gates use, rather than asserting a hardcoded list —
a hardcoded list is exactly what drifted the first time. It covers all three
tier-engine scripts and their shared library.

## Verification

| Check | Result |
|---|---|
| Full file | 13/13 pass |
| **Negative control** — registry line removed | exit 1, and *only* the `check_code_review_pass_exists.dart is >= platform` assertion fails |
| Guard against a vacuous pass | a test asserts `scripts/some_unrelated_helper.dart` resolves to `feature`, so an exact rule is provably the only thing saving these three |
| Classifier output | re-verified with positional args plus known-good controls (`pre-commit.sh` → platform, a docs file → feature) after the stdin path returned inconsistent results |

That last row is its own small lesson: a run of this classifier that prints no
tier at all, or the same tier for every input, is not a result. Check a control
before believing it.
