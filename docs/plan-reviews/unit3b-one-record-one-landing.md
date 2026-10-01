---
branch: unit3b-one-record-one-landing
date: 2026-08-05
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/unit3b-one-record-one-landing-bpass.md
---

# Plan review — unit3b-one-record-one-landing (diagnose a7f3c2)

## Scope

`_checkOneRecordOneLanding` in `scripts/check_plan_review_record_exists.dart`
(+91) plus its three e2e tests (+105). Nothing else. Tier re-derived from the
real staged diff rather than assumed: **`platform`**, driven by the gate script
itself.

## Where the review rounds happened — stated plainly

The two independent context-blind rounds did **not** run under this branch name.
They ran on `discipline-tooling-hardening` (diagnose `c9f4e1`), which bundled 3a
(a git lock), 3b (this) and 3c (`safe_merge.sh`). This branch is the §4.12 split
of that unit, and 3b's *content* is byte-identical to what those rounds reviewed
— verified by md5, not by assertion: the two files were byte-copied out of that
worktree (`a9667c19…`, `8f98eb5b…`) and both are unchanged between the split's
base `570feddf` and current `main`, so nothing drifted underneath them.

Recording it this way rather than silently inheriting the count, because a
record that implies two rounds examined *this branch* when they examined its
parent unit would be the same class of unearned claim this batch has been
correcting elsewhere.

What those rounds actually found **in 3b specifically**:

- **Round 1** — the function's own doc comment claimed it implemented the
  `gate-input-family.md` predicate ("the record must have been modified in this
  range"). It does not; it does a point-in-time blob comparison. The claim was
  corrected in the comment rather than left standing.
- **Round 1, finding #9** — the `branchMerge`/`pullRequestMerge` restriction is
  bypassable by phrasing a landing's subject in the `remoteSyncMerge` shape.
  Harmless while the check is advisory; recorded at the code as a
  must-close-before-`fail()`.
- **Round 2** — carried the divergences into the doc comment explicitly (no
  prior-tier check; blob comparison not range walk) instead of shipping a
  function whose comment overstated it.

## The §4.12 split signal

Rounds 1, 2 and 3 each surfaced NEW material issues on the combined unit — round
2 rewrote 3a's lock-claim mechanism after reproducing a live race; round 3 then
found the reclaim branch had the same check-then-act shape one step over, which
neither earlier round caught. That is the stated signal to ship the smallest
converged piece.

3b is that piece. Independence verified by grep, not assertion: its diff
contains zero references to `_git_lock`, `git_lock_acquire`, `git_lock_release`
or `safe_merge`. 3a and 3c cannot be cut apart from each other (`safe_merge.sh`
sources `_git_lock.sh` at runtime) and ship after one narrowly-scoped round on
the round-3 reclaim fix.

## Ground-truth verification

- Tier re-derived from the actual staged diff via the `-` stdin form (avoiding
  the documented positional-args trap that silently returns `feature`).
- `dart analyze` on the gate: 0 issues. All 8 e2e tests green.
- **Negative-controlled by execution in both directions** — the check that
  distinguishes a discriminating test from one that merely passes. Never-fires ⇒
  only the positive test fails. Always-fires ⇒ all three fail, including the
  positive one, because it pins the message CONTENT (the fixture branch name
  `reuse-stale`), not just the `NOTE (possible stale reuse)` marker. Script
  restored from a byte-copy after each mutation, md5-verified, grep-confirmed
  free of residue.
- The gate was run against the live repo with `GITHUB_REF=refs/heads/main` and a
  real `PUSH_BEFORE`, so the not-on-main short-circuit could not produce a
  vacuous PASS.
- The caller context was read rather than assumed: `branch = recordSlug(rawBranch)`,
  so the function receives the slugged record path but matches on the raw branch
  name. Same raw branch ⇒ same slug ⇒ same path, and a many-to-one slug cannot
  produce a false positive because the `priorMs.branch != rawBranch` filter
  rejects it. It is also called *before* `_validateRecord`, so a missing record
  yields no NOTE and then fails properly in the validator.

## Convergence

Converged. The shipped surface is one advisory `stdout` line in a pre-commit/CI
gate — it cannot block a correct merge and cannot pass a merge the pre-existing
checks would have failed. Promotion to `fail()` is the moment real risk begins
and takes a full §4.12 review then; round-1 finding #9 must close first.

OI-58b stays OPEN. This ships its realistic half; the residual first-time spoof
needs PR-enforced merge subjects, which is a repository-settings decision rather
than a code change.
