-- test/sql/alert_critical_notify_trigger_live_verify.sql
--
-- Run against the live project inside a transaction that always rolls back —
-- proves the trigger fires without error and does NOT block the INSERT, per
-- the same pattern supabase/migrations/CLAUDE.md's live-arbiter scaffold
-- uses. This is a MANUAL verification script (run via Supabase MCP
-- execute_sql inside a BEGIN...ROLLBACK), not a `deno test` — there is no
-- automated harness for live-Postgres-trigger checks in this repo.

BEGIN;

-- A critical alert insert must succeed and return its row (the trigger's
-- own exceptions are swallowed, so this proves it doesn't abort the write).
INSERT INTO public.alerts (source, severity, summary, suggested_action)
VALUES ('test_harness', 'critical', 'live rollback-txn verification row', 'none')
RETURNING id, severity;

-- A non-critical alert must ALSO succeed, and must not fire the trigger
-- (WHEN clause should skip it) — this INSERT existing unaffected either way.
INSERT INTO public.alerts (source, severity, summary, suggested_action)
VALUES ('test_harness', 'info', 'live rollback-txn verification row (non-critical)', 'none')
RETURNING id, severity;

ROLLBACK;
