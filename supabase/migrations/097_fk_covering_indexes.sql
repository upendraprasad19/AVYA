-- Intent: Add covering indexes for the 5 unindexed foreign keys (food_corrections.food_id, rank_promotions.rank_code, user_profile.current_rank_code, workout_logs.scheduled_workout_id, workout_logs.template_id) — clears the 5 `unindexed_foreign_keys` performance advisories; speeds FK validation, joins, and ON DELETE checks at scale. (OPT-C, cost-optimization audit 2026-06-28. The advisor's 17 "unused_index" findings were intentionally left untouched — "unused" is an unreliable signal on a near-empty pre-launch DB.)
-- Destructive?: no   -- additive indexes only; no data change, no behavior change
-- Rollback strategy: inline   -- reverse = DROP the 5 indexes (block at end of file)
-- Linked diagnose-doc: n/a   -- pure infra hygiene (FK index coverage)
-- ============================================================
-- OPT-C — FK covering indexes (branch: opt-quick-wins, 2026-06-28)
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_food_corrections_food_id
  ON public.food_corrections (food_id);

CREATE INDEX IF NOT EXISTS idx_rank_promotions_rank_code
  ON public.rank_promotions (rank_code);

CREATE INDEX IF NOT EXISTS idx_user_profile_current_rank_code
  ON public.user_profile (current_rank_code);

CREATE INDEX IF NOT EXISTS idx_workout_logs_scheduled_workout_id
  ON public.workout_logs (scheduled_workout_id);

CREATE INDEX IF NOT EXISTS idx_workout_logs_template_id
  ON public.workout_logs (template_id);

-- ── Rollback (inline) ──────────────────────────────────────
-- DROP INDEX IF EXISTS public.idx_food_corrections_food_id;
-- DROP INDEX IF EXISTS public.idx_rank_promotions_rank_code;
-- DROP INDEX IF EXISTS public.idx_user_profile_current_rank_code;
-- DROP INDEX IF EXISTS public.idx_workout_logs_scheduled_workout_id;
-- DROP INDEX IF EXISTS public.idx_workout_logs_template_id;
