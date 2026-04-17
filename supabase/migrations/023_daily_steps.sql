-- Daily step history (F20).
--
-- Today: steps are read from Health Connect on each device and written to
-- Hive (`healthBox['step_<date>']`) but never synced to Supabase. Only the
-- current day's number reaches the cloud via `user_daily_snapshots` (for
-- AI context). A new device re-reads from Health Connect from its install
-- time, so pre-install step history is inaccessible.
--
-- This table durable-logs daily step totals. Enables the step sparkline to
-- survive device changes, and gives the AI coach longer-window trend data
-- than today's snapshot.
--
-- Plan reference: plan file Part 4 F20.

CREATE TABLE IF NOT EXISTS public.daily_steps (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date        date NOT NULL,
  steps       int NOT NULL,
  source      text,
    -- 'health_connect' | 'google_fit' | 'samsung_health' | 'manual'
  synced_at   timestamptz DEFAULT now(),
  created_at  timestamptz DEFAULT now()
);

-- One row per user per date — idempotent upserts from any device.
CREATE UNIQUE INDEX IF NOT EXISTS ux_daily_steps_user_date
  ON public.daily_steps(user_id, date);

-- Efficient trend queries (last N days).
CREATE INDEX IF NOT EXISTS idx_daily_steps_user_date_desc
  ON public.daily_steps(user_id, date DESC);

ALTER TABLE public.daily_steps ENABLE ROW LEVEL SECURITY;

CREATE POLICY "daily_steps_select_own" ON public.daily_steps
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "daily_steps_insert_own" ON public.daily_steps
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "daily_steps_update_own" ON public.daily_steps
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "daily_steps_delete_own" ON public.daily_steps
  FOR DELETE USING (auth.uid() = user_id);
