---
hermes_pass_id: 2026-10-16-hermes-referral-hardening-migration-160
ran_at: 2026-10-16T23:40:00+05:30
batch_scope: working tree of branch referral-migration-160 (migration 160 untracked by design, tests, registry, docs), after the B-pass
lens_set: [L1, L14, L22, L23, L25, L29, L34, L35, L40]
agents_dispatched: 4
findings_total: 27
findings_by_severity: { P0: 0, P1: 0, P2: 8, P3: 19, false_alarm: 0 }
verdict: accepted
---

# Hermes pass - migration 160 (referral hardening, referrer_summary, promo ceiling)

Four fresh Sonnet seats (founder rule: Sonnet only, at most four at once), read-only with an exhaustive command list, no database access.
Seat A: SQL semantics, locking, PostgREST (L1 L14 L22 L35). Seat B: abuse, privacy, information leakage (L23 L29 L40). Seat C: test and mutation
adequacy, second look (L1 L22 L34). Seat D: apply protocol, rollback, ledgers, docs, gates (L1 L25 L34 L35). The B-pass had already run and its
fixes were in the tree the seats read. No seat found a P0 or a P1. Every finding below has exactly one terminal state; the migration was
re-proven on the replica after the fixes (live verify 111 ok / 0 fail, deletion D1-D7, concurrency C1-C17, more than 50 mutants).

## Summary
- 0 P0, 0 P1, 8 P2, 19 P3, 0 false alarms.
- Ship-blockers: none.
- One finding needs the founder (B1, the promo ceiling against the break-even): terminal state `blocked_on_user`, tracked by OI-342.

## Findings and dispositions

### Seat A (SQL, locking, PostgREST)
- **A1 P2 L35 - the inline rollback was never executed; the table-level GRANT leaves the six column-level SELECT entries.** FIXED: the rollback now starts with `REVOKE ALL ON public.referral_redemptions FROM anon, authenticated` and the new replica case C17 EXTRACTS the commented block from the migration text, applies it over 159+160 and compares md5 of both function definitions, sorted relacl, column ACL count, the promo CHECK, referrer_summary and both function ACLs with a 159-only database. Mutants red: rollback without REVOKE ALL, without MAINTAIN, with the wrong promo bound (C17); Dart pins `d_rollback_no_revokeall`, `d_rollback_no_maintain`.
- **A2 P3 L35 - "aborts the whole migration" overstated if the apply runner is not transactional.** FIXED: the migration header states the transaction-wrapped case and the statement-by-statement case (every earlier statement only narrows access, the promo CHECK is last and skipped, the file is idempotent).
- **A3 P3 L22 - after a 55P03 retry succeeds, the `referee_has_paid_plan` check is not re-run.** FIXED: the retry handler re-checks the same predicate after every pause and raises P0001 (rolls the call back). New case C16d (a paid row lands during the wait: P0001 after ONE helper attempt, no audit row); mutant `c_no_revalidate` red (C16d and the Dart redeem-body equality).
- **A4 P3 L14 - `MAINTAIN` exists only on PostgreSQL 17.** DOCUMENTED in the header: live is 17.6, the check fails closed ("unrecognized privilege type") on an older server.

### Seat B (abuse, privacy)
- **B1 P2 L29 - the 90 percent ceiling sits above the 76.7 percent break-even OI-342 names.** `blocked_on_user`: plan 2.6, closure ledger N5 and OI-342 now state it (monthly 90 percent = 3490 paise earns 7 days worth about 81 rupees; yearly = 29990 paise earns 30 days worth about 349). The ceiling still closes the technical hole (no 91-100 percent code, no 0-paise order); the economics floor is the founder's call, OI-342 stays open.
- **B2 P2 L40 - shipped invite copy says "you both get 7 days" (pre-existing, commit 3874196f).** `upstream_blocked` on Unit C, already listed in OI-336 ("What to build"); no new text contradicts the aggregate-only rule.
- **B3 P3 L40 - OI-336's data-source paragraph says the client reads the table.** FIXED in the apply commit (OI-336 rewritten to "call referrer_summary()", X7 residual appended).
- **B4 P3 L40 - a paying friend who deletes their account makes `subscribed`/`pending` drop (a deletion signal).** FIXED: stated in the migration header residual, plan 2.4 and ledger X7.

