---
hermes_pass_id: 2026-10-06-hermes-progress-photos-pro-server-rule
ran_at: 2026-10-06T17:30:00+05:30
batch_scope: branch progress-photos-pro-server-rule, staged tree at staging hash 2b2b17ef23d8 (draft migration 154, contract test, live-verify and arbiter SQL, docs) vs main
lens_set: [L1, L2, L12, L14, L22, L23, L35]
agents_dispatched: 7
findings_total: 24
findings_by_severity: { P0: 0, P1: 0, P2: 2, P3: 22 }
verdict: accepted
---

# Hermes Pass: progress-photos-pro-server-rule (unit B1, catastrophic tier)

Batch: a Postgres migration (one `DO` block, draft `docs/drafts/154_progress_photos_pro_insert_rls_rule.sql`, to be
`supabase/migrations/154_...` after the founder-authorised apply) that makes the database refuse a NEW progress photo
unless the user has an active, unexpired subscription: the Storage INSERT policy `progress_photos_insert_own` is
altered in place, a BEFORE INSERT trigger guards `public.progress_photos`, and a repo-history policy
`users_own_subscriptions` is dropped (`IF EXISTS`). INSERT only. Catastrophic by the slug rule (`rls`); this pass is
mandatory at that tier.

## Provenance and disclosures

- Seven context-blind **Opus** agents, one lens each (L1, L2, L12, L14, L22, L23, L35), in two waves of at most four
  (founder rule 2026-09-26), each with an exhaustive read-only command list and its own seat database in a local
  throwaway Postgres replica. Earlier review rounds on this draft (rounds 1 to 3, plan sections 9c and 9d) used
  smaller-model seats and are NOT counted as the Hermes pass; the skill's Opus default applies to this one.
- `docs/agent_brief_preamble.md` (the bug-diagnosis stanza) was not prepended: these are review lenses that propose no
  fix and diagnose no bug; the lenses are named from `docs/audit/LENS_REGISTRY.md` (§4.8).
- The executable SQL was not changed by this pass (the text from `DO $mig$` to the end of the file is byte-identical
  to round 1, checked with `diff`). Everything below changed tests, the live-verify file, header comments and docs.
- Brief deviations by seats: the L35 seat wrote two catalog dumps with shell redirects into the scratchpad and read the
  sandbox wrapper script; the L1, L14 and L22 seats had their sandbox write actions refused by the permission
  classifier and said so (their sandbox parts were not run by them; the arbiter run before and after the migration
  and the other probes were run by me or by the L2, L12, L23 and L35 seats). No seat touched anything but the
  local sandbox and files.
- Raw per-seat reports are not archived; this report is written from each seat's hand-back and my own verification of
  every finding (file reads, sandbox runs, and the live read-only queries E27 to E29 in the evidence file).

## Summary

- 0 P0, 0 P1, 2 P2, 22 P3 (24 finding records; 22 distinct once the three reports of one misnamed bucket are merged).
- Ship-blockers: none. The rule held at both doors (Storage object, table row) in every sandbox case the seats ran:
  free, lapsed (three variants plus `end_date = now()`), payer, another user's folder or id, NULL values,
  `INSERT ... ON CONFLICT`, service role, postgres, search-path and shadowing attempts.
- Fixed in this batch: every finding that is a defect of this unit (pins that checked text and not meaning, a
  live-verify check that read only half of an UPDATE policy, header and doc statements that overreached or misnamed).
- Verified clean with new live evidence: E27 (the only function writing `public.subscriptions` is
  `redeem_referral_atomic`, EXECUTE for service_role only), E28 (the deployed `verify-subscription` v16 carries the
  repo's predicate), E29 (no function writes `storage.objects` or `public.progress_photos`; no shadow `now()` or
  timestamptz/text operator; the postgres role's search_path does not list `pg_catalog`; only postgres can CREATE in
  `public`).
