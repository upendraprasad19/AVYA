---
reviewed_at: 2026-09-30
branch: oi-182-202-subscription-state
staged_against: oi-182-202-subscription-state Commit 2 (migration 152, ledger, schema snapshot, board move, SoT, diagnose, Hermes report)
blast_radius: catastrophic
reviewer: one fresh context-blind B-pass reviewer (read-only, no DB access), dispatched per §4.3 after the live dry-run and apply
lens_set: [rollback_accuracy, test_discriminates_fix, self_attesting_artifact, writer_reader_drift, ledger_hash_integrity]
findings_count: 5
verdict: accepted
---

# B-pass: oi-182-202-subscription-state (Commit 2)

Scope: `supabase/migrations/152_drop_users_subscription_mirror.sql` (already applied live as
`20260930065332`), its ledger entry and sha256, the `users` schema snapshot, the OI-202 board move
(open to closed, index regenerated), the SoT entry, the diagnose-doc, the Hermes report and the
13-test migration text contract.

Result: no P0, no P1. The reviewer re-proved the partition
(`pro_active + pro_expired + free == total` for any status value and for soft-deleted users), the
drop order, the REVOKE/GRANT re-issue, the rollback against the snapshot and migrations 093/094, the
ledger hash (`dart run scripts/migration_ledger_hash.dart 152` equals the recorded value), both JSON
files, the 94-line board move byte-for-byte, and a classified sweep of every remaining mention of the
dropped names (none is a live reader or writer).

## Findings

| # | Sev | Where | Finding | Terminal state |
|---|---|---|---|---|
| 1 | P2 | migration test, privileges group | The GRANT check was a bare substring, so `TO service_role, authenticated` still passed and would have opened a SECURITY DEFINER function. | Fixed in the test: whole statement with `;` plus a sole-grantee regex. Mutation A (grant widened) reddens 2. |
| 2 | P3 | migration test, `_code()` | Only `--` comments were stripped, so a DROP COLUMN hidden in a `/* */` block still satisfied the order tests. | Fixed: block comments stripped. Mutation B reddens the order test. |
| 3 | P3 | migration test, founder_metrics group | Only pro_active, pro_expired, free_users and the CTE were pinned. Dropping `where status = 'active'` from `active_subscriptions` passed. | Fixed: the six unchanged column expressions are pinned. Mutation C reddens 1. |
| 4 | P3 | migration test, rollback group | The rollback's trigger, function bodies, columns and 093 body were unpinned, and `-- START TRANSACTION;` would pass. | Fixed: the reverse DDL is pinned (un-commented and normalized) and the transaction-control regex covers BEGIN/COMMIT/START TRANSACTION. Mutations D and E redden 1 each. |
| 5 | P3 | migration file lines 9 and 67 | Plain `SET lock_timeout` + closing `RESET` would leak the 5s timeout into a pooled session if a non-transactional runner died between them. | verified_clean: the file is applied and immutable, and the postgres log shows `apply_migration` wraps the file in begin/commit, so both ran in one transaction. The header's "unverified" sentence is corrected in the diagnose-doc. |

Each mutation was a single-occurrence replace on a copy, confirmed applied, and the SQL restored with
`cp` and re-hashed equal to the ledger. None was a compile error; each red was read, not counted.
Mutations were run against the final 16-test file.

## Not findings

- `active_subscriptions` still counts any `status='active'` row, including expired or deleted users.
  Unchanged from migration 093, not a regression.
- Historical `open_issues.md:NNNN` self-citations in old plan and audit docs were already stale and
  are not gated. This diff shifts them again but did not introduce the class.
