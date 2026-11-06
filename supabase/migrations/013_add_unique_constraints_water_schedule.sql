-- ============================================================
-- Migration 013: Add UNIQUE constraints for water_logs and scheduled_workouts
--
-- Problem: sync_service.dart upserts on (user_id, date) and (user_id, scheduled_date)
-- but neither table has the corresponding UNIQUE constraint, causing upserts to fail.
-- ============================================================

-- 1. Deduplicate existing water_logs rows
-- Keep the one with latest updated_at per (user_id, date), delete the rest
DELETE FROM water_logs
WHERE id NOT IN (
  SELECT DISTINCT ON (user_id, date) id
  FROM water_logs
  ORDER BY user_id, date, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
);

-- 2. Add UNIQUE constraint on water_logs(user_id, date)
ALTER TABLE water_logs
  ADD CONSTRAINT uq_water_logs_user_date UNIQUE (user_id, date);

-- 3. Deduplicate existing scheduled_workouts rows
-- Keep the one with latest created_at per (user_id, scheduled_date), delete the rest
DELETE FROM scheduled_workouts
WHERE id NOT IN (
  SELECT DISTINCT ON (user_id, scheduled_date) id
  FROM scheduled_workouts
  ORDER BY user_id, scheduled_date, created_at DESC NULLS LAST
);

-- 4. Add UNIQUE constraint on scheduled_workouts(user_id, scheduled_date)
ALTER TABLE scheduled_workouts
  ADD CONSTRAINT uq_scheduled_workouts_user_date UNIQUE (user_id, scheduled_date);
