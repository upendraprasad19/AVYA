-- Intent: Add user_progress.streak_freezes_first_pro_grant_done so the first-ever PRO upgrade grants an instant 3 freezes exactly once per account (never on boot-refresh or renewal), with a backfill marking every ever-PRO/has-subscription user already-granted so no existing user is phantom-granted on next launch.
-- Destructive?: no   -- additive column with DEFAULT false; backfill is forward-only
-- Rollback strategy: inline   -- reverse DDL at end of file
-- Linked diagnose-doc: f9d2e7
-- ============================================================
-- Phase 2 Unit C — first-PRO instant-3 freeze grant
-- (branch: discipline-overhaul, 2026-06-18)
-- ============================================================

-- 1. Add the flag column.
ALTER TABLE public.user_progress
  ADD COLUMN streak_freezes_first_pro_grant_done boolean NOT NULL DEFAULT false;

-- 2. Backfill: mark every user who has EVER had a non-free
--    subscription as already granted so their next boot doesn't
--    phantom-grant 3 freezes.
--    Covers two evidence sources:
--      (a) users.subscription_status — set to a non-free value by
--          the Razorpay webhook / referral grant at activation.
--      (b) subscriptions table — any row at all means a payment or
--          referral trial was recorded, even if the status column
--          was later rolled back to null.
UPDATE public.user_progress up
SET    streak_freezes_first_pro_grant_done = true
WHERE  up.user_id IN (
         SELECT id
         FROM   public.users
         WHERE  subscription_status IS NOT NULL
           AND  subscription_status <> 'free'
       )
   OR  up.user_id IN (
         SELECT DISTINCT user_id
         FROM   public.subscriptions
       );

-- 3. Cover ever-PRO users who have NO user_progress row yet (e.g. went PRO
--    before logging any workout). The UPDATE above only touches EXISTING rows,
--    so without this such a user is left at the column DEFAULT (false) and gets
--    phantom-granted 3 freezes — and any freezes they later spend get refunded —
--    on a reinstall (B-pass Finding 3, f9d2e7). Every NOT NULL column except
--    user_id has a DEFAULT, so this minimal insert is safe; user_id has a UNIQUE
--    index (the syncFreezes onConflict:'user_id' target), so ON CONFLICT is valid.
INSERT INTO public.user_progress (user_id, streak_freezes_first_pro_grant_done)
SELECT u.id, true
FROM   public.users u
WHERE  u.subscription_status IS NOT NULL
  AND  u.subscription_status <> 'free'
  AND  NOT EXISTS (SELECT 1 FROM public.user_progress up WHERE up.user_id = u.id)
UNION
SELECT DISTINCT s.user_id, true
FROM   public.subscriptions s
WHERE  s.user_id IS NOT NULL
  AND  NOT EXISTS (SELECT 1 FROM public.user_progress up WHERE up.user_id = s.user_id)
ON CONFLICT DO NOTHING;

-- ── Rollback (inline) ──────────────────────────────────────
-- ALTER TABLE public.user_progress
--   DROP COLUMN streak_freezes_first_pro_grant_done;
