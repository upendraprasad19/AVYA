---
branch: audit-fixwave-2026-07-02
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/audit-fixwave-bpass-review.md
hermes: accepted
hermes_report: docs/audit/audit-fixwave-hermes.md
---

# Plan-review record — audit-fixwave-2026-07-02 (§4.12)

Fixes all 20 findings + 2 known items from the 2026-07-02 comprehensive functional
audit (`docs/audit/2026-07-02-comprehensive-app-audit.md`) in one batch. Founder
directive: "make a comprehensive plan; don't defer anything." Blast radius =
platform (NUT-02 touches `lib/core/services/sync/**`); NUT-02 elevated to
Hermes-grade (data-loss).

## Round 1 — context-blind plan review (pre-implementation, correctness + completeness)
Two diverse-lens reviewers verified every proposed fix against the actual code +
LIVE schema (not memory). Caught: F3 "BROKEN" reassessed (live query: `scheduled_
workouts` has NO status CHECK → accepts 'paused'); **F5 merge-at-sync triple-count**
on a top-up restore → redesigned; F16 half-migration → documented device-level
decision; F1 `logMealByText` confirmed a real typed tool; coverage of all 20
findings confirmed.

## Round 2 — context-blind plan review on the hardened plan (new-defect + convergence lenses)
Confirmed F3/F16 sound; discounted an invalid "un-executed = broken" alarm;
surfaced that F1/F5 needed design detail → nailed in v3 (F1 routing dedup + F5
`appendItemsToMeal` reuse + lazy coalesce). Verdict: CONVERGED-WITH-SPLIT was
overridden by the founder ("don't defer"); F1/F5 hardened rather than split.

## Implementation review — self-triggered B-pass + Hermes over the diff
- **B-pass** (`docs/reviews/audit-fixwave-bpass-review.md`) — 4 context-blind
  lenses + adversarial verification. 5 CONFIRMED findings (2×P1 data-loss in NUT-02,
  F1 over-suppression, F2 stale-drop, presence_only) — ALL fixed in-batch.
- **Hermes** (`docs/audit/audit-fixwave-hermes.md`) — the NUT-02 data-loss lens
  caught 3 P1s across passes (orphan-on-shrink, partial-restore-loss, duplicate-
  serving drop); all fixed with an item tail-vacuum + a 3-way MULTISET restore
  merge, each regression-tested.

## Convergence
No open findings. Full `flutter test` green; all pre-commit gates green (SoT parity
+ completeness, Gate-42 behavioral paths, Gate-40 closure, diagnose validators, the
broadened schedule-put gate, coach dedup gate). Closure ledger
`docs/audit/audit-fixwave-2026-07-02.closure.yaml` — 22 findings, all terminal
(closed==22). Design decisions vs. the approved plan (both documented in diagnoses):
NUT-02 → merge-at-sync + 3-way restore merge (no boot migration); coach content-
marker dropped (unsafe). Converged.

> Founder-gated (per-action): the live re-verify on test7 (logins), the `--no-ff`
> merge to `main`, and `/build-apk` (ships this batch + C3 + OBS-6 to Android).
