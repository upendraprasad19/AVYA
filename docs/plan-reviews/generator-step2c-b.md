---
branch: generator-step2c-b
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: pending
---

# Plan review: generator-step2c-b (Unit 2C-b, the weekly minimum and the 5-minute allowance)

- **Plan:** `docs/plans/2026-11-14-generator-step2c-b-weekly-minimum.md` (v5). It supersedes §2B, §4B and §5B of the
  parent plan `docs/plans/2026-11-14-generator-step2c-balanced-week.md` (Part 2C-a merged, PR #272).
- **Founder basis:** decisions d35, d37, d38, d42, d44, d45 (2026-11-14, step-2 board card t212) and 2A's d26-d29 (the
  lead), plus d47-d49 taken after the rounds (plan §7): the swap design at 285 s, the lead kept over d35, and d45
  over d38 for Calves at 30 minutes.
- **Tier and blast radius:** tier L (plan engine), blast radius platform. No edit to `plan_generator.dart` (rule 14):
  the allowance signal rides on `PopulatedDay`, which `generateV4` already passes unchanged to `PeriodizationEngine`.
- **§4.6:** 2C-a's Hive kill switch `disable_balanced_week` (d37, one switch for 2C) reaches the allocator as
  `allocate(balancedWeek:)`; switched off, the allocator returns R (today's output) and every day's `allowance` is
  false. With 2A or 2B off the plan is the pre-unit output byte for byte.

## Review rounds

Four rounds of fresh, context-blind Sonnet seats (read-only; no tests run), each verifying claims against merged main
(de30a0a7) and the prototype dumps (2,304-plan audit, plus the 5,760-plan five-focus grid in round 4).

- **Round 1 (v1, two seats): not converged.** P1s: the minimum's count guard missed A2 / floor seats; no terminal guard
  (the fallback was a pinned re-run under 60 only); Q1 mis-described the pin; the 30-minute `glutes_legs` plan became
  a Calves plan (d38 over d45).
- **Round 2 (v2, two seats): not converged.** No P0; P1s on framing: the readers passed the allowance whatever 2A / 2B
  / the fallback did; Q1 mixed Calves (d45) with the d35 groups and hid the lead-versus-d35 trade; a false `ab_swing`
  mechanism.
- **Round 3 (v3, one seat): not converged.** One P1: §0 said OI-501 was fixed (it is not; it stays open with the
  numbers). P2s: Calves for a focus at 30 is a founder call (Q3); a per-plan signal can reach the readers without
  `plan_generator.dart`; the pin at 285 s and the five-focus grid were unmeasured (both measured for v4).
- **Round 4 (v4, one seat, confirming): converged on the design.** Every recomputed number reproduced (the signal runs
  b23 / b25 differ from b18 / b17 in exactly the 2 fallback plans; every §7 cell; every §4.8 five-focus cell). One P1:
  the signal cannot reach `VolumeTitration`, which titrates `WeekPlan`s (`plan_generator.dart:332`); verified by the
  coordinator and fixed by keeping titration's ledger at `allowance: false` (conservative; titration is opt-in and off
  in every measurement). P2 / P3: §5's tests still named round 2's gate (replaced by per-path field fixtures and
  mutants), question numbering, text.

## Ground truth

Every number in the plan comes from the scratchpad runs (`step2cb/audit_*`, scripts `m10.py`, `mx.py`, `mx2.py`,
`newmajor.py`, `gl2.py`, `fgcmp.py`) on the worktree's tree with the prototype patched in and restored by sha after
each run; each seat recomputed the cells it cites with its own scripts.

## B-pass

Pending: `/code-review` on the built diff before the merge; this record's `bpass` and `bpass_review` are set then.
