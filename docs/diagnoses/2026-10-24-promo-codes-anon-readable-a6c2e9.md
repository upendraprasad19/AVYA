---
bug_id: a6c2e9
date: 2026-10-24
batch: promo-codes-server-only (OI-406; unit U4 of docs/plans/2026-10-24-payment-hardening.md)
status: fixed_in_code_apply_pending
tier: l_fix
blast_radius: platform
symptom: >-
  Anyone holding the app's public anon key (it ships inside the web bundle and the APK) could list every active
  promo code with its discount percentage, expiry and use counts without signing in. Measured live on 2026-10-24:
  a count-only PostgREST request on /rest/v1/promo_codes with the anon key answered 206 `content-range: */3`,
  and the pre-apply run of the live verify read P1 `VERIFY_UNEXPECTED_OK 3` (anon) and P2 the same
  (authenticated). Found while verifying OI-366 for the payment-hardening plan (round 1, finding C4). The codes
  are the founder's discount codes (the live maximum is 30 percent, migration 160 caps new rows at 90), so a
  listed code is a free discount for anyone who reads the list.
concept: promo_codes_server_only — promo codes and their discounts are read only by the payment Edge Functions, through the service role.
sot_registry_entry: promo_codes_server_only
writers:
  - { file: supabase/migrations/20260330_create_promo_codes.sql, method_or_widget: "CREATE POLICY \"Anyone can read active promo codes\" (FOR SELECT, roles public, USING is_active = true): the access rule that opened the rows", line: 28 }
  - { file: supabase/migrations/163_promo_codes_server_only_access.sql, method_or_widget: "DROP POLICY IF EXISTS + REVOKE ALL FROM PUBLIC, anon, authenticated (applied live 2026-10-24, cloud version 20261024121637)", line: 24 }
readers:
  - { file: supabase/functions/validate-promo/index.ts, method_or_widget: "handler: the promo_codes read, service-role client", line: 84 }
  - { file: supabase/functions/create-razorpay-order/index.ts, method_or_widget: "handler: the promo_codes read that prices the order, service-role client", line: 198 }
  - { file: supabase/functions/verify-payment/index.ts, method_or_widget: "the tolerant promo read that derives the plan from the amount, service-role client", line: 95 }
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: "the tolerant promo reads (126, 183) that derive the plan from the amount, service-role client", line: 126 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: promo_codes
cloud_columns: [code, discount_pct, valid_until, max_uses, used_count, is_active, created_at]
contract_test_path: test/contracts/promo_codes_server_only_writer_to_reader_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: ["none: a catalog change, no runtime path changes"]
  failure: ["a client read now answers 401/403 from PostgREST (42501 underneath); no client reads the table"]
cross_account_guard: "not a per-user surface: the rows are global; the change removes every client role's access, so no user can read them at all."
forbidden_patterns_checked:
  - "REVOKE FROM anon, authenticated only — REJECTED: the c9b3e2 lesson (migrations 090/091): a role-specific REVOKE is a no-op for anything PUBLIC also holds, so PUBLIC is named too; the live verify reads the ACL itself (P3) instead of trusting the statement."
  - "keeping the policy and narrowing it (for example TO authenticated) — REJECTED: no client reads the table (no hit in lib/ or web/), a signed-in account is free to create, and validate-promo already answers the one question a client needs (is this code valid for me) through the service role."
  - "disabling RLS — REJECTED: RLS stays ENABLED with no policy, so a grant added by mistake later still exposes no row (P6 checks it)."
  - "a column-level grant for code only — REJECTED: the code IS the secret; there is nothing safe to list."
proposed_fix: >-
  Migration 163 `promo_codes_server_only_access`: `DROP POLICY IF EXISTS "Anyone can read active promo codes" ON
  public.promo_codes;` and `REVOKE ALL ON TABLE public.promo_codes FROM PUBLIC, anon, authenticated;`. RLS stays
  enabled; service_role keeps its own grant and bypasses RLS, so the four payment Edge Functions are unchanged.
  The pre-apply ACL (anon and authenticated: DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE,
  UPDATE, every one granted by postgres; no PUBLIC entry; no column grants) is restored by the inline rollback
  block. Drafted under docs/plans/ until the apply (Gate 14 fails an unledgered file in supabase/migrations/),
  then moved with `git mv` and ledgered in the same commit.
