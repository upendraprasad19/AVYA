---
bug_id: a3d7b1
date: 2026-07-27
batch: script-tier-promotion
status: fixed
blast_radius: platform
symptom: >-
  Ten enforcement scripts — two of the four git hooks setup-hooks.sh installs,
  both sanctioned write wrappers, the whole rule-22 diagnose-doc chain, and two
  hard-fail discipline gates — were all feature tier. A change to any of them
  cleared no review gate at all.
concept: blast_radius_registry_coverage
recurrence: >-
  Third instance of the same COVERAGE failure in this registry block, and the
  first two were fixed the same way that failed again: by hand-typing a list.
  2026-07-19 promoted the keystone-gate family; c9f1d3 (2026-07-26) caught
  check_code_review_pass_exists.dart; this batch's own first draft then promoted
  two of the four installed hooks and missed commit-msg.sh. Same shape as
  feedback_ist_sweep_gap — an exhaustive-sounding sweep leaving sites behind.
  Closed structurally this time: the hook half of the set is DERIVED from
  setup-hooks.sh, not restated.
related_bugs: c9f1d3
sot_registry_entry: blast_radius_registry_coverage
writers:
  - { file: docs/blast_radius.yaml, method: paths_rule_enforcement_scripts, line: 124 }
readers:
  - { file: scripts/blast_radius_from_diff.dart, method_or_widget: main, line: 120 }
  - { file: scripts/check_plan_review_record_exists.dart, method_or_widget: _parseRules, line: 72 }
  - { file: scripts/check_code_review_pass_exists.dart, method_or_widget: parseRules, line: 28 }
  - { file: scripts/check_blast_radius_coverage.dart, method_or_widget: parseRules, line: 30 }
  - { file: test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart, method_or_widget: registry_tiering_group, line: 112 }
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
  - { pattern: "an enforcement script resolving to feature via the scripts/** catch-all", absent_after_fix: true }
