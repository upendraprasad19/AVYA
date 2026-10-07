---
reviewed_at: 2026-06-26T01:30:00+05:30
staged_against: fix-ai-snapshot-drift (ai_snapshot_builder.dart + ai_snapshot_builder_only_test.dart)
blast_radius: account
reviewer: claude-opus-field-audit + claude-sonnet-bpass
lens_set: [writer_reader_drift, cron_regression, schedule_semantics, null_safety, snapshot_size, test_quality]
findings_count: 4
verdict: accepted
---

# Code review — fix-ai-snapshot-drift (AI snapshot target/streak/plan drift, f3c8d1)

Two independent context-blind passes: (R1) an Opus field-by-field audit of every
`buildAiContext` emit vs the canonical writer — surfaced the 5 drifts; (R2) a fresh
Sonnet B-pass on the implementation. All findings resolved in-batch.

## R2 (B-pass) findings
### Finding 1 — P1 — schedule_semantics — ACCEPTED → FIXED
- `ai_snapshot_builder.dart` planned_this_week loop: travel-mode days
  (`swap_service.activateTravelMode:431` writes `status:'travel'` but KEEPS the
  workout `type`) would be counted as planned gym workouts → inflated count.
- **Fix:** the `isWorkoutDay` filter now also requires `status != 'travel'`.
  Pinned by a new test case (travel day → excluded, planned stays 3).

### Finding 2 — P2 — test_quality — ACCEPTED → FIXED
- planned_this_week test had no travel case. Added (`schedule_<dk4>` type PUSH
  status travel → asserted excluded).

### Finding 3 — P2 — test_quality — ACCEPTED → FIXED
- `current_streak_days` weeks*7 FALLBACK (absent real field) uncovered. Added a
  test seeding only `current_streak_weeks:3` → asserts 21.

### Finding 4 — P2 — test_quality — ACCEPTED → FIXED
- `daily_calorie_target` tdee FALLBACK (absent `daily_calories`) uncovered. Added
  a test seeding only `tdee:2400` → asserts 2400.

## Clean (verified by both passes)
- **Canonical field names:** `BmrCalculator.toMap` writes exactly `daily_calories`,
  `protein_grams`, `carb_grams`/`carbs_grams`, `fat_grams`; the snapshot now reads
  those (carbs dual-name). `protein_g_target`/`protein_target_g` confirmed phantom.
- **Cron regression — NONE:** morning-alert (`daily_calorie_target` proximity check,
  `current_streak_days` milestones) is made MORE correct; protein-gap-alert primary is
  cloud `protein_grams` (snapshot fallback only) so unaffected; streak-guardian has its
  own weeks*7 fallback. No EF threshold breaks. No EF deploy required.
- **Null-safety:** all reads `as num?` + `??` fallbacks; no new throw/null.
- **Snapshot size:** +3 doubles in `daily_targets` (~60 bytes) — within the ~9.5K
  budget; `_compactContext` trim order unaffected. Snapshot-contract gate green.
- **planned date derivation:** `keyStr.substring('schedule_'.length)` extracts the
  ISO date; string range-compare correct.

## Verdict
**accepted** — 1 P1 + 3 P2 fixed in-batch; no P0; canonical names + cron compatibility
verified. Client-side only (no EF deploy).
