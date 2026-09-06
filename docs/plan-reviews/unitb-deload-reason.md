---
branch: unitb-deload-reason
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/06d7bc7f5e28-bpass.md
blast_radius: platform
reviewed_at: 2026-09-06T07:10:00+05:30
closure_ledger: docs/audit/unitb-deload-reason.closure.yaml
---

# Plan review — `unitb-deload-reason` (Unit B, OI-53 flag 4 of 12)

Fix the stale week-4 deload reason, then flip `enable_deload_reason_line` →
`disable_deload_reason_line`. §4.12.4's lighter ship-dark tier does **not** apply:
this is a flip, so the full ×2 plus `bpass: accepted` is required. Three
independent context-blind rounds ran; 38 findings are terminal in the closure
ledger.

## Rounds

| Round | Against | Verdict | Findings |
|---|---|---|---|
| B-pass | `c22e12c2` | rejected | 10 (1 P0, 1 P1, 3 P2, 5 P3) |
| 1 | `c22e12c2` | not-converged | 12 (1 P0, 3 P1, 5 P2, 3 P3) |
| 2 | `23bc109c` (hardened) | not-converged | 7 (1 P1, 2 P2, 4 P3) |
| 3 | `8a96a1d2` (r2 remediation) | not-converged → **conditions met** | 7 (1 P2, 6 P3) |

## Why this is `converged` rather than a fourth round

Round 3 stated its own exit condition verbatim: *"Required before merge, all
mechanical, no further review round needed beyond re-running the greps."* Its six
items are closed and each was verified by the command it named — most importantly
`git grep -nE "deload_evaluator\.dart:(241|244)"` → **0**. Round 3 also recorded
that the **code** fix is converged: B1 correct and complete, mutation-proven at 2
red, no P0/P1 in the new copy across every reachable state it enumerated.

The trend supports it rather than §4.12.1's split signal: severity fell each round
(P0 → P1 → P2), and rounds 2 and 3 each independently reproduced the prior round's
measurements instead of overturning them — the mutation table 4-2-3-1 was measured
three times by three parties and agreed each time. The one genuinely new issue
round 2 raised was carved out rather than absorbed: **OI-166**, terminal in the
ledger as `blocked_on_user`, because its fix changes an AI-coach WRITE path.

## Ground truth verified

- **Full suite green** at `23bc109c`: `+5392 ~7, 0 failures` (round 2, foreground).
  At HEAD the five touched files are 75/75 and `flutter analyze lib/` is 0
  warnings / 0 errors; the required-parameter change has exactly one production
  call site plus one test helper, and round 3 ran the 8 contract tests that read
  the touched files as source text (88/88).
- **Mutation-proven, four legs, re-measured independently three times:** equality
  guard deleted → 4 red; one-sided → 2; writer reverted to a bare String → 3;
  `waves.length < 4` deleted → 1. Plus the copy fix: collapsing the ternary → 2.
  All compiling, all real assertion failures, each confirmed applied by `grep -c`.
- **Gates:** Gate 40 (39 ledgers), `check_sot_registry_parity`,
  `check_claude_md_citations`, `check_oi_numbering_unique`,
  `check_sot_behavioral_test_paths`, `check_skill_tuning_history`,
  `check_context_artifact_budget`, `check_no_deferral_euphemism`, and
  `validate_diagnose_doc` on both docs — all pass.
- **Blast radius** `platform`, via `blast_radius_from_diff.dart -` with the
  explicit stdin dash.

## The three findings worth remembering

**1. A decision boolean is not an explanation** (round 2, the only P1, diagnose
`d9e1b4`). `notBackstop` is false in three worlds — never recorded, overdue,
corrupt marker — which is the right polarity for a *decision* and wrong as an
*explanation*. The copy was worded for the second, and
`last_actual_deload_phase` has one writer in the repo and is never synced, so a
user in **block one** was told they were "two blocks in". Not in this batch's
code: the flip made five pre-existing copy branches user-visible.

**2. A mutation that reddens nothing is not proof of coverage** (round 1). Three
guard deletions each reddened **zero of twelve**, because an enclosing
`catch (_) { return null; }` produced the same `null` the tests asserted — four
assertions were testing the exception handler. Fixed structurally by extracting
the pure `validatedDeloadReason`; the same deletion now reddens 3. Added to
CLAUDE.md rule 21 as its third named mutation trap.

**3. A correction is not the fix; removing the falsehood is** (rounds 2 and 3).
The scope overclaim survived its own remediation because the retraction was added
without the original claim being struck, in three places including source. Then
the round-2 fix — a single inserted line — re-staled 13 citations the branch had
corrected one commit earlier. **Capture citations LAST, and re-derive after every
edit pass, including one that adds one line.**

## Process defect, recorded

The B-pass and round 1 were dispatched **concurrently against one worktree** and
both were authorised to mutate. They saw each other's edits mid-run; the B-pass
declined to run its mutations and said so. Rounds 2 and 3 ran alone and
re-measured everything, so no conclusion rests on the contaminated window — but
the dispatch rule now lives in `.claude/skills/code-review/SKILL.md`: serialise
review rounds, or give each reviewer its own worktree.
