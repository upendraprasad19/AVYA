-- 042_coach_memory_induction.sql
-- Adds induction-related columns to coach_memory.
-- Source of truth: docs/superpowers/specs/2026-04-27-ai-coach-brilliance-design.md §9.

ALTER TABLE coach_memory
  ADD COLUMN IF NOT EXISTS committed_at          TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS committed_to_lt_cdr   BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS induction_completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS why_now               TEXT,
  ADD COLUMN IF NOT EXISTS definition_of_winning TEXT,
  ADD COLUMN IF NOT EXISTS known_injuries        TEXT[],
  ADD COLUMN IF NOT EXISTS typical_wake_time     TEXT,
  ADD COLUMN IF NOT EXISTS preferred_workout_time TEXT,
  ADD COLUMN IF NOT EXISTS body_part_priorities  TEXT[];

COMMENT ON COLUMN coach_memory.committed_at IS
  'When the user tapped I COMMIT on the induction Lt Cdr contract.';
COMMENT ON COLUMN coach_memory.committed_to_lt_cdr IS
  'True after first contract acceptance. Never reset to false.';
COMMENT ON COLUMN coach_memory.induction_completed_at IS
  'When user finished the 5-question muster. Idempotency check key.';
