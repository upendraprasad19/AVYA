---
reviewed_at: 2026-10-16
reviewer: round 1 (2026-10-13) four fresh context-blind Sonnet seats; round 2 (2026-10-16) four fresh context-blind Sonnet seats, read-only (Read, Grep, Glob only; three of the four could not search and read files directly)
findings: round 1 no P0, no P1; round 2 no P0, no P1, P2s (seat B: a test gap on the NULL-referrer filter; seat C: stale ledger states and a contradicted row; seat D: privacy exposure, refund and chargeback not seen, promo ceiling is a promise), the rest P3; every finding is resolved in the batch or has a terminal state in docs/audit/referral-pay-on-conversion.closure.yaml (rows N1-N15, X7, X9, X10, U1, U2)
verdict: accepted
---

# Hermes pass and mutation evidence - referral reward on conversion (unit S1, migration 159)

Date: 2026-10-13. Four fresh, context-blind Sonnet seats (A SQL semantics and locking; B tests, mutation adequacy and live-verify safety; C docs, registry and gates; D abuse, economics, privacy, security and the live-apply protocol) read the post-B-pass tree, read-only. **No P0, no P1 from any seat.** Verdicts: A sound; B sound with fixes; C sound with fixes; D sound with fixes. Every finding was verified against the tree by the author and resolved in the batch or given a terminal state in `docs/audit/referral-pay-on-conversion.closure.yaml`.

## Findings and dispositions

