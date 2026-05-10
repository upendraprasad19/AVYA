# Skipped discipline log (append-only)

Every entry is a `regression-test-skipped:` waiver from a `fix:`/`bug:`/`regression:` commit. Each row: timestamp · commit-SHA · reason.

- 2026-05-11 · `<sha-tbd-053>` · SQL-only migration (053_security_definer_hardening); pre/post-state verified via MCP and recorded in `docs/diagnoses/2026-05-11-audit-h35-h36-h37-secdef-hardening.md`. Future re-grants of EXECUTE to anon would be caught by the Supabase `anon_security_definer_function_executable` advisor.
