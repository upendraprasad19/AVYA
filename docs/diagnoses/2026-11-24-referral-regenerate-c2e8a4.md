---
bug_id: c2e8a4
date: 2026-11-24
batch: oi348-walk-fixes Landing 2 PR B (B2)
status: fixed
tier: full
blast_radius: catastrophic
symptom: |
  OI-348 walk A10 (AAB 1.0.0+50, 2026-11-22): on an expired referral code the Invite sheet's REGENERATE button does nothing and shows no error. Telemetry: 42501 on referral_codes. Live 2026-11-23: referral_codes has RLS policies SELECT own + INSERT own only (no UPDATE, no DELETE, since migration 035); 3 rows, 2 expired; UNIQUE(user_id), UNIQUE(code); no triggers.
concept: referral_code_issue
sot_registry_entry: referral_code_issue
writers:
  - { file: supabase/migrations/186_issue_referral_code.sql, method_or_widget: "public.issue_referral_code(): SECURITY DEFINER, search_path ''; per-user advisory xact lock; live row returned unchanged; else mint AVYA- + 8 unbiased chars, INSERT ON CONFLICT (user_id) DO UPDATE WHERE expired (a live row committed meanwhile is kept), retry on referral_codes_code_key only (5 attempts); final re-select, zero rows raise. REPLACES the client upsert SupabaseService._generateNewCode (deleted).", line: 35 }
readers:
  - { file: lib/core/services/supabase_service.dart, method_or_widget: "parseIssuedReferralCode (List -> first Map -> out_code non-empty, out_expires_at parseable, else null)", line: 16 }
  - { file: lib/core/services/supabase_service.dart, method_or_widget: "getOrCreateReferralCode / regenerateReferralCode -> _issueReferralCode -> issueReferralCodeVia (signed out -> null, no call; ensureFreshToken, then rpc('issue_referral_code') with a 15 s timeout); empty -> referral_code_issue_empty event; throw -> recordNonFatal supabase_service_issue_referral_code; null", line: 147 }
  - { file: lib/features/profile/screens/invite_friends_sheet.dart, method_or_widget: "_load / _regenerate: a null result sets _issueFailed (ReferralCopy.codeIssueFailed + TRY AGAIN); REGENERATE keeps the old code on failure and re-enables in finally", line: 88 }
  - { file: supabase/functions/redeem-referral/index.ts, method_or_widget: "service-role code lookup + expiry check (unchanged)", line: 82 }
  - { file: lib/core/services/sync/sync_restore_completeness.dart, method_or_widget: "restore SELECT of referral_codes into Hive referral_code (unchanged)", line: 646 }
  - { file: supabase/functions/restore-user-snapshot/restore_reads.ts, method_or_widget: "single-call restore read of the own live code (gt expires_at now), injected into the restore above (unchanged)", line: 131 }
hive_key_prefix: "userBox referral_code (written by the restore only; read by nothing else in lib/, so issue needs no cache write)"
hive_key_formula: "n/a (single key)"
sync_methods: []
restore_methods: [restore of referral_codes in sync_restore_completeness.dart]
cloud_table: referral_codes
cloud_columns: [user_id, code, expires_at, created_at]
contract_test_path: test/contracts/referral_code_issue_writer_to_reader_test.dart
ist_handling: ["none: expiry is a timestamptz compared with now() on the server; no date key"]
provider_invalidations: ["none: the sheet holds the code in widget state, as before"]
telemetry_op_types:
  success: []
  failure: [referral_code_issue_empty, supabase_service_issue_referral_code]
cross_account_guard: "The function reads auth.uid() only and scopes every statement by user_id = v_uid (live verify V5/V6; mutant MS5). No client-supplied user id exists."
forbidden_patterns_checked:
  - { pattern: "a client write chain on referral_codes (.upsert/.insert/.update/.delete) anywhere in lib/", absent: true }
  - { pattern: "_generateNewCode / _buildReferralCode / dart:math in supabase_service.dart", absent: true }
  - { pattern: "REVOKE ... FROM PUBLIC without anon (platform default grants, migration 103 / a9d3f1)", absent: true }
  - { pattern: "an unqualified name inside the function body (search_path is '')", absent: true }
proposed_fix: |
  Plan docs/plans/oi348-walk-fixes-landing2.md, Unit B2 (v4 CONVERGED; founder 2026-11-23: the server makes codes).
  1. Migration 186 (this PR, M1): public.issue_referral_code() as in the writers row. EXECUTE revoked from PUBLIC and anon, granted to authenticated.
  2. Client: both entry points call the RPC; the old upsert, the local code builder and dart:math are deleted. The path is SupabaseService.issueReferralCodeVia (dependencies passed in, driven by tests with fakes); the widget-test seam issueReferralCodeRpcForTest replaces only the RPC. test/referral_code_test.dart is deleted: it tested its own copy of a name-prefix builder (AVYA-<NAME4><4 digits>) that the app had already replaced before this change; no production code was under test.
  3. Sheet: a null result on load or REGENERATE shows ReferralCopy.codeIssueFailed with a TRY AGAIN button; the old code stays on a failed REGENERATE; the button re-enables.
  4. PR C (M2), after the web build calling the RPC is live: drop the INSERT policy, REVOKE ALL on referral_codes from anon and authenticated, GRANT SELECT to authenticated, with a self-check DO block.
