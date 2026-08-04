---
branch: repo-gate-pattern-sweep
date: 2026-08-05
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/repo-gate-pattern-sweep-bpass.md
---

# Plan review — repo-gate-pattern-sweep (Unit 2, diagnose e7c3b9)

## Scope

A sweep for siblings of the three gate-tripping content patterns that the
`terms-accepted-fix` batch (b3f9e7) hit: a stale cross-doc `§N` citation, dead
`CLAUDE.md §N` citations in un-gated paths, and a screen at the Gate 43 ceiling.
Plus one genuine gate hole found along the way — Gate 26's regexes had no
letter-suffix support, so every `§2a` citation validated only by colliding with
the unrelated `## 2.`

Tier re-derived rather than assumed: **`account`**, driven by
`lib/features/auth/screens/restoring_screen.dart`. The diagnose-doc originally
declared `feature`, which is exactly what would have let a reader conclude this
review was not owed.

## Review arc

**Round 1 — NOT CONVERGED (2 blocking, 5 should-fix).** Its most valuable act
was mechanical, not analytical: stripping comment and blank lines from both
sides of `restoring_screen.dart` and diffing what remained (542 code lines,
byte-identical). That is what actually establishes "comment-only" on an auth
post-boot path; reading the diff by eye would not have. It also found a third
dead `§19` the sweep had missed, the wrong `blast_radius:`, and — sharpest —
that the trim's new pointers led to `lib/features/auth/CLAUDE.md`, which
carried the *same* stale timeout claim the trim was correcting.

**Round 2 — NOT CONVERGED (1 blocking, 2 should-fix).** The blocking finding
was that round 1 had repeated the mistake it diagnosed: it wrote down the rule
("re-derive the count by grep, or the prose becomes evidence for its own
completeness"), then corrected 2 → 3 by adding the single site it had been
handed, without re-deriving. Round 2 ran the grep: five more, including a
near-twin in the very file already edited and a *template* instructing future
diagnose-docs to add a "§19 entry".

**B-pass — rejected → accepted after fixes (2 P1, 2 P2).** See
`docs/reviews/repo-gate-pattern-sweep-bpass.md`. P1-A: the trim invalidated
three SoT-registry `line_range:` entries while the same branch repointed the
drift-detector agent *at* that registry — and both registry gates pass on a
wrong map because they only bounds-check. P1-B: the completeness grep's input
set was three directories while its conclusion was stated unscoped; repo-wide
re-derivation found 9 more in `docs/naming_conventions.md`, a file CLAUDE.md
§4.7 mandates reading.

## The §4.12 split signal, and how it was answered

Three consecutive rounds each surfaced NEW material issues. §4.12 names that
as the signal a unit is too large and says to ship the smallest converged
piece rather than review the large thing again.

The converged piece is everything whose *correctness* was attacked and held:
the Gate 26 regex fix and its negative-controlled test, the comment trim
(proven byte-identical in code), the 20 repointed citations (each target
verified to exist and to deliver what its sentence promises), and the
`auth/CLAUDE.md` correction.

What was NOT converged was a **claim**, not a fix: "the sweep is complete."
That claim was wrong three times. So it was scoped to what was actually swept
— the prescriptive doc/skill zones — and the remainder (**138** dead citations
in `lib/`/`test/`/`scripts/`/`supabase/` code comments, invisible to Gate 26)
filed as **OI-91** with its reproduction command and an explicit note that 138
is a floor. That is the split: ship the verified fixes, stop asserting more
than was verified.

## Ground-truth verification

- Blast radius re-derived from the real diff every round (stdin `-` form).
- The comment-only claim proven by mechanical strip-and-compare in two
  independent rounds, including validation of the strip method itself.
- The new gate test negative-controlled by execution, mutating each regex
  separately, with the script restored from a byte-copy and md5-verified.
- Every repoint target opened and checked for the promised content — a
  repoint to a wrong-but-live target is worse than the dead one it replaces.
- Two **wrong-but-live** citations found only by reading, because the
  grep filter is structurally blind to that class.
- Every number re-measured at the end: 791 / 824 / −33 / `:103` / 8505.

## Convergence

Converged. The production surface is one regex widening in a pre-commit gate,
plus comment and documentation text; no application logic changed. The
`restoring_screen.dart` trim brings the file to 791 lines, under Gate 43's 800
ceiling, which makes the transitional allow-list entry unnecessary — removing
it is done in the follow-up commit on this branch, closing **OI-88**.
