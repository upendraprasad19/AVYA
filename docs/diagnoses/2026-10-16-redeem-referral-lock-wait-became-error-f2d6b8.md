---
bug_id: f2d6b8
date: 2026-10-16
batch: referral-migration-160
status: fixed
blast_radius: catastrophic
tier: full
symptom: >-
  `redeem_referral_atomic` can fail with SQLSTATE 55P03 (lock_not_available) for a friend applying a referral code while another
  session holds that friend's active `subscriptions` row for a moment (for example the payment webhook updating or inserting around
  it). Migration 158 granted the referee's days with a plain UPDATE, which WAITED for the lock. Migration 159 replaced that with
  `private.grant_referral_days`, whose first query is `SELECT ... FOR UPDATE NOWAIT`: a held row now raises 55P03 at once, the whole
  RPC call is rolled back, and `redeem-referral` returns a generic 500 to the friend. A regression of 158's behaviour introduced by
  159 (hermes round 2, seat A finding 3 / OI-344 item 5 / ledger row N3).
concept: referral_reward_on_conversion
sot_registry_entry: referral_reward_on_conversion
writers:
  - { file: supabase/migrations/159_referral_reward_on_conversion.sql, method: redeem_referral_atomic (the grant call), line: 164 }
  - { file: supabase/migrations/159_referral_reward_on_conversion.sql, method: private.grant_referral_days (FOR UPDATE NOWAIT), line: 109 }