- Not defects of this unit, terminal state `blocked_on_user` (an OI mint needs the founder's go): three pre-existing
  items found on the way (below).

## Findings by lens

### L1 writer/reader drift (3 findings + 1 note, P2 x1)
- **F1 P2 REAL, fixed.** The cross-check against `verify-subscription` pinned substrings; a grace window
  (`> Date.now() - GRACE_MS`), `is_pro: true` and a dropped `.eq("user_id", userId)` all stayed green. Now whole
  statements are pinned (query chain, comparison, `is_pro: isActive`); in-test mutants X1b and real-file mutants H7,
  H8, H9 are red.
- **F2 P3 REAL, fixed.** Parity pins read a hand-written constant and the first definers of the cap functions (111's
  were replaced by 113, 114, 127, 129, 132, 153). The live definition of each cap function is now read through
  `migration_cap_reader.dart`; the shared helper's cutoff and `.gt` argument are pinned; real-file mutants H1 to H6 red.
- **F3 P3 REAL, fixed.** PROF-09 named the bucket `progress_photos` (it is `progress-photos`); also raised by L12 and L22.
- **Note P3, blocked_on_user.** `clean-orphan-media` reads a user with two unexpired active rows as free
  (`.maybeSingle()`); pre-existing, chat-media only.
- Clean: every copy of the predicate agrees; every in-repo writer of `subscriptions` writes a passing row; the photo-row
  writers are `capture`, arbiter case 16 and the live-verify file.

### L2 RLS table-level (3 findings + 1 observation, P2 x1)
- **F1 P2 PARTIAL, verified clean.** "No client write path into `subscriptions`" was evidenced live for policies only.
  E27 closes it.
- **F2 P3, blocked_on_user.** `redeem-referral` has no per-referrer cap (idempotent per referee only): throwaway
  accounts can extend a referrer's PRO. Pre-existing; the rule inherits it.
- **F3 P3 REAL, fixed.** Live-verify V8c checked only `qual` of UPDATE/ALL policies; an UPDATE policy with a
  bucket-scoped `USING` and `WITH CHECK (true)` lets an avatars object be moved into the bucket. V8c now checks the
  new-row check too; sandbox mutant N12 flagged, N13 stays ok, real-file mutant H10 red.
- Observation (verified clean for this unit): `anon` with a project-signed JWT carrying a `sub` can insert a row because
  the table policies are `{public}`; unchanged by the migration.

### L12 subscription server-verification (4 findings, no P2)
- F1 P3 REAL, fixed: `naming_conventions.md` claimed the test reads every copy of the predicate; it now says which it
  pins and lists the reviewed-not-pinned copies.
- F2 P3 REAL, fixed: debug builds can show PRO with no row; named in the header and the profile failure-mode row.
- F3 P3 REAL, fixed: bucket name (see L1 F3).
- F4 P3 PARTIAL, verified clean: E28.
- Clean: every product path that grants PRO writes a passing row by the time the client is told; the reverse direction
  (the rule admitting a user the server calls free) has no case; a 12-state sandbox matrix matches `verify-subscription`.

### L14 onConflict arbiter (3 findings)
- F1 P3, verified clean by design: case 16's DELETE removes every row of Alice because case 27 needs her to have none.
- F2 P3 REAL, fixed: stale line numbers in the plan.
- F3 P3 PARTIAL, fixed: nothing pinned case 16's `ON CONFLICT (id) DO UPDATE`; pin plus test A3b and real-file mutant H11.
- Run by me (the seat's sandbox writes were refused): the arbiter file before and after the migration, 28 result rows,
  identical.

### L22 schema-vs-payload parity (3 findings)
- F1 P3 REAL, fixed: a PAYER inserting a row for another user's id (or NULL) now gets `P0001`, not `42501`; docs corrected
  and live-verify V3f added (never accepted; ok before and after; mutant N14 reads `fail (23503)`).
- F2 P3 REAL, fixed: bucket name.
- F3 P3 PARTIAL, blocked_on_user: `capture` sends `takenAt.toIso8601String()` (local time, no offset) to a `timestamptz`
  column and PostgREST's session TimeZone is UTC (live read), so `taken_at` is stored 5.5 hours late for IST users and
  the client-side daily-cap window is mis-aligned. Pre-existing, outside the diff, in the file unit B2 edits.

### L23 service-role paths (3 findings)
- F1 P3 PARTIAL, verified clean live (E29): the policy's `now()` and operators bind through the apply session's
  search_path; a shadow `public.now()` plus a path listing `public` first would bind it (the seat reproduced it in the
  sandbox). None exists live; named in the header; the apply request states the apply session's `show search_path`.
- F2 P3, fixed: only the table owner can step around the trigger (`session_replication_role = replica`,
  `DISABLE TRIGGER`).
- F3 P3, verified clean: E29, zero writers.
- Clean: no signed-upload or TUS call in the repo; the service-role Storage bypass is as the header says; shadowing the
  trigger function's lookups failed in every attempt (pinned search_path).

### L35 reversibility and forward compatibility (3 findings)
- F1 and F2 P3 REAL, fixed: the lock footprint is wider than stated (a second supautils hook, `drop_trigger_grants`, fires
  on DROP TRIGGER; both hooks list the same 24 tables; worst case many 5 s waits; a concurrent auth transaction can be
  the deadlock victim); header LOCKS paragraph and the rollback comment rewritten; verified by me in the sandbox.
- F3 P3 REAL, fixed: the inline rollback does not undo the CREATE branch; the header says so (live runs the ALTER branch).
- Clean: rollback restores the catalog byte-for-byte on the ALTER branch; idempotent twice and forward-rollback-forward;
  forward compatibility for old APKs (the only writer is `capture`; no queue, retry or sync loop; a refusal shows the
  generic upload failure).

## Founder triage

Pending the founder's go on the three `blocked_on_user` rows (each needs an OI mint):

1. Per-referrer cap on `referral_trial` credits (L2 F2): a product decision.
2. `clean-orphan-media` `.maybeSingle()` with two unexpired active rows (L1 note).
3. `taken_at` naive-local timestamp and the UTC cap window (L22 F3): fix inside unit B2, or its own OI.

## Action items

Every finding takes exactly one terminal state.

- [x] fixed in this batch: L1 F1, L1 F2, L1 F3 (= L12 F3 = L22 F2), L2 F3, L12 F1, L12 F2, L14 F2, L14 F3, L22 F1, L23 F2,
  L35 F1, L35 F2, L35 F3 (tests, live-verify, header comments, docs; the executable SQL is unchanged).
- [x] verified_clean: L2 F1 (E27), L2 observation, L12 F4 (E28), L14 F1 (by design), L23 F1 (E29), L23 F3 (E29).
- [ ] blocked_on_user: L2 F2 (referral cap), L1 note (`clean-orphan-media`), L22 F3 (`taken_at` timezone): an OI mint needs
  the founder's go; the decision needed is stated per row above.
- upstream_blocked: none.
