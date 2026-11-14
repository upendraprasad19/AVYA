# OI-162 slice 4 — §4.12 split decision

**Question**: round 2 found a P0 inside a unit (C) that round 1 itself
introduced. §4.12.1 says successive rounds surfacing *new* material issues is
the signal a unit is too large — split it, don't review the large thing a
fifth time. Does that apply here?

**Decision: no split.** Reasoning:

1. **The rule targets a specific failure shape**: round 3, 4, 5 keep finding
   *more* new problems, meaning the unit is too tangled to converge. That is
   not what happened — this is round 2, and it found exactly one class of
   defect, in exactly one place.
2. **Round 1's growth was legitimate, not scope creep.** It found a real gap
   (consume_quota's ACL exposure) that had to become a new unit — that is the
   review process working, not a sign of a badly-scoped plan.
3. **Round 2's finding was a bug INSIDE that one new unit**, not a new
   category of problem in units A or B, and not a new gap elsewhere. I
   applied a memory-recalled pattern (REVOKE FROM PUBLIC, per migration
   091's fix) without reading this function's actual ACL first — a
   process failure (verify before reusing a remembered pattern), not
   evidence the unit itself is too big.
4. **The fix was mechanical and independently verified**, not merely
   accepted on the reviewer's word: I re-derived the correct REVOKE
   statement from the live `proacl` myself, and separately re-checked the
   safety question (does revoking `authenticated`'s EXECUTE break the live
   chat/food/vision caps) on a WIDER input set than round 2 used — round 2
   checked Edge-Function writers only; I additionally checked the Dart
   client's cloud writes and found exactly two channel values, both
   excluded by all three triggers' early-return guards.
5. **Units A, B, D carried zero P0/P1 findings across two rounds** — the
   only unit under genuine doubt was C, and that doubt is now resolved and
   independently checked, not just patched and hoped.

**Not treated as a founder decision** — offered as information (see chat),
not a question, per §4.12: the ×2 review process exists precisely so
technical convergence judgments like this don't need to go to the founder
every time. Confirmed 2026-09-11.
