---
reviewed_at: 2026-11-24T19:30:00+05:30
staged_against: 23ddbeedbc3c
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill (3 context-blind seats: A SQL, B client + sheet, C docs + registry + fallout)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 18
verdict: accepted
verdict_note: all 18 triaged (17 from the seats, 1 found by the coordinator while proving A1/A2); 15 fixed in the reviewed tree before the commit, 2 by design, 1 verified clean (see each status). The seats reviewed staged hash 50c056340198; this file is named for the final staged diff: first ac718e458303 (post-fix), renamed to 23ddbeedbc3c after migration 186 was applied (staging moved: the ledger row, and the diagnose doc and closure ledger recording the apply, the post-apply verify and the race-test decision).
---

# Code Review — OI-348 Landing 2 PR B (B2, migration 186 issue_referral_code)

Seats read the staged diff 50c056340198 (the plan-review record is deliberately outside the code commit, skill §3 step 3). Fixes below were applied to the tree and re-staged; the post-fix gate loop, the dry run (13/13) and the targeted tests ran on the post-fix tree.

## Finding A1 — P2 — guard_without_its_mirror (live verify)
- **file:line:** test/sql/referral_code_issue_live_verify.sql V8
- **claim:** V8 ran as anon with the V7 claims (no sub) still set, so the function's own null-uid guard answered 42501 even if anon kept EXECUTE; only C1 caught a missing anon revoke.
- **verification:** read V7 -> V8; no claim reset between them.
- **status:** fixed. V8 now sets claims with a real sub and requires `permission denied for function`. Mutant (anon keeps EXECUTE + early RETURN removed, one aborting run): V8 red ("sqlstate=none"), V2 red ("calls=2").

## Finding A2 — P2 — test teeth (live verify V2)
- **claim:** V2 read only the first returned row: a missing `RETURN;` after the early `RETURN QUERY` would return two rows and overwrite the table, still green.
- **status:** fixed. V2 counts the rows the call returns (= 1) and re-reads the table row; V3/V4/V6 compare the returned code with the stored one. Mutant above: V2 red (calls=2).

## Finding A3 — P2 — guard_without_its_mirror (the old client's INSERT bypasses the lock)
- **file:line:** supabase/migrations/186_issue_referral_code.sql, ON CONFLICT DO UPDATE
- **claim:** until M2 the old client can INSERT a first code without the advisory lock; committed between the expiry check and the upsert, it was overwritten unconditionally and the old client showed a dead code.
- **status:** fixed (migration not yet applied). `DO UPDATE ... WHERE rc.expires_at <= now()`: a live row is kept and the final re-select returns it. Pinned by the whole-text pin; a single session cannot interleave it (stated in the live verify header and the diagnose doc).

## Finding A4 — P2 — the retry's constraint name never checked against the live catalog
- **status:** fixed. Live verify C3: the unique indexes on referral_codes are exactly pkey(id), referral_codes_code_key(code), referral_codes_user_id_key(user_id) (read live 2026-11-24, ok in the dry run).

## Finding A5 — P2 — the later-migration tripwire
- **claim:** `> 186` skipped `186b_...`; ROUTINE/PROCEDURE spellings and bulk `ON ALL FUNCTIONS IN SCHEMA public` grants were missed; not recursive.
- **status:** fixed. `_isLaterMigration` (>= 186, letter suffix, never this file; recursive scan); the regex reads FUNCTION/ROUTINE/PROCEDURE and bulk grants on schema public; controls for each, plus a negative control for another schema.

## Finding A6 — P3 — V5 true by construction, V6 one-sided
- **status:** fixed. V5 expires A's row first (the write path runs) and checks B's row; V6 captures A's row and requires it unchanged after B's call.

## Finding A7 — P3 — B0 could pass for the wrong reason
- **status:** fixed. B0 requires `row-level security` in the message; new control B0c: a first-row INSERT as authenticated succeeds (pre-M2).

