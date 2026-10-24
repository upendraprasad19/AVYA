---
bug_id: a7f3d1
date: 2026-07-27
batch: gate-input-family
status: fixed
blast_radius: platform
symptom: >
  The merge-to-main keystone gate returned PASS for changes it was built to
  block. A branch could lower its own tier by editing the registry in the same
  commit, and content written while resolving a merge conflict was never
  inspected. (A third face — account-tier code committed straight to main —
  was diagnosed here and SPLIT OUT unfixed; see the scope note below.)
concept: plan_review_record_enforcement
sot_registry_entry: not_applicable
writers: >
  scripts/check_plan_review_record_exists.dart (the gate itself);
  scripts/plan_review_record_lib.dart:173 recordFrontmatter (the only helper this
  batch adds; the OI-58 helpers that briefly lived here are REMOVED — see the
  NOTE at :215-223, and do not look for them at the line numbers an earlier
  draft of this field cited, which no longer exist in a 237-line file);
  .github/workflows/test.yml:191 step, :199 PUSH_BEFORE from github.event.before
readers: >
  .github/workflows/test.yml:191 job `plan-review-record` (the enforcing
  consumer); scripts/git_safety_hook.dart:177 also invokes it advisory-only on
  push-shaped commands — it cannot block, but it DOES run locally, which the
  first draft of this doc missed by calling the CI job "the only consumer"
  (round-2 review P2-D). scripts/pre-commit.sh and the CI gate loop both SKIP
  the script deliberately (it needs fetch-depth 0)
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/scripts/gate_input_family_e2e_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >
  three-dot merge diff (HEAD^1...HEAD^2); registry read from the merged working
  tree; git wrapper returning empty-string on failure so callers cannot tell
  "no output" from "git failed"; content rules reading the working tree rather
  than the commit's own tree
proposed_fix: >
  Walk the pushed range (PUSH_BEFORE..HEAD) instead of assuming HEAD is a merge;
  diff two-dot so merge-resolution content is inspected; evaluate tier as
  max(registry at range base, registry at HEAD); read content rules and the
  record itself at each landing's own rev; fail loud whenever git cannot answer.
regression_test_planned: >
  test/scripts/gate_input_family_e2e_test.dart — 8 controls in isolated git
  repos: 3 for the original findings (OI-71, OI-70 x2) and 5 for the round-1
  review findings. Seven are revert-controls (they fail against the pre-fix
  gate); ONE is labelled DESIGN-LOCK because it also fails pre-fix and instead
  pins a rejected alternative design. Plus 3 controls appended to
  test/contracts/review_gate_staged_content_not_working_tree_test.dart for
  OI-72. (An earlier draft of this field said 16/14/2 — it counted the OI-58
  tests that were removed with the split, and contradicted this doc's own body.)
touched_layers_checked:
  - { tier: 1_client_code, status: not_applicable, evidence: "no lib/ change — this is CI enforcement tooling" }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive surface" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema change" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no data touched" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no SQL migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function changed" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: verified, evidence: "GitHub Actions is the only external surface — the job now passes PUSH_BEFORE from github.event.before; fetch-depth 0 was already set and is unchanged" }
  - { tier: 12_client_server_contract, status: fixed_in_this_batch, evidence: "8 e2e controls here plus 3 for OI-72; replayed four real commits through the rewritten gate in an isolated clone with scrubbed GIT_* env — be3b4baf FAIL, 8c38c855 FAIL, 2c4cbddd PASS, 1b02d00e PASS, all four matching the expected verdict; the full gate suite green (100 tests at B-pass time). NOTE: the four-commit replay is per-commit and was structurally blind to the per-push union defect round-1 review found (P1-1) — recorded because the evidence looked stronger than it was. An independent reviewer also observed one non-reproducible run with 5 spawn-level failures (exit 254, not assertion failures); green on every subsequent run, flagged as a possible parallelism flake rather than claimed clean" }
impact_analysis: >
  Two account-tier auth commits (be3b4baf, 8c38c855) shipped unreviewed through
  this hole; the gate is the repo's single structural enforcement point for
  CLAUDE.md section 4.12, so every batch landed since it was written inherited
  whatever it failed to check. Fix raises tiers and can only add failures, never
  remove them; measured baseline is 3 of the last 60 first-parent commits, of
  which 1 is exempted mechanically.