regression_test_planned:
  - "test/contracts/promo_codes_server_only_writer_to_reader_test.dart (10 tests): the executable body is exactly the two statements; the header tags; the inline rollback; the dropped policy name equals the one 20260330 created; the tier guards; no file of any type under lib/ or web/ names promo_codes; every createClient( call in the four Edge Function readers (comments stripped) passes the service-role key, read from the service-role env var, and no anon key appears in code; no other migration re-opens the table (a grant naming it anywhere in the ON list, ON ALL TABLES IN SCHEMA public, or a policy on it, quoted identifiers included); the rehearsal file equals the live verify plus exactly the migration statements, and neither file opens or ends a transaction."
  - "test/sql/promo_codes_no_client_access_live_verify.sql (16 cases P0-P15, one always-aborting read-only DO block): anon and authenticated reads refused with the TABLE's 42501 (a refused role switch is a fail); no table or column ACL entry for PUBLIC, anon or authenticated; has_table_privilege false for every privilege, so membership routes too; no policy; RLS on; the counter function closed; no client-callable definer function names the table; no publication; no view; service_role really reads every row under RLS (BYPASSRLS) and keeps SELECT and UPDATE, as does postgres; promo_code_uses' policy untouched."
  - "test/sql/promo_codes_server_only_rehearsal.sql: the dry run, the same block with the two migration statements first, as ONE aborting statement (B-pass F8)."
mutation_proof: >-
  23 mutants (scratchpad u4/mutate_u4.py; each computed before any write, every file restored and byte-compared in
  `finally`, applied-ness checked by re-reading), every one red: M1 REVOKE line dropped, M2 authenticated dropped,
  M3 PUBLIC dropped, M5 REVOKE SELECT only, M6 an added DISABLE ROW LEVEL SECURITY: 2 red each (group 1 and the
  rehearsal pin); M4 a typo in the dropped policy name: 3 red; M12 both the draft and the final file present: 6 red;
  1 red each for M7 the rollback GRANT dropped, M8 a later migration re-grants SELECT to anon, M9 a later migration
  re-creates a policy, M10 a client file names promo_codes, M11 validate-promo's key replaced everywhere, M13 the
  diagnose id changed, M14 "security definer" text in a comment, and the B-pass escapes: M15 one call site moved to
  the anon key with the constant kept, M16 GRANT ON ALL TABLES IN SCHEMA public, M17 promo_codes second in a GRANT
  list, M18 a policy on "public"."promo_codes", M19 a .mjs reader under web/, M20 a rehearsal check drifting from the
  verify, M21 an extra statement in the rehearsal prelude, M22 the rehearsal opening its own transaction, M23 the key
  named only in a comment. Before the B-pass fixes M15-M18 and M23 were green (the reviewer measured M16-M18). The
  live verify was run BEFORE the apply (2026-10-24, read-only, aborting): `SUMMARY ok=10 fail=6`, exactly P1-P5 and
  P14 fail as its header predicts and the other 10 ok (P13: service_role read 3 of 3 rows). Self-attested.
impact_analysis: >-
  No client code reads the table, so nothing in the app changes. The four payment Edge Functions read it with the
  service role, which keeps its explicit grant (P10). A signed-in user still checks a code through validate-promo.
  The DROP POLICY and REVOKE take a brief ACCESS EXCLUSIVE lock on promo_codes, a 3-row table read only by the
  payment functions; no real payment has run since the live keys went in.
