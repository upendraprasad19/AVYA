---
reviewed_at: 2026-10-16
staged_against: hermes-report-verdict-line (commit 4a189d5e on top of main 745bdc95; the fixes below were made afterwards in 4225209f and f7f9f240)
blast_radius: platform (every changed path is feature tier or lower; the one-clause edit to supabase/functions/CLAUDE.md lifts the diff to platform)
reviewer: claude-sonnet-b-pass (fresh, context-blind; asked to be read-only with Read, Grep and Glob; see "Process deviation")
lens_set: [writer_reader_drift, asserted_fixture_value, guard_without_its_mirror, documentation_rot, blast_radius_mismatch, secrets_in_tree]
findings_count: 5
verdict: accepted
---

# Code Review (B-pass) - the hermes round-2 docs-and-tests batch for migration 159

A fresh reader with no access to the author's reasoning read the whole diff: three new SQL cases (X5, H1, H2) and a stricter W15 in the live-verify file, the anchored numeric matches and the new C13 ordering assertion in the concurrency script, two registry line ranges, the closure ledger, the hermes report, the OI-344 text and several stale-text fixes. **No P0, no P1; verdict accepted.** Five P3 findings, all verified by the reviewer; the author resolved or answered each one in the batch.

## Process deviation (disclosed)

The brief allowed Read, Grep and Glob only. Grep was not available in the reviewer's session, so it used Bash for read-only commands only (`git diff main`, grep, sed, wc). It ran no script, psql, dart or docker command and edited nothing. The effect is that it saw the exact diff and not only the files; it does not weaken the review.

## Findings

1. **P3 - `test/sql/referral_pay_on_conversion_concurrency_local.sh` (former lines 429, 450, 500): `'"failed": 1'` and `'"reconciled": 1'` were still unanchored** and would also match 10 to 19. RESOLVED: anchored with the trailing comma in 4a189d5e/4225209f; the remaining `"failed": 0` and `"reconciled": 0` matches were anchored too; the script still ends `CONCURRENCY OK` on a fresh replica. Not exploitable before (each case seeds one row).
2. **P3 - live verify X5: on a live project with 50 or more REAL vested creditable redemptions older than the fixture, r1's row would be starved and X5 would fail.** RESOLVED by documentation: the file now states the precondition in a comment above X5. It fails loudly, never passes vacuously; the live table has 3 legacy rows.
3. **P3 - W15 bounds are lower bounds** (real rows can only add to the counters), so a counter swap is caught only when fewer than 2 real voided rows exist. ANSWERED: acknowledged in the file header, benign; W14 also asserts a lower bound on reconciled and the replica run (exact counts) kills the swap (mutant MD reddens W14 and W15).
4. **P3 - ledger N14 `commit:` held prose instead of a SHA.** RESOLVED: the five closed_in_commit rows of this batch (N8, N9, N10, N11, N14) carry `4a189d5e`, and the ledger header says so.
5. **P3 - the X5 cleanup `DELETE ... (referrer_id IS NULL AND code = v_code)` targets rows by code alone.** ANSWERED: safe, `v_code` is `AVYA-VERIFY01`, the whole block always aborts with VERIFY_RESULTS and no earlier group leaves NULL-referrer rows with that code.

## Checked and clean (reviewer's list, abridged)

The X5 fixture satisfies the coherence CHECK and the 7/30 CHECK, NULL `referee_id` does not collide on UNIQUE, the 55 rows sit outside the 24-hour volume count and the stall watch; H1 and H2 are not vacuous and leave nothing behind; the shell edit's `psql_` call sits before `C13_R2`, quoting survives, `C13_LEFT_NEWEST` is 5 on a correct run; jsonb key order is failed, voided, credited, reconciled, skipped_locked so the anchors are right; registry ranges 113-186 and 5-35 match the files; no secret, token or key in any changed file; the OI-344 body matches the migration lines; the ledger has valid terminal states and no `deferred:` key.

## Not verified by the reviewer

It ran no SQL or shell. The author ran, after the fixes, on a fresh replica whose job function md5 equals the applied one: the live verify (`SUMMARY ok=89 fail=0 skipped=0`), the concurrency script (`CONCURRENCY OK`), six new mutants (each applied, each reddening exactly its case), the re-run of M02, M05, M17 and M22, the two referral contract tests (47 of 47) and the full local suite (9628 passed, 0 failed, at 4a189d5e). The live-grant claim in OI-344 item 3 was read by the author from the live catalog on 2026-10-16.
