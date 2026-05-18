-- Migration 072 — APK Test #16.2 Bug f8c1a5 Layer 4
--
-- Clamp existing `user_progress.streak_freezes_available` rows to the
-- absolute tier max (3), then add a CHECK constraint that prevents any
-- future write from producing an out-of-range value.
--
-- Why
-- ---
-- Founder's prod row showed `streak_freezes_available = 8` rendered as
-- "8/3" on the streak badge. `StreakProgressService.commitRefill` clamps
-- on write, but a legacy code path or direct write produced a value
-- above the cap before clamping was added. The Monday refill was
-- idempotency-gated by an already-set `streak_freezes_last_refill`, so
-- the corrupted value parked itself indefinitely.
--
-- Layers 1-3 on the client (read-side clamp, one-shot
-- StreakFreezeClampMigrator, restore-path clamp) hide and repair the
-- value on every device. This server-side CHECK is the durable
-- prevention — no client path, no admin SQL, and no future
-- backfill can re-introduce an out-of-range value silently.
--
-- Safety: idempotent. The CHECK is dropped if it already exists before
-- being re-added (Postgres has no IF NOT EXISTS for ADD CONSTRAINT). The
-- UPDATE is a no-op for rows already in range.

BEGIN;

-- Step 1 — one-shot backfill of out-of-range rows. Cap is 3 (PRO tier
-- max). Free-tier users with corrupted 3 stay at 3 server-side; the
-- client's tier-aware read-clamp narrows display to 1.
UPDATE public.user_progress
SET streak_freezes_available = 3
WHERE streak_freezes_available > 3;

UPDATE public.user_progress
SET streak_freezes_available = 0
WHERE streak_freezes_available < 0;

-- Step 2 — drop the constraint if it exists, then re-add. Both
-- constraint name + the literal SQL are kept stable for grep-ability.
ALTER TABLE public.user_progress
  DROP CONSTRAINT IF EXISTS user_progress_streak_freezes_available_range;

ALTER TABLE public.user_progress
  ADD CONSTRAINT user_progress_streak_freezes_available_range
  CHECK (
    streak_freezes_available IS NULL
    OR (streak_freezes_available BETWEEN 0 AND 3)
  );

COMMIT;
