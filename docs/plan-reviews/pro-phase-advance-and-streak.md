---
branch: pro-phase-advance-and-streak
scope: Piece A - PRO next phase builds itself after a restore (ensureProPhaseAfterRestore), bounded plan push, phase-gated plan-window re-anchor with an in-flight pin, Train expired-PRO card
blast_radius: platform
review_rounds: 9
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/pro-phase-advance-and-streak-bpass.md
---

# Plan-review record - pro-phase-advance-and-streak (Piece A)

Plan: [`docs/plans/2026-10-16-pro-phase-advance-ensure-current.md`](../plans/2026-10-16-pro-phase-advance-ensure-current.md) (v10).
Diagnose: [`d9b3e7`](../diagnoses/2026-10-16-pro-phase-ensure-after-restore-d9b3e7.md). Closure ledger: `docs/audit/pro-phase-advance-and-streak.closure.yaml`.

## Rounds
Nine independent context-blind Sonnet plan-review rounds, each verifying claims against the code and the read-only live state. P1 counts per round: 7, 5, 5, 3, 1, 1, 1, 2 (then none open at v10). The plan was split into Piece A (the trigger, this branch) and Piece B (the long-gap cap, `allowGapStart`, the auto-run card, the coach `plan_status` fact, the streak diagnose) after round 5 on the "too large to converge" rule (CLAUDE.md section 4.12.1).

## What the rounds did NOT verify (stated plainly)
v10 deleted an in-flight-counter / leaf-file / Train-guard / restore-writer-skip mechanism because it was the source of the last rounds' P1s. **No plan-review round re-verified that deletion.** The B-pass was therefore pointed at it, and found a real P1: the deleted Train guard was needed (a lazy provider rebuild regenerates the OLD phase over a half-written window). It was reproduced with a failing test and replaced by a much smaller guard (`phaseAdvanceInFlight`, the lock's own completer) in this branch; the B-pass round 2 reviewed those fixes. The restore-writer half of the deleted mechanism returned in reduced form as the window pin (`planWindowPinnedByAdvance`).

## Ground truth verified
- The splash `advanceProPhaseIfExpired` is the only automatic advance and runs before the restore (hypothesis for the founder's tab, consistent with `client_errors`; no event existed to prove it - the new `pro_phase_ensure` events make the next case observable).
- Local run, final tree: `flutter analyze lib/` 0 warnings / 0 errors (59 existing infos), full suite 9694 passed 9 skipped, pre-commit gates green, 61 mutants over the ensure path plus 22 for the review fixes all red.
- Not verified: behaviour on a device (founder-owned), the live `pro_phase_ensure` events, any Edge Function (none touched).

## B-pass
Two rounds, see the review file. Verdict accepted by the author; founder triage not yet done.
