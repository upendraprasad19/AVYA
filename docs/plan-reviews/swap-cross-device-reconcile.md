---
branch: swap-cross-device-reconcile
date: 2026-10-03
blast_radius: feature
review_rounds: 2
ground_truth_verified: true
verdict: converged
---

# Plan-review record — Home insight follows today's row (`swap-cross-device-reconcile`)

Founder report 2026-10-01: after a web day swap, the Android Train row, Home Today widget and Home insight
showed the pre-swap workout. Plan: `docs/plans/swap-cross-device-reconcile.md` (v6).

## Lineage

Rounds 1-4 reviewed plans v1-v4 (cross-device reconcile, completed-row heal, merge lock, allowance, surface
fixes). None converged; every non-converging unit was split onto the OI board (§4.12.1) with evidence:
OI-284..290, OI-292..295. The founder chose, after round 5, to ship U1 alone (chat 2026-10-03, "Option A ...
OK proceed"). `review_rounds: 2` counts only rounds on the v5/v6 lineage, not the cumulative six.

## Rounds on this lineage

- **R5** (v5, two fresh context-blind reviewers): U1's mechanism sound (no cycle, rollover covered, counts
  21/7 verified, no test pins the old `ref.read`); scope wording too wide (cross-device launch path never
  invalidates `todayWorkoutProvider` → OI-294). U2 and U6 had new design defects → split to OI-292 / OI-293.
- **R6** (v6, one fresh context-blind reviewer): **converged**, mechanical only — test 2 must avoid a
  `todayWorkoutProvider` override (pre-fix code ignores it) and add logged-flag/moved cases; spell out the
  setup; keep `ref.watch(authUserIdTokenProvider)`; update the existing SoT reader row; ref-less writers
  (OI-295); closure states `blocked_on_user`. All applied in v6.

## Ground truth

Every reviewer claim the plan relied on was re-read by the coordinator before use (e.g. 21/7 invalidation
counts, `todayWorkoutProvider` build at `home_provider.dart:519-529`, `deload_evaluator.dart:223` ref-less
write, `allowBackup=false`, morning-alert reading `yesterdayIST`).

## Execution evidence

Test written first, red on the pre-fix code (group 1 only); fix applied; green 8/8; mutation (old `ref.read`
restored) reddened exactly the regression test (+7 -1), restored and `cmp`-verified. Blast radius `feature`
(measured), so no B-pass record is required; a code review still runs before the merge.
