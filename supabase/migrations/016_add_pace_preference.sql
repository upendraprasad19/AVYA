-- Bug #24 — pace preference column for user_profile.
--
-- Tracks weekly body-weight change rate preference used by the BMR calculator
-- and goal projection UI. Defaults to 'balanced' (0.5% BW/week) which is the
-- evidence-based sweet spot. CHECK constraint ensures values stay in the
-- three-option set the Flutter UI exposes.

ALTER TABLE public.user_profile
  ADD COLUMN IF NOT EXISTS pace_preference text NOT NULL DEFAULT 'balanced'
  CHECK (pace_preference IN ('slow', 'balanced', 'aggressive'));

COMMENT ON COLUMN public.user_profile.pace_preference IS
  'Bug #24 — weekly body-weight change rate preference. slow=0.25%, balanced=0.5%, aggressive=0.75% BW/week. Used for kcal delta derivation in BmrCalculator.calculateTargets and goal date projection in BmrCalculator.projectGoalDate.';
