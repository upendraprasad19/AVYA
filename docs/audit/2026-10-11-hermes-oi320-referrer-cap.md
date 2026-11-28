---
hermes_pass_id: 2026-10-11-hermes-oi320-referrer-cap
ran_at: 2026-10-11T16:30:00+05:30
batch_scope: working tree of branch oi320-referrer-cap (base main df2b1282) - the untracked supabase/migrations/158_referral_referrer_cap.sql (sha256 527999b451925d04bf8bafba10be5f3e8e44d7dc8922f59ba6cba5a8e92ecafa, unchanged by every fix below) plus the staged tests, plan, ledger and docs, AFTER the B-pass fixes
lens_set: [L1, L2, L11, L14, L21, L22, L23, L27, L35, L36, L37, L39]
agents_dispatched: 4
findings_total: 10
findings_by_severity: { P0: 0, P1: 0, P2: 2, P3: 7, false_alarm: 1 }
verdict: accepted
---

# Hermes Pass - OI-320, migration 158 (per-referrer referral cap), catastrophic tier

Catastrophic by CONTENT: a migration that contains SECURITY DEFINER is forced to catastrophic by `scripts/blast_radius_from_diff.dart`. Recorded deviation from the skill's Opus default: **four Sonnet seats in ONE wave of four** under the founder's standing Sonnet-only and max-4-concurrent rules (2026-10-07, 2026-09-26). Each seat took three lenses (the "migration / schema" set L1, L14, L22, L35 plus L2, L11, L27, L36, L37, L39 and, because the change sits on a service-role path, L21 and L23), read its charter from `docs/audit/LENS_REGISTRY.md`, had an EXHAUSTIVE read-only command list (no `dart run scripts/*`, no `scripts/*.sh`, no network, no Supabase tool, sandbox databases `hq<n>_*` in the throwaway container only, no worktree edit) and no live access. Dispatched after the B-pass (`docs/reviews/<staged-diff-hash>-review.md`) was folded, so it saw the post-fix tree.

## Summary
- 16 seat records, **10 distinct findings: 0 P0, 0 P1, 2 P2, 7 P3, 1 false alarm by design.** Four seats independently found the same stale count; two found the same pin-reach gap, two the same stale registry citation, two the same RLS gap.
- Ship-blockers: none. No seat found a way to exceed the cap, to bypass `unique_referee_redemption`, to break a reader, to lock up the Edge Function path, or to make the rollback differ from the recorded `md5`.
- Every finding has exactly one terminal state below and a row in `docs/audit/oi320-referrer-cap.closure.yaml` (HM1-HM10).

## Findings by lens

### L1 writer/reader drift, L37 empty-state / null-shape readers, L2 RLS (seat H1) - 1 P2, 4 P3
- **P2 (also seat H4, L23), REAL/PARTIAL - nothing pins who can read or write the audit rows.** The replica ran with RLS off and no grants; no file used a role or `auth.uid()`. Behaviour was right (the seat modelled the live shape and measured: a referrer of a NULL-referee row sees it, a both-NULL row is visible to nobody, anon sees 0, an own-row UPDATE/DELETE touches 0 rows, an INSERT is refused) but only a manual apply-time read covered it. **Terminal: closed_in_commit (HM1)** - the replica carries the live RLS shape, deletion case K6 and live verify case I7 pin it, Dart group 3e pins the replica; six replica-schema mutants R1-R6 are red.
- **P3 REAL (seats H1, H2, H3, H4 independently) - `supabase/functions/CLAUDE.md:181` still said 26 cases and 20 source pins.** **Terminal: closed_in_commit (HM2)**, every count-bearing document re-grepped.
- **P3 REAL (seats H1, H4) - two older registry concepts name migration 038 as the writer** (`subscription_expiry_derived`, `referral_trial_subscription_grant`). **Terminal: closed_in_commit (HM3).**
- **P3 PARTIAL - `days_granted_each` stays 7 on a capped row and the restore selects omit the two flags.** Nothing reads the history today. **Terminal: closed_in_commit (HM4)** - documented in `database.md`, the CLAUDE.md row and OI-336 with the precondition for any surface.
- **P3 PARTIAL (seats H1, H2) - the "readers tolerate NULL" pin scanned `lib/*.dart` bracket reads only.** **Terminal: closed_in_commit (HM5)** - group 4b also scans Edge Function TypeScript and pins the raw store in the restore path.
- Clean: every writer and reader of the five columns (only `redeem_referral_atomic` writes the flags, no code reads them); function inputs NULL referrer/referee/days/code, self, ghost users and a duplicate referee all behave as claimed; the migration applied twice with rc 0 and `lock_timeout` 0 afterwards; the ACL after 158 is `{postgres=X/postgres,service_role=X/postgres}`.

