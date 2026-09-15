-- Intent: Create readiness_daily (⑥ Batch 6 6-C) — cloud-durable daily readiness check-in (Sleep/Soreness/Energy → Green/Yellow/Red level) so the W2.3 check-in + the W3.7 PRO trend survive reinstall / a new device.
-- Destructive?: no   -- pure new table; no existing rows touched
-- Rollback strategy: inline   -- reverse DDL commented at end
-- Linked diagnose-doc: n/a   -- feature (⑥ Batch 6 6-C readiness cloud durability), not a bug fix

-- One row per (user, IST date). The composite PRIMARY KEY is the ON CONFLICT
-- arbiter for the client upsert `onConflict: 'user_id,date'` — a NON-partial
-- unique constraint over two NOT NULL columns, so no 42P10 partial-arbiter trap
-- (feedback_partial_unique_arbiter_trap). `created_at` is REQUIRED — the restore
-- reads via sync_service._fetchAllRows whose default orderBy/since column is
-- `created_at` (R2a P1-C: without it → 42703 undefined_column → silent no-restore).
CREATE TABLE IF NOT EXISTS public.readiness_daily (
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date       date NOT NULL,
  sleep      smallint,
  soreness   smallint,
  energy     smallint,
  level      text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, date)
);

-- Own-rows RLS (mirrors sleep_logs / weight_logs — a synced user-data table).
-- Without this, any authenticated JWT could read/write any user's readiness via
-- PostgREST (R2a P0-B).
ALTER TABLE public.readiness_daily ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users_own_readiness_daily" ON public.readiness_daily
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Supports the restore query (created_at-ordered, user-scoped).
CREATE INDEX IF NOT EXISTS idx_readiness_daily_user_created
  ON public.readiness_daily (user_id, created_at);

-- Rollback:
-- DROP TABLE IF EXISTS public.readiness_daily;
