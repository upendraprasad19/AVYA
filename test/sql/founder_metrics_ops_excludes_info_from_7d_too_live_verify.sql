-- test/sql/founder_metrics_ops_excludes_info_from_7d_too_live_verify.sql
--
-- F1 (telegram-admin-bot Hermes pass 2026-09-14, corroborated by L1/L22/L35):
-- verifies migration 136_founder_metrics_ops_exclude_info_client_errors_7d
-- .sql's fix — that founder_metrics_ops()'s client_errors_7d count excludes
-- error_code='info' rows, the same way migration 135 already fixed
-- client_errors_today. Migration 134's success-path telemetry writes an
-- 'info'-coded client_errors row on every successful critical-alert
-- dispatch, which inflates client_errors_7d exactly as it used to inflate
-- client_errors_today before 135.
--
-- Run against the live project inside a transaction that always rolls
-- back, following the same pattern as
-- founder_metrics_ops_excludes_info_client_errors_live_verify.sql (manual
-- verification via Supabase MCP execute_sql — not a `deno test`).

BEGIN;

-- Baseline: 7d count before inserting anything new.
SELECT client_errors_7d AS baseline_7d
FROM public.founder_metrics_ops();

-- An 'info'-coded row (the shape migration 134's success-path telemetry
-- writes) must NOT move client_errors_7d.
INSERT INTO public.client_errors (op_type, error_code, client_version, platform, created_at)
VALUES ('critical_alert_dispatched', 'info', 'test', 'test', now());

SELECT client_errors_7d AS after_info_row
FROM public.founder_metrics_ops();
-- EXPECT: after_info_row = baseline_7d (unchanged).

-- A real error-coded row MUST still move client_errors_7d — proves the fix
-- excludes 'info' specifically, not client_errors_7d counting as a whole
-- (the "did the mutation land, or does the assertion pass by design"
-- distinction CLAUDE.md §4.4 rule 21 requires).
INSERT INTO public.client_errors (op_type, error_code, client_version, platform, created_at)
VALUES ('sync_service_restore_op_timeout', 'minified:x', 'test', 'test', now());

SELECT client_errors_7d AS after_real_error_row
FROM public.founder_metrics_ops();
-- EXPECT: after_real_error_row = baseline_7d + 1.

-- And client_errors_today (already fixed by 135, untouched by this
-- migration) must still correctly exclude the 'info' row but count the real
-- error row — proves 136 did not regress 135's fix.
SELECT client_errors_today AS today_after_both_rows
FROM public.founder_metrics_ops();
-- EXPECT: today_after_both_rows = (today baseline, taken before this
-- transaction) + 1 (only the real-error row counts; the info row stays
-- excluded, same as before).

ROLLBACK;

-- EXECUTED 2026-09-14 post-apply, inside a rolled-back transaction (CTEs
-- used to capture all five values in one round trip): baseline_7d=140,
-- baseline_today=4, after_info_row=140 (unchanged — info row correctly
-- excluded), after_real_error_row=141 (baseline+1 — real error correctly
-- counted), today_after_both_rows=5 (baseline_today+1 — 135's earlier
-- fix to client_errors_today unregressed by this migration). All five
-- values match expectation.