### L11 restore completeness, L39 backup/restore round-trip, L35 reversibility / forward-compat (seat H2) - 3 P3
- **P3 PARTIAL - the plan's description of the state after a fired `lock_timeout`** held only for a stop-at-first-error runner; under plain `psql` the NEW capped body can sit beside CASCADE keys until the re-run. **Terminal: closed_in_commit (HM6)** - plan section 4 step 3 rewritten; the seat measured convergence from apply-once, apply-twice, timeout-then-rerun and five hand-built half states to one catalog digest.
- The other two P3 are duplicates of the stale count and the pin reach above.
- Clean: no new Hive surface (`referral_redemption_history` has one writer, no reader, is never pushed back); a restored row with a NULL party is inert; older Edge Function bundles also call the RPC and never insert directly, so an EF rollback cannot bypass the cap; the rollback block, run after 158 with real redemptions and NULL-party rows, restores `md5(pg_get_functiondef)` `1066f4cb5b1c36058fd5c0b635e3209d` (length 1825), both CASCADE keys, NOT NULL and the ACL, and a catalog digest equal to `rev_before`'s, idempotently; the unapplied file on disk reddens Gate 14 and the parity test only.

### L27 concurrency, L36 idempotency replay, L14 arbiter (seat H3) - 2 P3
- **P3 PARTIAL - the live verify is ONE transaction that calls the function about 20 times on real ids**, so a production redemption touching two of the same borrowed users in the opposite order could be the deadlock victim (reproduced in the sandbox). **Terminal: closed_in_commit (HM8)** - run it in a quiet moment, check no redemption in the last hour; the exposure is 3 redemptions all-time.
- **P3 REAL (reproduced) - the race script's cleanup left one (NULL, NULL) audit row per redemption** (6000 by default) because deleting users no longer deletes their rows. **Terminal: closed_in_commit (HM9)**; the final matrix's baseline prints 0 left behind.
- Clean: the only writers of the rows are the RPC, `verify-payment` and `razorpay-webhook` (inserts only), so no other read-modify-write shares them; pgbench 8 clients x 4 hot referrers gave exactly 7 credited each (a copy without the locks credited 9-10); a 3-cycle redemption (A to B, B to C, C to A) gave 1 `40P01` on the old body and 0 on 158; three replays of one referee are byte-equal; there is no `ON CONFLICT` on the table anywhere; a NULL referee never arbitrates `UNIQUE(referee_id)`.

### L22 schema-vs-payload parity, L23 service-role path, L21 Edge Function semantics (seat H4) - 1 P2 (dup), 3 P3, 1 false alarm
- **P3 PARTIAL - the apply protocol did not ask for a live inventory of dashboard-created objects that mention the table.** **Terminal: closed_in_commit (HM7)** - run 2026-10-11 (read-only): exactly one hit, `public.redeem_referral_atomic`, still the old body; no views, matviews, rule-dependent views, triggers, policies on other tables, cron jobs or inbound foreign keys. Plan section 4 step 1 repeats it at apply time.
- **P3 PARTIAL - nothing persists the RLS posture** (a future permissive policy would reopen the cap): covered by HM1 (I7 runs at apply time).
- **False alarm by design - the two `delete-account` comments say "5 community surfaces ... per migration 049".** True of migration 049; not edited (git-vs-deployed drift of a catastrophic-tier function). **Terminal: verified_clean (HM10).**
- Clean: `redeem-referral/index.ts` derives the referee only from `getUser(token)` and the referrer only from `referral_codes.user_id`, so the only caller-controlled input is the code string; self-redemption is blocked at the Edge Function and by the CHECK after the locks; no TDZ, no missing `await`, no unreachable branch; 23502/40P01/55P03/57014 return a generic 500 with nothing half-written; the only other advisory-lock user in the repo (migration 155) uses a different key text; the migration leaves both columns nullable, both FKs `confdeltype n`, the ACL and `search_path` unchanged when applied twice.

## Verification of the folded fixes
- SQL mutation matrix on the final tree (28-case verify, 6-case deletion, race script): **58 mutants, 54 red, 4 green by design** - the post-condition block removed alone, `lock_timeout` removed, and two edits to the restated credit block (a dropped status filter, a hard-coded 7-day amount), all owned by Dart pins. The six replica-schema RLS mutants are red through I7 and K6.
- Dart-pin mutants on the final 29-test file: **80 mutants in three sets, 80 of 80 red** (the migration, an Edge Function reader, a Dart reader, the credit blocks, the raw restore, the replica schema file's transaction wrap, guard probes and RLS shape), every original restored byte-identical by sha256.
- Duplicate-FK and refusal controls (`run_fk.py`): both planted-key sides fail to load and go red without the block; every replica-only refusal path was exercised.

## Founder triage
Not yet read by the founder. The coordinator has resolved every finding below (fixed in the working tree with the proof above, or verified clean with evidence); the founder's go is still needed to commit, to apply the migration, and to merge.

## Action items
- [x] RLS shape on the replica, K6, I7, Dart 3e (HM1) - fixed in this batch
- [x] stale counts in `supabase/functions/CLAUDE.md` (HM2) - fixed in this batch
- [x] registry writer citations (HM3) - fixed in this batch
- [x] `days_granted_each` meaning and the restore-flags precondition (HM4) - fixed in this batch, preconditions recorded on OI-336
- [x] pin 4b reach (HM5) - fixed in this batch
- [x] half-applied runner states (HM6) - fixed in this batch
- [x] live inventory (HM7) - done and recorded in this batch
- [x] live verify in a quiet moment (HM8) - fixed in this batch
- [x] race script cleanup (HM9) - fixed in this batch
- [x] delete-account comments, seat deviations (HM10) - verified_clean
