---
hermes_pass_id: 2026-11-26-hermes-oi348-landing3c
ran_at: 2026-11-26T21:45:00+05:30
batch_scope: branch oi348-landing3c at e77c1933 (post-B-pass) vs origin/main 8cd4556f; the SQL draft is the migration-to-be
lens_set: [L1, L2, L14, L22, L23, L29, L35, L37, L40]
agents_dispatched: 4
findings_total: 13
findings_by_severity: { P0: 0, P1: 0, P2: 6, P3: 7 }
verdict: accepted
verdict_note: every finding terminal - 10 fixed in this batch (mutation-proven where client code), 1 filed on OI-316, 2 documented as known residue already on OI-531 / the diagnose doc
---

# Hermes Pass: OI-348 Landing 3c (free progress photo, 1 per IST week; catastrophic by content)

Four **Sonnet** seats in one wave (the founder's Sonnet-only rule of 2026-10-07 overrides this skill's Opus
default), context-blind, read-only (no SQL, no scripts, no network), after the B-pass fixes, on `e77c1933`.
Seat A: L2 + L23 + abuse. Seat B: L35 + L14 + the live runbook. Seat C: L1 + L37. Seat D: L22 + L29 + L40 + the
PRO predicate. Every claim below was re-checked by the coordinator against the file before it was fixed.

## Summary
- 0 P0, 0 P1, 6 P2, 7 P3 (C2 and D1 are one defect seen by two seats; counted once in each seat's list below).
- No way past the weekly cap was found at either door. The defects were: an information leak the batch's own
  DEFINER switch created (A1), an UPDATE path that split the two counts (A2), an unproven rollback (B1), an
  incomplete apply runbook (B2), and failure paths whose OUTCOME was unknown but treated as known (C1, C2/D1, C3).

## Findings by seat

### Seat A (L2 / L23 / abuse)
- **A1 - P2 - REAL. The row door answered about another user.** `enforce_progress_photo_pro` became SECURITY
  DEFINER and keyed on `NEW.user_id` with no caller test; a BEFORE trigger runs before RLS WITH CHECK, so a free
  account POSTing a row with a victim's `user_id` got RLS (victim PRO or free without a row) or P0001 (free victim
  holding a row this week), learning the victim's PRO state and week, and took the victim's advisory lock. Under
  154 (INVOKER) the subscriptions read saw nothing through RLS. **Fixed:** the storage door's guard at the top of
  the row door (`auth.role() IN ('anon','authenticated') AND NEW.user_id IS DISTINCT FROM auth.uid()` returns at
  once, RLS refuses). Rule-test pin + 2 mutants (guard removed; role test dropped); live verify W10b (free victim
  holding a row) and W14b (PRO victim) both expect the RLS message.
- **A2 - P3 - PARTIAL. UPDATE of `storage_path` split the counts.** An old-week row repointed at this week's
  object kept its old `created_at`, so a second row for the same object passed the row door (no extra object
  stored). **Fixed:** the UPDATE guard also keeps `storage_path` (no client updates it: `git grep storage_path lib`
  shows insert and select only). Pin + mutant; live verify W8b.
- **A3 - P3 - note. A bucket UPDATE policy would open a move past the INSERT-only trigger.** None exists today.
  **Filed:** added to OI-316 (the catalog check must flag an UPDATE policy on the bucket).

### Seat B (L35 / L14 / live runbook)
- **B1 - P2 - REAL. The rollback had never run.** The header said "the rehearsal runs this block too"; the
  rehearsal never did, and no step had dropped an existing trigger on `storage.objects` (owned by
  `supabase_storage_admin`). **Fixed:** `test/sql/progress_photos_free_weekly_cap_rollback_verify.sql` (R1-R6:
  triggers and functions gone, 154's row trigger kept, the function INVOKER with 154's body and ACL, the policy's
  conjunct back), run as a second always-aborting rehearsal (forward + rollback + verify in one statement).
