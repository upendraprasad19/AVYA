---
bug_id: a6c4e2
date: 2026-11-23
batch: oi348-walk-fixes Landing 1a-ii (nutrition slot sync, decision B)
status: fixed
tier: full
blast_radius: platform
symptom: |
  OI-348 walk (AAB 1.0.0+50, Upendra, 2026-11-22), and OI-281: a meal deleted on the phone came back at the next cold start (the delete never reached the cloud, and the restore wrote the cloud row back); a meal moved to another slot came back in its old slot too; a meal logged on one device reached another populated device only by a full restore (after 1a-i removed the launch pull, b1d2a8). Two devices logging the same slot overwrote each other's items in the cloud (the push upserted the whole slot from one device's view).
concept: nutrition_slot_sync
sot_registry_entry: nutrition_slot_sync
writers:
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: "logMeal (stamps a stable entry_id per meal)", line: 138 }
  - { file: lib/core/services/sync/nutrition_slot_engine.dart, method_or_widget: "NslotEngine.push / _pushSlot (conditional put / delete per slot, ledger)", line: 606 }
  - { file: lib/core/services/sync/nutrition_slot_engine.dart, method_or_widget: "NslotEngine._applyWinners / applyLocked (3-way merge of cloud winners into nlog_ rows)", line: 906 }
  - { file: lib/core/services/sync/nutrition_slot_engine.dart, method_or_widget: "NslotEngine.rebaseline (one-time FULL re-baseline of every slot)", line: 973 }
  - { file: supabase/migrations/181_nutrition_slot_sync.sql, method_or_widget: "nutrition_slot_put / nutrition_slot_delete (CAS on rev, tombstones)", line: 87 }
readers:
  - { file: lib/core/services/sync/nutrition_slot_engine.dart, method_or_widget: "NslotEngine.pull (keyset cursor over rows and tombstones)", line: 776 }
  - { file: lib/core/services/sync/nutrition_slot_section.dart, method_or_widget: "NslotSection.restoreBody (restore through the same merge)", line: 249 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "whole-box walk by date (day total)", line: 440 }
  - { file: lib/core/services/nutrition_read_service.dart, method_or_widget: "whole-box walk", line: 120 }
hive_key_prefix: "nlog_ (meal rows, unchanged); nslot_ (engine store: ledger shards nslot_ledger_<date>, cursor, meta)"
hive_key_formula: "nlog_<date>_<meal>_<hash8> (NutritionWriteService.logKeyForHash; a cloud entry placed here takes hash8 = first 8 hex of its entry_id when its own key is not shaped for this slot)"
sync_methods: [_syncNutritionLogs, NslotSection.pushBody, NslotSection.pullBody, SyncService.pullNutritionSlots]
restore_methods: [_restoreNutritionLogs, NslotSection.restoreBody, NslotEngine.restoreSteady]
cloud_table: nutrition_logs
cloud_columns: [id, user_id, date, meal_type, rev, updated_at, entries, legacy_rev, total_calories, total_protein, total_carbs, total_fat, total_fiber, created_at, "nutrition_log_items.entry_key", "nutrition_slot_tombstones.*"]
contract_test_path: test/contracts/nutrition_slot_sync_writer_to_reader_test.dart
ist_handling: ["slot date is the IST date already stored on the nlog_ row (istDateStr at logMeal); the engine never derives a date from a clock"]
provider_invalidations: ["NutritionWriteService.invalidateAfterSync (dailyNutritionProvider, nutritionSummaryProvider, recentFoodLogsProvider, macroTargetsProvider, aiInsightProvider, foodLogProvider)"]
telemetry_op_types:
  success: [nslot_legacy_seen_rebaseline, nslot_rebaseline_resumed]
  failure: [sync_nslot_put, pull_nutrition_slots, rebaseline_nutrition, restore_nutrition_slots, restore_nutrition_logs, nslot_bad_meal_type, nslot_slot_too_large, nslot_conflict_rounds_exhausted, nslot_rebaseline_not_committed, nslot_rebaseline_stopped]
cross_account_guard: "true: every section body runs under a SerialSlot ticket bound to (userId, generation); onUserChanged bumps the generation, and every sink re-checks ownerChangedSince(userId) || generation before a Hive write; owed follow-ups fire only when owner and generation are unchanged."
forbidden_patterns_checked:
  - { pattern: "SECURITY DEFINER in migration 181 (every RPC is INVOKER, RLS applies)", absent: true }
  - { pattern: "a nutrition push outside SyncSkipIndex.pushIfChanged (Gate G1)", absent: true }
  - { pattern: "a meal row written under a key that is not nlog_ by the engine", absent: true }
  - { pattern: "an RPC-missing answer that selects legacy mode (a missing RPC keeps the probe failing, never downgrades)", absent: true }
