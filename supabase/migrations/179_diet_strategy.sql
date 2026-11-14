-- Intent: Add user_profile.diet_strategy (text, NULL, CHECK balanced|low_carb|keto) so a PRO user's diet strategy (diet plan Unit 3a) survives a reinstall and reaches a second device.
-- Destructive?: no   -- single ADD COLUMN IF NOT EXISTS, NULLABLE, NO DEFAULT, plus a CHECK that every existing row (all NULL) passes. No row is rewritten, nothing is dropped.
-- Rollback strategy: inline   -- reverse DDL is at the end of this file (revert the client first)
-- Linked diagnose-doc: n/a

-- ─────────────────────────────────────────────────────────────────────
-- Diet plan Unit 3a (docs/plans/diet-strategy.md §3.10, founder decisions
-- 2026-11-14): Balanced (default), Low carb, Keto. PRO.
--
-- The column holds the user's CHOICE only. No target is stored for it: the
-- stored carbs_grams / fat_grams stay the Balanced split, and the client
-- applies the strategy when it READS targets (effectiveMacroTargets). No
-- server code reads this column in Unit 3a.
--
-- NULLABLE with NO DEFAULT: NULL and 'balanced' mean the same to every reader
-- (dietStrategyOf), and a DEFAULT would rewrite every row for nothing.
--
-- Writers: the client profile push (sync_profile.dart, a conditional entry
-- that is sent only with DietStrategyFlags on, and always as a canonical key,
-- so a stray local value can never fail this CHECK and with it the whole
-- profile upsert). Reader: _restoreUserProfile (bare select, merges every
-- non-null cloud key). RLS: user_profile has row-level policies only
-- (100_rls_initplan_select_wrap.sql), so no policy change.
--
-- DEPLOY ORDERING: apply BEFORE the 3a client merges. PostgREST rejects an
-- unknown column and the WHOLE profile upsert fails. 3a ships dark (nothing
-- writes the field until Unit 3b flips the flag), so applying early is free.
-- ─────────────────────────────────────────────────────────────────────

-- Never queue behind a long lock on a hot table (the same guard as 178).
SET lock_timeout = '5s';

ALTER TABLE public.user_profile
  ADD COLUMN IF NOT EXISTS diet_strategy text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'user_profile_diet_strategy_check'
      AND conrelid = 'public.user_profile'::regclass
  ) THEN
    ALTER TABLE public.user_profile
      ADD CONSTRAINT user_profile_diet_strategy_check
      CHECK (diet_strategy IS NULL
             OR diet_strategy IN ('balanced', 'low_carb', 'keto'));
  END IF;
END $$;

RESET lock_timeout;

COMMENT ON COLUMN public.user_profile.diet_strategy IS
  'Diet plan Unit 3a: the user''s diet strategy (balanced | low_carb | keto; NULL = balanced). PRO. The choice only: stored carbs_grams / fat_grams stay the Balanced split and the client applies the strategy at read time.';

-- ── Rollback (manual; revert the client first) ──────────────────────
-- ALTER TABLE public.user_profile DROP CONSTRAINT IF EXISTS user_profile_diet_strategy_check;
-- ALTER TABLE public.user_profile DROP COLUMN IF EXISTS diet_strategy;
