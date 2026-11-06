---
bug_id: c5e9a3
date: 2026-10-16
batch: referral-migration-160
status: fixed
blast_radius: catastrophic
tier: full
symptom: >-
  The hourly referral reward job (`private.process_referral_conversions`, migration 159) can credit a referrer PRO days for a payment
  that no longer exists. A friend's account deleted BETWEEN the job's reconcile statement and its credit select leaves the
  redemption row with `referee_id` NULL (the foreign key is ON DELETE SET NULL) and a STALE `converted_at` (the friend's paid
  `subscriptions` row was deleted with the user by the cascade). The credit select reads only `converted_at`, the vest, `referrer_id`
  and the flag, so it credits the row; the next run's reconcile would have voided it. Found by plan-review and hermes round 2 (seat
  A, ledger row N1 / OI-344 item 1); not seen live (zero rows have ever been credited).
concept: referral_reward_on_conversion
sot_registry_entry: referral_reward_on_conversion
writers:
  - { file: supabase/migrations/159_referral_reward_on_conversion.sql, method: process_referral_conversions credit select, line: 272 }
  - { file: supabase/migrations/159_referral_reward_on_conversion.sql, method: process_referral_conversions reconcile, line: 231 }
  - { file: supabase/migrations/159_referral_reward_on_conversion.sql, method: private.grant_referral_days (the credit), line: 104 }
