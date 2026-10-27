-- Intent: Restore idx_nutrition_log_items_food_id, dropped by migration 141 on the
--   basis of idx_scan=0 without checking that it was the SOLE index backing the
--   nutrition_log_items_food_id_fkey foreign key -- a regression on the exact axis
--   (DB resource pressure) migration 141 exists to fix, caught by a self-triggered
--   B-pass review before commit.
-- Destructive?: no -- pure CREATE INDEX, no data touched, no rows read/written/deleted
-- Rollback strategy: inline -- see commented block at end of file
-- Linked diagnose-doc: e8b4a1

-- Verified live (2026-09-22): after migration 141 dropped this index, pg_indexes
-- showed food_id had ZERO index coverage on nutrition_log_items (confirmed via
-- pg_constraint + pg_indexes), and get_advisors newly flagged an
-- "unindexed_foreign_keys" finding that did not exist before 141. idx_scan=0
-- measures QUERY access paths only -- it says nothing about whether an index
-- backs a foreign key, which Postgres uses for referential-integrity checks on
-- the REFERENCED table's side (DELETE/UPDATE on food_database.id) regardless of
-- whether any SELECT ever used it directly.
--
-- The sibling drop in the same migration (idx_ai_coach_interactions_tool_calls_failed)
-- was independently re-verified live and does NOT back any FK on
-- ai_coach_interactions (its two FKs -- snapshot_id, user_id -- both have their
-- own separate, still-live indexes). This is an isolated fix for one dropped
-- index, not evidence the other drop needs revisiting.

CREATE INDEX IF NOT EXISTS idx_nutrition_log_items_food_id
  ON public.nutrition_log_items
  USING btree (food_id);

-- Rollback (commented):
-- DROP INDEX IF EXISTS public.idx_nutrition_log_items_food_id;
