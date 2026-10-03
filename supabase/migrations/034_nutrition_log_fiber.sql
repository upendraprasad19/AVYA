-- 034_nutrition_log_fiber.sql
-- Add total_fiber column to nutrition_logs so the Indian-audience AI coach
-- can reference the #1 macro gap (fiber) alongside calories / protein /
-- carbs / fat. Before this migration, the client wrote `total_fiber` to
-- every Hive `nlog_*` row but the Supabase projection dropped it — so it
-- never reached the cloud and `_getTodayNutrition()` in the coach
-- repository had no source of truth for fiber.
--
-- Additive and safe. Historical rows default to 0 — `nutrition_log_items`
-- (migration 003) has calories/protein/carbs/fat columns but NO fiber
-- column, so there's no server-side source to backfill from. Going
-- forward, new logs carry `total_fiber` from the Hive nlog_* row via
-- sync_service._syncNutritionLogs.

ALTER TABLE nutrition_logs ADD COLUMN IF NOT EXISTS total_fiber NUMERIC DEFAULT 0;

COMMENT ON COLUMN nutrition_logs.total_fiber IS
  'Fiber (g) — sum of per-item fiber from the Hive nutrition log. UI shows 0/30g target bar. Historical rows default to 0 (no backfill source exists — nutrition_log_items has no fiber column).';