readers:
  - { file: lib/features/profile/repositories/referral_repository.dart, method_or_widget: hasRedeemed, line: 55 }
  - { file: supabase/migrations/160_referral_hardening.sql, method_or_widget: referrer_summary (counts credited and days earned), line: 326 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: referral_redemptions
cloud_columns: referee_id, converted_at, referrer_rewarded, referrer_credited_at
contract_test_path: test/sql/referral_pay_on_conversion_concurrency_local.sh
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: >-
  The fix adds `AND rr.referee_id IS NOT NULL` to the credit select. The reconcile (which voids a row whose referee is gone) is
  unchanged, so a deleted friend's row is never credited and is voided on the next run. Account deletion (delete-account) is
  untouched. The job still never waits for a lock (SKIP LOCKED, try advisory locks, NOWAIT).
forbidden_patterns_checked: >-
  Read every place that credits a referrer: `PERFORM private.grant_referral_days(r.referrer_id, r.reward_days)` is called from the
  credit loop only (pinned by `3c` in referral_pay_on_conversion_migration_test.dart). No other path credits the referrer.
proposed_fix: >-
  `CREATE OR REPLACE FUNCTION private.process_referral_conversions` in migration 160, identical to the 159 body except for ONE added
  predicate in the credit select (`AND rr.referee_id IS NOT NULL`). The Dart test compares the new body to the 159 body extracted
  from the immutable file with exactly that one change.
regression_test_planned: >-
  test/sql/referral_pay_on_conversion_concurrency_local.sh case C14 (replica only, two sessions plus a lock holder, deterministic:
  no sleeps, it polls pg_locks). It reproduces the window: the target row T (vested, converted, payment present) is inserted
  before a decoy D whose reconcile UPDATE fires a replica-only trigger that blocks on advisory lock K; session B deletes T's
  referee and holds the row lock uncommitted, so the reconcile SKIPS T (SKIP LOCKED); B commits while the job is blocked on D; the
  credit select then meets a committed row with referee_id NULL and a stale converted_at. Asserted: credited 0, T still converted /
  orphaned / unrewarded (proving it was skipped, not voided), the referrer holds 0 subscription rows, run 2 voids T and still
  credits nothing. MUTATED: removing the predicate (mutant c_no_predicate) reddens C14 with three FAIL lines ("run 1 must credit
  nothing", "T must still be converted, orphaned and unrewarded", "the referrer was credited for a deleted friend's stale
  payment"); every other case stays green, because within ONE run the reconcile voids such a row before the credit select (live
  verify Q8 documents that it is NOT a killer for this mutant). Source pin: group 6 of referral_pay_on_conversion_migration_test.dart.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No client code changes for this bug; the client counts surface is the separate Unit C plan." }
  - { tier: 2, name: hive, status: not_applicable, evidence: "No Hive involvement." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "Live read 2026-10-16: referral_redemptions has 11 columns, FKs referrer_id and referee_id are ON DELETE SET NULL, CHECKs referral_redemptions_reward_days_check and referral_redemptions_converted_coherent_check present." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Zero redemption rows have ever been credited by the job; the three legacy rows are outside the 97-day scan. No row is affected by the fix." }
  - { tier: 5, name: migrations_applied, status: verified, evidence: "Applied live 2026-10-17 06:21 IST (cloud version 20261017005132, file sha256 85a71a1a... equal to the reviewed file); live function md5s equal the replica (redeem b1973dd9, job 51d8a812, referrer_summary 162d3890); test/sql/referral_pay_on_conversion_live_verify.sql ran through execute_sql in eight aborting chunks (the tool rejects a single request of about 12 KB or more): 111 of 111 cases ok, nothing left behind; hourly job succeeded at 01:41, 02:41 and 03:41 UTC on the new body." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "No Edge Function is changed; redeem-referral does not call the job." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "referral_conversions_hourly, 41 * * * *, active (migration 159 A5 in the live verify); the fix changes the function body only, not the job." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "The job is SECURITY DEFINER and bypasses row security; no policy changes for this bug (the grants change is a separate item of the same migration)." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket involved." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Live verify on the live project 111 ok / 0 fail including chain cases F6a/F6b and Q8; replica concurrency suite C1-C17 passes with the predicate; the two-session proof (C14) is replica-only by nature." }
impact_analysis: >-
  No user has been affected (the job has credited nothing yet). The exposure is a referrer receiving up to 30 PRO days for a payment
  deleted with the friend's account, in a window that requires an account deletion to commit in the middle of one job statement
  sequence; the hourly job makes the window real over time and the consequence is free entitlement.
  .
  WHY THE OBVIOUS TEST DOES NOT CATCH IT. A single-session test cannot produce the state: within ONE run the reconcile (which
  voids a row whose referee is gone) runs BEFORE the credit select, so the stale row is voided first. The state needs a deletion
  that commits between the two statements, and the reconcile must have SKIPPED the row (it was locked by the uncommitted deletion)
  rather than voided it. The round-2 plan review caught a harness ordering that would have let the mutant survive: if the decoy
  row came before the target in heap order the reconcile would update the decoy first, the deletion would commit, and the
  reconcile would then follow the update chain and void the target in the same statement, so the missing predicate would never
  show. The fixture therefore inserts the target first (converted and vested IN the insert) and asserts the target was skipped,
  not voided.
  .
  NEAREST CLASS, NOT A RECURRENCE. Debugging class 2.25 (a precondition checked at the entry of an async operation and relied on
  at the side effect) has the same shape: the reconcile is the entry check, the credit select the side effect. A search of
  docs/diagnoses/INDEX.md for stale-credit, referee_id NULL and deleted-referee found no prior diagnose; this is the first.
related_bugs:
  - "hermes round 2, seat A (2026-10-13): the finding behind ledger row N1 / OI-344 item 1."
  - "migration 159 header, KNOWN LIMITS: lists a deleted referee as matching nothing in the reconcile but not the credit select."
  - "bug class 2.25: nearest class (check at entry, reliance later); not a recurrence."
recurrence: none
---

# 2026-10-16-referral-credit-select-stale-after-referee-deleted-c5e9a3

See the frontmatter above: it is the record. The fix ships in migration 160 (docs/plans/referral-hardening-migration-160.md); the proof is the replica runs and the mutation table in `regression_test_planned`. Live apply, live verify and the ledger row are tracked in docs/audit/referral-hardening-migration-160.closure.yaml.