regression_test_planned: |
  test/contracts/referral_code_issue_writer_to_reader_test.dart (27): parser table (list/map/empty/wrong types/unparseable expiry); seam entry points; issueReferralCodeVia's real order (signed out -> no refresh, no RPC; refresh BEFORE the RPC; a never-answering RPC -> null after the timeout; a throwing refresh -> no RPC; a throwing check -> null) and the production wiring pin; client <-> migration names (one .rpc('issue_referral_code'), the OUT names); no client statement on referral_codes other than a .select( chain (split-chain control included) and only two allowlisted lib/ files spell the table name; the restore read still present.
  test/contracts/issue_referral_code_function_pin_test.dart (24): the whole migration text, comment-insensitive and whitespace-insensitive outside literals only, equals a literal; header tags; every GRANT/REVOKE whatever the spelling; DDL-only tripwire (FUNCTION / ROUTINE / PROCEDURE, bulk grants on schema public, any later or letter-suffixed migration, nested folders) with controls.
  test/profile/invite_friends_sheet_issue_failure_test.dart (4): load failure shows the line + retry; retry success clears it; REGENERATE failure keeps the old code and shows the line; success replaces the code.
  Live: test/sql/referral_code_issue_live_verify.sql (one always-aborting DO block, NULL results count as fail): B0 the old upsert is refused by RLS (42501, message names row-level security: the bug); B0c control, a first-row INSERT as authenticated succeeds (pre-M2); V1 none -> created AVYA-[A-Z0-9]{8} +7 d one row; V2 live -> one row returned, unchanged, table untouched; V3 expired -> new, returned = stored; V4 expires_at = now() is expired; V5 A's write-path call leaves B's expired row; V6 B's call replaces only B's row, A's unchanged; V7 no sub -> 42501; V8 anon with a real sub -> permission denied for function; C1 ACL; C2 prosecdef, proconfig, owner; C3 the unique indexes, compared by full definition (an expression or partial index counts), are exactly pkey(id), referral_codes_code_key(code), referral_codes_user_id_key(user_id); C4 extensions.gen_random_bytes(integer) exists; C1 prints every grantee.
mutation_proof: |
  Rule 21. Restore by cp + cmp, never git checkout; grep -c confirmed each mutation applied.
  SQL (live, pg_get_functiondef + replace() into a renamed copy inside one aborting DO block, 2026-11-24): MS1 expiry > -> >= (V4 red); MS2 null-uid raise removed (V7 red); MS3 anon revoke removed (V8/C1 red); MS4 search_path dropped (C2 red); MS5 user_id scoping removed from the final select (V5/V6 red). Control (unmutated copy) green.
  File mutants (scratchpad mut_b2/run.sh, re-run 2026-11-24; each applied per grep -c, restored by cp, cmp clean): function pin issue_referral_code_function_pin_test 1 red each for MP1 byte rejection 252 -> 256, MP2 retry constraint name -> referral_codes_pkey, MP3 advisory lock -> the _shared variant (no longer serialises), MP4 expiry > -> >=. Client: MC1 parseIssuedReferralCode accepting an empty out_code -> 1 red (writer_to_reader parser table). Sheet (line-targeted sed; the count of `_issueFailed = false;` rose 2 -> 3): L96 (_load's assignment forced false) -> 1 red; L115 (_regenerate's) -> 2 red.
  After the B-pass (2026-11-24): client mutants (scratchpad mut_b2/run2.sh, same protocol) on writer_to_reader, 27 tests: MG1 signed-in guard removed -> 1 red; MG2 RPC started before the token refresh -> 5 red; MG3 timeout removed -> 1 red (the never-answering RPC); MG4 production refreshToken replaced by a no-op -> 1 red (wiring pin); MG5 a new 'referral_codes' literal in supabase_service.dart -> 1 red (allowlist). SQL, one aborting run with the early RETURN removed AND anon left with EXECUTE: V2 red (calls=2), V8 red (no error); that run also exposed the SUMMARY counting a NULL result as neither ok nor fail, now fixed.
  Pre-apply dry runs (2026-11-24): migration 186 text + the live verify in ONE execute_sql: first version SUMMARY ok=11 fail=0; post-B-pass version (DO UPDATE ... WHERE expired, the tightened cases, B0c, C3) SUMMARY ok=13 fail=0; after each, to_regprocedure('public.issue_referral_code()') is null, referral_codes still 3 rows and 0 fixture rows (rolled back).
