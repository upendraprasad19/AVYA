---
branch: review-gate-tier-gap
date: 2026-07-27
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/review-gate-tier-gap-bpass.md
---

# Plan review — review-gate-tier-gap

§4.12 record. Two independent context-blind rounds ran in parallel, and round 1
**rejected the original change outright**. What ships is a strict subset of what
was reviewed, so the reviews cover it fully.

## What was proposed vs what ships

Proposed: a merge exemption for `scripts/check_code_review_pass_exists.dart`
(stand down while `MERGE_HEAD`/`CHERRY_PICK_HEAD`/`REVERT_HEAD` exists), plus a
registry line promoting that gate to platform tier.

Ships: **the registry line only**, plus a test pinning it. The exemption is
reverted — the gate file is byte-identical to `main` and its test is deleted.

## Why the exemption died

My justification was that the gate is unsatisfiable at a merge: the required
filename derives from the staged-diff hash, so adding the review file changes
the hash. **Verified false.** The hash comes from `git diff --cached` (the
index) but the file is read with `File(...).existsSync()` (the working tree), so
an unstaged review file satisfies it without moving the hash. Five untracked
`docs/reviews/*-review.md` files were already sitting in `git status` proving it.

Round 1 then showed the exemption was actively harmful: cherry-pick and revert
produce **single-parent** commits, which the CI keystone gate skips
(`check_plan_review_record_exists.dart:142-145`), so `git revert -n` — needing no
conflict at all — would have landed catastrophic content past both gates.

I verified both claims against source myself before acting on them.

## Ground truth

- Registry ordering checked operationally, not by reading: new rule line 97,
  `scripts/**` catch-all line 130, first-match-wins per the file's own header.
- Tier re-verified with **positional args and known-good controls** after the
  stdin invocation started returning `platform` for every input including a
  plain docs file. Controls: `scripts/pre-commit.sh` → platform, a docs file →
  feature.
- On that basis I **rejected** round 2's P1 that local `main` carried an
  unreviewed platform merge: `0cbeb646`'s branch diff is `feature`, so no record
  is required and the push is not blocked.
- Negative control on the new test: removing the registry line fails exactly one
  assertion, exit 1.

## Convergence

Converged because the disagreement resolved by **removing** the contested change
rather than defending it. The residue is one registry line and a test — the part
both rounds independently endorsed. Nothing contested ships.

Per §4.12, successive rounds finding new material issues is the signal to split
and ship the smallest converged piece. That is exactly what happened here, with
the split falling at "revert the risky half".

## Deliberately not closed here

- Five further discipline-enforcement scripts remain `feature` tier
  (`safe_commit.sh`, `safe_push.sh`, `validate_audit_closure.dart`,
  `check_no_deferral_euphemism.dart`, `pre-push.sh`). Promoting them adds a
  recurring review cost to every future edit — a founder scope call, recorded in
  `memory/feedback_gates_unsatisfiable_at_merge.md`.
- The keystone gate computes blast-radius from the branch diff
  (`HEAD^1...HEAD^2`), so content written during conflict resolution is invisible
  to it. Real, pre-existing, in a different file, and it needs its own unit —
  recorded in the B-pass rather than bundled in.
