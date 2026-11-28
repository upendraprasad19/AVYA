---
branch: workout-progression-resolver
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-progression-resolver-bpass.md
---

# Plan review — workout-progression-resolver (Batch 3b-i: ⑦(a) detraining WEIGHT decay)

Item ⑦(a) of the workout-generator overhaul. Split TWICE: founder split Batch 3 → 3a(④,shipped)+3b;
the round-1 ×2 review then split 3b → **3b-i (⑦a, this) + 3b-ii (W2.1 graded progression, next)**.
Blast radius **platform** (`progression_resolver.dart` prescribes every phase-2+ starting weight).
`feat`. One item, terminal.

## Review rounds (≥2, before code)

- **Round 1 (context-blind, on the ⑦a+W2.1 plan) → VERDICT: split.** Verified the ground-truth
  (resolve signature, single-`lastSession` model, reps-rule, Epley, the call site passes names-only,
  `populated` carries `repRange`). Headline: ⑦(a) needs ONLY the single most-recent `lastSession.date`
  (already present) → shares ZERO refactor with W2.1 → ship ⑦(a) first (§4.12). Also: the Batch-0
  scorecard is VACUOUS for this (never invokes resolve(), seeds no logs, scores set-count not weight →
  behavioral test is the SOLE proof); ⑦(a) set-halving would force a return-type change → weight-decay
  only (W2.1/follow); read experience+training-age INSIDE resolve() using RAW `fitness_experience`.
- **Round 2 (context-blind, on the hardened ⑦a-ONLY plan) → VERDICT: harden (2 P2, surgical).** Both
  folded in-place (scope confirmed right, not a further split):
  - **F3 (correctness inversion):** the reps-rule references the baseline in FOUR places incl. the
    `<=0` back-off floor. FIX: the decayed `base` replaces `top.weight` in ALL FOUR (a light lower-body
    lift at >35d/<5-reps would else reset the floor to the ORIGINAL weight = go UP, inverting
    "reduce-only"). Only `est1rm` keeps the original weight. Pinned by the F3 test.
  - **F5 (IST zone double-shift):** `top.date` is the local-midnight parse of an already-IST date
    string → re-zoning double-shifts east-of-IST devices (Test #11.1 class). FIX: carry the RAW
    `log['date']` string; `gapDays = DateTime.parse(istTodayStr()).difference(DateTime.parse(dateStr)).inDays`
    (both date-only → zone cancels).
  - P3s folded: F7 (test in the HOLD band so the Epley clamp can't mask decay), F4 (boundary days
    7/8/21/22/35/36), F1 (two imports). Kill-switch default-ON confirmed sound **given F3**.

## Ground-truth verification (true)

Self-verified: resolve's single-`lastSession` model + real date at `:76-79` (not `_topSet`'s `DateTime(0)`
placeholder); Epley `:89-90`, reps-rule 4 baseline refs incl. `<=0` floor `:104`; `exlog_*` `date` is an
IST date-only string; `istTodayStr()`/`setTestClockTo`/`resetTestClock` exist (`ist_date.dart`); scorecard
structurally can't invoke resolve(). Every cited line read directly.

## Verdict: converged

Behavioral test `progression_resolver_decay_test.dart` 5/5 (HOLD-band decay, boundary days, F3
inversion guard, kill-switch verbatim, phase-1 no-op); Batch-0 scorecard green (no-regression,
trivially — Finding A); analyze clean; SoT `detraining_decay` + plan_engine CLAUDE.md Stage-0 note.
B-pass on the diff accepted (docs/reviews/workout-progression-resolver-bpass.md). W2.1 = Batch 3b-ii
(explicit §4.12 split, NOT a deferral — its binding notes are captured in the batch plan).
