---
hermes_pass_id: 2026-11-25-hermes-oi348-landing2-m2
ran_at: 2026-11-25T15:10:00+05:30
batch_scope: staged diff of branch oi348-landing2-m2 on origin/main cf988f07, after the B-pass fixes (migration 189 not yet applied)
lens_set: [L1, L2]
agents_dispatched: 2
findings_total: 4
findings_by_severity: { P0: 0, P1: 0, P2: 0, P3: 4, false_alarm: 0 }
verdict: accepted
---

# Hermes Pass — OI-348 Landing 2 PR C (migration 189, referral_codes server-only writes)

Privilege-only migration on one table: lens L1 (every reader and writer of `referral_codes` under the
role it really runs as) and L2 (RLS and table privileges, every route a client role could still
write or read across users). One context-blind Sonnet seat per lens, read-only on
`dedsavbjuwgarrhphgnl`; the L2 seat inspected the post-189 state by running the DDL inside an
always-aborting request. Consolidated by the coordinator.

## Summary
- 0 P0, 0 P1, 0 P2, 4 P3. No ship-blocker.

## L1 — writer/reader drift
Verified clean, per site and role: the client RPC (`supabase_service.dart`, authenticated) never
touches the table and the function writes as its owner; the client restore read
(`sync_restore_completeness.dart:651`, authenticated, a named 3-column select, no column ACLs) keeps
SELECT and the own-row policy, whose live roles and condition equal what the self-check compares;
`redeem-referral` and `restore-user-snapshot` read with the service role (BYPASSRLS, keeps
arwdDxtm); `delete-account` never names the table and the `auth.users` FK cascade runs as the owner;
no other Edge Function, SQL function, view, cron job, trigger, publication, integration test, script
or skill writes it as a client role (`reset-test-user` deletes via the database tool as postgres); no
`select *`, no `.select()` chained after a write.
- **L1-F1 (P3)** `docs/sot_registry.yaml` said the function's EXECUTE is "for authenticated only";
  live `proacl` is `{postgres, authenticated, service_role}` (service_role by the platform default;
  anon and PUBLIC none). **Fixed** in the registry text.
- **L1-F2 (P3)** the reader manifest is complete (the function's own re-select is covered by the
  writer entry). **No action.**

## L2 — RLS table-level
Verified clean: after the DDL, `relacl` is `{postgres=arwdDxtm, service_role=arwdDxtm,
authenticated=r}`, no column ACLs; across every non-system role only service_role, supabase_admin and
postgres can write; anon and authenticated are members of no role; authenticator holds nothing itself
and can switch only to anon, authenticated or service_role; the only grantor was postgres, so the
REVOKE removed everything; `pg_default_acl` re-grants apply to new tables only; RLS on, not forced,
owner postgres; with a real JWT authenticated counted 1 of 3 rows (its own); anon gets 42501; no
lock holders on the table (3 rows), a lock timeout aborts the whole transaction; the security advisor
has no `referral_codes` finding and the change adds none (the pre-existing
`authenticated_security_definer_function_executable` entry for the function is unchanged and
intended).
- **L2-F1 (P3)** `SET lock_timeout` is session-level, not `SET LOCAL`. **Kept, by design:**
  `apply_migration` runs the file as one transaction, so a failure rolls the SET back and a success
  reaches the `RESET`; the migration 160 precedent uses the same pair; under a statement-by-statement
  run `SET LOCAL` outside a transaction would have no effect at all (no timeout), while the session SET
  still bounds the DDL, and the self-check still fails closed if the DROP did not happen.
- **L2-F2 (P3, informational)** platform event triggers exist (7); a re-grant fired by this DDL
  would be visible to the in-transaction self-check, and none appeared in the aborted run.
  **Verified clean.**
