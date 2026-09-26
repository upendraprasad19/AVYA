-- test/sql/founder_metrics_ops_excludes_info_client_errors_live_verify.sql
--
-- R2-10 (telegram-admin-bot review round 2): verifies migration
-- 135_founder_metrics_ops_exclude_info_client_errors.sql's fix — that
-- founder_metrics_ops()'s client_errors_today count excludes error_code
-- ='info' rows, so a successful critical-alert dispatch (migration 134's
-- telemetry, which writes an 'info'-coded client_errors row on every
-- success) no longer inflates /status's "Client errors today" number.
--
-- Run against the live project inside a transaction that always rolls back,
-- same pattern as alert_critical_notify_trigger_live_verify.sql — a MANUAL
-- verification script (Supabase MCP execute_sql inside BEGIN...ROLLBACK),
-- not a `deno test`.

BEGIN;

-- Baseline: today's count before inserting anything new.
SELECT client_errors_today AS baseline_today
FROM public.founder_metrics_ops();

-- An 'info'-coded row (the shape migration 134's success-path telemetry
-- writes) must NOT move client_errors_today.
INSERT INTO public.client_errors (op_type, error_code, client_version, platform, created_at)
VALUES ('critical_alert_dispatched', 'info', 'test', 'test', now());

SELECT client_errors_today AS after_info_row
FROM public.founder_metrics_ops();
-- EXPECT: after_info_row = baseline_today (unchanged).

-- A real error-coded row MUST still move client_errors_today — proves the
-- fix excludes 'info' specifically, not client_errors_today counting as a
-- whole (the "did the mutation land, or does the assertion pass by design"
-- distinction CLAUDE.md §4.4 rule 21 requires).
INSERT INTO public.client_errors (op_type, error_code, client_version, platform, created_at)
VALUES ('sync_service_restore_op_timeout', 'minified:x', 'test', 'test', now());

SELECT client_errors_today AS after_real_error_row
FROM public.founder_metrics_ops();
-- EXPECT: after_real_error_row = baseline_today + 1.

-- And client_errors_7d (untouched by this migration, deliberately — the
-- finding scoped the fix to client_errors_today only) MUST include BOTH
-- rows just inserted, proving the fix did not accidentally narrow it too.
SELECT client_errors_7d AS after_both_rows_7d
FROM public.founder_metrics_ops();
-- EXPECT: after_both_rows_7d = (7d baseline, taken before this transaction) + 2.

ROLLBACK;

-- EXECUTED 2026-09-14 post-apply, inside a rolled-back transaction (CTEs
-- used to capture all five values in one round trip): baseline_today=4,
-- after_info_row=4 (unchanged — info row correctly excluded),
-- after_real_error_row=5 (baseline+1 — real error correctly counted),
-- baseline_7d=143, after_both_rows_7d=145 (+2 for both rows — 7d
-- deliberately untouched by the fix). All five values match expectation.
