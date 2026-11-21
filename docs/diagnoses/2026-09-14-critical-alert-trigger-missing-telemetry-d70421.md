---
bug_id: d70421
date: 2026-09-14
batch: Task 6 - Telegram admin bot critical alert trigger
status: fixed
blast_radius: catastrophic
symptom: |
  B-pass review of migration 133 (docs/reviews/28213f7956e2-review.md, Finding 3) found
  private.dispatch_critical_alert_notify()'s EXCEPTION WHEN OTHERS handler was a bare
  `RETURN NEW;` with zero observability, despite 133's own header claiming "same shape as
  073_proactive_coach_promotion_trigger.sql (... exception-swallowing)" -- a claim only half
  true, since 073 (before its own migration-078 fix) also logged client_errors telemetry on
  both the success and failure paths. A dispatch failure (CRON_SECRET unset, pg_net error,
  any other exception) was completely invisible: no row anywhere, no log, nothing any
  dashboard or the founder's own alert-triage flow could surface.
concept: server_trigger_telemetry
sot_registry_entry: |
  Not applicable -- this is an Edge-adjacent Postgres trigger's own observability, not a
  writer-reader contract between client and cloud.
writers:
  - { file: supabase/migrations/134_alert_critical_notify_telemetry.sql, method_or_widget: private.dispatch_critical_alert_notify, line: 63 }
readers:
  - { file: supabase/migrations/078_fix_dispatch_proactive_coach_promotion_columns.sql, method_or_widget: private.dispatch_proactive_coach_promotion, line: 54 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: client_errors
cloud_columns:
  - error_code
  - error_message
  - client_version
  - platform
  - user_id
  - op_type
contract_test_path: test/sql/alert_critical_notify_trigger_live_verify.sql
ist_handling:
  - "Not applicable -- no date keys or counters involved."
provider_invalidations: []
telemetry_op_types:
  success: [critical_alert_dispatched]
  failure: [critical_alert_dispatch_failed]
cross_account_guard: Not applicable -- server-side trigger, no per-user account context (user_id is always NULL for this telemetry).
forbidden_patterns_checked:
  - { pattern: "client_errors INSERT using the non-existent message/severity columns (073's original P0 class)", absent: true }
proposed_fix: |
  CREATE OR REPLACE the trigger function to add client_errors telemetry (success + failure
  paths, real columns error_code/error_message/client_version/platform) using
  078_fix_dispatch_proactive_coach_promotion_columns.sql's corrected pattern, with the
  failure-path telemetry insert nested in its own BEGIN/EXCEPTION WHEN OTHERS THEN NULL
  block so a telemetry-insert failure can never itself abort the parent alerts INSERT.
regression_test_planned:
  - test/sql/alert_critical_notify_trigger_live_verify.sql
impact_analysis: |
  Observability only -- no change to the trigger's firing condition, its dispatch target, or
  the alerts table's row shape. Before this fix, a dispatch failure was silently invisible;
  after, it produces a client_errors row an operator or future dashboard can query. A
  successful dispatch now also produces an audit-trail row (mirroring 073/078's pattern),
  which was previously entirely absent for this trigger.
touched_layers_checked:
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "client_errors columns (error_code/error_message/client_version/platform) confirmed live via information_schema.columns before writing any SQL -- independently re-derived rather than trusting the review's own (incorrect) suggested-fix, which cited the message/severity columns that caused 073's original P0." }
  - { tier: 4, name: "Postgres data", status: fixed_in_this_batch, evidence: "Rolled-back-transaction live verify: a critical alert insert produced a real critical_alert_dispatched / error_code='info' client_errors row." }
  - { tier: 5, name: "Migrations applied", status: fixed_in_this_batch, evidence: "Migration 134 applied to dedsavbjuwgarrhphgnl (cloud_version 20260914010918); backups/applied_migrations.json updated in the same commit." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No client-facing surface; this is a server-side trigger's own internal telemetry." }
---

## Summary

Migration 133 shipped `private.dispatch_critical_alert_notify()` with a bare
`EXCEPTION WHEN OTHERS THEN RETURN NEW;` handler — the trigger's header claimed
this matched `073_proactive_coach_promotion_trigger.sql`'s "exception-swallowing"
shape, but omitted that 073 (in its ORIGINAL form) also logged `client_errors`
telemetry on both the success and failure paths. A B-pass review (Finding 3,
`docs/reviews/28213f7956e2-review.md`) caught the gap: a dispatch failure for
this trigger was completely invisible anywhere in the system.

## Root cause

Migration 133's author copied 073's exception-swallowing SHAPE but not its
telemetry CONTENT. No prior incident directly caused this — it is a genuine
omission caught by review before any real dispatch failure occurred in
practice, not a regression of a previously-working behaviour.

## Fix

Migration 134 (`CREATE OR REPLACE FUNCTION`, body-only, trigger binding
untouched) adds a `client_errors` insert on both the guard-failure path (secret
not set) and the outer `EXCEPTION WHEN OTHERS` path, plus a success-path insert
mirroring 073/078's pattern. Critically, the fix does NOT copy 073's ORIGINAL
column choice (`user_id, op_type, message, severity` — columns `client_errors`
has never had) — that exact mistake caused a real prod P0 documented in
`078_fix_dispatch_proactive_coach_promotion_columns.sql` (a plpgsql trigger
body is never validated against schema until it runs; 073's own exception
handler used the same bad columns for its telemetry insert, so the re-raised
exception escaped the trigger and aborted every `rank_promotions` row). This
migration was independently written from 078's CORRECTED pattern
(`error_code`/`error_message`/`client_version`/`platform`), verified live via
`information_schema.columns` before any SQL was written, with every
failure-path telemetry insert nested in its own
`BEGIN/EXCEPTION WHEN OTHERS THEN NULL; END;` block — 078's own fix for the
identical re-raise hazard.

Notably, the B-pass review's OWN suggested-fix for this finding repeated 073's
original wrong columns verbatim. Had it been applied as written, it would have
reintroduced the exact P0 078 exists to prevent. Caught only because the
suggested-fix was independently re-verified against live schema rather than
trusted.

## Verification

- Pre-apply: `information_schema.columns` confirmed the real `client_errors`
  column set and NOT NULL constraints.
- Post-apply, rolled-back transaction: a critical-severity alert insert
  produced a real `critical_alert_dispatched` / `error_code='info'` telemetry
  row.
- Live `obj_description()` on the trigger confirmed the new `COMMENT ON
  TRIGGER` text landed correctly.
- A second B-pass review (`docs/reviews/297bae7db41c-review.md`) independently
  traced the PL/pgSQL exception-nesting structure at all three insert call
  sites against the LIVE deployed function body and confirmed the nesting
  genuinely prevents a telemetry-insert failure from propagating.

## Related bugs

`078_fix_dispatch_proactive_coach_promotion_columns.sql` (diagnose `f4b2c9`) —
the original instance of the exact wrong-column mistake this fix deliberately
avoided repeating, in a sibling trigger on the same "notification dispatch
trigger" family.
