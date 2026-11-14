-- Add plan_json column to user_progress.
-- This column already exists in the live DB (added manually via dashboard)
-- but was never codified in a migration file.
ALTER TABLE user_progress ADD COLUMN IF NOT EXISTS plan_json jsonb;