| Seat | Finding | Disposition |
|---|---|---|
| A | A1 P3 wording "never waits for a lock" (it holds for row and advisory locks only) | Fixed in the migration header (immutable once applied), ADR-0021, the registry, CRON_REGISTRY. No function-level `lock_timeout` on purpose (it would fail the whole run on benign DDL contention). |
| A | A2 P3 an unbounded batch in one transaction (subtransaction ids, locks held to the end of the run) | Fixed: `LIMIT c_batch` (50 per run); concurrency C13 (55 rows: 50 then 5); mutants M105, M106. |
| A | A3/A4/A5 stale numbers and cites; hourly `FOR UPDATE` of every in-scan row; no CHECK ties `referrer_credited_at` to the flag | Cites re-pointed; A4 accepted (3 rows today); A5 correct as built. |
| B | F1 P2 session-level advisory lock mutants were Dart-only | Concurrency C10; mutants M89-M91. |
| B | F2 P2 live verify lost the FK, nullability and RLS catalog checks of the old file | Restored as A6-A9 (A9 also covers `subscriptions`); the replica now models RLS on `subscriptions`. Live read 2026-10-13: both tables RLS on, SELECT-only policies. |
| B | F3 P2 the coherence CHECK was tested in one direction; column types unchecked | K3; A4 checks `data_type`; mutants M102, M103. |
| B | F4 P2 alert-write isolation had no behavioural test | Concurrency C11 (a trigger refuses every alert INSERT; the job still credits); mutants M93-M95. |
| B | F5 P2 `FOR KEY SHARE` to `FOR SHARE` was Dart-only | Concurrency C5e (a `FOR NO KEY UPDATE` holder); mutant M92. |
| B | F6 P2 a false plan claim (X3 kills dropping `referrer_id IS NOT NULL` from the credit select) | Corrected in the plan; that mutant (M22) was Dart-pin-only in round 1 and masked by the `NOT FOUND` branch for the alert-based cases; round 2 killed it behaviourally with verify X5, a starvation case round 1 did not consider (see Round 2). |
| B | F7 P2 the live-verify header understated its blast radius | Rewritten. |
| B | F8-F10 P3 and Q2 mutation classes | SUMMARY now reports `skipped=`; W14-W16 (counter swap, lower bound), P6 (expired status), S5/S6 (dedup edge), C12 (locked payment row), second-apply assertion in the runner; M96-M101. Two classes were called equivalent in round 1 (helper `<` vs `<=` at exactly now(); the second `IS DISTINCT FROM` arm); round 2 proved both killable (verify H1 and H2, mutants MB and MC) because now() is frozen inside the transaction and a plan can be edited in place. Only the ORDER BY id tie-break among identical candidates stays equivalent. |
| C | F1 P2 two docs still stated the withdrawn cap | `payment.md` and `supabase/migrations/CLAUDE.md` reworded. |
| C | F2 P2 plan 2.1 did not describe the code | Synced (stall watch first, three alerts, `LIMIT c_batch`). |
| C | F3 P2 units S2 and C had no terminal state | Ledger entries. |
| C | F4 P2 the mutation evidence was not in the repo | This file. |
| C | F5-F11 P3 | Wording, ADR headings (`Status`, `Alternatives considered`), section 4.6 position, registry precision, case-count numbers dropped, break-even unified at 76.7 percent. |
| D | D1 P2 promo exposure | Live read: 3 codes, all active, maximum discount 30 percent, none unbounded (plan section 6). |
| D | D2 P2 the volume alert carried no numbers | `context_json` now carries `redemptions_24h` and the largest per-referrer count (M104). A per-referrer concentration alert needs a baseline: `blocked_on_user`. |
| D | D3 P2 the referrer can read the friend's payment time and plan class | `blocked_on_user` (a disclosure line for Unit C and the privacy policy text). |
| D | D4-D6 P3 | Retention accepted; rollback `SET lock_timeout` added; naming row updated; `p_days` bounded by the helper and the CHECK. |
| B-pass (earlier) | finding 1 a stalled reward is invisible | The `referral_conversions_stalled` alert, counted BEFORE the job lock (a reviewer's suggested placement inside the job would have missed exactly the held-lock case). |
| B-pass (earlier) | finding 3 the live verify could be silenced by the bug it should catch | `v_pre` read at the start; case Z; mutant M78. |

## Mutation matrix (rule 21; self-attested, run on a local replica of the live objects)

104 mutants of the final migration (sha256 `74631ee7d4ba2d3fe1b0b3b54a98ddae84652d38e8957fe66a115b09f6740df1`), each applied twice to a fresh replica database (the second apply must succeed and leave one cron job), then the live verify (86 cases), the deletion file (D1-D7), the concurrency script (C1-C13) where the mutant touches locking, and the Dart contract test. **0 survivors.** 100 are killed by a behavioural SQL case; the other 4 (M22, M32b, M32c, M32e) are killed by Dart pins and cannot have a behavioural twin: M22 (dropping `referrer_id IS NOT NULL` from the credit select) is masked by the `NOT FOUND` branch after the key-share read, and the double mutants that remove both guards (M76, M77) are killed by verify X3/F3; M32b/M32c are ACL edits that `CREATE OR REPLACE` preserves; M32e is a REVOKE on a function in schema `private`. The runner is a scratch script (compute-before-write, restore in `finally`, sha check) and is not committed. **Round 2 correction (2026-10-16):** M22 does have a behavioural twin, verify X5 (55 older NULL-referrer rows starve the 50-row credit batch when the filter is dropped, a mechanism round 1 did not consider): 101 behavioural, 3 Dart-only (M32b, M32c, M32e).

| id | mutant | killed by (behavioural) | Dart pin |
|---|---|---|---|
| M01 | drop the paid-referee refusal (RAISE replaced by NULL) | verify R4,R5,R6 |  |
| M02 | redeem refusal: drop AND razorpay_payment_id IS NOT NULL | verify aborts at R8 (the refusal fires for a referee whose only row has no payment id); re-run 2026-10-16 |  |
| M03 | reconcile: drop s.razorpay_payment_id IS NOT NULL | verify P2 |  |
| M04 | redeem refusal: drop the plan IN clause | verify R11,R12 |  |
| M05 | reconcile: drop the s.plan IN clause | verify aborts: the coherence CHECK (23514) fires inside the job; re-run 2026-10-16 |  |
| M06 | window edge: start_date >= created_at becomes > | verify W14,W4 |  |
| M07 | window edge: start_date >= created_at becomes <= | verify W14,W1,W2,W3,W5,W16…; deletion D2,D3 |  |
| M08 | window edge: start_date <= created_at+window becomes < | verify W14,W5 |  |
| M09 | window edge: start_date <= created_at+window becomes >= | verify W14,W1,W2,W4,W6,W8…; deletion D2,D3 |  |
| M10 | scan operator > becomes >= | verify W7 |  |
| M11 | reconcile: drop s.status = active | verify P4,P6 |  |
| M12 | reconcile: drop s.cancelled_at IS NULL | verify P5 |  |
| M13 | order the earliest payment LATEST | verify W9,W10 |  |
| M14 | converted_at := now() instead of the payment start_date | verify W1,W13,W9,W10,V2,V2b…; deletion D3 |  |
| M15 | drop the vest (credit selects every converted row) | verify W5,V1,V2b,X1b,X1c; deletion D2,D3 |  |
| M16 | swap the 7/30 arms (both CASEs) | verify W1,W2,W4,W5,W8,W9…; deletion D3 |  |
| M17 | add ELSE 7 to the reward CASE (both) | verify aborts: the coherence CHECK (23514) fires inside the job; re-run 2026-10-16 |  |
| M18 | scan 97 -> 130 days | verify W7,L1 |  |
| M19 | reconcile candidates: IS NOT TRUE becomes a bare NOT | verify V10,V11 |  |
| M20 | reconcile candidates: drop referrer_rewarded IS NOT TRUE | verify X4b; deletion D3 |  |
| M21 | reconcile candidates: drop the OR converted_at IS NOT NULL arm | verify W15,W11 |  |
| M22 | credit select: drop referrer_id IS NOT NULL | verify X5 (round 2, 2026-10-16) | Dart pin |
| M23 | flag UPDATE by referrer_id instead of id | verify V2,V2b,V4,V9,V10,V11…; deletion D3,D4 |  |
| M24 | referrer try-lock replaced by the blocking lock | concurrency C3 |  |
| M25 | drop the users-row key-share pre-check | concurrency C5,C5c |  |
| M26 | helper: drop NOWAIT | concurrency C4 |  |
| M27 | helper: drop the bounds check | verify F5.1,F5.2,F5.3,F5.4,F5.5 |  |
| M28 | helper: drop the status = 'active' read filter | verify V8 |  |
| M29 | drop the ROW_COUNT = 1 check | concurrency C6 |  |
| M30 | credit the referrer inside the redeem function | verify R2,F6a,F6b; deletion D7,D1,D2,D3 |  |
| M31 | drop the NULL guard of the redeem function | verify R10,R10b,R11,R12 | Dart pin |
| M32a | drop REVOKE FROM PUBLIC on the job function | verify A2 |  |
| M32b | drop REVOKE FROM anon, authenticated on the redeem RPC | - | Dart pin |
| M32c | drop the GRANT to service_role | - | Dart pin |
| M32d | drop REVOKE FROM PUBLIC on the helper | verify A2 |  |
| M32e | drop REVOKE FROM anon, authenticated on the job function | - | Dart pin |
| M33 | change the schedule | verify A5 |  |
| M34 | drop the jobid-form unschedule (idempotency) | verify A5 |  |
| M35a | failed alert: drop the dedup WHERE NOT EXISTS | verify F3,F4 |  |
| M35b | volume alert: drop the dedup WHERE NOT EXISTS | concurrency C7 |  |
| M36 | both alerts under one source | verify S4,F3; concurrency C7,C8 |  |
| M37a | volume: credits > becomes >= | concurrency C7 |  |
| M37b | volume: redemptions > becomes >= | concurrency C7 |  |
| M38 | volume threshold constant 10 -> 11 | concurrency C7 |  |
| M39a | reconcile candidates: drop SKIP LOCKED | concurrency C5b,C5d |  |
| M39b | credit select: drop SKIP LOCKED | concurrency C5d |  |
| M40 | job-level try-lock replaced by the blocking lock | concurrency C2,C2b |  |
| M41 | helper: UPDATE every active row of the user instead of the one by id | verify V7,V11 |  |
| M42 | redeem: lock the REFERRER's key instead of the referee's | concurrency C1,C8 |  |
| M44 | flag UPDATE does not stamp referrer_credited_at | verify V2,X4b; deletion D3 |  |
| M47 | window 90 -> 60 days | verify W14,W5 |  |
| M48 | vest 7 -> 3 days | verify W5,V1,V2b,X1b,X1c; deletion D2,D3 |  |
| M49 | credit grants a fixed 7 days instead of the row reward_days | verify V5,V9; deletion D3 |  |
| M52 | users-row lock: FOR KEY SHARE without NOWAIT | concurrency C5c |  |
| M53 | drop the lock_not_available handler (a skip becomes a failure) | concurrency C4,C5c |  |
| M55 | audit row: referrer_rewarded true at redemption | verify R3,F6b; deletion D7,D1,D2,D3,D4 |  |
| M56 | audit row: referee_rewarded false | verify R3 |  |
| M57a | audit row: days_granted_each hard-coded 7 | verify R12 |  |
| M57b | referee grant hard-coded 7 days | verify R12 |  |
| M58a | helper INSERT end_date hard-coded 7 days | verify V5,F5.5; deletion D3 |  |
| M58b | helper UPDATE extends by a hard-coded 7 days | verify R12,V9,F5.5 |  |
| M59 | coherence CHECK made trivial | verify K1,K3 |  |
| M60 | reward-days CHECK widened to allow 8 | verify K2,K3 |  |
| M61a | redeem refusal list: yearly dropped | verify R5 |  |
| M61b | reconcile list: yearly dropped | verify W14,W2,W10,V5,V9,X1c; deletion D3 |  |
| M62 | credit-loop lock key uses another prefix (not the redeem key) | concurrency C1,C3,C8 |  |
| M65 | failed alert never written | verify F3,F4 |  |
| M66 | failed alert written as critical | verify F3,F4 |  |
| M68 | reconcile candidates: drop referrer_id IS NOT NULL | deletion D4 |  |
| M71 | LEFT JOIN LATERAL becomes an inner JOIN LATERAL | verify W15,W11,X1b,X2; deletion D2 |  |
| M72 | helper reads the EARLIEST-ending active row | verify V7,V11 |  |
| M73 | helper extends a lapsed row instead of inserting a new one | verify V11 |  |
| M74 | reconcile: drop the IS DISTINCT FROM guard (steady state rewrites) | verify W13; concurrency C3,C4 |  |
| M75 | drop the ROW_COUNT guard handler: swallow failures silently (no failed count) | verify F3,F4 |  |
| M76 | DOUBLE (M22+M25): no referrer_id IS NOT NULL in the credit select AND no key-share pre-check: a NULL-referrer row reaches the helper | verify X3,Z,F3 |  |
| M77 | DOUBLE (M22+M25) plus a referrer try-lock that treats NULL as acquired: same family, different shape (lock first) | verify X3,Z,F3 |  |
| M78 | credit select: drop referrer_rewarded IS NOT TRUE (B-pass finding 3) | verify Z,F3; deletion D4 | Dart pin |
| M80 | stall watch moved AFTER the job lock (a held lock hides a stall) | concurrency C2b | Dart pin |
| M81 | stalled alert: drop the dedup WHERE NOT EXISTS | verify S3,S5,S6; concurrency C2b | Dart pin |
| M82 | stall edge <= becomes < | verify S2 | Dart pin |
| M83 | stall constant 10 -> 11 days | verify S2 | Dart pin |
| M84 | stall count: drop referrer_id IS NOT NULL (a deleted referrer counts) | verify S1 | Dart pin |
| M85 | stall count: drop referrer_rewarded IS NOT TRUE (a credited row counts) | verify S1 | Dart pin |
| M86 | stalled alert severity critical (would page Telegram) | verify S2,S3 | Dart pin |
| M87 | stalled alert written under the failed source | verify Z,S2,S3,S6,F3,F4 | Dart pin |
| M88 | stall alert fires at v_stalled >= 0 (always) | verify S1,S2 | Dart pin |
| M89 | redeem: xact advisory lock becomes a SESSION lock | concurrency C10 | Dart pin |
| M90 | job lock: xact try-lock becomes a SESSION try-lock | concurrency C10 | Dart pin |
| M91 | referrer lock: xact try-lock becomes a SESSION try-lock | concurrency C10 | Dart pin |
| M92 | users row lock FOR KEY SHARE becomes FOR SHARE | concurrency C5e | Dart pin |
| M93 | failed-alert block loses its EXCEPTION clause | concurrency C11 | Dart pin |
| M94 | volume-alert block loses its EXCEPTION clause | concurrency C11 | Dart pin |
| M95 | stall-alert block loses its EXCEPTION clause | concurrency C11 | Dart pin |
| M96 | reconcile lateral locks the PAYMENT row (FOR UPDATE OF s) | concurrency C12 | Dart pin |
| M97 | stalled dedup window 23 hours -> 1 hour | verify S5 | Dart pin |
| M98 | stalled dedup window 23 hours -> 48 hours | verify S6 | Dart pin |
| M99 | return value: reconciled and voided swapped | verify W14 | Dart pin |
| M100 | payment status active becomes <> cancelled | verify P6 | Dart pin |
| M101 | window lower bound loosened by one second | verify W16 | Dart pin |
| M102 | coherence CHECK made one-directional | verify K3 | Dart pin |
| M103 | converted_at column type timestamptz -> timestamp | verify A4 | Dart pin |
| M104 | volume alert context loses redemptions_24h | verify S4 | Dart pin |
| M105 | credit select: drop LIMIT c_batch | concurrency C13 | Dart pin |
| M106 | batch constant 50 -> 500 | concurrency C13 | Dart pin |

## Round 2 (2026-10-16) - re-run after the merge-time plan-review gate failed on this file

Why: the main-branch job "Plan-review record" failed on ff0858f6 (the #114 merge) because this report carried no line-anchored `verdict: accepted`. That gate reads each commit of the pushed range at its own tree, so the failed run is historical: main CI on the next merge (745bdc95) passed every job. The report still had no recorded verdict, so the founder chose to re-run the review (four fresh seats) so the verdict is not just the author's attestation. The tree read was main at 745bdc95 (migration 159 and both pull requests merged). The seats could use only Read, Grep and Glob; seats A, B, C and D could not search (Grep and Glob were unavailable to them), so each read named files directly and said what it did not cover. Each report was treated as a claim and the load-bearing ones were re-checked by the author against the files and, read-only, against the live project (see "Re-checked" below).

| Seat | Verdict | Highest | Where it is resolved |
|---|---|---|---|
| A SQL semantics and locking | sound with fixes | P3 (six findings) | N1, N2, N3 (need migration 160, OI-344), N13 (verified_clean) |
| B tests, mutation adequacy, live-verify safety | sound with fixes | P2 (finding 1) | N8, N9, N10, N11 closed in this batch; N12 verified_clean |
| C docs, registry, gates, ledgers | sound with fixes | P2 (findings 1 to 3) | N14 and the re-stated rows X3, X9, U1, U2, D4; X10 added |
| D abuse, economics, privacy, security, apply protocol | sound with fixes | P2 (findings 1 to 3) | X7 (decision recorded), X1/X2 (OI-339/340), N5 (OI-342, OI-344 item 4), N4, N6, N7, N15 |

### Re-checked by the author (not taken from the seats)

- The NULL-referrer filter exists at migration 159 lines 203, 234 and 277; what was missing was a behavioural test (seat B 1). Verified by reading, then by the new case X5 and the mutant that drops the filter.
- The credit select has no referee_id predicate (lines 275-281), the known window of B-pass finding 9 (seat A 1). Needs migration 160, OI-344 item 1.
- Live read-only (project dedsavbjuwgarrhphgnl, 2026-10-16): the 3 redemptions carry referrer_rewarded = false and converted_at NULL (the plan was right, ledger D4 was wrong; seat C 3 and seat D 7 flagged the contradiction without being able to read the database); anon and authenticated hold INSERT, UPDATE, DELETE and TRUNCATE on referral_redemptions, row security is on and the only policy is the SELECT policy (seat D 4); promo_codes has "Anyone can read active promo codes" (seat D 3).
- razorpay-webhook/index.ts lines 457-458 read notes.user_id and nothing checks notes.source (seat D 5); create-razorpay-order sets source: "AVYA_app" in its notes. Exploitability stays unverified (it needs a flow on the shared Razorpay account where the payer controls notes).

### New and changed cases, all run on a fresh replica (schema file plus the unmodified migration, job md5 d24f43267f2beb15ac569c73e7c54555 = the applied one)

Live verify: SUMMARY ok=89 fail=0 skipped=0 (86 before, plus X5, H1, H2). The concurrency script (bash) ends CONCURRENCY OK with C13 now asserting that the 5 newest rows are the ones left pending.

| id | mutant | killed by | other cases red |
|---|---|---|---|
| MA (= M22) | credit select: drop referrer_id IS NOT NULL | verify X5 | none |
| MB | grant helper: v_end < now() becomes <= | verify H1 | none |
| MC | reconcile: drop the second IS DISTINCT FROM arm | verify H2 | none |
| MD | reconcile counters swapped (reconciled and voided) | verify W14, W15 | none |
| ME | credit select ORDER BY converted_at DESC | concurrency C13 | none |
| MF | credit select without ORDER BY | concurrency C13 | none |

Each mutant was applied to the replica (the function md5 changed from the pristine one) and the pristine body restored and md5-checked afterwards. M02, M05 and M17 were re-run against the extended verify (see their rows above): they abort the verify block with an error instead of printing a result table, which is why the first table could not attribute a case to them.

### What round 2 does NOT change

- Migration 159 is live and hash-pinned; nothing here edits it. Seat A's P3s that need SQL changes are OI-344 (migration 160).
- The mutation runner is a scratch script outside the repo; the 104-mutant table still lists only the cases it can attribute. The six round-2 mutants above are reproducible from the quoted substitutions.
- Open founder decisions kept as `blocked_on_user` with the seats' evidence: privacy exposure and Unit C (X7, U2), refund and chargeback (X1, X2), promo ceiling (X4, N5), payment attribution (N6, N7), start of OI-341 (X3), start of migration 160 (N1 to N4).
