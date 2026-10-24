-- Intent: Add user_profile.equipment_exclusions (text[]) — the user's equipment-exclusion preference (items SUBTRACTED from their tier via the Edit-Profile "Customize" UI, ⑥ slice C1); activates B1's inert queryV4 exclusion filter.
-- Destructive?: no   -- pure additive column with a safe DEFAULT '{}'; existing rows backfill to an empty array
-- Rollback strategy: inline   -- reverse DDL commented at end
-- Linked diagnose-doc: n/a   -- feature (⑥ slice C1 equipment-exclusions activation), not a bug fix

-- text[] mirrors the `injuries` column type, but DEFAULT '{}' (empty) NOT
-- ARRAY['none'] — exclusions have no `none` sentinel (empty = exclude nothing).
-- Nullable; the client always writes a List, restore merges non-null, and
-- EquipmentVocab.fromProfile is crash-safe on null.
ALTER TABLE public.user_profile
  ADD COLUMN IF NOT EXISTS equipment_exclusions text[] DEFAULT '{}'::text[];

-- Rollback:
-- ALTER TABLE public.user_profile DROP COLUMN IF EXISTS equipment_exclusions;
