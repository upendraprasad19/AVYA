---
branch: fix-ai-snapshot-drift
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/ai-snapshot-drift-bpass.md
---

# Plan-review record — fix-ai-snapshot-drift (AI chat snapshot target drift)

§4.12 plan-review record for the founder-directed AI-chat fix (2026-06-26): "investigate
first and then fix all issues in AI chat. no defer. use discipline." Account-tier
(ai_coach), client-side only — NO Edge Function deploy (the corrected snapshot propagates
to the cron read surface via `pushSnapshot`).

**Diagnose:** `docs/diagnoses/2026-06-26-ai-snapshot-target-drift-f3c8d1.md`.

## Reviews (independent, context-blind) — 2 rounds
- **R1 — Opus field-by-field audit** of every `buildAiContext` emit vs the canonical
  writer/source. Surfaced 5 drifts: `daily_calorie_target`=tdee (P0), `daily_targets.protein`
  =phantom→0 (P0), `current_streak_days`=weeks*7 (P1), `daily_targets` missing carbs/fat (P2),
  `planned_this_week` travel-day inflation (P2). Verified the canonical field names against
  `BmrCalculator.toMap` + traced the 3 cron consumers. NOTE: the R1 audit ALSO mis-claimed
  planned_this_week "counts a no-writer type==workout → always 0" — an ERROR (the plan writer
  DOES stamp type:'workout', workout_schedule_read_service.dart:160). The first fix attempt
  acted on it (scanned schedule_* by type!=rest/off) and FAILED two gates (hive_key_contracts
  contract test + reader-manifest); reverted to the canonical type=='workout' count + travel
  exclusion. The gates caught the bad fix before merge — see diagnose f3c8d1 Notes.
- **R2 — Sonnet B-pass** on the implementation (6 lenses). Found 1 P1 (travel-status days
  inflate planned_this_week — `swap_service:431` keeps the type) + 3 P2 test-coverage gaps
  (travel case, both fallback paths). ALL fixed in-batch. Verified canonical names + cron
  non-regression CLEAN. Record: `docs/reviews/ai-snapshot-drift-bpass.md`.

## Ground-truth audit (verified, not asserted)
Read `ai_snapshot_builder.dart` (buildAiContext + _getThisWeekWorkouts), `bmr_calculator.dart`
(toMap emit set), `swap_service.dart:416-447` (travel writes status:'travel', keeps type),
`workout_repository.dart:336/425` (streak rest/off filter — mirrored), and the cron readers
`morning-alert/index.ts:149/157` + `protein-gap-alert/index.ts:140/177` (primary = cloud
`protein_grams`, snapshot is a defensive fallback). Confirmed: no EF change needed.

## Verdict
**Converged.** 2 P0 + 1 P1 + 2 P2 (the field drifts) fixed; the B-pass's P1 (travel) + 3 P2
(test gaps) fixed. Behavioral tests (Hive harness + buildAiContext) pin every field reads the
canonical, the real streak, the schedule-derived planned count (travel excluded), and both
fallback paths. analyze clean; snapshot-contract gate green.

**bpass: accepted** — `docs/reviews/ai-snapshot-drift-bpass.md`.