## Finding A8 — P3 — whitespace inside literals not pinned
- **status:** fixed. `_squash` squashes only outside single-quoted literals; a test pins that a double space inside a literal is a change and outside is not.

## Finding A9 — P3 — extensions.gen_random_bytes has no precedent
- **status:** verified_clean. The pre-apply dry run (migration + verify in one aborting request) runs V1/V3-V6 through it: 13/13 ok.

## Finding B1 — P2 — test teeth (the seam skipped the real path)
- **file:line:** lib/core/services/supabase_service.dart `_issueReferralCode`
- **claim:** every test went through the seam, which skipped the signed-in guard, ensureFreshToken and the timeout; seat B's mutant removing the guard reddened nothing.
- **status:** fixed. The path is `SupabaseService.issueReferralCodeVia(isSignedIn, refreshToken, rpc, timeout)`; tests drive it with fakes (signed out -> no refresh, no RPC; refresh BEFORE the RPC; a never-answering RPC -> null after the timeout; a throwing refresh -> no RPC; a throwing check -> null) and a wiring pin holds the production arguments. Mutants MG1-MG4 in the diagnose doc.

## Finding B2 — P2 — test teeth (write scan spelling holes)
- **claim:** a builder held in a variable, a variable-held table name or a helper taking the name passed the scan.
- **status:** fixed. A `.from('referral_codes')` statement that is not a `.select(` chain is flagged (split-chain control added); only two allowlisted lib/ files may spell the table name as a literal (the restore SELECT and the restore bundle key list). Mutant MG5 (a new literal in supabase_service.dart) reddens it.

## Finding B3 — P3 — two buttons after a failed first load
- **status:** by design. After a failed first load the main button reads REGENERATE (no code = expired) and the error row offers TRY AGAIN; both call the same function and both are disabled while a call runs. Kept: the error row is the explanation, the main button stays where the user expects it.

## Finding C1 — P2 — registry cites shifted by the diff
- **status:** fixed. The five refresh-join cites in the same file re-pointed to the post-fix lines (read with grep).

## Finding C2 — P2 — catastrophic rollback thin
- **status:** fixed. The migration's rollback section says the real rollback is roll-forward (CREATE OR REPLACE restating SECURITY DEFINER and search_path), what a DROP does to builds from this change, and that a replaced expired code is not restorable.

## Finding C3 — P2 — plan-review record unstaged / pending
- **status:** by design (skill §3 step 3: the record cites this file's name and lands in its own later commit to break the hash fixed point; `bpass` / `hermes` are set to accepted there).

## Finding C4 — P3 — cqrs rationale cites a stale line
- **status:** fixed. "the invite sheet: load and REGENERATE"; `check_cqrs_query_naming.dart` OK with the exemption live.

## Finding C5 — P3 — stale doc and stale test
- **status:** fixed. docs/architecture/database.md sentence rewritten for the server function; test/referral_code_test.dart deleted (it tested a copy of the deleted local code builder defined inside the test itself, asserting a format that no longer exists); redeem-referral range 82-96.

## Coordinator finding (found while proving A1/A2) — P2 — the SUMMARY under-counted a NULL result
- **claim:** `count(*) FILTER (WHERE NOT ok)` skips a NULL `ok` (a case whose SQLSTATE is NULL), so the SUMMARY line said `fail=1` for two red cases.
- **status:** fixed. `ok IS NOT TRUE` counts as fail and prints as fail; no other test/sql file uses the pattern (grep).

## Founder triage notes
Triaged by the coordinator under the founder's standing "build it properly, no shortcuts"; no finding reverses a recorded decision.

## Tuning entry
- **2026-11-24** - blast-radius catastrophic - 18 findings; 0 false_alarm; tuning: none (three-seat split by layer again found disjoint sets; seat B's "mutate the guard" step found the seam-bypass hole that every author-written test shared).
