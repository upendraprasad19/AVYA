-- Intent: Add user_profile.diet_supplements (boolean, NULL) so a PRO user's Supplements opt-in (diet plan Unit 4a) survives a reinstall and reaches a second device.
-- Destructive?: no   -- single ADD COLUMN IF NOT EXISTS, NULLABLE, NO DEFAULT. No row is rewritten, nothing is dropped.
-- Rollback strategy: inline   -- reverse DDL is at the end of this file (revert the client first)
-- Linked diagnose-doc: n/a

-- ─────────────────────────────────────────────────────────────────────
-- Diet plan Unit 4a (docs/plans/diet-supplements.md section 2, founder spec
-- 2026-11-14): an opt-in "Supplements" switch on the Diet Plan screen (PRO,
-- adults only): a protein shake in the plan and a daily supplement card.
--
-- The column holds the user's CHOICE only. Whether Supplements are ACTIVE is
-- decided on the client (flag AND PRO AND this value true AND age 18 or more)
-- and reaches the coach as snapshot.profile.diet_supplements; no server code
-- reads this column.
--
-- NULLABLE with NO DEFAULT: NULL and false mean the same to every reader, and
-- a DEFAULT would rewrite every row for nothing. A plain boolean has no value
-- to CHECK, so no constraint.
--
-- Writers: the client profile push (sync_profile.dart, a conditional entry
-- that pushes a stored bool, false included, because a restore merge ignores
-- a cloud NULL). Reader: _restoreUserProfile (bare select, merges every
-- non-null cloud key). RLS: user_profile has row-level policies only
-- (100_rls_initplan_select_wrap.sql), so no policy change.
--
-- DEPLOY ORDERING: apply BEFORE the 4a client merges. PostgREST rejects an
-- unknown column and the WHOLE profile upsert fails. The push entry sends the
-- key only for a user whose local profile holds a bool, which only the
-- Supplements switch writes, so applying early is free.
-- ─────────────────────────────────────────────────────────────────────

-- Never queue behind a long lock on a hot table (the same guard as 179).
SET lock_timeout = '5s';

ALTER TABLE public.user_profile
  ADD COLUMN IF NOT EXISTS diet_supplements boolean;

RESET lock_timeout;

COMMENT ON COLUMN public.user_profile.diet_supplements IS
  'Diet plan Unit 4a: the user''s Supplements opt-in (true = on; NULL or false = off). PRO, adults only. The choice only: whether Supplements are active is decided on the client and reaches the coach as snapshot.profile.diet_supplements.';

-- Rollback (revert the client first):
--   ALTER TABLE public.user_profile DROP COLUMN IF EXISTS diet_supplements;  (the COMMENT goes with it)