proposed_fix: >-
  Add ten exact-path platform rules above the scripts/** catch-all; DERIVE the
  git-hook half of the set from scripts/setup-hooks.sh so a fifth hook cannot be
  missed; assert parity against the real classifier binary rather than the
  test's own glob reimplementation; and move the Gate-DEU phrase list to a
  feature-tier data file so promoting the gate does not ossify its list.
regression_test_planned:
  - test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart
  - test/contracts/deferral_euphemism_gate_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "10 registry rules + derived setup-hooks assertion + real-classifier parity + Gate-DEU data split; flutter analyze clean; 25/25 and 7/7 pass; per-file negative control fails EXACTLY that rule's assertion; removing commit-msg.sh also trips the derived assertion independently" }
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
  - { tier: 12_client_server_contract, status: verified, evidence: "no runtime contract; classifier output verified positionally with controls (pre-commit.sh -> platform, docs file -> feature)" }
impact_analysis: >-
  No user-facing impact. The exposure was that the scripts enforcing every other
  rule could be weakened without any review — including by an agent, silently.
  pre-push.sh is the sharpest case because it is self-referential: it decides
  whether the ~7-minute full suite runs before code leaves the machine, so an
  edit disabling it would clear zero review gates AND skip the suite on the very
  push that lands it, and CI is not a substitute because golden-image tests run
  only in that local suite. check_no_deferral_euphemism.dart was the thinnest
  defended: one commit ever, no test of its phrase list, hard-fail locally, and
  it fails OPEN on a git error — so emptying its list would have been
  indistinguishable from working. (It is not allow-listed out of CI, but runs
  vacuously there since CI has no staged diff, so "no CI backstop" is true in
  substance.) This batch gives it its first behavioural tests. Nothing indicates
  any of this was exploited; it is a latent hole being closed — with one residual
  named in the body: the tier engines read the registry from the merged tree, so
  a commit deleting its own protecting rule is still classified by the
  post-change registry.
---

# The scripts that enforce everything else were exempt from review

## What was wrong

`docs/blast_radius.yaml` promotes discipline-enforcement scripts to `platform`,
with the rationale stated in the file itself:

> A change to the reviewer must not be exempt from review.

Successive sweeps applied that to some scripts and missed others. `c9f1d3`
closed the gap for `check_code_review_pass_exists.dart`. Ten more remained on
`scripts/** → feature`:

| Script | Why it matters | What defended it |
|---|---|---|
| `pre-push.sh` | Decides whether the full suite runs before a push | A source-grep text test only |
| `commit-msg.sh` | Sole **local** enforcement of rule 22; owns the `regression-test-skipped:` waiver, which has no CI equivalent | **Nothing** |
| `safe_commit.sh` | Sole sanctioned commit path | Its *filename* is asserted by the git-safety tests; its own verify-after-write logic is untested |
| `safe_push.sh` | Sole sanctioned push path | Same |
| `validate_audit_closure.dart` | Gate 40 — the no-deferrals invariant | CI + an invoking test |
| `check_no_deferral_euphemism.dart` | Blocks deferral-by-rewording | Wiring only; nothing tested the phrase list |
| `validate_diagnose_doc.dart` + `_lib` | The rule-22 validator `commit-msg.sh` calls | — |
| `check_bugfix_commits_have_diagnose.dart` | Rule-22 CI backstop | — |
| `check_blast_radius_coverage.dart` | Third of the CLAUDE.md §7 blast-radius trio | — |

The rule-22 row is the one that makes the omission indefensible rather than
merely incomplete: the first draft promoted the §4.2 no-deferrals chain **in
full** while leaving the parallel rule-22 chain **entirely** at feature. Two
invariants of identical standing, opposite treatment, for no stated reason.

## Why `pre-push.sh` is the sharpest case

It is self-referential. `pre-push.sh:64` is a string equality against
`"feature"` — if the tier is feature, the local full suite is skipped. So an
edit that disabled the gate would (a) clear no review gate, because the file
itself was feature tier, and (b) skip the suite **on the very push that landed
it**.

CI does not cover the difference: `.github/workflows/test.yml` excludes
golden-image tests, which run **only** in that local pre-push suite. A visual
regression would reach `main` with nothing having checked it.

Its sibling `pre-commit.sh` was promoted by **`d947743d` (2026-07-26,
merge-governance F8)** under *"A change to the reviewer must not be exempt from
review"* — not, as an earlier draft of this doc claimed, by the 2026-07-19
sweep under a different rationale. `git blame` corrected that; the claim mattered
because it framed which sweep was incomplete.

## Cost, measured before deciding — and corrected

Promotion is not free: every future edit needs a plan-review record plus a
B-pass. So the churn was measured rather than assumed.

| Script | Commits |
|---|---|
| `check_no_deferral_euphemism.dart` | 1 |
| `safe_commit.sh` | 2 |
| `pre-push.sh` | 2 |
| `safe_push.sh` | 3 |
| `validate_audit_closure.dart` | 4 |

Those per-file counts sum to 12, but that **double-counts**: two commits touch
more than one of the files. The real figure is **10 distinct commits, across 6
distinct days, in the repo's 4.1-month life** — call it **4–5 review events per
quarter**, not the "~3 per quarter" an earlier draft stated and that was quoted
to the founder. The B-pass caught it before ratification.

The conclusion survives the correction (well under 1% of commits, all clustered
into deliberate discipline batches), which is why promoting the whole set beats
picking a subset — a hand-maintained exception list is precisely what has now
failed three times.

## The fix

Exact-path rules at `tier: platform`, above the `scripts/**` catch-all
(first-match-wins, per the registry's own header). Exact paths over globs
deliberately: a glob auto-promotes future files with nobody deciding, and this
repo already reverted promoting a data file for exactly that reason. A glob
would also not have caught `commit-msg.sh` — `pre-*.sh` misses it — because the
family is defined by *what setup-hooks.sh installs*, not by a filename prefix.

**The structural half matters more than the list.** The git-hook portion of the
set is now **derived from `scripts/setup-hooks.sh`**: every source it installs
must be ≥platform or appear in an explicit declined-with-reason set. Add a fifth
hook and the test fails until its tier is decided. That is what stops a fourth
sweep, and it is verified by removing `commit-msg.sh` from the registry — both
its own assertion *and* the derived assertion fail independently.

### Cost guard shipped with the promotion

`check_no_deferral_euphemism.dart` is platform now, so changing how it matches
is gated — correct. But its **phrase list** is data that must stay cheap to
grow: a one-line "ban another euphemism" costing two review rounds plus a B-pass
would ossify the list while §4.2 violations invent the next phrasing. That decay
is not hypothetical here — a sibling gate has sat `--warn-only` for weeks
against a documented 24-hour window.

So the list moved to `docs/deferral_euphemisms.yaml` at **feature** tier. Same
split the repo already uses for `docs/blast_radius.yaml` (platform registry) vs
the code that reads it. The loader **fails closed**: a missing or empty file
exits non-zero rather than matching nothing, so deleting a feature-tier data
file cannot quietly disable a hard-fail gate.

## Known residual — not closed here

Both tier engines read `docs/blast_radius.yaml` from the **merged tree**, so a
commit that deletes its own protecting rule is classified by the *post-change*
registry: delete the `docs/blast_radius.yaml` and `scripts/pre-push.sh` rules in
one commit and the merge gate computes `feature` and waves it through.
Pre-existing since `d947743d`, demonstrated by the B-pass, and **not** fixed by
this batch — closing it means classifying a merge using the registry as of
`HEAD^1`. Recorded in `docs/audit/open_issues.md` rather than left implicit,
because this doc would otherwise read as if the hole were fully closed.

## Verification

| Check | Result |
|---|---|
| `blast_radius_content_rule_wired_all_scripts_test.dart` | **25/25 pass** |
| `deferral_euphemism_gate_test.dart` (new) | **7/7 pass** |
| **Per-file negative control** — remove one rule, re-run | **1 failure each, and it is that file's own assertion** |
| **Derived-assertion control** — remove `commit-msg.sh`'s rule | **both** its own assertion and the setup-hooks-derived assertion fail, independently |
| Vacuity guard | an unrelated `scripts/*.dart` still resolves to `feature`, so an exact rule is provably the only thing saving these |
| Real-classifier parity | the promoted set classified by the actual binary → `platform`; control `docs/diagnoses/x.md` → `feature` |
| Gate-DEU fail-closed | file missing → **exit 1**; list empty → **exit 1**; present → exit 0 (exit codes read directly, not through a pipe) |
| Gate-DEU data-driven | a phrase present **only** in the yaml is enforced — proving the list is read from disk, not compiled in |

Two of these are load-bearing rather than decorative. The **per-file** negative
control catches one rule silently doing the work of all ten, which a single
"delete something and watch it fail" check would not. And the **real-classifier
parity** test exists because the tiering assertions otherwise re-implement the
glob engine — verified faithful today, but "verified today" is not a guard; the
parity check makes drift impossible rather than unlikely.

The Gate-DEU exit codes were re-read without a pipe after an initial check
reported the *pipe's* status instead of the process's — the same failure class
`safe_commit.sh` exists to prevent, encountered while promoting it.
