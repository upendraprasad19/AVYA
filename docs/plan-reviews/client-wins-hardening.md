---
branch: client-wins-hardening
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/a29e8f8075a0-review.md
---

# Plan-review record — client-wins-hardening (§4.12)

Two logical changes on this branch:
- **logUrine sync routing** (diagnose b6d3f9, account) — `logUrine` fired
  `syncNutritionData()` (which only pushes `water_ml_`/nutrition rows), so the
  healthBox `urine_color_<date>` row never synced per-mutation. Now fires the
  dedicated `pushUrineColorLogsForSyncDomain()`.
- **rank copy truthfulness** (diagnose f1a9d3, platform — OBS-1) — the induction
  pledge + promotion ceremony promised rank on a workout count; the engine gates
  on time + consistency only. Copy rewritten truthful (framing B). **Engine
  UNCHANGED** per founder directive.

## Round 1 — domain + ground-truth verification (pre-implementation)
Every claim was verified writer→reader by file:line against live code, not memory:
- logUrine: read `health_write_service.dart` (writes `urine_color_` to healthBox),
  `sync_nutrition.dart:286-311` (`_syncWaterLogs` reads ONLY `water_ml_`),
  `sync_health.dart:256-281/478` (`_syncUrineColorLogs` is the real urine push) —
  confirmed the routing bug + that sibling health writes use dedicated `*Now()`.
- rank copy: read `rank_ladder_data.dart` (kRankGates — `totalWorkoutsAtLeast`
  defined but NEVER set; gates are minWeeks + streak/completionRate) and
  `rank_service._humanGateText` (the engine already renders the honest gate) —
  confirmed the copy↔engine drift. Founder picked framing B; engine left untouched.

## Round 2 — review lenses
- **psychology-pass-fitness** on the induction pledge (copy is a key conversion +
  retention surface): caught the "Petty Officer by month three" over-promise →
  threaded under a conditional "Hold the line"; "guarantee" → "the contract";
  confirmed no dark pattern + Wardroom/Navy voice intact.
- **B-pass** (fresh context-blind Sonnet) over the full branch diff — see
  `docs/reviews/a29e8f8075a0-review.md`. 1 finding (P2 stale doc comment) fixed
  in-batch; all 5 lenses clean. Specifically verified the CRITICAL EF risk:
  `weeksHeld` is in scope in the new `ceremony_text.ts` branches (no
  ReferenceError on redeploy), and the rewritten contract tests match the new
  source (substring-safe across Dart literal line-wraps).

## Convergence
No open findings. The copy tests were flipped from PINNING the false "104
workouts" claim to GUARDING the truth (12/12 green). Engine confirmed unchanged.
Converged.

> Deploys gated (founder per-action): web push (induction copy) + an
> `evaluate-rank-promotions` EF redeploy (ceremony copy — shared-file change only
> takes effect on redeploy).
