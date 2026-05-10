# Skipped discipline log (append-only)

Every entry is a `regression-test-skipped:` waiver from a `fix:`/`bug:`/`regression:` commit. Each row: timestamp · commit-SHA · reason.

- 2026-05-11 · `<sha-tbd-053>` · SQL-only migration (053_security_definer_hardening); pre/post-state verified via MCP and recorded in `docs/diagnoses/2026-05-11-secdef-hardening-7ad035.md`. Future re-grants of EXECUTE to anon would be caught by the Supabase `anon_security_definer_function_executable` advisor.
- 2026-05-11 · `<sha-tbd-054>` · SQL-only RLS-policy migration (054_rls_policy_cleanup) closing H-30 + H-40; pre/post state captured in `docs/diagnoses/2026-05-11-rls-cleanup-7ad054.md`. The `WITH CHECK (false)` policy on promo_code_uses is itself the regression test — any future authenticated INSERT fails at runtime.