- **B2 - P2 - REAL. The apply commit would have gone red.** The runbook omitted the 154 tripwire allow-entry, the
  draft-path repointing (SoT, CLAUDE.md, subscription.md, OI-531, verify headers) and the staged review.
  **Fixed:** plan section 6 step 3 lists all six steps in order.
- **B3 - P3 - REAL. The applied file would have called itself a DRAFT forever.** **Fixed:** header reworded
  before the mint (comments only; the rule test pins statements).

### Seat C (L1 / L37)
- **C1 - P3 - REAL. A lost UPLOAD response left an untracked object** holding the slot for 60 minutes.
  **Fixed:** the path is noted before the upload; a failure without a server answer goes to `ownFailedCleanups`
  (`noteFailedUpload`), swept after 2 minutes.
- **C2 - P3 (D1 rated P2-low) - REAL. A deleted photo whose object removal failed** held the slot for an hour,
  defeating the founder's retake. **Fixed:** `removeDeletedPhotoObject` (10 s bound) remembers the path.
- **C3 - P3 - PARTIAL. A gateway 502 / 504 arrives as a `PostgrestException`** (postgrest-dart 2.9.1 sets `code`
  to the bare HTTP status for a non-JSON body) and the insert can still commit. **Fixed:** one pure rule,
  `progressPhotoServerRefused` (a SQLSTATE / PGRST code or a 4xx is an answer; a 5xx, a type-name status from
  storage_client 2.8.1's transport path, a timeout are not), used by all three failure paths.

### Seat D (L22 / L29 / L40 / PRO predicate)
- **D1** = C2 above.
- **D2 - P3 - REAL. Release builds printed storage paths (user id).** `debugPrint` is not stripped in this repo.
  **Fixed:** every log line in the repository goes through `_log` (`kDebugMode` only; rule 17); a pin counts one
  `debugPrint(` in the file.
- **D3 - P3 - known.** `ownFailedCleanups` is in memory: an app killed between upload and row holds the slot up
  to 60 minutes. Already stated in the repository docs and the diagnose doc's residue; no change.
- Clean with evidence: L22 (NOT NULL `user_id`, `storage_path`, `taken_at` all sent; no other writer); the PRO
  predicate is identical in SQL, `_shared/subscription.ts`, `verify-subscription` and migration 154, and
  `end_date` is NOT NULL (migration 006).

## Mutations (client fixes; `cp` / `cmp` after each, file byte-identical)
Gateway 5xx counted as an answer [3 red]; any Storage status counted [5]; `noteFailedUpload` remembers nothing
[4]; `capture` never notes a failed upload [1, pin]; failed delete removal not remembered [1]; logs print in
release [1, pin]. SQL: 3 new in-process mutants in the rule test (guard removed, role test dropped, `storage_path`
guard dropped), each breaks a whole-text pin.

## Founder triage
None needed: no finding reverses a founder decision; all fixed or filed by the author.

## Action items
- [x] A1, A2, B1, B2, B3, C1, C2/D1, C3, D2 - fixed in this batch (commit after `e77c1933`).
- [x] A3 - filed on OI-316.
- [x] D3 - verified_clean as documented residue (diagnose f3c9a1, "Residue, stated").

## Self-evolution
- 4 Sonnet seats, about 4-8 minutes each, one wave. Signal: A 2/2 real, B 3/3, C 3/3 (one PARTIAL), D 2/3 real
  (one already documented). 0 false alarms.
- **Lesson:** switching a trigger function from INVOKER to DEFINER removes the RLS blindness it had about OTHER
  users' rows; every DEFINER trigger keyed on a client-supplied id needs the caller guard, not only the one the
  author was thinking about. Seat A found it on the row door after three plan rounds and a B-pass had reviewed the
  same guard on the storage door.

## Delta B-pass of the fix commit
`docs/reviews/oi348-landing3c-hermes-delta-bpass.md` (one fresh Sonnet seat on `e77c1933..e474ed8e`): 0 P0, 0 P1, 5 P2/P3: the rollback verify R4 now checks `proconfig` and the absence of the guard, R5 the exact ACL; the live-verify header lists every pre-apply `fail`; a 408 / 499 is not an answer (mutant: 3 red); one no-change.