---

# The keystone gate derived every input from state the author controls

> **SCOPE NOTE.** This diagnose-doc covers the two faces that SHIPPED: the tier
> registry read from the merged tree (OI-70) and the three-dot changed-set diff
> (OI-71), plus the fail-open git wrapper and content-read fixes review surfaced
> alongside them. The single-parent bypass (OI-58a) and the merge-subject
> identity (OI-58b) are diagnosed here too — the analysis is sound and the
> measurements stand — but their *enforcement* was split out unfixed on
> 2026-07-27 after three review rounds each found a new material defect in it
> (CLAUDE.md §4.12.1, founder-approved). They remain OPEN in
> `docs/audit/open_issues.md` under OI-58, which carries the fix shape and both
> failed attempts. Sections below marked SPLIT describe analysis, not shipped code.

## What was wrong

`scripts/check_plan_review_record_exists.dart` is the one gate CLAUDE.md §4.12
leans on: at a merge landing on `main`, a ≥account branch must carry a converged
`docs/plan-reviews/<branch>.md`. Four of its inputs came from the wrong place.

**1. It only ran for merge commits.** *(SPLIT — analysed, not fixed here.)* Line 142 was
`if (!_gitOk(['rev-parse','--verify','--quiet','HEAD^2'])) exit(0)`. Anything
committed straight to `main` has no second parent, so the gate exited before
looking at the diff.

This is not a theoretical bypass — it is the observed default. Of the last 60
first-parent commits on `main`, 5 are single-parent and 3 of those are ≥account:

| Commit | Tier | Files |
|---|---|---|
| `be3b4baf` | account | 11 — `app_router.dart`, `reset_password_screen.dart`, `forgot_password_sheet.dart`, … |
| `8c38c855` | account | 8 — `app_router.dart`, `main.dart`, `splash_screen.dart`, … |
| `2c4cbddd` | platform | 2 — `pubspec.yaml`, `app_constants.dart` |

The first two are account-tier **auth** work that landed with no branch, no
merge, and no plan-review record.

**2. The tier registry came from the merged tree.** `File(_registryPath)` reads
the working copy, which at a merge commit is the post-merge state. A branch that
edits `docs/blast_radius.yaml` to relax a rule *and* changes a file governed by
that rule is judged by the relaxed rule — it exempts itself.

**3. The changed set was a three-dot diff.** `HEAD^1...HEAD^2` means
`merge-base..branch-tip`: the branch's own commits, excluding whatever the merge
commit wrote while resolving conflicts. A platform-tier file introduced during
conflict resolution was invisible.

**4. Branch identity came from the merge subject** *(SPLIT — analysed, not fixed
here)*, free text, with nothing binding a record to the content it vouches for.

## What I checked before believing it

`904e6961` (`ci-speed`) looked like a live instance of #3 — a platform merge with
no record. It is not. Its two-dot and three-dot file lists are identical
(`comm -13` empty). The real explanation is #2 in reverse: at that commit
`docs/blast_radius.yaml` graded `test.yml` only through a BROADER rule,
`.github/** → feature` (line 111) — the narrower
`.github/workflows/test.yml → platform` promotion landed a batch later in
`ci-governance` (`9e3ce5d8`, line 96). So the gate correctly saw `feature`.

(An earlier draft said "no rule covered that path at all, so it fell to
`default_tier`". Round-1B review showed that is false: I had grepped the historical
registry for `workflows` and `scripts/` and never for `.github/**` — the second
incomplete-grep conclusion in this same batch. The tier outcome, and the max()
decision it motivates, are unchanged.)

That mattered for the fix. OI-70 proposed reading the registry as of `HEAD^1`,
which would close the self-exemption hole and *preserve* this one: a branch that
introduces a promotion would be exempt from the promotion it introduces. So the
implementation takes **`max(tier under the range base, tier under HEAD)`**
instead of either single source.

## The fix

- Trigger on the **pushed range** (`PUSH_BEFORE..HEAD`, from
  `github.event.before`), not on `HEAD` being a merge. Falls back to the event
  payload, then `HEAD^1` — which reproduces the old single-merge behaviour, so
  the five pre-existing e2e tests still pass unchanged.