### Seat C (test adequacy)
- **C1 P2 L34 - the table-level C15 scenario did not exercise the table loop.** FIXED: scenarios now name their own clause (INSERT to authenticated, DELETE to authenticated, MAINTAIN to anon). Mutants red: table loop deleted, privilege array cut, role array cut to anon.
- **C2 P3 L34 - the PUBLIC `aclexplode` clauses of the self-check were unreachable (anon inherits PUBLIC).** FIXED: removed; a Dart negative pin forbids `aclexplode` in the block; the catalog check A10 keeps the aclexplode read.
- **C3 P3 L22 - no fixture had a NULL `referrer_rewarded`.** FIXED: case Q6h; mutant `s_pending_eq_false` red.
- **C4 P3 L1 - C16a's holder could release when attempt 1 merely STARTED (rare false red).** FIXED: the holder now waits for the redeem to be ASLEEP (`pg_stat_activity` wait_event PgSleep, snapshot cleared every poll, a trap found while fixing it).
- **C5 P3 L1 - script header drift (two C15 scenarios, 3 s hold, 2 s bound).** FIXED.
- **C6 P3 L34 - the live-verify SUMMARY is a count nobody pins.** FIXED: a Dart test requires every migration-160 case id exactly once; the SUMMARY now counts a NULL case as a failure (`ok IS NOT TRUE`), found when a mutant printed `fail=0` beside a failing line.
- **C7 P3 L1 - the Dart test read the migration at collection time.** FIXED: absent file is a clear failure of group 6 only.
- **C8 P3 L34 - mutants killed only by Dart text pins (`1..4` with the `IF v_attempt = 3` test unchanged, a 0.30 s sleep, the `lock_timeout` lines).** `verified_clean` as behaviourally equivalent or bounded by an exact-text pin, written in diagnose f2d6b8; the promo ALTER position and the lock_timeout order are pinned (mutant `d_promo_first`).

### Seat D (apply, docs, gates)
- **D1 P2 L25 - three docs named the wrong party for the exposure.** FIXED (ADR-0021, payment.md, the registry): the REFERRER could read when each named friend paid and on which plan.
- **D2 P2 L25 - ADR cited ledger N2 as an alert-counter race.** FIXED (N2 is the credit-batch ORDER residual).
- **D3 P2 L35 - Gate 14, the parity test and the single full-suite red are expected until the ledger row exists.** FIXED: plan section 5 step 3 says so.
- **D4 P2 L35 - the apply commit needs a review file for ITS staged diff plus a tuning-history entry; the plan-review record cites it and must land in a later commit.** FIXED in the plan (section 4); executed at the commit.
- **D5 P3 L1 - stale 159 line cites in the registry.** FIXED (re-pointed to 160).
- **D6 P3 L25 - plan section 4 said no `closes-oi: OI-344`.** FIXED: OI-344 closes entirely in the apply commit (items 1, 3, 4, 5 closed, item 2 verified_clean).
- **D7 P3 L25 - header "four review rounds"; "authenticated only" vs service_role.** FIXED before the apply (the header is hashed afterwards).
- **D8 P3 L34 - diagnose count stale; "pins to re-point" not done.** FIXED: counts updated; `redeem_referral_paid_referee_migration_pin_test.dart` now reads the latest definition (160, else 159); the other listed tests read no migration text (verified); `onconflict_live_arbiter.sql` case 27 calls the function and is behavioural.
- **D9 P3 L25 - no step removes the `160-PENDING-APPLY` markers; the pitfall row names `relacl` but column privileges live in `attacl`.** FIXED: step in plan section 4; pitfall row names both.
- **D10 P3 L34 - `supabase/functions/CLAUDE.md` and `supabase/migrations/CLAUDE.md` pass the 15 percent soft band of the context budget.** FIXED in the apply commit by `check_context_artifact_budget.dart --record` (the hard band is 50 percent).
- **D11 P3 L35 - the rollback does not say it must be coordinated with the Unit C client release.** FIXED: a COORDINATION note at the head of the rollback.

## Lens signal
L35 4/4 real, L25 5/5, L34 6/6, L22 2/2, L1 5/5, L40 3/3, L29 1/1, L14 1/1 (documentation only), L23 found nothing: every cross-user path stays behind `auth.uid()` or service-role-only functions.

## Lessons for the skill history
1. A reviewer that cannot run SQL still finds what the author's proofs missed when the brief hands it the author's mutant list: seat C produced three surviving mutants (a table loop no scenario exercised, a NULL flag no fixture held, a holder that could release too early).
2. A retry must re-validate the precondition it waited on (seat A): the original 159 check-then-act gap was widened by the wait.
3. `pg_stat_activity` is a per-transaction snapshot: a polling loop inside one transaction never sees another session change state unless it calls `pg_stat_clear_snapshot()`.
4. A pass/fail counter that counts `ok` and `NOT ok` leaves a NULL case uncounted: use `IS TRUE` / `IS NOT TRUE`.

## Founder triage
B1 (promo ceiling against the break-even) is the only item that needs the founder.
