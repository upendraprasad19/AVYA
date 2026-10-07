---
branch: script-tier-promotion
date: 2026-07-27
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/script-tier-promotion-bpass.md
---

# Plan review — script-tier-promotion

§4.12 record. Two independent context-blind rounds ran in parallel on the staged
implementation. Both found material defects; everything material is fixed in the
same commit, and the one item that is not fixed is named rather than absorbed.

## What this is

Promote the scripts that enforce the discipline system from `feature` to
`platform` tier, so editing them requires the review they impose on everyone
else. `docs/blast_radius.yaml` already states the rule in its own comment — *"A
change to the reviewer must not be exempt from review"* — and had applied it
inconsistently across three successive sweeps.

Founder ratified the scope after being shown the measured cost.

## What the rounds changed

**Round 1 (completeness) found the set was wrong.** `scripts/setup-hooks.sh`
installs four hook sources in four consecutive lines; the plan promoted two.
`commit-msg.sh` — hard-fail, zero tests, sole local enforcement of rule 22 — was
left at feature, along with the entire rule-22 chain behind it, while the
parallel §4.2 chain was promoted in full.

**Round 2 (adversarial) found a number I had already quoted to the founder was
wrong.** "12 commits / ~3 review events per quarter" double-counted: it is 10
distinct commits, ≈4–5 events per quarter. It also caught that my correction to
a wrong line citation was sitting unstaged and would not have committed.

Both were verified against the source before acting, not taken on the agents'
word — `setup-hooks.sh:38-41`, the `commit-msg.sh` tier and test count, the
distinct-commit count, and the `git log -S` attribution were each re-run by me.

## Ground truth

- All ten paths classify `platform`; controls `scripts/pre-commit.sh` → platform
  and `docs/diagnoses/x.md` → feature confirm the classifier answers correctly.
- Per-file negative control: removing any one rule fails **exactly that rule's**
  assertion. Removing `commit-msg.sh`'s also trips the derived assertion,
  independently.
- Gate-DEU fail-closed verified by reading exit codes **directly**, after a first
  attempt reported the pipe's status instead of the process's.
- 32/32 across both test files; `flutter analyze` clean.

## Convergence

Converged because the disagreement resolved by **enlarging and restructuring**
the change rather than defending it, and because the round-2 findings were
corrections of fact that I could verify independently — not judgement calls left
unresolved.

The structural half is what makes this converged rather than merely bigger: a
hand-typed list failed three times, so the git-hook portion of the set is now
**derived from `setup-hooks.sh`**. A fourth omission of that kind now fails a
test instead of shipping.

## Deliberately not closed

**OI-70** — the tier engines read `docs/blast_radius.yaml` from the merged tree,
so a commit that deletes its own protecting rule is classified by the
post-change registry. Pre-existing, demonstrated by the B-pass, and the one route
by which this batch's own thesis can still be defeated. Fixing it means changing
how every tier decision is computed and needs its own review round; it is
recorded in `docs/audit/open_issues.md` and in the diagnose-doc's residual
section, not left implicit.

**OI-71 / OI-72** — two gate defects found during the preceding merges (keystone
gate blind to conflict-resolution content; a review file able to satisfy the
catastrophic gate without entering history). Same file, different batches.