- Every diff is **two-dot**, so merge-resolution content counts.
- Tier is the **max across both registries**.
- **Every git call that cannot answer fails loud** rather than returning an empty
  string that reads as "nothing to see".
- **Content rules and the record itself are read at each landing's own rev**, not
  from the working tree.

*(The single-parent judgement and one-record-one-landing were built here and
removed again — see the scope note.)*

Shipping hard-fail rather than `--warn-only` was deliberate. §4.11 prescribes a
warn-only window, but OI-68 records that `check_skipped_discipline_budget.dart`
has sat `--warn-only` for 38 days against a documented "24h smoke window" — a
warn-only gate with no flip mechanism is the documented decay pattern here. The
baseline was measured first (3 of 60, 1 exempt) precisely so it could ship hard.

## What is NOT closed

**The gate itself is still read from the tree it judges.** `.github/workflows/test.yml`
runs `dart run scripts/check_plan_review_record_exists.dart` out of the merged
checkout, and on a `push` event GitHub evaluates the workflow file at the pushed SHA —
so the gate *and* its invocation both come from the commit under test. Both are
`platform` in `docs/blast_radius.yaml`, so the registry demands a record while the
check enforcing that demand is supplied by the artifact being changed.

That is the same class this batch closes for the registry, and an earlier draft of this
section named only the merge-subject spoof — an over-claim against the batch's own
thesis, found by round-1 review and corrected here rather than widened quietly. It is
not fixable in-repo (pinning the script to a base revision leaves the workflow step
author-supplied, and would stop any genuine improvement to the gate from governing its
own merge), so it shares the single real control with the spoof below.

**A deliberate merge-subject spoof by someone with push access.** Every input the
script can read is authored by that same person, so no in-repo check can
distinguish `git merge --no-ff other-work -m "Merge branch 'approved-thing'"`
from the real thing. One-record-one-landing removes the realistic form (re-using
an old approval); a first-time spoof naming a never-landed branch remains.

The control for that is requiring PRs so GitHub writes the subject from the real
head ref — a repository-settings decision, recorded as `blocked_on_user` in
`docs/audit/gate-input-family.closure.yaml`. Deliberately not touched here:
`feedback_mistake_branch_protection_semantics` records three prior occasions of
getting those semantics wrong.

## Why the tests are e2e and not source-greps

Every one of these bugs was a gate that **ran and returned the wrong answer**. A
test asserting the new code exists would pass against all four bugs. Each of the
8 controls in `test/scripts/gate_input_family_e2e_test.dart` builds real commits
in an isolated repo and asserts an exit code; two of them carry explicit setup
guards that fail if the scenario is not actually the shape being tested (e.g.
the OI-71 case asserts the old three-dot diff really is blind to the file).

`feedback_source_grep_false_confidence.md`, and one level up from it: unit-testing
a helper certifies the helper, not the gate.

## What round-1 review found, and the method lesson

An independent context-blind round returned 3 P1s, 3 P2s and 3 P3s. All nine are fixed
in-branch with a regression test each; the full accounting is in
`docs/plan-reviews/gate-input-family.md`. Two are worth repeating here because they are
about *how the work was verified*, not about the code:

**The exemption was per-push while its justification was per-commit.** Shipping
hard-fail instead of `--warn-only` was argued on a measured baseline — "3 of the last 60
first-parent commits, of which 1 is exempted mechanically". That baseline was computed
per-commit. The code as first written unioned all direct commits in a push before
testing the exemption, so in the real release flow (`2c4cbddd` bump at 05:24 +
`6a364656` docs at 06:42, two halves of shipping APK +37) **zero** would have been
exempted and the next release push would have reddened main. A measurement only
licenses the behaviour it actually measured.

**The tier-12 evidence above could not have caught it.** Replaying `be3b4baf`,
`8c38c855`, `2c4cbddd` and `1b02d00e` *individually* is structurally blind to a defect
that only appears when two commits share a push. Four passing replays looked like
strong evidence and were the wrong shape of evidence — the same failure mode as an
adoption test that asserts a call is present without asserting where.
