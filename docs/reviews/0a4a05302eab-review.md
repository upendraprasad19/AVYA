---
reviewed_at: 2026-10-17T09:30:00+05:30
staged_against: 0a4a05302eab (staged diff of branch referral-migration-160, the apply commit of migration 160)
blast_radius: catastrophic
reviewer: fresh-context-blind-sonnet-agents (2 seats, read-only, exhaustive command list, no database access)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 16
verdict: accepted
---

# Code Review (B-pass) - migration 160 (referral hardening, referrer_summary, 90 percent promo ceiling)

Two fresh, context-blind Sonnet seats reviewed the working tree of branch `referral-migration-160` BEFORE the live apply: seat A (SQL semantics, locking,
privileges) and seat B (proofs, tests, mutation adequacy, replica fidelity, registry, docs, ledgers). Both were told to find bugs, not validate. The
pre-apply tree they read is the tree of this commit except for the apply artefacts added afterwards: the `backups/applied_migrations.json` entry, the
removal of the six `160-PENDING-APPLY` markers, the live evidence in the two diagnose docs, the closure ledger `docs/audit/referral-hardening-migration-160.closure.yaml`,
the OI board moves (OI-344 archived, OI-342 and OI-336 text) and the context-budget re-baseline. The migration file is byte-identical to the file
applied live (sha256 85a71a1a...8ca, cloud version 20261017005132). A 4-seat hermes pass followed (`docs/audit/2026-10-16-hermes-referral-hardening-migration-160.md`, accepted).

**Overall verdict: SHIP-WITH-FIXES, no P0.** 1 P1, 2 P2, 13 P3 records (16 findings, two of them the same MAINTAIN gap seen by both seats). Every one was fixed in the batch
except one that is verified clean; the disposition of each is also a row of the closure ledger (`BP-*`). The migration was re-proven on the replica after the fixes
(live-verify 111 of 111, deletion D1-D7, concurrency C1-C17, more than 50 mutants).

## Findings and dispositions

### Seat A (0 P0, 0 P1, 0 P2, 5 P3)
- **A1 P3 guard_without_its_mirror - the rollback re-grants seven privileges, not MAINTAIN (relacl arwdDxtm).** FIXED: MAINTAIN in the rollback GRANT list, the Dart pin and the replica grant; case C17 EXECUTES the extracted rollback and diffs the result against a 159-only database.
- **A2 P3 missing_input - the header says "three app readers", there are two.** FIXED: the header says two.
- **A3 P3 blast_radius_mismatch - the promo ALTER (ACCESS EXCLUSIVE on promo_codes, read by four payment functions) ran first and was held to commit.** FIXED: the ALTER moved to the end, after the self-check; Dart pin on its position (mutant d_promo_first).
- **A4 P3 guard_without_its_mirror - the self-check never asserted the ACL of the two replaced functions nor referrer_summary's security mode.** FIXED: has_function_privilege for both, prosecdef, STABLE and proconfig; C15 scenarios 5 and 6.
- **A5 P3 asserted_fixture_value - the live promo values come only from the plan's catalog read.** VERIFIED CLEAN: ADD CONSTRAINT validates existing rows, so a row above 90 could only abort, never pass silently; the pre-apply live count outside 1..90 was 0 and the apply succeeded.

### Seat B (0 P0, 1 P1, 2 P2, 8 P3)
- **B1 P1 asserted_fixture_value / missing_input - live-verify Q9 inserted into promo_codes without the NOT NULL valid_until.** The replica declared the column nullable, so a CORRECT migration would have shown a red case on the live project while the replica was green. FIXED: Q9 inserts valid_until = current_date + 1; the replica carries the live shape (date NOT NULL); a Dart test requires every NOT NULL column of the live table to be supplied. Q9 passed on the live project.
- **B2 P2 guard_without_its_mirror - no case called referrer_summary() as a REFEREE, so an OR referee_id = uid mutant survived every behavioural case.** FIXED: case Q6g; mutant red.
- **B3 P2 writer_reader_drift - two registry statements said the 159 columns are readable by both parties.** FIXED in docs/sot_registry.yaml.
- **B4 P3 - MAINTAIN never exercised or restored.** Same finding as A1. FIXED.
- **B5 P3 - C14 could pass vacuously if the rendezvous never happened.** FIXED: the decoy trigger calls nextval('rpoc_c14_seq') after the unlock and C14 asserts it; an ordering guard (rpoc_c14_early) kills the NOWAIT mutant.
- **B6 P3 - C16b let a sleep after the last attempt through, and a 3 s holder could race a loaded host.** FIXED: holder 6 s, upper bound 700 ms, the holder released when the redeem is ASLEEP (pg_stat_activity wait_event PgSleep, snapshot cleared every poll).
- **B7 P3 - the Dart self-check pins were positive-only.** FIXED: whole-statement pins plus a negative pin forbidding aclexplode.
- **B8 P3 - registry citations and line ranges pointed at 159 and past function ends; a plan file that does not exist was cited.** FIXED.
- **B9 P3 - ledger wording (N1 "credit sub-block", N4 "mutants g_* all red") did not match the harness.** FIXED in docs/audit/referral-pay-on-conversion.closure.yaml.
- **B10 P3 - live-verify header, the Q3 TRUNCATE on a pre-160 database, the Q6f search_path.** FIXED: header updated, TRUNCATE only attempted when the privilege is gone, Q6f restores the saved search_path.
- **B11 P3 - docs stated the unapplied change in the present tense.** FIXED: the markers carried the state until the apply and are removed in this commit.

## What this commit adds on top of the reviewed tree (read these lines, not the migration)
- `backups/applied_migrations.json`: the entry for 160 (hash, cloud version, live evidence). Gates 14 and 39 pass.
- The six marker removals and the eight-chunk live-verify evidence (the Supabase tool rejects a single request of about 12 KB or more; the assertions are the file's, regrouped, and Z was checked within its chunk only).
- OI-344 archived to closed_issues.md; OI-342 gains the 90-versus-76.7/88.4 percent paragraph; OI-336 now calls referrer_summary() and carries the aggregates' residual.
- The context-artifact budget re-baseline (functions and migrations CLAUDE.md passed the 15 percent soft band, the hard band is 50).

## Rollback
The inline commented block at the end of 160_referral_hardening.sql (executed and diffed on a fresh replica, C17). It must be coordinated with the Unit C client release: dropping referrer_summary() makes a client that calls it fail on that line.
