---
reviewed_at: 2026-11-23T10:30:00+05:30
staged_against: fffbe6b1d574
blast_radius: platform
reviewer: claude-sonnet-via-skill (two seats: A server, B client)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, asserted_fixture_value, fake_vs_sql_parity, migration_live_table_safety, cross_platform_determinism]
findings_count: 23
verdict: accepted
verdict_note: 15 first-round findings and 5 delta-seat findings fixed or recorded in the same batch; the delta seat found no P0 or P1 in the fixes
---

# Code Review — fffbe6b1d574 (OI-348 Landing 1a-ii, nutrition slot sync)

Branch `oi348-slot-sync`, staged diff of 43 files (migration 181 unapplied). Two context-blind
Sonnet seats: A (migration 181, `nutrition_slot_remote.dart`, the fake, the live verify, the
contract test) and B (engine, section, merge, wiring). Every fix below landed in the same batch;
each mutant is recorded in diagnose `a6c4e2` `mutation_proof`.

## Finding 1 — P1 — performance / Hive-first (seat B)
- **file:line:** lib/core/services/sync/nutrition_slot_engine.dart push loop (was :643) and `_pushSlot` (was :678)
- **claim:** the push loop re-read and signed the whole box for every slot before the skip decision: O(slots x rows) SHA-1 on the UI isolate per meal log.
- **verification:** race test 'a push of many unchanged slots builds and signs O(rows)' (810 builds for 120 rows; ~14,400 before)
- **status:** accepted, fixed (`_rowsOfDate` filters on the stored date before building a row)

## Finding 2 — P2 — unawaited_no_error_sink (seat B)
- **file:line:** nutrition_slot_section.dart `_release` (`unawaited(pullBody(userId))`)
- **claim:** the owed / follow-up pull had no error sink.
- **status:** accepted, fixed (`_owedPull` reports `pull_nutrition_slots`; race test, mutant red)

## Finding 3 — P2 — asserted_fixture_value (seat A)
- **file:line:** migration 181 put / delete (`set_config('app.nutrition_rpc','on',true)`)
- **claim:** the marker stayed on for the rest of the transaction: a later plain write in it skipped all three triggers; the live verify could not pass from case C on.
- **status:** accepted, fixed (the body saves the marker and restores it before every return; pinned; verify C runs after RPC calls, N reads the marker after every return path). The first fix, a function-level `SET app.nutrition_rpc = 'on'`, was refused by the live apply (42501, rolled back clean); see the diagnose doc "Found at apply".

## Finding 4 — P2 — asserted_fixture_value (seat A)
- **file:line:** supabase/tests/nutrition_slot_rpc_live_verify.sql section J
- **claim:** the second user was read after `SET LOCAL ROLE authenticated` (users RLS own-row only): J vacuous, then aborted.
- **status:** accepted, fixed (read before the switch; J1-J6)

## Finding 5 — P2 — fake_vs_sql_parity (seat A)
- **file:line:** test/sync/nutrition_slot_fake_server.dart `oldClientUpsertSlot`
- **claim:** an identical old-client re-push became a legacy write in the fake; SQL suppresses it (trg_suppress_redundant_updates); an item update dropped entry_key.
- **status:** accepted, fixed (C5a; race test with the changed-re-push mirror; verify case M)

## Finding 6 — P2 — guard_without_its_mirror (seat A)
- **file:line:** live verify B, G, J, E
- **claim:** unasserted RPC statuses; the item trigger's `entries = NULL` arm never driven on an RPC row; grants checked on one RPC only.
- **status:** accepted, fixed (status + rev after every call; E2; K1-K4)

## Finding 7 — P3 — guard_without_its_mirror (seat B)
- **file:line:** nutrition_slot_section.dart `_release`
- **claim:** an older generation's release consumed the current generation's owed flags (A -> B -> A).
- **status:** accepted, fixed (generation check first; race test, mutant red)

## Finding 8 — P3 — function_exception_swallow (seat B)
- **file:line:** sync_nutrition.dart new-mode `_restoreNutritionLogs`
- **claim:** could throw where the legacy body never did (matters for the flag-gated sync-domain restore).
- **status:** accepted, fixed (catch with the H-42 pair; pinned by the pair count, presence only)

## Finding 9 — P3 — writer_reader_drift (seat B)
- **file:line:** nutrition_slot_merge.dart `nslotCanonicalText`
- **claim:** signature read only `name`; the payload falls back to `food_name`.
- **status:** accepted, fixed (merge test with mirror, mutant red)

## Finding 10 — P3 — telemetry noise (seat B)
- **file:line:** engine `_pushSlot` `nslot_slot_too_large`
- **claim:** logged on every pass for a stuck slot; the mirror `nslot_bad_meal_type` too.
- **status:** accepted, fixed (once per launch per message in the section; test pushes three times)

## Finding 11 — P3 — fake_vs_sql_parity (seat A)
- **claim:** length semantics (UTF-16 vs characters) and string totals differ between fake/client and SQL.
- **status:** accepted, recorded as fake contract row C4a (the client is the stricter side; no string total is ever sent)

