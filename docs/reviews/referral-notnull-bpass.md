---
reviewed_at: 2026-06-16
batch: referral-notnull-fix
diagnose: a1c9f4
blast_radius: account
reviewer: fresh context-blind subagent (B-pass, §4.3 self-initiated, pre-merge)
verdict: accepted
---

# B-pass — referral subscriptions NOT-NULL fix (a1c9f4)

Self-initiated per §4.3 (account-tier schema + shared-trigger change). The implementation
plan was already reviewed twice (§4.12); this pass reviewed the ACTUAL CODE for implementation
defects + faithfulness. All facts verified read-only against live `dedsavbjuwgarrhphgnl`.

## Scope reviewed
- `supabase/migrations/094_subscriptions_razorpay_nullable.sql` (3 DROP NOT NULL + trigger GREATEST)
- `scripts/check_schema_payload_parity.dart` (Gate-19 ordered SET/DROP resolver)
- `test/sql/onconflict_live_arbiter.sql` (2 live cases: RPC-grant + GREATEST monotonicity)
- `test/contracts/referral_trial_subscription_grant_test.dart` (CI presence test)
- `docs/diagnoses/2026-06-16-referral-subscriptions-notnull-a1c9f4.md`, `docs/sot_registry.yaml`

## Findings
1. **Migration trigger attribute preservation** — clean. `pg_get_functiondef` (live) vs the
   CREATE OR REPLACE: all 4 attributes preserved (LANGUAGE/SECURITY DEFINER/search_path/IF-guard);
   only the expiry RHS changed.
2. **GREATEST correctness** — clean. Live DO-block: unqualified `subscription_expires_at` = OLD
   row value in `UPDATE users SET`; 365d-vs-7d keeps 365d; NULL old coalesces to NEW.end_date.
   Never lowers nor NULLs expiry.
3. **3 DROP NOT NULLs** — clean. Right table+columns (live confirms is_nullable=NO/no-default);
   0 referral_trial rows → nothing stranded; idempotent; 4-tag header present.
4. **UNIQUE-NULL safety** — clean. `unique_razorpay_payment_id` indnullsnotdistinct=false → 2
   NULL-payment_id referral rows don't collide.
5. **Gate-19 resolver** — clean. `check_schema_payload_parity.dart` exit 0 ("auditing 6" — razorpay_*
   dropped); lexical sort + source-ordered `allMatches` resolve 052(SET)→094(DROP)=relaxed; downstream
   callsite scan intact.
6. **Test red/green honesty** — clean. Both live cases genuinely error pre-094 (23502) and pass
   post-094; presence test's `_stripSql` neutralizes the rollback comment's `= NEW.end_date`;
   `flutter test` 5/5.
7. **Diagnose-doc + SoT** — clean. `validate_diagnose_doc.dart` OK; SoT writers/readers accurate.
8. **Faithfulness / drift** — clean. Matches the approved plan; no leftover debug, no secret-shaped
   literals; `blast_radius: account` defensible (paid path always SETs the IDs; GREATEST monotone-safe).

## NIT (resolved in this batch)
- `check_schema_payload_parity.dart` header comment claimed it scanned inline `CREATE TABLE … NOT
  NULL` — it was always ALTER-only (pre-existing, confirmed via `git show main:`). Comment corrected
  in this commit (no-deferral).

## Verdict
**ACCEPTED.** No blockers. The single NIT (stale comment) was fixed in-batch. Remaining steps gated
on the founder: live `apply_migration` (094) + the in-app AVYA-TESTCODE smoke.
