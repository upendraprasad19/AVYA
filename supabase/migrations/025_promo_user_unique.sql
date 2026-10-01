-- Migration 025 · 2026-04-18
-- Ensure each (promo code, user) pair can only be redeemed once.
--
-- Context: `promo_code_uses` audit trail lacked UNIQUE(code, user_id).
-- Without it, a user could re-redeem the same promo on successive
-- subscription upgrades (e.g. redeem MONSOON50 on monthly, cancel,
-- re-redeem on yearly). Promo economics assumed one-use-per-user.
--
-- Year-suffix policy going forward: marketing generates
-- INDEPENDENCEDAY2026, INDEPENDENCEDAY2027, etc. so a user who
-- redeemed last year's code is free to redeem next year's.
--
-- NOTE: this migration was applied live via MCP on 2026-04-18 under
-- the name `023_promo_user_unique`. Written here with an available
-- file-system index (025) to avoid clashing with `023_daily_steps.sql`
-- which already existed on disk. Safe to re-run — the ALTER is
-- idempotent via constraint name.

-- Dedupe any existing duplicates (keep the earliest)
DELETE FROM promo_code_uses p1
USING promo_code_uses p2
WHERE p1.code = p2.code
  AND p1.user_id = p2.user_id
  AND p1.used_at > p2.used_at;

-- Add the unique constraint (no-op if already present from the MCP run)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'promo_code_uses_code_user_unique'
  ) THEN
    ALTER TABLE promo_code_uses
      ADD CONSTRAINT promo_code_uses_code_user_unique UNIQUE (code, user_id);
  END IF;
END $$;