concurrency_note: |
  The plan's two-session test (docker replica) needs a local Postgres; this PC and WSL have none. The advisory lock is pinned by the whole-text function pin; the race it closes is stated in the migration header. Founder chose 2026-11-24 a live run after the apply: two parallel calls on one QA account, each holding the transaction 4 s after the call; the same code from both, with overlapping timestamps, passes; a lock-less copy of the function run the same way must give two different codes (the red side), then is dropped. Attempt 2026-11-24 after the apply (VOID, recorded as such): the MCP database tool runs calls one after another (S1 transaction ended 08:12:27.36 UTC, S2 started 08:12:30.74), so two "parallel" calls never overlapped; dblink is available but not installed and a loopback connection needs the database password. Cleanup verified: the three temporary copies dropped, the QA row removed, referral_codes back to 3 rows. Founder decision 2026-11-24 ("Ship on reasoning"): no runtime race proof; two independent guards each close the race (the per-user advisory xact lock; DO UPDATE only when the row is expired, so a concurrent writer never overwrites a live code), checked by reasoning by 3 B-pass seats and Hermes L2/L14. NOT runtime-proven, stated (closure ledger B2-CONCURRENCY).
impact_analysis: |
  REGENERATE works on an expired code; a first code is minted server-side with an unbiased alphabet. A live code is never replaced, so nothing redeemable is lost (redeem-referral already refuses an expired code). Old builds (AAB +50) keep their client upsert until PR C: their first-code INSERT keeps working until M2 and their REGENERATE stays broken (testing accounts only, CLAUDE.md section 1). redeem-referral, restore-user-snapshot and the restore read are unchanged. Between the apply and M2, an old client and the function cannot overwrite each other: the old UPDATE stays refused (an old client that loses the race to a function-issued code shows an empty sheet once, then reads the live code on the next open), and the function keeps a live row an old client inserted (DO UPDATE ... WHERE expired). Reader consequence (Hermes L1): once a referrer regenerates, a friend holding the OLD shared link gets "We don't recognize that code." instead of "This code has expired..." (the expired row is replaced, not kept); the old code was refused either way. Code format is unchanged: the old client already minted AVYA- + 8 [A-Z0-9], and redeem-referral and the apply sheet accept exactly that.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "supabase_service.dart (RPC + parser + seam), invite_friends_sheet.dart (error + retry), referral_copy.dart; 55 new tests (27 + 24 + 4) + all touched pins green." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Hive referral_code is written only by the restore and read by nothing else in lib/ (grep); unchanged." }
  - { tier: 3, name: "Postgres schema", status: fixed_in_this_batch, evidence: "One new function (migration 186); no table or column change, so live_schema_columns.json is unchanged." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "referral_codes 3 rows, 2 expired (read-only, 2026-11-23/24); no data migration." }
  - { tier: 5, name: "Migrations applied", status: fixed_in_this_batch, evidence: "Dry runs 11/11 then 13/13 in one aborting request; applied 2026-11-24 after the staged B-pass + Hermes accepted and the founder go (Apply 186 now), cloud version 20261124080819; live md5(prosrc) equals the file body; post-apply live verify 14/14 (rolled back); ledger entry in the same commit (Gate 39 PASS)." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed; redeem-referral reads as before." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "None." }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "Policies unchanged in PR B (SELECT own + INSERT own); the function bypasses RLS as owner postgres with relforcerowsecurity false (live). M2 (PR C) removes the INSERT policy." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "None." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "None." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "None." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Live verify runs the function as authenticated with real JWT claims; the client parses the OUT names pinned against the migration." }
recurrence: "Not a recurrence of a prior referral bug. Same CLASS as the policy-less write family: a client write the RLS policy set never allowed (no UPDATE policy since migration 035), swallowed by a catch, surfaced only as telemetry. Related: migration 160 (referrer_summary definer door), a9d3f1 (anon default grants)."
related_bugs: [a9d3f1]
---

# c2e8a4 - referral-regenerate

## What happened
The client minted referral codes itself and upserted `{user_id, code, expires_at}` on conflict `user_id`. For an existing row that upsert is an UPDATE, and `referral_codes` has no UPDATE policy, so every REGENERATE after the first code failed with 42501. The service retried four times, logged telemetry and returned null; the sheet ignored a null result, so the button did nothing.

## The fix
The server makes codes: `public.issue_referral_code()` returns the caller's live code or mints a fresh 7-day one under a per-user lock. The client only calls it, and the sheet shows an error with a retry when no code comes back. See the frontmatter.

## Residual, stated
- The INSERT policy still lets a client write its first row with any code and expiry until PR C (M2) lands after the web deploy.
- The two-session race test is not run locally (no Postgres here); see `concurrency_note`.
