-- Nutrition target columns (F17).
--
-- `daily_calories`, `protein_grams`, `carbs_grams`, `fat_grams`, `water_target_ml`
-- are computed at onboarding from BMR/TDEE/goal/pace and stored only in Hive
-- today. On re-login or new-device restore, the client recomputes from the
-- same inputs — which works IF the BMR formula is stable. If we tweak the
-- formula, existing users get silently different numbers than they had before.
--
-- Syncing these five computed values to Supabase gives us:
--   1. A durable record of the targets the user is actually operating against
--   2. A restore path that produces the same numbers regardless of client version
--   3. Admin visibility into outliers (e.g. users with 0 daily_calories)
--
-- Plan reference: plan file Part 4 F17.

ALTER TABLE public.user_profile
  ADD COLUMN IF NOT EXISTS daily_calories    int,
  ADD COLUMN IF NOT EXISTS protein_grams     int,
  ADD COLUMN IF NOT EXISTS carbs_grams       int,
  ADD COLUMN IF NOT EXISTS fat_grams         int,
  ADD COLUMN IF NOT EXISTS water_target_ml   int;

COMMENT ON COLUMN public.user_profile.daily_calories IS
  'Computed TDEE +/- deficit/surplus based on goal + pace_preference. Written at onboarding; re-written on profile edits that change inputs.';
COMMENT ON COLUMN public.user_profile.protein_grams IS
  'Target daily protein in grams. Derived from body weight and goal (e.g., 2g/kg for build_muscle).';
COMMENT ON COLUMN public.user_profile.carbs_grams IS
  'Target daily carbohydrate in grams. Derived after protein + fat allocated from daily_calories.';
COMMENT ON COLUMN public.user_profile.fat_grams IS
  'Target daily fat in grams. Typically 0.8-1.0g/kg body weight.';
COMMENT ON COLUMN public.user_profile.water_target_ml IS
  'Target daily water in ml. Usually body_weight_kg * 35.';