touched_layers_checked:
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "pre-apply live read 2026-10-24: aclexplode(relacl) lists anon and authenticated with all 8 privileges, grantor postgres; no PUBLIC entry; aclexplode(attacl) empty; pg_policies has the one policy; relrowsecurity true; no publication; no dependent view; no client-callable definer function names the table; service_role has BYPASSRLS and reads 3 of 3 rows (live verify P0-P15 pre-apply: ok=10 fail=6)" }
  - { tier: 5, name: "Migrations applied", status: fixed_in_this_batch, evidence: "number 163 reserved by mint_migration.sh (refs/heads/mig/163); rehearsed and applied live 2026-10-24 on the founder's go via MCP apply_migration (cloud version 20261024121637, name promo_codes_server_only_access); ledger entry and the git mv in this commit" }
  - { tier: 8, name: "RLS policies", status: fixed_in_this_batch, evidence: "post-apply live verify 2026-10-24: 16 of 16 ok; the one SELECT policy is gone (P5), RLS stays enabled (P6), anon and authenticated hold no privilege (P3, P4, P14) and are refused with 42501 (P1, P2), service_role reads 3 of 3 rows (P13)" }
  - { tier: 1, name: "Client code", status: verified, evidence: "no file under lib/ or web/ names promo_codes (contract test group 5)" }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "the four readers build their client with SUPABASE_SERVICE_ROLE_KEY (contract test group 6); live validate-promo v21, create-razorpay-order v18, verify-payment v30, razorpay-webhook v34 were compared to main earlier this session; no redeploy is needed" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "the client asks validate-promo (JWT-authenticated) and never reads the table. After the apply the anon key read of /rest/v1/promo_codes answers 401 code 42501 (was 206 */3). The service-role read the four payment functions use is proven at the database (P10, P13: 3 of 3 rows under SET ROLE service_role); the signed-in validate-promo call from the app is a founder check (no test-account credential is held on the VPS)" }
recurrence: >-
  Same class as c9b3e2 (2026-06-11): a server-only object left reachable by the anon and authenticated API roles
  through the platform's default privileges, there definer-rights functions, here a table plus a permissive SELECT
  policy. The known-good fix is applied: REVOKE FROM PUBLIC as well as the named roles (c9b3e2's 090 revoke was a
  no-op because PUBLIC held the grant) and a live post-apply privilege read rather than trusting the statement.
  Same family as 7ad054 (2026-05-11, migration 054): that cleanup fixed promo_code_uses' over-broad INSERT policy
  and left promo_codes' public SELECT policy in place; 7ad035 closed the counter function's anon EXECUTE. Searched
  INDEX for 'promo', 'enumeration', 'anon key', 'default grant', plus the two promo tables by name in the diagnose
  bodies (the INDEX line of 7ad054 starts with rank_ladder, so a symptom grep misses it). c3e7a1 is a different
  defect.
related_bugs:
  - c9b3e2
  - 7ad054
  - 7ad035
---

# promo_codes was readable with the public anon key

## What was wrong

`20260330_create_promo_codes.sql` gave the table the SELECT policy "Anyone can read active promo codes" with the
comment "needed for client validation". The client never read it (validation moved to the JWT-authenticated
`validate-promo` function), but the policy and the platform's default grants to `anon` and `authenticated`
stayed. So anyone with the public anon key could list every active code and its discount.

Out-of-repo readers: the Telegram bot (a separate OpenClaw project) is disabled (OI-278, founder 2026-10-24), so
no reader outside this repo is known; that is the founder's statement, not verified from this repo.

## Writer and reader

Writer of the access rule: the policy in `20260330_create_promo_codes.sql:28` plus the default grants (live ACL,
grantor `postgres`). Readers that must keep working: the four payment Edge Functions, all on the service role.
Readers that must stop: every client role (none exist in the app).

## The fix

See `proposed_fix`. Plan: `docs/plans/2026-10-24-payment-hardening.md` section 3 U4 (kept on the
`payment-hardening` branch; this unit ships first on its own branch). Proof after the apply:
`test/sql/promo_codes_no_client_access_live_verify.sql`, every line `ok`, then an anon-key count-only request
answering 401/403 instead of `*/3`, and a signed-in `validate-promo` call still answering.

## Apply record (2026-10-24)

On the founder's go. The rehearsal (the migration's two statements, then the 16 checks, in one aborting
statement) ran through MCP `execute_sql` as three self-contained chunks, each repeating the two statements:
the whole block (about 7 KB without comments) came back `Invalid or expired requestState` twice with nothing
run (a read right after showed the policy, the grants and 0 locks unchanged), while chunks of 2.5-4 KB ran.
Rehearsal: A ok=5, B ok=8, C ok=3 (16 of 16). Afterwards the policy and all 16 client grants were still there,
0 locks on promo_codes. Applied with `apply_migration` (cloud version `20261024121637`; the request carried the
header, the two statements and the commented rollback, not the WHY prose). Post-apply verify in the same three
chunks: 16 of 16 ok. Anon-key `GET /rest/v1/promo_codes` with `Prefer: count=exact`: 401, code 42501,
`permission denied for table promo_codes`.