readers:
  - { file: supabase/functions/redeem-referral/index.ts, method_or_widget: rpc error mapping (55P03 reaches the generic 500), line: 168 }
  - { file: lib/features/profile/repositories/referral_repository.dart, method_or_widget: redeem, line: 95 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: subscriptions
cloud_columns: user_id, status, end_date
contract_test_path: test/sql/referral_pay_on_conversion_concurrency_local.sh
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: >-
  Unchanged. The retry is inside the same RPC call and the same transaction; the per-referee advisory lock is held across the sleep,
  and the hourly job only TRY-locks that key, so there is no wait cycle (measured by the unchanged C1, C8 and C5 cases). Only
  lock_not_available is retried; the helper and the job keep NOWAIT (the job must never wait).
forbidden_patterns_checked: >-
  The retry is a bounded loop (3 attempts), not an unbounded wait, and catches ONE exception name. A `WHEN OTHERS` handler would
  retry every error including the helper's 22023 bounds error (mutant c_when_others, killed by C16c and live-verify Q7).
proposed_fix: >-
  In migration 160 the single `PERFORM private.grant_referral_days(p_referee_id, p_days)` of the redeem function becomes a bounded
  retry: `FOR v_attempt IN 1..3 LOOP BEGIN PERFORM ...; EXIT; EXCEPTION WHEN lock_not_available THEN IF v_attempt = 3 THEN RAISE;
  END IF; PERFORM pg_sleep(0.25); <the 159 paid-plan refusal, re-checked>; END; END LOOP;`. The refusal is re-checked after every pause (hermes seat A: a payment can land during the wait, and a retry must re-validate what it waited on). Worst case adds 0.5 s. After the third failure the caller still gets 55P03 (a
  bounded retry, not an elimination). No Edge Function change: the final 55P03 still reaches `redeem-referral` as the same generic
  500 as today. Everything else of the redeem body is byte-identical to 159 (compared by the Dart test).
regression_test_planned: >-
  test/sql/referral_pay_on_conversion_concurrency_local.sh case C16 (replica only), observed through a NON-transactional attempt
  counter: a replica-only wrapper of private.grant_referral_days calls nextval() on a sequence (a sequence survives rollback), is
  installed then restored and md5-checked against the original. (a) the friend's active row is held by a top-level DO block that
  commits once the redeem is ASLEEP between attempts (pg_stat_activity wait_event PgSleep, snapshot cleared each poll): the redeem succeeds on attempt 2, in 256 ms (window 240 to 1500), one audit row, the
  trial extended 6 + 7 = 13 days. (b) held for 6 s: fails with 55P03 after exactly 3 attempts in 505 ms (window 480 to 700, so a third pause would be caught), NO
  audit row, the row untouched. (c) a non-lock error (0 days, 22023) is attempted once and fails in 4 ms. (d) a PAID monthly row lands during the wait: refused with P0001 referee_has_paid_plan after ONE helper attempt, no audit row, the trial untouched (C16d). Live-verify Q7 checks (c)
  without a second session. MUTATED, each reddening its own case: retry count 1 (C16a: 55P03 at 5 ms, 1 attempt); no retry (C16a:
  55P03 at 4 ms); WHEN OTHERS (C16c: 3 attempts, 504 ms); final failure swallowed (C16b: the call returns ok in 783 ms with an audit
  row and the grant never made); sleep removed (C16a: 3 attempts in 4 ms, 55P03); sleep made 2 s (C16a 2008 ms); sleep moved after the last failed attempt (C16b 756 ms, above the 700 ms bound); the paid-plan re-validation removed (C16d: the redeem succeeds on attempt 2 for a referee who paid). Text-pin-only (equivalent in behaviour, killed by the Dart redeem-body equality): `1..4` with the `IF v_attempt = 3` test unchanged; a sleep of 0.30 s. The inline ROLLBACK block is also executed and compared with a 159-only database (C17).
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No client change; the friend sees the same message as today on the final failure." }
  - { tier: 2, name: hive, status: not_applicable, evidence: "No Hive involvement." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "Signature, return type, security mode and ACL of redeem_referral_atomic unchanged (live-verify A2, A3 on the replica); CREATE OR REPLACE preserves the ACL." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "No data touched; the retry only changes how a lock conflict inside one call resolves." }
  - { tier: 5, name: migrations_applied, status: verified, evidence: "Applied live 2026-10-17 06:21 IST (cloud version 20261017005132, file sha256 85a71a1a... equal to the reviewed file); live function md5s equal the replica (redeem b1973dd9, job 51d8a812, referrer_summary 162d3890); test/sql/referral_pay_on_conversion_live_verify.sql ran through execute_sql in eight aborting chunks (the tool rejects a single request of about 12 KB or more): 111 of 111 cases ok, nothing left behind; hourly job succeeded at 01:41, 02:41 and 03:41 UTC on the new body." }
  - { tier: 6, name: edge_function_deploy, status: verified, evidence: "redeem-referral v20 (deployed 2026-10-13) calls the RPC and maps P0001 to a 400; any other error is the generic 500. Unchanged by this fix; no redeploy." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "The job is not changed by this fix; it keeps NOWAIT on the same helper." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket involved." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "Razorpay is only the reason a row may be held; nothing external is called." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "C16a-d and the unchanged C1 (redeem vs job on one user), C8 (pgbench, 400 pairs, zero deadlocks) all pass on the replica with 160 applied; live Q7 (non-lock error propagates at once, no audit row) ok on the live project, live function md5 equals the replica." }
impact_analysis: >-
  A friend applying a code at the moment a payment-related session holds their subscription row sees an error and must retry; the
  referral is not recorded (the RPC rolls back). Rare, because the friend is usually on no subscription row yet (the row the helper
  locks exists only for a friend who already has an active row, for example a previous trial), but it is a regression from 158 where
  the same moment merely waited.
  .
  A SUBTLETY THE TEST HAD TO RESPECT. The final failure must abort the WHOLE call: the audit row is inserted before the retry loop and
  the sub-block rolls back only the grant attempt, so the final `RAISE` is what removes the audit row (C16b asserts zero audit rows).
  Swallowing the final failure would leave an audit row with no days granted (mutant c_swallow_final, killed by C16b).
  .
  NOT A RECURRENCE. A search of docs/diagnoses/INDEX.md for 55P03, NOWAIT and lock_not_available found no prior diagnose. The closest
  related fact is the migrations pitfall row on key-share locks (migration 159's own measured deadlock), which concerns the job, not
  the redeem.
related_bugs:
  - "hermes round 2, seat A finding 3 (2026-10-13): the finding behind ledger row N3 / OI-344 item 5."
  - "migration 158 replica schema lines 195-199: the plain UPDATE that waited."
recurrence: none
---

# 2026-10-16-redeem-referral-lock-wait-became-error-f2d6b8

See the frontmatter above: it is the record. The fix ships in migration 160 (docs/plans/referral-hardening-migration-160.md); the proof is the replica runs and the mutation table in `regression_test_planned`. Live apply, live verify and the ledger row are tracked in docs/audit/referral-hardening-migration-160.closure.yaml.