## Finding 12 — P3 — fake_vs_sql_parity (seat A)
- **claim:** the fake's timestamp text always had 6 fraction digits; PostgREST trims.
- **status:** accepted, fixed (fake C6 emits the trimmed shapes; the 500-seed test requires all three)

## Finding 13 — P3 — migration_live_table_safety (seat A)
- **claim:** no lock timeout around the ALTER of a live table.
- **status:** accepted, fixed (`SET LOCAL lock_timeout = '5s'` heads the file)

## Finding 14 — P3 — blast_radius_mismatch (seat A)
- **claim:** the ledger entry and schema snapshot are not paired yet; the hash must follow the last edit.
- **status:** accepted, blocked_on_user (the apply step, founder's go; closure BPA-8)

## Finding 15 — P3 — asserted_fixture_value (seat A)
- **claim:** the contract test did not pin grants, search_path, policies, the advisory lock, FOR UPDATE.
- **status:** accepted, fixed (three new pin tests, mutant red on the marker pin)

## Clean lenses (summary of the seats' own records)
Seat A: writer/reader columns and payload keys match; RPCs INVOKER with `search_path = public`,
uid only from `auth.uid()`; additive columns need no rewrite and old-client arbiters are untouched;
the migration is re-runnable. Seat B: every whole-box nutrition reader filters on `date` or `nlog_`
(the `nslot_` keys never count); legacy bodies renamed verbatim with their reports and owner checks;
Hive-first kept in every writer; no clock-derived date; cross-platform text rules hold below 1e21.

## Delta round (fresh Sonnet seat on the fixes, 2026-11-23)
No P0 or P1. It walked the rewritten live verify by hand (every expected value, case M trigger order) and confirmed the function-level SET semantics. Neither seat could see that live Postgres refuses that form for the migration role; the apply did (42501), and the fix moved into the body (diagnose a6c4e2, "Found at apply").

### Finding 16 — P2 — asserted_fixture_value
- **claim:** the O(rows) test only ran a pass that sent nothing, so `_pushSlot` and `applyLocked` were never measured.
- **status:** accepted, fixed (the test adds a put pass over 40 changed days and a 40-date pull on a second device; mutants at `_pushSlot` and at `applyLocked` each red)

### Finding 17 — P3 — telemetry
- **claim:** `_onceThisLaunch` was not cleared on an account change.
- **status:** accepted, fixed (cleared in `onUserChanged`; the oversized-slot test logs again after a change; mutant red)

### Finding 18 — P3 — asserted_fixture_value
- **claim:** the live verify ended "ALL OK" with J skipped.
- **status:** accepted, fixed (`v_j_ran`; the final notice says when the cross-user check did not run)

### Finding 19 — P3 — fake_vs_sql_parity
- **claim:** the fake compared `since` as text; a client `...:05.000Z` and a server `...:05+00:00` order wrongly at an equal instant.
- **status:** accepted, fixed (instant compare; contract test across shapes; mutant red)

### Finding 20 — P3 — performance
- **claim:** the row readers read every value before the prefix test.
- **status:** accepted, fixed (prefix check first; no behaviour change, so no mutant can prove it)

## Delta round 2 (fresh Sonnet seat on the marker fix made at apply, 2026-11-23)
No P0 or P1. No path leaves the marker on at exit; no RPC write runs before the set; NULL and '' read the same in all three triggers; nesting is safe.

### Finding 21 — P2 — guard_without_its_mirror
- **claim:** the contract test counted only lines starting with `RETURN `; an inline `THEN RETURN ...` or a bare `RETURN;` without a restore stayed green.
- **status:** accepted, fixed (every `\bRETURN\b` in the body must be one the line scan saw; mutant with an inline `THEN RETURN NULL` in delete red)

### Finding 22 — P3 — asserted_fixture_value
- **claim:** live case N cannot reach put's `unique_violation` return (it needs a concurrent insert that skips the advisory lock).
- **status:** accepted, verified clean: one transaction sees its own rows, so the path is unreachable from the verify; the restore before that RETURN is pinned by the contract test (now including inline forms), and a subtransaction abort on handler entry leaves the outer value 'on' until that restore.

### Finding 23 — P3 — asserted_fixture_value
- **claim:** case N checks only the setting, not that a plain write after an RPC behaves as an outside write.
- **status:** accepted, verified clean: cases C (plain INSERT after RPC calls: rev 5, legacy_rev 5, tombstone consumed), E2b to E2d (item UPDATE and DELETE after a put: rev bumped, entries null) and H (plain DELETE after a put: tombstone) assert exactly that and passed on the applied schema.

## Founder triage notes
Pre-launch, testing accounts only. No finding re-opened a recorded decision (spec §9).

## Tuning entry
- **2026-11-23** - blast-radius platform - 15 findings; 0 false_alarm; tuning: split a migration-bearing batch into a server seat and a client seat; the server seat found the transaction-scoped marker leak and a live verify that could not pass, both invisible to the client tests and to sixteen plan-review rounds. Then the seat's own fix (a function-level SET of a custom setting) was refused by live Postgres at apply (42501): no reviewer or local test can see a privilege the migration role lacks, so a migration that sets any custom setting is dry-run in BEGIN..ROLLBACK before the apply, and the fix to a guard gets its own fresh seat (round 2 found a P2 in the new pin).
