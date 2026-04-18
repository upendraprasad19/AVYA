-- supabase/migrations/027_create_coach_memory.sql
-- Creates coach_memory table for AI coach personalization (Layers 4 + 5).
-- One row per user. Backfilled from legacy user_preferences.coaching_notes.

CREATE TABLE IF NOT EXISTS public.coach_memory (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,

  -- Layer 5: Identity mirroring
  preferred_name        text,
  communication_style   text CHECK (communication_style IN ('hinglish','english','formal','casual')),
  humor_tolerance       text CHECK (humor_tolerance IN ('high','low','none')),
  depth_preference      text CHECK (depth_preference IN ('explanation_seeker','action_taker')),
  motivation_style      text CHECK (motivation_style IN ('tough_love','gentle','data_driven')),

  -- Layer 2: Behavioral (backfilled from existing extraction)
  injuries              jsonb DEFAULT '[]'::jsonb,
  food_preferences      jsonb DEFAULT '{}'::jsonb,
  equipment_notes       text,
  excuse_patterns       jsonb DEFAULT '[]'::jsonb,
  lifestyle             jsonb DEFAULT '{}'::jsonb,
  supplement_stack      jsonb DEFAULT '[]'::jsonb,
  peak_activity_hour    int CHECK (peak_activity_hour BETWEEN 0 AND 23),
  weak_day              text CHECK (weak_day IN ('mon','tue','wed','thu','fri','sat','sun')),
  cheat_day_pattern     text,

  -- Layer 4: Predictive signals
  dropout_risk_score        real CHECK (dropout_risk_score BETWEEN 0 AND 1),
  plateau_risk_score        real CHECK (plateau_risk_score BETWEEN 0 AND 1),
  pro_upgrade_probability   real CHECK (pro_upgrade_probability BETWEEN 0 AND 1),
  signals_computed_at       timestamptz,

  -- Operational
  last_proactive_type   text,
  last_extraction_at    timestamptz,
  consent_version       text DEFAULT 'v1',
  private_mode          boolean NOT NULL DEFAULT false,
  coach_notes           text,  -- free-form, NEVER used for training
  updated_at            timestamptz NOT NULL DEFAULT now()
);

-- Indexes for cron job iteration over active users.
CREATE INDEX IF NOT EXISTS idx_coach_memory_signals_computed_at
  ON public.coach_memory (signals_computed_at NULLS FIRST);

CREATE INDEX IF NOT EXISTS idx_coach_memory_dropout_risk
  ON public.coach_memory (dropout_risk_score DESC NULLS LAST);

-- RLS
ALTER TABLE public.coach_memory ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_read_own_coach_memory" ON public.coach_memory
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "users_update_own_coach_memory" ON public.coach_memory
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "users_insert_own_coach_memory" ON public.coach_memory
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Service role bypasses RLS automatically (used by Edge Functions).

-- Auto-update updated_at on any change.
CREATE OR REPLACE FUNCTION public.touch_coach_memory_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_coach_memory_touch
  BEFORE UPDATE ON public.coach_memory
  FOR EACH ROW EXECUTE FUNCTION public.touch_coach_memory_updated_at();

COMMENT ON TABLE public.coach_memory IS
  'AI coach personalization — identity mirroring + predictive signals. One row per user. coach_notes column is NEVER used as training data.';
