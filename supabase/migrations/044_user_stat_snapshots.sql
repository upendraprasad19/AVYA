-- Migration 044: user_stat_snapshots
-- APK Test #6 obs #6 + spec §9.5.1
--
-- Capture starting-stats snapshots at three trigger points:
--   1. onboarding (auto, zero-friction — single row per user)
--   2. promotion (auto, fired by RankService.evaluateAndPromote per new rank)
--   3. manual (user-initiated from Profile → Take Snapshot Now)
--
-- The oldest row (source='onboarding') is the user's "baseline" for
-- year-1 transformation comparisons. Diffs between any two rows fuel
-- the Reports → Progress Comparison surface and the navy-style
-- promotion-day celebration overlay.

CREATE TABLE public.user_stat_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  snapshot_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  source TEXT NOT NULL CHECK (source IN ('onboarding', 'promotion', 'manual')),
  rank_at_snapshot TEXT,                    -- e.g., 'SD1' if source='promotion' to LS
  weight_kg NUMERIC,
  body_fat_pct NUMERIC,
  height_cm NUMERIC,                        -- snapshot-time (rare to change)
  age_years INT,
  measurements JSONB,                       -- {chest, waist, arms_l, arms_r, thighs_l, thighs_r}
  photos JSONB,                             -- [{url, taken_at, angle}]
  avg_calories_7d INT,
  avg_protein_7d INT,
  avg_steps_7d INT,
  avg_sleep_hours_7d NUMERIC,
  plan_phase INT,
  plan_week INT,
  primary_goal TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_uss_user_snapshot_at
  ON public.user_stat_snapshots(user_id, snapshot_at DESC);

-- RLS: a user can read/write only their own snapshots.
ALTER TABLE public.user_stat_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY uss_self_read ON public.user_stat_snapshots
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY uss_self_insert ON public.user_stat_snapshots
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY uss_self_update ON public.user_stat_snapshots
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY uss_self_delete ON public.user_stat_snapshots
  FOR DELETE USING (auth.uid() = user_id);

COMMENT ON TABLE public.user_stat_snapshots IS
  'Starting-stats snapshots for transformation comparison. APK Test #6 obs #6.';
