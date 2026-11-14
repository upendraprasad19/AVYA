# Rank Rebalance + Lt — Smoke Verification

**Branch:** `feat/apk-test-6-batch`
**Plan:** G (rank ladder rebalance + Lt insertion)
**Date:** 2026-05-01

## Spec §12 success criteria coverage

| # | Criterion | Verifier |
|---|---|---|
| **C21** | Roadmap labels read "WEEK 156" — no ambiguous "W156" | `test/widgets/roadmap_label_test.dart` (G-11) |
| **C22** | Lt rank between SubLt and LtCdr at ordinal 7; insignia (2 thick stripes) renders | `test/rank_service/lt_inserted_at_ordinal_7_test.dart` (G-2); insignia widget delivered by Plan D — covered in `WardRankInsignia` golden tests |
| **C23** | SD2 → SD1 promotion requires 7 consecutive completed scheduled workouts AND ≥1 week elapsed | `test/rank_service/sd1_wed_joiner_unlocks_day_8_test.dart` (G-7); negative cases for 6-streak and 0-week elapsed |
| **C24** | All dates/times derive from IST; daily counter reset fires at IST 00:00 | `test/workout_repository/completion_rate_over_window_test.dart` IST-aware date math (G-4); broader IST coverage delivered cross-plan |

## Files touched

- `lib/core/services/rank_ladder_data.dart` — RankGate fields + 11-rung ladder + rebalanced gates
- `lib/core/services/rank_service.dart` — `_qualifies` + `_EvalState` extended for completion rate + `testQualify`
- `lib/shared/repositories/workout_repository.dart` — `completionRateOverWindow` + streak audit
- `lib/features/train/screens/phase_roadmap_screen.dart` — label disambiguation (`W` → `WEEK`) + Lt marker added
- `supabase/functions/_shared/rank_engine.ts` — server mirror with `kRankLadder` + `kRankGates` + `qualifies` (async) + `completionRateOverWindow`
- `supabase/functions/evaluate-rank-promotions/index.ts` — wired to new EvalState shape
- `supabase/migrations/045_lt_rank_addition.sql` — Postgres mirror
- 9 new test files under `test/rank_service/`, `test/workout_repository/`, `test/widgets/`

## Server deploy

- `evaluate-rank-promotions` deployed via `.claude/deploy_via_api.js` (G-10).
  HTTP 201, version 3 ACTIVE,
  `ezbr_sha256=3fe2fc7c7b5a9a548e19dfa72efe429517bae463858c023ed9d1ad6d9291ca56`.
  Cron continues firing 18:30 UTC nightly; first cron firing post-deploy
  uses the rebalanced ladder.

## Database state

Migration 045 applied to prod via MCP `apply_migration`. Verified via
`SELECT rank_code, ordinal, short_name, min_weeks, category, is_terminal
FROM public.rank_ladder ORDER BY ordinal;` — 11 rows, ordinals 0..10
dense, Lt at ordinal 7 (`min_weeks=130`, `LIEUTENANT`, officer), Capt
terminal at ordinal 10. Note: column is `rank_code` (the canonical
project schema) — the plan's draft SQL using `code` was corrected
in-flight before `apply_migration`.

## Test summary

`flutter test test/rank_service/ test/workout_repository/
test/widgets/roadmap_label_test.dart` — 37 tests, all passing.

`flutter analyze lib/core/services/ lib/shared/repositories/
lib/features/train/screens/` — 0 errors. 2 pre-existing
`use_null_aware_elements` info hints in `sync_service.dart` and
`workout_write_service.dart`, untouched by this batch.

## Open follow-ups

- `lt.svg` insignia asset + `WardRankInsignia` Lt painter — handled in Plan D.
- Promotion celebration overlay rendering when a user crosses the new Lt
  gate — handled in Plan F (starting stats system + promotion-day overlay).
- Cache for `completionRateOverWindow` (per spec §11.2 risk register) —
  defer until first scaling pain; current implementation walks ≤ 728 keys
  (104 weeks × 7 days) which is bounded.
