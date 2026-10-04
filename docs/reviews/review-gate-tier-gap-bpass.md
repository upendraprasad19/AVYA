---
reviewed_at: 2026-07-27
branch: review-gate-tier-gap
blast_radius: platform
reviewer: two independent context-blind agents (adversarial-bypass lens; correctness/completeness lens)
lens_set: [bypass_surface, gate_wiring, registry_ordering, test_vacuity, doc_factual_accuracy]
findings_count: 5
verdict: accepted
---

# Review — review-gate-tier-gap

Two independent reviewers ran in parallel on the branch as originally staged,
which then contained a **merge exemption** for
`scripts/check_code_review_pass_exists.dart` plus the registry promotion.

**The reviews killed the exemption.** It has been reverted in full — gate file
now byte-identical to `main`, its test deleted, its diagnose-doc replaced. What
ships is only the registry line and a test pinning it.

## Round 1 — adversarial bypass lens: REJECTED the exemption

Three findings, two P0. Every one verified against source by me before acting,
per `feedback_audit_verifier_cannot_trust_own_subagent`.

**P1-3 — the premise was false (the finding that mattered most).** I claimed the
gate was "unsatisfiable by construction" at a merge: the required filename comes
from the staged-diff hash, so adding the review file changes the hash. Verified
false — `stagedDiffHash()` (`:161`) hashes `git diff --cached`, the *index*, but
the artifact is read at `:236` with `File(...).existsSync()`, the *working tree*.
An unstaged review file satisfies it without moving the hash. `git status` on
main already showed five untracked `docs/reviews/*-review.md` files. No
circularity ever existed.

**P0-1 — the exemption was net-new bypass surface.** Cherry-pick and revert
produce **single-parent** commits, and the CI keystone gate exits at
`check_plan_review_record_exists.dart:142-145` when `HEAD^2` is absent. So
`git revert -n <any trivial commit>` — clean, no conflict required — would have
walked catastrophic content past **both** gates. My header's "LOSES NO
ENFORCEMENT" claim was wrong for two of the three refs I exempted.

**P0-2 — the CI fallback is blind to merge-resolution content**, even for real
two-parent merges: the keystone gate computes tier from
`git diff --name-only HEAD^1...HEAD^2`, the branch diff, so a file created only
while resolving conflicts is invisible to it. Pre-existing, not introduced here;
recorded because it undercut the argument I was leaning on.

Also flagged and accepted: the refs are trivially forgeable (one file write
disables three gates, and cherry-pick/revert leave no trace since git clears the
ref on commit), and my own test **pinned the hole as intended behaviour**.

**Action: full revert.** No part of the exemption ships.

## Round 2 — correctness lens: endorsed the registry promotion

Ran the tests, mutation-tested the (now-reverted) exemption, and confirmed it
restored my files cleanly (md5 match, empty `git diff`).

Its findings on the exemption are moot. What survives and was acted on:

- **The registry promotion is correct.** Verified ordering operationally, not
  just by reading: first-match-wins, new rule at line 97, `scripts/**` catch-all
  at line 130. Confirmed the classifier reports `platform` for the staged diff.
- **This branch needs a plan-review record** — written, at
  `docs/plan-reviews/review-gate-tier-gap.md`.

**One P1 of its own I checked and rejected.** It claimed local `main` was
2 commits ahead with a platform-tier merge (`0cbeb646`) lacking a record, so a
push would fail CI. Re-verified positionally with controls: that branch diff is
**`feature`**, so no record is required and nothing is blocking. Its reading came
from the same stdin invocation that was returning `platform` for a plain docs
file. Subagent classification claims are unverified until re-run with a control
— `feedback_audit_verifier_cannot_trust_own_subagent` again, in the other
direction.

Accepted P3s not applicable to the shipped diff (they described the reverted
file). The `sot_registry_entry` naming point is noted for a later registry pass.

## What ships

| File | Change |
|---|---|
| `docs/blast_radius.yaml` | one rule promoting `check_code_review_pass_exists.dart` to platform |
| `test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart` | pins all three tier-engine scripts + shared lib by **reading the registry**, not a hardcoded list |
| `docs/diagnoses/…-review-gate-exempt-from-review-c9f1d3.md` | records the gap, and the retracted misdiagnosis that exposed it |

13/13 pass. Negative control: with the registry line removed, exit 1 and *only*
the `check_code_review_pass_exists.dart is >= platform` assertion fails. A
further test asserts an unrelated `scripts/*.dart` resolves to `feature`, so the
assertions cannot pass for the wrong reason.

## Residual, not closed here

**CLOSED by `a3d7b1` (2026-07-27)** — founder ratified the promotion, and the
set turned out to be larger than the five listed here: `commit-msg.sh` and the
whole rule-22 chain were missed by this review too. The git-hook half of the set
is now derived from `setup-hooks.sh` rather than hand-typed.

~~`safe_commit.sh`, `safe_push.sh`, `validate_audit_closure.dart`,
`check_no_deferral_euphemism.dart` and `pre-push.sh` remain `feature` tier while
enforcing the same system.~~ Extending the promotion carries a recurring review
cost on every future edit, so it is a founder scope decision, recorded in
`memory/feedback_gates_unsatisfiable_at_merge.md` rather than taken unilaterally.

P0-2 above (keystone gate blind to merge-resolution content) is a real
pre-existing gap in a different file and is likewise recorded, not silently
dropped.