proposed_fix: |
  Spec docs/plans/nutrition-slot-sync.md (FINAL v17, plan review 16 rounds). Server (migration 181, applied 2026-11-23 on the founder's go): nutrition_logs gains rev / updated_at / entries / legacy_rev, items gain entry_key, a nutrition_slot_tombstones table; INVOKER RPCs nutrition_slot_put / nutrition_slot_delete do a compare-and-set on rev under an advisory lock and return the current state on conflict; triggers bump rev and mark a non-RPC write (an old client) as legacy (entries null). Client: every meal carries a stable entry_id; the push sends per slot only what changed since the ledger (put or delete), the pull walks a keyset cursor over rows and tombstones, and both merge three-way by entry_id (base = ledger), with a day pass that removes a moved meal from its old slot. A legacy row (old client) triggers a FULL re-baseline. Restore goes through the same merge. The old push / restore paths are kept verbatim behind the kill switch disable_nutrition_slot_sync (CLAUDE.md 4.6), the ONLY way into legacy mode: while the RPC probe fails (migration 181 absent) new mode sends nothing and the re-baseline does not commit, so 181 is applied before any build carries this code (spec §7).
regression_test_planned: |
  test/sync/nutrition_slot_merge_test.dart (pure merge), test/sync/nutrition_slot_sync_behavioral_test.dart (two devices against FakeNslotServer), test/sync/nutrition_slot_race_behavioral_test.dart (in-call races, B-pass regressions), test/sync/nutrition_rebaseline_test.dart, test/sync/nutrition_slot_convergence_random_test.dart (random multi-device schedules, NSLOT_SEEDS, 500 seeds green, every PostgREST timestamp text shape covered), test/sync/nutrition_slot_store_readers_test.dart, test/contracts/nutrition_slot_sync_writer_to_reader_test.dart (text pins incl. grants and the RPC marker), supabase/tests/nutrition_slot_rpc_live_verify.sql (live, BEGIN..ROLLBACK, after the apply).
mutation_proof: |
  Rule 21. Backups by cp in the session scratchpad; every mutant applied by an exact-text perl replace and checked applied (cmp differs from the backup), restored by cp and cmp-checked after the run (never git checkout: uncommitted work). Suite per mutant: the behavioural, re-baseline, contract and random-schedule files (NSLOT_SEEDS=60), plus the race file once written.
  Merge module (pure, test/sync/nutrition_slot_merge_test.dart): 9 of 9 red: rule2_rule3_swap 3, neg_zero 1, rule4_inverted 2, rule5_drop 1, day_key_tie 1, norm_nopad 1, ascii_lower 3, place_cross_slot 1, sig_no_trim 1.
  Engine + section, run 1 (47 tests): 28 mutants. 18 red: drop_delete_for_emptied_slot 3, delete_before_put 1, identity_is_key 2, drop_steady_rev_gate 1, legacy_merged_in_steady_state 2, legacy_test_before_stale_gate 2, drop_admission 1, steady_restore_moves_cursor 1, cursor_advanced_on_failed_page 1, drop_s0_check 1, delete_rows_of_slot_without_cloud 2, rebaselined_before_commit 1, deletekeys_includes_placed 4, drop_generation 1, drop_legacy_pass_full 1, drop_legacy_pass_rebaselined_false 1, drop_scheduled_pull_after_legacy_seen 1, push_writes_nlog_index 1. 9 GREEN (survivors): drop_apply_day_pass, first_seen_winner, drop_legacy_rev_from_test, keep_old_ledger_shards, stamp_before_gate, conflict_no_merge, ledger_from_local_after_ok, drop_pull_owed, drop_push_owed (the owed-push test asserted >= 1 after setup had already scheduled pushes). 1 did not compile (restore_queues_behind_rebaseline as `if (false)`: a compile error is NOT a proof).
  Fix: test/sync/nutrition_slot_race_behavioral_test.dart (9 tests, each names its mutant; the harness pulled before every push, so no test reached the conflict path, debugging bug-class 2.166) and the owed-push assertion tightened to before + 1.
  Run 2 (55 tests): 8 of the 9 survivors red, 1 each. drop_apply_day_pass stayed green: stampLocked dedupes same-id copies at the next push, so the duplicate lived only between a pull and the next push (what the screen shows); the test now checks right after the pull. Run 3 (56 tests, baseline 56/56 green): drop_apply_day_pass red 1; restore_queues_behind_rebaseline in a compiling form (`running != null && false`) red 1 (the restore must report the running re-baseline's own failure and read nothing).
  Result: 28 of 28 engine and section mutants red; 9 of 9 merge mutants red. The engine and section files were cmp-identical to the backups after every run (RESTORED).
  B-pass fixes (2026-11-23, review fffbe6b1d574; each mutant applied by sed/perl, grep -c of a MUT marker = applied, restored by cp, cmp-identical):
  - Seat A F1, RPC marker: delete header's SET app.nutrition_rpc removed -> the contract pin red (1). The live leg is verify case C (an old-client INSERT after RPC calls in the same transaction). SUPERSEDED at apply (see "Found at apply"): the marker moved into the body with a restore before every return. New proof (2026-11-23): restore line of delete's no-op path removed -> the repinned contract test red (1); a function-level `SET app.nutrition_rpc = 'on'` re-added after delete's header -> red (1); both restored by cp, cmp-identical, hash re-checked. Live: a rolled-back dry run with the put's ok-path restore removed failed at C1 ("rev 1 legacy 0") as predicted; the real file's dry run and the post-apply verify passed A to N (N reads the marker after every return path of both RPCs).
  - Seat A F3, fake C5a: identical item re-push treated as changed while entries is non-null -> 'an identical old-client re-push ... is invisible' red (1).
  - Seat B P1, push cost: the per-slot whole-box read restored at both sites -> 'O(rows), not O(slots x rows)' red (1). A lazy signature was tried and dropped: its mutant (eager signing) stayed green, because every row built on this path is signed anyway; the filtered read is the fix.
  - Seat B P2, owed-pull sink: bare unawaited(pullBody) restored -> 'an owed pull that throws is reported' red (1; the error escaped unreported).
  - Seat B P3, generation: flags consumed before the generation check -> 'A -> B -> A' red (1).
  - Seat B P3, restore never throws: the new catch's telemetry pair removed -> sync_telemetry_test pair count red (1). PRESENCE only: no behavioural test drives restoreNutritionLogsForSyncDomain (flag-gated off).
  - Seat B P3, food_name signature: the name-only read restored -> 'only food_name signs like its cloud copy' red (1).
  - Seat B P3, stuck-slot log: the section's dedupe bypassed -> the oversized-slot test red (1).
  - Delta seat P2: `_pushSlot` re-read reverted to the whole box (MA) -> O(rows) test red (put pass); `applyLocked` reverted (MB) -> red (pull pass). Delta P3: the fake `since` back to a text compare (MC) -> contract shape test red; `_onceThisLaunch.clear()` removed (MD) -> oversized-slot test red. The prefix-before-read change is equivalent (no mutant possible).
impact_analysis: |
  Readers are unchanged: the engine writes only nlog_ rows of the shape logMeal writes, and its own store keys (nslot_) are skipped by every whole-box reader (store_readers test runs each reader with and without them and gets identical answers; the 17 whole-box loops are pinned). Old clients keep working: their plain upserts still land (the trigger marks them legacy) and a new client re-baselines on seeing one. Undo of a delete is refused when the entry is already back or when an id-less snapshot predates the re-baseline (never a duplicate). Every account is a testing account (CLAUDE.md 1), so the one-time re-baseline of existing rows is not a real-user migration.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "New nutrition_slot_{merge,remote,engine,section}.dart; nutrition_write_service.dart, sync_service.dart, sync/sync_nutrition.dart routed; flutter analyze clean." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "nlog_ rows carry entry_id; nslot_ store keys; behavioural tests assert content per device after every schedule." }
  - { tier: 3, name: "Postgres schema", status: fixed_in_this_batch, evidence: "Migration 181 applied 2026-11-23 on the founder's go (cloud version 20261123074819); information_schema shows the 4 nutrition_logs columns, entry_key and the tombstone table; 7 functions INVOKER, search_path=public, 4 marker calls in each RPC." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "After the apply all 92 existing nutrition_logs rows read rev 1, legacy_rev 0, entries null (legacy) and are re-baselined by the first new client; no backfill." }
  - { tier: 5, name: "Migrations applied", status: fixed_in_this_batch, evidence: "schema_migrations has 181_nutrition_slot_sync (20261123074819); backups/applied_migrations.json entry 181 with the file hash, live_schema_columns.json regenerated for the three tables, same commit." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: fixed_in_this_batch, evidence: "nutrition_slot_tombstones: RLS on, four own-row policies, REVOKE ALL FROM anon; RPCs are INVOKER so nutrition_logs RLS applies. Live: has_function_privilege anon false on all 7 functions, authenticated true only on the 4 RPCs; verify J (a second testing user) saw none of the first user's rows or tombstones." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: fixed_in_this_batch, evidence: "FakeNslotServer contract table C1-C10 mirrors the RPCs; supabase/tests/nutrition_slot_rpc_live_verify.sql ran on the real server after the apply (testing user, BEGIN..ROLLBACK) and passed A to N incl. J." }
recurrence: "Recurrence of the class 'restore overwrites / resurrects what the user changed locally' (lib/core/services/CLAUDE.md pitfall row 'Restore overwrites a local row the user just logged', c5a1f2) and of the nutrition push FK class c9f2a7; OI-281 (deletes never reach the cloud) is the open board instance. Known-good fix applied: tombstones plus a three-way merge with a per-device base instead of local-wins-only."
related_bugs: [b1d2a8, c9f2a7, e4a8b1]
---

# a6c4e2 - nutrition-slot-sync

## What happened
The nutrition push upserted each slot (date + meal) whole from the pushing device's view, and a delete was local only (OI-281). The cold-start restore wrote back any cloud row the device did not hold, so a deleted meal returned, and a moved meal returned in its old slot. With the launch pull removed (b1d2a8) a meal from another device reached a populated device only through a full restore.

## The fix
Decision B (founder, 2026-11-22): a proper cross-device slot sync. Every meal has a stable `entry_id`; the server keeps a revision per slot and tombstones for deleted slots; writes are compare-and-set; each device keeps a ledger (the last state it agreed with the server) and merges three ways by `entry_id`. Spec: `docs/plans/nutrition-slot-sync.md`.

## Residual, stated
Migration 181 is live (applied 2026-11-23, before the merge, on the founder's go): without it the RPC probe would fail and new mode would send and restore no meals (a missing RPC never selects the old path; only the kill switch does). Removing the legacy paths and the kill switch is OI-522.

## Found at apply (2026-11-23)
The first `apply_migration` of 181 failed and rolled back whole: `42501 permission denied to set parameter "app.nutrition_rpc"`. The B-pass fix for seat A finding 1 had moved the marker into the function headers (`SET app.nutrition_rpc = 'on'`); Postgres 17 lets only a superuser (or a role granted `SET` on that parameter) attach a custom placeholder to a function, and the migration role `postgres` is not one. No local test, fake or reviewer could see it. Nothing landed (0 new columns, no table, 0 functions, 163 migrations, checked live). Fix: each RPC saves the marker, sets it `'on'` after validation, and puts the saved value back on the line before every `RETURN`; an error rolls the local setting back by itself. Proved before the second apply by a rolled-back dry run of the file plus the full verify (new case N reads the marker after every return path) and a mutant dry run that failed at C1 as predicted. Bug-class 2.167 now warns against the function-level form. A fresh Sonnet seat on this fix found no P0/P1 and one P2 in the new pin (an inline `THEN RETURN` slipped past the line scan), fixed and mutant-proven; its two P3s were already covered (closure DELTA2-1..3).

## B-pass (2026-11-23, two seats, review fffbe6b1d574)
No P0. Fixed in this batch: the push loop re-read the whole box per slot (O(slots x rows) SHA-1 on the UI isolate, P1); the RPC marker stayed on for the rest of the transaction (restored before every return now; the first fix, a function-level SET, was refused at apply); the live verify could not pass (status asserts, the second user read before the role switch, an RPC-written row for the item trigger, an identical re-push case, all grants); the fake treated an identical old-client re-push as a legacy write; an owed pull had no error sink; an older generation's release ate the new generation's owed push; the new-mode restore could throw; the signature ignored `food_name`; an oversized slot logged on every pass; missing pins for the grants and the marker; the fake's timestamp text now has PostgREST's trimmed shapes; a 5 s lock timeout heads the migration. Full record: the review file and the closure ledger.

## Found on the way (2026-11-23)
`test/sync/nutrition_pull_removed_behavioral_test.dart` (Landing 1a-i, already on `main`) fixed its fixture `created_at` at 2026-11-22 while `pullRecentCrossChannelLogs` reads the last 24 h, so three tests went red the day after the merge, on `main` too. The fixture times now derive from `DateTime.now()`; bug-class 2.168.
