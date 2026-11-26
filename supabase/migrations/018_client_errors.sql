-- client_errors: structured sync failure telemetry from the Flutter app.
--
-- Written ONLY on dead-letter — after SyncQueue exhausts all retries for an
-- operation. Transient failures (retried and eventually succeeded) are NOT
-- logged here. Success stays silent.
--
-- Reference: docs/superpowers/specs/2026-04-17-sync-reliability.md Pillar D

CREATE TABLE public.client_errors (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  error_code      text NOT NULL,
    -- One of: NetworkError, AuthError, ValidationError, SchemaError,
    -- RateLimitError, UnknownError. Matches lib/core/services/sync_error.dart.
  error_message   text,
  op_type         text,
    -- e.g. 'upsert_user_profile', 'upsert_water_log', 'push_snapshot'.
    -- Used to diagnose which sync operation is failing systemically.
  retry_count     int DEFAULT 0,
  client_version  text NOT NULL,
    -- From package_info_plus so we can identify buggy client versions.
  platform        text NOT NULL,
    -- 'android' | 'ios' | 'web'
  created_at      timestamptz DEFAULT now()
);

-- Efficient lookups for the common admin queries:
--   "all errors from user X in last 7 days"
--   "trending error_code across all users"
CREATE INDEX idx_client_errors_user_created ON public.client_errors(user_id, created_at DESC);
CREATE INDEX idx_client_errors_code_created ON public.client_errors(error_code, created_at DESC);

ALTER TABLE public.client_errors ENABLE ROW LEVEL SECURITY;

-- Users can only insert their own rows (via log-client-error Edge Function).
CREATE POLICY "client_errors_insert_own" ON public.client_errors
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- No SELECT policy for regular users. Admin reads via service_role key only.
-- No UPDATE/DELETE — errors are append-only.
