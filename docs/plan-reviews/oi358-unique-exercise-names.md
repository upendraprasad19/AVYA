---
branch: oi358-unique-exercise-names
plan: docs/plans/oi358-unique-exercise-names.md
date: 2026-11-06
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/e141930e4739-review.md
---

# Plan review - OI-358 (an exercise name twice in one workout day)

Founder decisions, 2026-11-06, in chat: fix every door in one branch ("if we can do both in one branch, then why not?").
Grey-out in pickers (not hide) and keep-first in the template guard were stated as defaults and not objected to.

Round 1 (context-blind reviewer, code only): `needs_changes`. Two P1s, both accepted after reading the code: every call site
assumed success and the add path had no messenger; restore hydration is a carrier the census had missed. Also P2 and P3
items: dedupe before `_normalizeExercises`, the pre-pass copies the loop's skip rule, no exercise name in the event, section
4.6 must be addressed, UNDO's captured index. Author's own correction: the first bug-history search ran against an index
that did not exist in the fresh worktree, and `b3c8d2` had been missed.

Round 2 (fresh context-blind reviewer on the post-round-1 plan): no P0, no P1. P2 and P3 items applied: the UNDO rationale
was wrong (a removal stales the index, a move hides the snackbar); a `bool` would misreport a bad index, hence the enum;
`sets` parses tolerantly; both tap targets of `_SwapItem` die. Nothing material remained, so the plan converged.

Both reviewers verified the plan's claims against the code; the crash itself was reproduced on the real screen before
implementation. Detail: plan section 8. Implementation record: diagnose `e6a4d9`, closure
`docs/audit/oi358-unique-exercise-names.closure.yaml`.
