-- APK Test #12.7 — Migration 050: dedup workout_templates and add UNIQUE(user_id, name).
--
-- Founder install of APK 12.6 surfaced 8 duplicate `workout_templates` rows
-- (Back Day A × 3, Leg Day A × 3, Push Day × 2) for a single user. All rows
-- carried identical (user_id, name, source='user', is_active=true, created_at)
-- but different UUIDs, indicating that `SyncService` retried the template
-- upsert with a fresh non-deterministic UUID on each call. With no UNIQUE
-- constraint, Postgres happily accepted every retry as a new row.
--
-- This migration:
--   1. Re-points dependent FK rows from `template_exercises`,
--      `scheduled_workouts`, and `workout_logs` to the keeper template
--      (oldest by created_at, with `id::text` as deterministic tiebreaker
--      when timestamps tie — they do, in production).
--   2. Deletes the dup template rows.
--   3. Adds UNIQUE (user_id, name) so future re-syncs become idempotent.
--
-- COMPANION CLIENT FIX (separate Agent A change in same APK Test #12.7 batch):
-- `sync_service.dart` must derive the cloud `workout_templates.id` from a
-- deterministic UUIDv5 over (user_id, type, lower(name)) — same namespace
-- pattern used for `user_custom_exercises` / `user_custom_foods` (see
-- migration 020). Without that client-side fix, this constraint will simply
-- start surfacing 23505 errors on every retry instead of silently
-- duplicating. The retries themselves are harmless (Hive write already
-- succeeded), but they pollute logs.
--
-- Idempotent: safe to re-run. The dedup CTE is bounded by HAVING COUNT(*) > 1
-- so a second run with no dups is a no-op. The constraint ADD uses
-- IF NOT EXISTS via DO block since Postgres lacks `ADD CONSTRAINT IF NOT EXISTS`.

BEGIN;

-- 1. Compute keepers per (user_id, name) — one row each, oldest first,
--    deterministic tiebreaker on id::text. Stored in a temp table so the
--    re-point + delete steps below see a consistent snapshot.
CREATE TEMP TABLE _wt_dedup_plan ON COMMIT DROP AS
WITH ranked AS (
  SELECT
    id,
    user_id,
    name,
    created_at,
    row_number() OVER (
      PARTITION BY user_id, name
      ORDER BY created_at ASC, id::text ASC
    ) AS rn
  FROM public.workout_templates
),
groups AS (
  SELECT user_id, name
  FROM public.workout_templates
  GROUP BY user_id, name
  HAVING COUNT(*) > 1
)
SELECT
  r.id           AS row_id,
  r.user_id,
  r.name,
  r.rn,
  -- Keeper id for this (user_id, name) group — the row with rn=1.
  (
    SELECT r2.id
    FROM ranked r2
    WHERE r2.user_id = r.user_id AND r2.name = r.name AND r2.rn = 1
  )              AS keeper_id
FROM ranked r
JOIN groups g ON g.user_id = r.user_id AND g.name = r.name;

-- 2. Re-point dependent FK rows from dups → keeper.
--    `template_exercises.template_id` (CASCADE FK).
UPDATE public.template_exercises te
SET template_id = p.keeper_id
FROM _wt_dedup_plan p
WHERE te.template_id = p.row_id
  AND p.rn > 1;

--    `scheduled_workouts.template_id` (NO ACTION FK).
UPDATE public.scheduled_workouts sw
SET template_id = p.keeper_id
FROM _wt_dedup_plan p
WHERE sw.template_id = p.row_id
  AND p.rn > 1;

--    `workout_logs.template_id` (NO ACTION FK).
UPDATE public.workout_logs wl
SET template_id = p.keeper_id
FROM _wt_dedup_plan p
WHERE wl.template_id = p.row_id
  AND p.rn > 1;

-- 3. Delete the dup templates (rn > 1).
DELETE FROM public.workout_templates wt
USING _wt_dedup_plan p
WHERE wt.id = p.row_id
  AND p.rn > 1;

-- 4. Add UNIQUE(user_id, name). Wrapped in DO block for idempotency.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workout_templates_user_id_name_key'
      AND conrelid = 'public.workout_templates'::regclass
  ) THEN
    ALTER TABLE public.workout_templates
      ADD CONSTRAINT workout_templates_user_id_name_key
      UNIQUE (user_id, name);
  END IF;
END
$$;

COMMIT;
