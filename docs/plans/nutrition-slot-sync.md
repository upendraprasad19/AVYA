# Nutrition slot sync — every device converges on the same meals (B1 "B", OI-281, nutrition slice of OI-280)

Status: DRAFT v7 (2026-11-23) = LANDING 1a-ii. Round 6 `not_converged` (2 P1, both in the re-baseline's flush) → **§15 (v7) drops the flush: the re-baseline never writes to the cloud; it replaces only legacy (id-less) rows with the cloud's content, idempotently.** Precedence: §15 > §14 > §12 > §11 > body. Earlier: DRAFT v6 (2026-11-23). Round 5 `not_converged` (3 P1, all in pre-build history reconciliation) → **§14 (v6) REPLACES §13.1-§13.7 and every earlier bootstrap / Phase A / stamp-pass text with a one-time per-device re-baseline (flush, then rebuild from the cloud)**; precedence otherwise §14 > §12 > §11 > body. Earlier: DRAFT v5 (2026-11-22). Round 4 `not_converged` (3 P1, all in bootstrap content reconciliation) → **§13 "Round 4 amendments (v5)" OVERRIDES §12, §11 and the body** (bootstrap redesigned: each slot decided whole by one side). Earlier: DRAFT v4 (2026-11-22). Round 3 `not_converged` (3 P1) → split per §4.12.1 and **§12 "Round 3 amendments (v4)" OVERRIDES §11 and the body**. Earlier: DRAFT v3 (2026-11-22). Round 1 `not_converged` (4 P1) → v2 (body, §10). Round 2 `not_converged` (2 P1, both on entry identity, 7 P2) → **§11 "Round 2 amendments (v3)" OVERRIDES the body wherever they conflict** (identity, the base-unknown merge, serialization, cursors, op names). If round 3 surfaces new material P1s, the landing splits per §4.12.1 (push+tombstones+identity first, pull second), both built in this batch. Founder decision 2026-11-22: "We will build it properly, we will build B. No shortcuts." Replaces Landing 1a's B1 in `docs/plans/oi348-walk-fixes-landing1.md` (that file now only points here). P4 ships in the same landing as written there ("P4 v3").
Execution mode (§4.12.7): INLINE, one worktree (`oi348-device-walk`), decided now.
Tier: `platform` by `docs/blast_radius.yaml:107-108` (`supabase/migrations/**`, `lib/core/services/sync/**`). The RPCs are deliberately SECURITY INVOKER (a SECURITY DEFINER mention makes the migration catastrophic, `docs/blast_radius.yaml:55-56`, and is not needed, §3.3). So: ×2 plan review, plan-review record, B-pass; no Hermes.

## 1. Facts (each read in this worktree or queried live, 2026-11-22)

- **Cloud shape:** one `nutrition_logs` row per slot `(user_id, date, meal_type)` (unique `uniq_nutrition_logs_user_date_meal`); items in `nutrition_log_items` keyed `(log_id, item_index)`; FK `log_id → nutrition_logs.id ON DELETE CASCADE`, `user_id → users.id ON DELETE CASCADE`; no `updated_at`, no `deleted_at`, no revision; RLS select/insert/update/delete own on both; BEFORE UPDATE `trg_suppress_redundant_updates` on both (migration 149).
- **Only the client writes cloud meals.** `supabase/functions` holds readers only (`getNutritionHistory.ts`, `getProgressSummary.ts`, `protein-gap-alert`, `re-engagement`, `weekly-report`, `restore-user-snapshot`; `delete-account` via FK). SQL readers: migrations 028, 101, 117, 120. Telegram bot dropped (OI-476).
- **Local shape:** many `nlog_<date>_<meal>_<hash8>[_n]` entries per slot in the user-scoped `nutritionBox` (`computeLogKey`, `nutrition_write_service.dart:1057`; first free occurrence `:146`). Entry writers: `logMeal :67` (stamps `created_at` and `logged_at` `:132-133`), `appendItemsToMeal :273`, `editLog :328` (same key), `moveMealLog :407` (keeps the row's `created_at`, new key in the new slot, old key deleted), `deleteLog :502`, `restoreLastDeleted :607` and `restoreFoodLog :953` (put the saved copy back, same `created_at`), `relogSavedMeal :708` (through `logMeal`); restore writer `sync_nutrition.dart:773/783`; `NlogKeyMigrator` (one-shot v7, does not touch `created_at`).
- **Push** (`sync_nutrition.dart:201-432`): all local entries merged per slot (`mergeNutritionLogsBySlot :10`), upserted on the natural key; items upserted by index, vacuumed past the count. A slot that becomes EMPTY locally is never sent: its cloud row stays forever (OI-281). `SyncSkipIndex.commit(liveKeys)` drops a vanished slot's fingerprint, so nothing remembers it must be deleted. Items carry 8 fields (`:373-382`); `food_id` is never sent.
- **Pull:** a populated device has no nutrition pull except `_pullNutritionLogs` (`sync_service.dart:2658`, the dropped-Telegram copier, from `checkAndSync :1038`, launch only): each cloud row is written under its UUID with no items → the last 24 h counted twice (B1). `_restoreIfNeeded` restores nutrition only on a device with no workout history; `restoreLightweightAlways` none.
- **Restore** (`_restoreNutritionLogs :609`): a multiset union per slot that collapses each slot into ONE local entry under a re-derived key (`_nlogKeyForRestore`, `sync_service.dart:704`). Also reached through `restoreNutritionLogsForSyncDomain` / `pushNutritionLogsForSyncDomain` (`sync_nutrition.dart:918-928`) and the single-call snapshot (`preFetched`, read `select: "*, nutrition_log_items(*)"` filtered and ordered by `created_at`, `paged_reads.ts:170-177`).
- `SyncFingerprint.canonicalJson` (`sync_skip_index.dart:101`) sorts map keys but encodes numbers as given: `100` and `100.0` differ. Cloud numerics come back as doubles.
- `checkAndSync` runs only from the splash (`splash_screen.dart:203`). Resume hooks exist (`day_rollover_service.dart:71`, `home_screen.dart:102`); nothing pulls meals on resume (OI-279 excluded meals until OI-281).
- `syncBox` is ONE shared box (`hive_service.dart:42, 257`); `nutritionBox` is per user. `export_data.dart:25-26` exports EVERY Map in `nutritionBox` (today that already includes the nlog skip-index map: a live export defect, fixed here).
- Locked multi-device design (OI-280, founder 2026-10-01): server-set `updated_at` + tombstones, per-table cursor, per-row base version, conditional push, on conflict pull + merge + retry; add-only = union; per-key value = newer wins.

## 2. Acceptance scenarios (each a behavioural test)

Devices P (phone), W (web), X (third device), same account, all on this build unless stated.
- S1 W logs breakfast → P launches or resumes → breakfast appears ONCE with its items; day totals equal.
- S2 P edits the quantity → W reloads → W shows the edit only.
- S3 P deletes lunch → W reloads → gone on W and in the cloud (server readers stop seeing it).
- S4 P moves lunch → dinner → W shows it under dinner only. S4b: P moves it while W (offline) edits it in lunch → one copy, the newer `logged_at` wins.
- S5 P offline deletes a meal; W adds a different meal to the same slot; P online → only W's meal on both.
- S6 P and W offline add different meals to one slot → both meals on both, no double count.
- S7 P and W offline log the IDENTICAL meal (same key) → two entries on both (identity is `created_at`).
- S8 P and W edit the same meal offline → the later edit wins on both; one entry.
- S9 P deletes a meal while W edits it, both offline → the edit survives on both.
- S10 Launch, relaunch, resume ×10, and push→pull→re-sign round trips → totals and signatures never change; no `rev` churn (B1 cannot recur, no ping-pong).
- S11 Account switch mid-pull, mid-push or mid-restore → nothing written into the other account's box or rows.
- S12 An OLD client (AAB +50) writes a slot directly → new clients converge without a double count (legacy rule §4.1).
- S13 A fresh install restores each meal as its own entry under its original key.
- S14 A stale device (cursor a week old) restores through a snapshot while another device deleted a slot → the delete is applied (restore never moves the cursor of a populated device).
- S15 Seeded randomized convergence: 2-3 devices, random offline ops (log, append, edit, delete, move, undo, relog) and random sync interleavings against the fake server → all devices equal, day total = sum of live entries, no duplicate identity. ≥ 500 seeds in CI.

## 3. Server (one migration; number from `sh scripts/mint_migration.sh <slug>`, never `ls`)

1. `nutrition_logs`: `+ rev bigint not null default 1`, `+ updated_at timestamptz not null default clock_timestamp()`, `+ entries jsonb` (null = legacy row, no per-meal split). Index `(user_id, updated_at, id)`.
2. `nutrition_log_items`: `+ entry_key text` (null on legacy rows).
3. `nutrition_slot_tombstones(user_id uuid not null references users(id) on delete cascade, date date not null, meal_type text not null, rev bigint not null, deleted_at timestamptz not null default clock_timestamp(), primary key (user_id, date, meal_type))`, index `(user_id, deleted_at, date, meal_type)`. RLS: select/insert/update/delete own (the INVOKER RPCs write through it). A client could forge its OWN tombstone through PostgREST: self-harm only, the same accepted stance as `user_progress` (`lib/core/services/CLAUDE.md`, streak marker note). A hard delete plus this table instead of OI-280's `deleted_at` wording: every server reader keeps working with no filter (a `deleted_at` column needs all 9 swept, §4.1.5.3). Functionally the same tombstone.
4. **Revision rule (one rule, every writer):** a slot's `rev` only grows over its whole life, across delete and re-create: current rev = the row's `rev`, else the tombstone's `rev`, else 0; every successful write sets `current + 1`.
5. `nutrition_slot_put(p_date date, p_meal_type text, p_base_rev bigint, p_totals jsonb, p_entries jsonb, p_items jsonb, p_created_at timestamptz) returns jsonb`, plpgsql, SECURITY INVOKER, `set search_path = public`:
   - `v_uid := auth.uid()`, raise if null. Bounds: meal_type in {breakfast,lunch,dinner,snacks}; `jsonb_array_length(p_entries) <= 100`, `p_items <= 500`; numerics clamped to the FC6 ceilings (`nutrition_write_service.dart:191-194`); anything else raises.
   - `set_config('app.nutrition_rpc','on', true)`; `pg_advisory_xact_lock(hashtext(v_uid::text || '|' || p_date::text || '|' || p_meal_type))`; then `select id, rev from nutrition_logs where user_id = v_uid and date = p_date and meal_type = p_meal_type FOR UPDATE` (the row lock also serializes an old client's direct UPDATE, which takes no advisory lock); else the tombstone `FOR UPDATE`.
   - `current <> p_base_rev` → `{status:'conflict', rev, updated_at, row}` where `row` = totals, entries, items (with `entry_key`) or `{tombstone: true}` or null.
   - else: INSERT or UPDATE the parent (`rev = current + 1`); an INSERT's `unique_violation` (an old client inserted between the lock and the insert) is caught and returned as a conflict with the fresh row. Replace ALL items (delete + insert with ordinality `item_index` and `entry_key`). Delete the tombstone. Return `{status:'ok', rev, updated_at}`.
6. `nutrition_slot_delete(p_date, p_meal_type, p_base_rev)`: same lock, CAS and conflict payload; ok → delete the parent (items cascade), upsert the tombstone with `rev = current + 1`; nothing there and `p_base_rev = current` → `ok` no-op.
7. `nutrition_server_now() returns timestamptz` (`clock_timestamp()`, INVOKER): the restore's cursor start (§4.5).
8. Triggers for OLD clients (any write without `app.nutrition_rpc = on`):
   - `trg_zz_nutrition_rev` BEFORE INSERT OR UPDATE on `nutrition_logs` (sorts after `trg_suppress_redundant_updates`, so a true no-op stays suppressed): always `updated_at := clock_timestamp()`; non-RPC: `entries := null`; non-RPC INSERT: `rev := coalesce(tombstone.rev, 0) + 1` and delete that tombstone (no ABA after a delete); non-RPC UPDATE: `rev := OLD.rev + 1` only when `NEW.rev = OLD.rev` (no double bump).
   - `trg_zz_nutrition_items_rev` AFTER INSERT OR UPDATE OR DELETE on `nutrition_log_items`, non-RPC only: `update nutrition_logs set rev = rev + 1, entries = null where id = <log_id>`. The explicit `rev` change keeps the parent UPDATE from being suppressed when `entries` is already null; the parent trigger then sees `NEW.rev <> OLD.rev` and does not bump again. Row-level, so a multi-item write bumps several times: `rev` only needs to grow.
9. `REVOKE ALL ON FUNCTION ... FROM public, anon`; `GRANT EXECUTE ... TO authenticated` (memory `feedback_revoke_from_public_not_role`).
10. Old clients are UNSUPPORTED after this ships (pre-launch: every account is a testing account, CLAUDE.md §1): the triggers keep their writes visible and never corrupt the per-meal split, and §4.1's legacy rule keeps new clients free of double counts; an old client's edit can lose to a new client's dirty push (LOW event).
11. `restore-user-snapshot`: unchanged (`select *` carries the new columns). No EF deploy.
12. Same commit: `backups/live_schema_columns.json` regenerated, `backups/applied_migrations.json` entry, `docs/naming_conventions.md` terms (`slot`, `entry`, `slot ledger`, `nutrition tombstone`, `slot rev`).

## 4. Client

### 4.1 Model (pure, `lib/core/services/sync/nutrition_slot_merge.dart`, no Hive)
- **Entry** = one `nlog_` row. **Identity** = its `created_at` string; an entry with no `created_at` (pre-2026 legacy) uses `key:<hive key>`. The key is only WHERE it is stored.
- **Canonical projection** (one function, used for local rows, the RPC payload and rows read back): each item → `[lowercased trimmed name, quantity_g, calories, protein, carbs, fat, fiber]`, every number `toStringAsFixed(1)` of a double (null → `"0.0"`); the entry's five totals the same; **signature** = SHA of the joined projection. Only projected fields are sent and compared; a round trip cannot change a signature (S10 test). The RPC stores the signature in `entries[i].s` for diagnostics only; every comparison re-computes it.
- **Cloud slot content**: `entries` = ordered `[{id: identity, k: key, s, la: logged_at, ca: created_at, src: source, t: totals, n: item_count}]`; items ordered by entry with `entry_key = id`. Parent totals = sum of entry totals.
- **Slot ledger** = the 3-way BASE: `nutritionBox['nslot_ledger']` = `{slot: {rev, ua: updated_at, e: {identity: signature}}}`, and `nutritionBox['nslot_cursor']` = `{ua, id}` (keyset). They live in `nutritionBox` ON PURPOSE: same box, same lifetime as the entries (a sign-out or clear wipes both together, so a ledger can never describe a box that was emptied under it). Every whole-box reader is checked against these two keys (§5).
- **`mergeSlot(base, local, cloud)`** per identity in local ∪ cloud ∪ base (L, C, B = signatures; absent = null):
  1. L == C → keep L.
  2. base known: L == B → take C (C null → remove locally); C == B → keep L; both changed: both present → newer `logged_at` wins (tie → local); one null and the other edited → keep the edited one (S9).
  3. base unknown (slot never synced, or bootstrap): union by identity; both present and different → newer `logged_at`.
  - Placement: a kept entry keeps its key; an incoming entry whose key is taken locally by a DIFFERENT identity is stored at `firstFreeLogKey(baseLogKey(key))` (identity unchanged, so the re-key is invisible to every later merge, S7).
- **Legacy cloud slot** (`entries == null`, written by an old client): one synthetic cloud entry, identity `legacy:<row created_at>`, items = the row's items.
  - base unknown → the existing multiset rules (`nutritionLocalSlotIsSuperset`, `nutritionSlotUnion`) on the PROJECTED item signatures (so numeric rounding cannot fake a difference): local superset → keep local; else the missing items become ONE extra entry (identity `legacy:<created_at>`).
  - base known and local == base (clean) → the slot becomes exactly the synthetic entry (no double count; the per-meal split of that slot is lost, an old-client write's cost).
  - base known and local dirty → local wins; the push overwrites; LOW `nslot_legacy_overwritten`.
- **Day pass** (after every slot of a date is merged, S4/S4b): one identity present in two slots of the same date → keep the copy with the newer `logged_at`, remove the other (a removal that is now a local change, pushed like any other).

### 4.2 Push (replaces the `_syncNutritionLogs` body behind the switch)
- Slots = local slots ∪ ledger slots, ordered: every put before any delete (a move adds the destination before the source is removed). Each through `nlogIndex.pushIfChanged(slot, fp, push)`; `fp` = `"<ledger rev>|<ledger ua>|" + sorted local identity:signature pairs` (a ledger change forces a re-check). `liveKeys` = every slot visited. `.rpc(` is a terminal read to Gate G1 (`sync_hash_skip_atomicity_lib.dart:106`), so G1 does not enforce this placement: a new test pins that both RPC calls sit inside the closure.
- Closure: local signatures == ledger `e` → `return true`. Local empty, ledger `e` non-empty → `nutrition_slot_delete(base_rev)`. Else `nutrition_slot_put(base_rev, ...)`. Over 100 entries / 500 items (constants shared with the migration's bounds via one Dart const + a test that greps the SQL) → no RPC, `return false`, LOW `nslot_slot_too_large` once per launch per slot. `ownerChangedSince(userId)` immediately before every RPC.
- `ok` → ledger slot := `{rev, ua, e: local}`. `conflict` → `mergeSlot(ledger, local, returned)` + day pass → apply (§4.4) → ledger := returned → retry with the new base, max 3 rounds; then `return false` + LOW `nslot_conflict_rounds_exhausted`.
- RPC missing (`PGRST202` / 404) → the legacy upsert body (kept verbatim) for that pass + LOW `nslot_rpc_missing` once per launch.
- Failures go through `_reportSyncFailure` (it calls `ErrorTelemetry.redactRowValues`; an RPC error echoes the payload). Op literals `nslot_put`, `nslot_delete` = PUSH ops the sweep re-sends; `nslot_pull`, `nslot_restore` added to `kNotSweptOpTypes` (the forcing-function test enumerates them).

### 4.3 Pull
- `pullNutritionSlots(userId)`: rows with `(updated_at, id) > (cursor.ua − 5 min, '')`, keyset-paged on `(updated_at, id)` until a short page (`*, nutrition_log_items(*)`); tombstones keyset-paged on `(deleted_at, date, meal_type)`. The overlap absorbs commit-order skew; applying is idempotent.
- Per slot: skip when cloud `rev` AND `updated_at` equal the ledger's. Else `mergeSlot(ledger, local, cloud)` + day pass → apply → ledger := cloud. A result that differs from cloud is dirty and goes out with the push that follows (`syncNutritionData()` after a pull that wrote).
- The cursor advances to the last `(updated_at, id)` seen only after every slot applied; any failure leaves it.
- Runs: in `checkAndSync` where the Telegram nutrition leg ran (`:1038`), and on `AppLifecycleState.resumed` (registered by SyncService itself, at most once per 2 minutes, never while signed out).

### 4.4 Apply (the ONE local writer for pulled, conflicted and restored content)
- Re-read the slot's entries, compute, then start `box.putAll(changed)` and `box.deleteAll(removed)` in the same synchronous run with no `await` between the read and both calls, then `await Future.wait`. A key is deleted only if its value still has the identity and signature that was read (a user edit landing first is never removed).
- `ownerChangedSince(userId)` before the read and before the writes; every written entry clamped (`clampRestoredNutritionRow`); incoming entries keep their own `source`, `created_at`, `logged_at`.
- After a pass that wrote anything: `NutritionWriteService.invalidateAfterSync()` (a public static over the existing `_invalidateNutritionProviders`, same provider set).

### 4.5 Serialization, restore and bootstrap
- ONE `SerialSlot` (`serial_slot.dart`) for the nutrition domain, held by every entry point that reads or writes the ledger: the push (`syncNutritionDataNow`), the pull (launch and resume), `_restoreNutritionLogs` (all callers: `restoreFromCloud`, `_restoreIfNeeded`, the snapshot path, `restoreNutritionLogsForSyncDomain`) and `pushNutritionLogsForSyncDomain`. Test: a restore and a push racing.
- **Restore** under the new path = apply the rows it read with the ledger as base; a slot ABSENT from the snapshot is never treated as deleted (only tombstones delete). The cursor: if the ledger was EMPTY when the restore started (fresh device), cursor := `nutrition_server_now()` called BEFORE the read, minus 5 min; a populated device's cursor is never moved by a restore (S14), and its next pull applies the tombstones.
- **Bootstrap** (populated device, first launch of this build, no `nslot_ledger`): one full pull (cursor null) with base unknown = union, never a delete; then the ledger holds the cloud content. Stated consequence: a meal deleted on this device BEFORE this build (whose cloud row OI-281 kept) comes back once on that device; deleting it again now reaches the cloud. Testing accounts only (CLAUDE.md §1); every post-launch install starts on this build. Not offered as a founder choice (CLAUDE.md §1).
- **Phantom cleanup** (runs before the bootstrap, once per user, flag `syncBox['nutrition_phantom_clean_<userId>']`, owner check before the scan): delete UUID-keyed Map rows with `meal_type` + `date`, no `items`, `is_saved_meal != true` (the only shape the Telegram copier wrote). LOW `nutrition_pull_copies_removed count=N` when N > 0.
- **Telegram nutrition leg removed** from `pullRecentCrossChannelLogs`; the weight and measurement legs are untouched.

### 4.6 Kill switches (§4.6; default = new path ON)
- `configBox['disable_nutrition_slot_sync']` → old push, old restore, no slot pull, no resume pull, no cleanup (old paths verbatim).
- `configBox['restore_nutrition_launch_pull']` → the old Telegram nutrition leg runs again (old path reachable).
- One OI minted (`scripts/mint_oi.sh`) to remove both old paths after the device check.

## 5. Writers and readers (§4.1)
- Cloud writers: `nutrition_slot_put/delete`; the legacy upsert (`sync_nutrition.dart:337, 373, 403`; switch on or RPC missing); the two triggers. Cloud readers: §1 + pull + restore.
- Local writers: §1 entry writers + apply (§4.4) + the phantom cleanup. Local readers: the 17 whole-box walks (`nutrition_read_service.dart:120`; `ai_snapshot_builder.dart:870, 919, 984, 1161, 1224`; `home_provider.dart:794`; `nutrition_provider.dart:440, 1300, 1794`; `nutrition_repository.dart:77, 105, 169, 287, 468`; `weekly_report_data_provider.dart:79`; `export_data.dart:25`). `export_data.dart` changes to export only `nlog_` rows (fixes today's export of the skip-index map too; count = rows exported). A behavioural test seeds `nslot_ledger`, `nslot_cursor` and the skip index next to two meals and asserts every one of the 17 returns exactly the two meals.
- SoT registry: new concept `nutrition_slot_sync` (writers: RPCs, push, apply, cleanup; readers: pull, restore, the 17 walks; `behavioral_test_path`); the `sync_nutrition_log_payload_hash_index` entry and its row in `lib/core/services/CLAUDE.md` ("sole writer AND reader") updated for the new fingerprint.

## 6. Tests and mutations
- `test/sync/nutrition_slot_merge_test.dart` (pure): every §4.1 rule, the day pass, legacy rules, re-key, projection round trip (S10 signature), S5-S9, S4b, S7.
- `test/sync/nutrition_slot_sync_behavioral_test.dart` against a fake RPC server whose contract table is written FIRST (memory `feedback_test_fake_contract_table_before_cases`: CAS, conflict payload, tombstones, the revision rule, keyset order, bounds, legacy rows, RPC-missing): S1-S4, S10-S14, conflict retry cap, cursor kept on a failed slot, apply never deletes a key the user just changed, puts-before-deletes order, the 17 readers.
- `test/sync/nutrition_slot_convergence_random_test.dart`: S15 (seeded, failing seed printed).
- `test/sync/nutrition_restore_entries_test.dart`: S13, S14, legacy restore.
- `test/sync/nutrition_pull_removed_behavioral_test.dart`: Telegram leg gone; switch restores it; cleanup rule (removes the phantom shape, keeps `nlog_`, saved meal, UUID row with `items`); once only; no flag on a failed owner check; weight leg intact.
- SQL `supabase/tests/nutrition_slot_rpc_live_verify.sql` in `BEGIN … ROLLBACK` after the apply: CAS ok/conflict; delete → tombstone → put (rev keeps growing); old-client INSERT after a tombstone (rev = tombstone + 1, tombstone gone); two consecutive old-client item edits on a legacy row → two bumps; old-client UPDATE nulls `entries`; another uid cannot touch my slot; bounds raise.
- Mutations (each recorded with its red count in the diagnose-doc, applied-check by `grep -c`): drop the CAS compare; take cloud when the base is unknown; projection without rounding; identity = key instead of `created_at`; advance the cursor before apply; let restore move a populated cursor; skip `ownerChangedSince` before the RPC; drop the tombstone send for an emptied slot; delete-before-put ordering; drop the day pass; trigger keeps `entries` on a direct write; items trigger without the explicit `rev` bump; re-add the Telegram leg.
- Existing tests run and repointed (never loosened): `sync_fanout_contract_test`, `restore_local_wins_additive_test`, `restore_completeness_test`, every `nutrition_*` test in `test/contracts` and `test/sync`, `telegram_surface_removed_test.dart:260-268`, `sync_retry_controller_test` (op-type enumeration), Gate G1.

## 7. Rollout order and authorizations
1. ×2 context-blind plan review (this doc + landing1 "P4 v3") → converged; plan-review record.
2. Code + tests + full gate loop + `flutter analyze --no-fatal-infos` + PR + `land_pr.sh --ci-only` green.
3. **Migration apply to prod: the founder's explicit go** (§4.3), then the live SQL verify in `BEGIN … ROLLBACK`.
4. B-pass, then merge.
5. Web deploy and AAB build only when the founder asks (`/build-apk`).
6. Device check (§5): S1-S4 on phone + web, then the OI-348 walk resumes.

## 8. Docs and ledgers (same batch)
Diagnose-doc for B1 (+ OI-281 closure, `related_bugs` c9f2a7 / NUT-02 / e4a8b1), closure ledger `docs/audit/oi348-landing1a.closure.yaml` (every round-1 finding + B1 + P4 with a terminal state), `docs/architecture/sync.md` (nutrition section rewritten), `lib/core/services/CLAUDE.md` (new row; hash-index row), `lib/features/nutrition/CLAUDE.md` (the "LOCAL-ONLY cloud consistency" residual of move/delete, `nutrition_write_service.dart:398-406` comment, removed), `supabase/migrations/CLAUDE.md` (the revision rule + trigger naming), OI-279/280/281 text (281 → closed, 280 → nutrition done + tombstone pruning note, 279 → meals now pulled on resume), `docs/naming_conventions.md`.

## 9. Out of scope, recorded (other work, not this bug)
- OI-280's other tables (water entries, workouts, weight, schedule) stay on OI-280.
- Tombstone pruning: one row per deleted slot; none written by this batch. A future pruning job must force a full reconcile on any device whose cursor predates it (note added to OI-280).
- The ledger keeps one small entry per slot ever synced (including emptied ones), rewritten as one Hive value per pass: a few KB per year of daily logging.

## 10. Round 1 findings → resolution
1 signature round trip → §4.1 canonical projection + S10. 2 legacy item-only change suppressed → §3.8 explicit `rev` bump. 3 rev ABA → §3.4 revision rule + §3.8 INSERT leg + §4.3 skip on rev AND `updated_at`. 4 restore moves the cursor past tombstones → §4.5 (only a fresh device sets it, from `nutrition_server_now()` before the read) + S14. 5 move vs remote edit → §4.1 day pass + §4.2 puts before deletes + S4b. 6 identity → `created_at` (§4.1) + projected legacy signatures. 7 old client double count → §4.1 legacy rule + §3.10. 8 lock vs direct writes → §3.5 `FOR UPDATE` + `unique_violation` as conflict + explicit casts. 9 apply gap → §4.4. 10 offset paging → §4.3 keyset. 11 restore paths unserialized → §4.5 one `SerialSlot`. 12 export of non-meal keys → §5 export fix + 17-reader test (ledger stays in `nutritionBox` for the shared lifetime, §4.1). 13 contradictory switch names → one set (§4.6), landing1 B1 now a pointer. 14 tombstone RLS → INVOKER kept, forgery = self-harm, stated (§3.3). 15 process steps → §8 + §4.2 telemetry decisions + tier line. 16 bounds → §4.2 shared constants. 17 no change. 18 stated §9. 19 → S15.

## 11. Round 2 amendments (v3 — override the body where they conflict)

### 11.1 Identity = a stamped `entry_id` (R2 findings 1, 2; R1-6, R1-7)
- Every `nlog_` row carries `entry_id` (UUID v4). `logMeal` stamps it in the payload (`nutrition_write_service.dart:114-134`), so `relogSavedMeal`, the coach and every other caller of `logMeal` get one. `editLog` / `appendItemsToMeal` keep it (they copy the row), `moveMealLog` keeps it (the row is copied to the new key), `restoreLastDeleted` / `restoreFoodLog` keep it (the saved copy). `created_at` is NOT identity any more.
- **Stamp pass** (inside the nutrition slot, before any push / pull / restore of a pass, owner-checked): every `nlog_` row with no `entry_id` gets one, written into the row. A local DUPLICATE `entry_id` (two rows, one id) is a defect: if the two have the same signature they are a true duplicate row and the one at the later key keeps a NEW id (both meals stay, counted as logged); LOW `nslot_duplicate_entry_id`. Never collapsed.
- **Deterministic ids for synthetic/legacy entries:** an entry built from a legacy cloud row (no `entries`) gets `entry_id = uuid v5(namespace, "<date>|<meal>|<row created_at as parsed instant, ISO-Z>|<projected item multiset>")`, so two devices that synthesize from the same legacy row get the SAME id.
- Cloud: `entries[i].id` = `entry_id`; `nutrition_log_items.entry_key` = `entry_id`.

### 11.2 Merge = two phases (replaces §4.1 rule 3 "base unknown → union" and the legacy base-unknown rule)
- **Phase A, reconciliation**: for a slot whose ledger base is UNKNOWN (bootstrap, fresh restore, a slot first seen) or whose cloud content is legacy:
  1. Pair by id: local and cloud entries with the same `entry_id`.
  2. Adopt by signature: an unpaired local entry whose projected signature equals an unpaired cloud entry's takes the CLOUD `entry_id` (row rewritten, key kept). One-to-one multiset pairing.
  3. Remaining unpaired local entries L' and cloud entries C', compared as projected ITEM multisets M(L'), M(C'):
     - M(L') == M(C') → L' replaced by C' (same food; cloud's split and ids win; the "combined restored entry vs separate entries" case).
     - M(C') ⊂ M(L') → keep L' (local has more; the push sends it).
     - M(L') ⊂ M(C') → L' replaced by C'.
     - neither → keep L' and add ONE synthetic entry holding M(C') − M(L') (deterministic id, §11.1). Nothing lost, nothing counted twice.
  4. If the result equals the cloud content: ledger base := cloud and NO put (R2-6: a year of unchanged history costs zero RPCs). Else ledger base := cloud and the slot is dirty (one put).
- **Phase B, 3-way by `entry_id`**: base known → §4.1 rule 2, keyed by `entry_id`. A legacy cloud row with base known → §4.1 legacy rules (clean → becomes the synthetic entry; dirty → local wins + LOW event).
- **Ties (R2-10):** newer `logged_at` (parsed instants), then the larger signature, then the larger `entry_id`; the same order in the day pass. Deterministic on every device.
- **Projection precision (R2-11):** 3 decimals; the values SENT are the projected values, so cloud and local hold the same numbers; an edit below 0.0005 is invisible (accepted, stated). Signature = SHA-256 of `jsonEncode` of the projected list.

### 11.3 Serialization and ownership (R2-3, R2-4)
- The nutrition `SerialSlot` ticket is taken INSIDE the lowest bodies: `_syncNutritionLogs`, `_restoreNutritionLogs`, `pullNutritionSlots`, the stamp pass, the phantom cleanup; never above them. Every caller is covered, including `weeklyFullSync` (`sync_service.dart:1337`), `pushNutritionLogsForSyncDomain` (`sync_nutrition.dart:921`) and the three restore call sites (`sync_service.dart:1870, 2191, 2386`). Released in `finally`.
- No body calls another body or `syncNutritionData()` while holding the ticket; the pull schedules the push with `unawaited(syncNutritionData())` AFTER release (test: a push fired from a pull completion finishes; no deadlock).
- Timeouts: each RPC 15 s, each page read 20 s, the whole pull 60 s; a timeout = a failed pass (cursor kept).
- The slot is replaced in `_onUserChanged` (with the coalescers).
- `ownerChangedSince(userId)` after EVERY await and before every ledger or Hive write; ledger reads/writes go through one helper `_nslotLedger(userId)` that no-ops when the owner changed. S11 adds "RPC returns after the swap → nothing written".

### 11.4 Cursors (R2-5)
- `nutritionBox['nslot_cursor']` = `{rows: {ts, row}, tombs: {ts, d, m}}` (no top-level `id`, `date` or `meal_type`; the 17-reader test seeds this exact shape). Two independent keyset cursors; `ts` compared as parsed instants.
- Tombstone skip: tombstone `rev` <= the ledger's `rev` for that slot. A cloud ROW whose `rev` is below the ledger's is skipped as stale (R2-12).

### 11.5 Capability and fallback (R2-7)
- One memoized capability probe per launch: `nutrition_server_now()`. `PGRST202` / 404 / `42883` → legacy mode for the whole launch (old push, old restore, no pull) + LOW `nslot_rpc_missing`. A network failure → no nutrition sync this pass (nothing cached). No in-closure fallback, so every catch inside a `pushIfChanged` closure still ends in `rethrow;` or `return false;` (G1); a test pins the shape.

### 11.6 Telemetry op names (R2-8)
- Push ops `sync_nslot_put`, `sync_nslot_delete` (the `sync_` prefix makes `isPushFailureOpType`, `sync_retry_controller.dart:117-123`, re-arm the sweep). Reads `pull_nutrition_slots`, `stamp_nutrition_entries` (no push prefix; listed in the forcing-function test). Not in `highPriorityOpTypes`.

### 11.7 Fresh vs bootstrap (R2-9)
- Order inside a pass: phantom cleanup → stamp pass → exactly one of:
  - **fresh** = no `nslot_ledger` AND no `nlog_` rows → a restore may set both cursors from `nutrition_server_now()` read BEFORE the restore read;
  - **bootstrap** = no `nslot_ledger` AND `nlog_` rows exist → full pull (cursors null), Phase A for every slot; a restore in this state never sets a cursor;
  - **steady** = ledger present → normal pull; restores never move cursors.

### 11.8 Server additions (R2-12, R2-13)
- `nutrition_slot_put` also validates `sum(entries[].n) = jsonb_array_length(p_items)` and every item `entry_key` ∈ `entries[].id`; parent `created_at` := min(`entries[].ca`).
- AFTER DELETE trigger on `nutrition_logs`, non-RPC only: upsert the tombstone with `rev = OLD.rev + 1` (an old or manual delete still propagates).
- The migration text never contains the two-word phrase that `docs/blast_radius.yaml:55-56` matches (comments included); a test greps for it.
- The migration file and the regenerated `backups/live_schema_columns.json` land in the same commit (pre-apply); the live apply happens before the merge (§7 step 3), so snapshot and live schema agree at merge.

### 11.9 Apply and facts (R2-12, R2-13)
- Apply rewrites the row's `id` and `log_key` to the placed key on every re-key.
- Correction to §4.1: a sign-out CLOSES the per-uid boxes (per-uid files persist, `hive_user_session.dart`); ledger and entries still share one box and one lifetime.
- `simulation_service.dart:178` (dev reset) also clears `nslot_ledger` and `nslot_cursor`.
- The Dart fake mirrors the SQL contract by hand; the live-verify SQL runs once at apply. Stated in the diagnose-doc as a residual (CI cannot run live SQL).

### 11.10 Round 2 → resolution (kept below; §12 follows)
1 → §11.1 + §11.2 (adoption, item-multiset reconciliation, deterministic legacy ids). 2 → §11.1. 3 → §11.3. 4 → §11.3. 5 → §11.4. 6 → §11.2 step 4. 7 → §11.5. 8 → §11.6. 9 → §11.7. 10 → §11.2 ties. 11 → §11.2 precision. 12 → §11.8, §11.4, §11.9. 13 → §11.8, §11.9.

## 12. Round 3 amendments (v4 — override §11 and the body where they conflict)

**Split (§4.12.1, 2026-11-22):** three rounds each surfaced new P1s, so the landing splits. **Landing 1a-i** (B1 hotfix: Telegram nutrition leg removed + phantom cleanup, and P4) is specified in `docs/plans/oi348-walk-fixes-landing1.md` "v5" and ships first. **This plan is Landing 1a-ii** and no longer contains the Telegram-leg removal or the cleanup (§4.5's last two bullets and §4.6's second switch move to 1a-i). Both are built in this batch; this plan stays under review until converged. 1a-ii REUSES 1a-i's `_cleanupNutritionPullCopies` (and its tightened predicate: `user_id` present, `source != 'cloud_restore'`) as the first step of the bootstrap; it does not re-implement it.

### 12.1 The non-RPC delete trigger must not break account deletion (R3-1)
- `delete-account/index.ts:373` deletes the auth user; the cascade `auth.users → public.users → nutrition_logs` fires the AFTER DELETE trigger for rows whose `public.users` row is already gone, and a tombstone insert would raise 23503 (FK to `users`). The trigger returns at once when `pg_trigger_depth() > 1` (any cascade or trigger-driven delete) OR `not exists (select 1 from public.users where id = OLD.user_id)`. It writes a tombstone only for a top-level, non-RPC delete of a live user's row.
- Live verify (BEGIN … ROLLBACK): a throwaway `public.users` row with one meal, deleted through the cascade → succeeds, no tombstone; a top-level non-RPC delete of a live user's meal → one tombstone. Source-grep test pins both guard conditions; mutation: drop the guard → the cascade case reddens in the live verify (recorded, run once by hand) and the grep test reddens in CI.

### 12.2 Phase A is restricted (R3-2, R3-3, R3-5; replaces §11.2 Phase A)
- **Stamp marker.** The stamp pass writes `entry_id_src: 'stamp'` with the id; `logMeal` ids carry no marker. The marker is cleared (row rewritten) after the entry's slot is first confirmed by a successful put or a Phase A no-op. Only STAMPED entries (pre-1a-ii data) ever adopt or reconcile by content; an entry logged on this build is matched by `entry_id` only (S7 holds: two identical fresh logs stay two).
- **Steady state, slot first seen** (base unknown, not bootstrap): union by `entry_id`; adopt-by-signature only for stamped local entries; no item-multiset step.
- **Bootstrap** (§11.7), per slot:
  - cloud absent → local entries are the result (dirty → put).
  - cloud LEGACY (`entries == null`): compare the whole local slot with the cloud row as (projected item multiset, sum of entry totals). Equal → **keep the local split** (no collapse of the owner's cards), ledger base := `{rev: cloud rev, legacy: true, e: local signatures}`, NO put (R3-4: unchanged history costs zero RPCs); the first real local change puts and upgrades the row. Not equal → keep every local entry and add ONE synthetic entry holding M(C) − M(L) (deterministic id, §11.1) if non-empty; dirty → one put. This is today's proven restore union (`nutritionLocalSlotIsSuperset` / `nutritionSlotUnion`), applied without collapsing local entries; a pre-1a-ii local delete whose cloud row OI-281 kept comes back (stated, §4.5).
  - cloud NEW-FORMAT (another device bootstrapped first): pair by `entry_id`; adopt by signature (stamped local only, one-to-one); then for the remaining STAMPED local entries L' against the remaining cloud entries C': a stamped entry whose items are contained in what is left of M(C') AND whose totals equal its own item sums (no manual override) is **covered** and dropped (the other device already holds that food under its own split); every other stamped entry is kept; cloud entries are always kept. Non-stamped local entries are kept (union by id). Nothing on the cloud side is ever replaced by a synthetic entry (R3-2: no real id is lost, no item dropped).
- **Totals-only edits** (R3-3): any entry whose totals differ from its item sums is never dropped or replaced by Phase A; equality checks include totals.
- S7 text: two fresh identical logs on two devices stay two entries; two devices that hold the SAME pre-1a-ii history (one restored from the other) reconcile to one copy at bootstrap (intended).

### 12.3 Bootstrap budget (R3-4, R3-8)
- A push pass stops issuing RPCs after 50 slots or 30 s elapsed (whichever first) and returns; the remaining dirty slots go in the next pass (`pushIfChanged` returns false → re-tried; the coalescer re-arms with `syncNutritionData()` after release when slots remain). 30 s is below `_safeRestoreOp`'s 45 s ceiling (`sync_service.dart:1337` path), so the ticket is never held past it. Pull pages are bounded by §11.3's timeouts.

### 12.4 Locking and the stamp pass (R3-6)
- `_stampLocked(userId)` and `_cleanupLocked` (1a-i owns cleanup) assume the ticket is held; only the bodies (`_syncNutritionLogs`, `_restoreNutritionLogs`, `pullNutritionSlots`) take the ticket and call them first. Nothing else takes it. Test: a push body that stamps completes (no deadlock); a pull completion that fires a push completes.
- The stamp pass reads all `nlog_` rows, computes the stamped copies synchronously, then one `putAll` with no `await` between the read and the call; a key whose value changed before the write is skipped (re-stamped next pass).
- `editLog` strips `entry_id` and `entry_id_src` from `updates` (an `updates` map can never re-identify a row).
- A row with `migrated_from == <key that still exists>` (NlogKeyMigrator mid copy-then-delete) is not stamped this pass (R3-9).

### 12.5 Ledger sharding (R3-7)
- `nutritionBox['nslot_ledger_<date>']` = `{<meal>: {rev, ua, legacy?, e: {entry_id: signature}}}`, one shard per date; a pass accumulates shard changes in memory and writes each touched shard once (plus every 25 slots during a bootstrap). §9's size line corrected: about 150-400 KB per year in total, written only per touched date. The 17-reader test seeds a shard; the sim reset (`simulation_service.dart:178`) adds the `nslot_` prefix; `user_repository.dart:1210` `.clear()` already covers them.

### 12.6 Remaining items (R3-10, R3-11)
- The new path ignores `disable_nutrition_slot_merge` and `nlogHashSkipDisabledFor` (they govern only the legacy body, which they keep governing when `disable_nutrition_slot_sync` is on).
- Migration filename avoids the `*security_definer*` glob (`docs/blast_radius.yaml:93`); the grep test scans the filename and the text (comments included).
- Live verify adds: a PostgREST legacy upsert taking the DO UPDATE path (the BEFORE INSERT trigger fires on the proposed row): `rev` bumps exactly once and no tombstone is touched; the delete-account cascade case (§12.1).
- Mutations add: drop the delete-trigger guard; let Phase A reconcile non-stamped entries; drop the totals clause from "covered".

### 12.7 Round 3 → resolution (kept; §13 follows)
1 → §12.1. 2 → §12.2 (steady state: id union only; bootstrap: new-format cloud never replaced). 3 → §12.2 (legacy equal keeps the local split; totals clause). 4 → §12.2 legacy-equal no put + §12.3. 5 → §12.2 stamp marker + S7 text. 6 → §12.4. 7 → §12.5. 8 → §12.3. 9 → §12.4. 10 → §12.6. 11 → §12.6 + §12.1.

## 13. Round 4 amendments (v5 — override §12, §11 and the body where they conflict)

**Why a redesign of the bootstrap, not a fourth patch.** Rounds 2, 3 and 4 each found new double counts inside the CONTENT reconciliation of pre-1a-ii history (adopt-by-signature, item-multiset covering, legacy-equal split keeping). Every such rule mixes two devices' copies of one slot, and every mix has a partial-overlap case. v5 removes content mixing from the bootstrap entirely: **at bootstrap each slot is decided WHOLE by one side.** Steady state (Phase B, 3-way by `entry_id` over a known base) is unchanged; reviewers 2-4 traced it converged.

### 13.1 The base that already exists
Before 1a-ii every local meal write pushed its slot at once and `SyncSkipIndex` (domain `nlog`, stored in `nutritionBox` under its index key) recorded the CONFIRMED fingerprint per slot (`"<date> <meal>"`, `SyncService.nlogPayloadFingerprint`, `sync_service.dart:426`, written only after a confirmed push, `sync_skip_index.dart:285`). So at bootstrap a device can classify each local slot:
- **clean** — a confirmed fingerprint exists AND equals the fingerprint of the slot's current local content (recomputed by the same legacy payload builder);
- **dirty** — a confirmed fingerprint exists AND differs (a local change that never reached the cloud);
- **unknown** — no confirmed fingerprint (a restored slot never pushed from here, an index cleared by a sync epoch, or the hash-skip switch on). Treated as clean: before 1a-ii every local write pushed immediately, so a slot this device changed has a fingerprint unless that push failed offline AND the index was later cleared — stated residual (§13.6).
A read-only accessor `SyncSkipIndex.confirmedFingerprintOf(box, domain, rowKey)` is added (no write path).

### 13.2 Bootstrap rule (replaces §12.2 bootstrap and §11.2 Phase A entirely)
Bootstrap = no `bootstrap_done` marker in this device's ledger (`nutritionBox['nslot_meta'] = {bootstrap_done: bool}`); until it is set, every slot WITHOUT a ledger base is decided by this table, wherever it is first seen (bootstrap pull, push conflict, restore; R4 P2-5). Order inside a bootstrap pass: cleanup (1a-i's helper) → stamp pass → full pull (cursor null, resumable by keyset page) → decide every pulled slot → push local-only and winner slots (budget §13.4) → set `bootstrap_done` once every local slot has a ledger base.

| cloud slot | local slot | result |
|---|---|---|
| absent (no row, no tombstone) | any | local is the result; put with base 0 |
| tombstone | clean / unknown | cloud wins: local slot emptied (R4 P2-4: a post-1a-ii delete is not resurrected) |
| tombstone | dirty | local wins: put with base = tombstone rev |
| row (legacy or new-format) | absent | cloud wins: written locally |
| legacy | clean / unknown, items equal (projected multiset AND totals sum) | **converter**: this device's own split is put with base = legacy rev (the cloud learns per-meal ids from the device that owns the split); a conflict re-enters this table |
| legacy | clean / unknown, items differ | cloud wins: the slot becomes ONE synthetic entry (deterministic id, §11.1) |
| new-format | clean / unknown | cloud wins: the slot becomes exactly the cloud entries (their ids) |
| legacy or new-format | dirty | local wins WHOLE slot: put with base = cloud rev; LOW `nslot_bootstrap_local_wins` |
- No row of the table unions two sides, so no bootstrap path can count a food twice (R4 P1-1, P1-2: the scenarios end as "cloud wins" or "local wins whole", never both).
- After the decision the ledger base := the cloud content the device agreed with (or what its put confirmed); from then on Phase B applies (e.g. R4 P1-1: W took the synthetic entry; P converts later; W's base is the synthetic entry, W is clean → takes P's split).
- Stamp markers (§12.2) are no longer needed for matching and are dropped; ids from the stamp pass identify entries only inside this device until its slot is decided.
- Accepted losses, stated (testing accounts only, CLAUDE.md §1; every post-launch install starts on this build): (a) a device that does NOT own the split shows the slot as the converter's split or as one synthetic card; (b) an unpushed offline change in an "unknown" slot loses to the cloud (§13.6); (c) a dirty slot's whole-slot win overwrites a concurrent change another device made to the same slot before either upgraded.

### 13.3 Steady state, slot first seen after bootstrap
Only fresh `logMeal` ids exist locally after bootstrap, so a slot first seen is merged by `entry_id` union (S6, S7) with no content matching at all.

### 13.4 Budgets, ticket and ceilings (R4 P1-3)
- The nutrition ticket is NOT waited for by a push: a push that finds the nutrition section busy (pull, restore or another push running) sets `_nslotPushOwed = true` and returns `true` at once (no failure, so `_safeRestoreOp`'s 45 s ceiling and the sweep re-arm are never hit by queueing). The holder, on release in `finally`, fires `unawaited(syncNutritionData())` when owed. A busy-check is a synchronous check-and-set on one isolate.
- Push budget: stop issuing RPCs after 15 s elapsed or 50 slots; RPC timeout 10 s; so a body ends by ~25 s, under the 45 s ceiling, the stamp pass included (it is synchronous apart from one `putAll`). Remaining dirty slots set `_nslotPushOwed`.
- Pull budget: 25 s per pass; the cursor advances per fully applied keyset page, so a long pull resumes next pass. Restore keeps its own full read (today's paged read, `sync_nutrition.dart:619-645`), applies the bootstrap table, and on a fresh device sets the cursor to `nutrition_server_now()` taken before the read (the restore read is the full history, `since = '2020-01-01T00:00:00Z'`, `sync_service.dart` restore entry points; R4 P2-6).
- Permanent failures (`nslot_slot_too_large`, validation raise) never set `_nslotPushOwed` (no loop); they are logged once per launch.

### 13.5 Stamp pass vs NlogKeyMigrator (R4 P2-7)
- The stamp pass does not run until `configBox['nlog_key_migration_v7'] == true` (the migrator has finished on this device). The write guard is "key still PRESENT and its value equal to what was read"; an absent key is never re-created.

### 13.6 Residuals stated (diagnose-doc + OI-280 note)
- §13.2 (b): an unpushed offline edit in a slot with no confirmed fingerprint loses to the cloud at bootstrap.
- A delete-account test: the live verify deletes a throwaway user through the real `auth.users` cascade inside `BEGIN … ROLLBACK` and asserts it succeeds with no tombstone (R4 P2-8); a depth-1 delete of a live user's meal (e.g. a journey reset) writes a tombstone (intended: other devices drop it).
- A tombstone conflict reply to a device with no base: the table above decides (R4 P3-9).
- The 17-reader test seeds `nslot_ledger_<date>`, `nslot_cursor`, `nslot_meta` and the skip index exactly as written and asserts each reader returns only the meals.

### 13.7 Tests and mutations added
- Bootstrap table: one test per row, plus R4 P1-1 (legacy-equal: W bootstraps first, appends; P converts; both converge, rice counted once), R4 P1-2 (P converted; W dirty with an offline salad → W wins whole slot; P takes it; counted once), R4 P2-4 (X bootstraps after P deleted e2 → e2 gone on X), interrupted bootstrap (budget) resumes and still uses the table for undecided slots.
- S15 random convergence includes devices that start in the legacy state with overlapping histories and random dirty slots.
- Mutations: union instead of cloud-wins for a clean slot; treat dirty as clean; set `bootstrap_done` before every slot has a base; push waits for the ticket (the 45 s ceiling test reddens); stamp re-creates an absent key.

### 13.8 Round 4 → resolution (kept; §14 follows and REPLACES §13.1-§13.7)
P1-1 → §13.2 (no split keeping; converter + Phase B). P1-2 → §13.2 (no covering; whole-slot winner). P1-3 → §13.4. P2-4 → §13.2 tombstone rows. P2-5 → §13.2 "wherever first seen". P2-6 → §13.4 restore. P2-7 → §13.5. P2-8 → §13.6. P3-9 → §13.6.

## 14. Round 5 amendments (v6 — REPLACE §13.1-§13.7 and every earlier bootstrap / Phase A / stamp text)

**Why.** Rounds 2-5 all found their P1s in one place: reconciling PRE-1a-ii history (rows with no per-meal identity) between populated devices. Round 5 showed the v5 base (the legacy skip-index fingerprints) is erased by failed pushes, budget commits and sync epochs, so "dirty" cannot be detected reliably. CLAUDE.md §1: every account is a testing account pre-launch, existing-user migration is not a real-user risk, and every post-launch install starts on this build with NO pre-1a-ii history. So the migration is replaced by the simplest correct mechanism: a one-time **re-baseline** per device = flush, then rebuild from the cloud (what a reinstall already does today). Steady state (Phase B, 3-way by `entry_id` over a known base) is unchanged; rounds 2-5 traced it converged.

### 14.1 Removed
The §11.1 stamp pass and duplicate-id handling, §11.2 / §12.2 Phase A, §13.1 fingerprint classification, §13.2 table and converter, `confirmedFingerprintOf`, the stamp marker, `entry_id_src`, the `nlog_key_migration_v7` gate. `logMeal` still stamps `entry_id` (§11.1 first bullet stays), and edit / append / move / undo keep it.

### 14.2 Re-baseline (once per device and user; `nutritionBox['nslot_meta'] = {rebaselined: true}` when done)
Runs inside the nutrition section (§14.4), owner-checked after every await, at the first nutrition pass of this build:
1. **Snapshot** every local `nlog_` key and value (one synchronous read).
2. **Flush**: run the LEGACY push body (`_syncNutritionLogs` as it is today, verbatim) once. Any slot not confirmed (failure, timeout, owner change, aborted) → stop; the device stays in **legacy mode** this pass (old push, no pull) and retries at the next pass. Nothing local is touched.
3. **Read** `nutrition_server_now()`, then the full cloud history (`*, nutrition_log_items(*)`, keyset-paged, `since` none) and the tombstones. Any failure → stop, legacy mode, nothing local touched.
4. **Rebuild**, in one synchronous run before one `putAll` + one `deleteAll` (both started with no await between): if any snapshotted key was CHANGED or DELETED since step 1 → stop (a user write landed; retry next pass). Else delete every snapshotted key, and write every cloud slot as entries: a new-format row → its entries under their ids (key `firstFreeLogKey(baseKey)` per entry); a legacy row (`entries == null`) → ONE synthetic entry, `syn: true`, id = uuid v5(namespace, `"<date>|<meal>|<row created_at as parsed instant>|<projected item multiset>"`) (deterministic: every device builds the same id). Keys written by the user AFTER step 1 (new `logMeal` rows) are left untouched: they are fresh entries the flush never sent, so no cloud row contains them (no double count) and the next push sends them.
5. Ledger := every cloud slot read (rev, `updated_at`, entry signatures); cursors := the server time from step 3 minus 5 min; `rebaselined: true`. Then the normal push and pull run.
- **Results, stated** (testing accounts only; never shown as a founder choice, CLAUDE.md §1): (a) pre-1a-ii history shows ONE card per meal slot on every device (the owner's per-meal split of OLD days is not kept; new days keep it); (b) a meal deleted or moved before this build whose cloud row OI-281 kept comes back (in its old slot) on every device, once; deleting it now reaches the cloud; (c) the flush is the legacy last-writer push (today's behaviour on every launch): a slot changed on two devices before either upgraded keeps the last flusher's copy.
- Nothing in the re-baseline unions two sides, reads the skip index, or depends on detecting dirty slots: the flush sends this device's state first, and a user write during the window aborts the step.
- A fresh device (no `nlog_` rows) runs the same steps (the flush sends nothing): its restore IS the re-baseline (R4 P2-6). The existing restore entry points call the re-baseline when `rebaselined` is absent, and the steady-state restore (apply with the ledger base, never moving cursors) otherwise.

### 14.3 Legacy rows after the re-baseline (an old client still writing)
A legacy row seen in steady state is one synthetic entry with the §14.2 id. Base known, local clean → take it. Local dirty → local wins whole slot (put), LOW `nslot_legacy_overwritten`. **Synthetic supersede (R5 P2-2):** when the cloud slot is new-format and the base slot is a single `syn: true` entry, the synthetic entry is dropped even if edited locally (its items are the legacy row's, which the new-format content replaced); LOW `nslot_synthetic_superseded`. A local edit of a synthetic entry is pushed as a new-format slot holding that entry (id kept), so another device with base {syn} takes it (clean).

### 14.4 Section, budgets, owed (R5 P1-C, P2-3, P2-4)
- `SerialSlot` gains `bool get isBusy => _tail != null` (and `reset()` stays as is). The nutrition section is held by exactly three bodies: the re-baseline, the push, the pull. Each is a SEPARATE body: the pull never pushes, the push never pulls, the re-baseline is its own pass; a body that wants another schedules it with `unawaited(...)` AFTER release.
- A push that finds the section busy sets `_nslotPushOwed` (per-user state, cleared in `_onUserChanged` with the slot reset) and returns. The holder's `finally` releases, then reads owed, then fires `unawaited(syncNutritionData())`, in one synchronous run (test pins the order).
- **Owed is set only for "stopped on budget with progress"** (the pass confirmed at least one RPC and stopped at 50 slots / 15 s) or "found the section busy". A pass that only failed sets nothing: failures wait for the existing retry sweep and the next launch/resume (no hot loop offline; test: 20 failing passes → one body run each, no re-trigger). Permanent failures (`nslot_slot_too_large`, validation) never set owed.
- The pull: 25 s per pass, cursor advanced per fully applied keyset page; ends by `unawaited(syncNutritionData())` after release when it wrote anything.
- `weeklyFullSync` (`sync_service.dart:1337`): a busy-return is not a failure; the owed push follows.

### 14.5 Facts and tests (R5 P1-A, P1-B, P2-1, P2-5, P2-6, P3-7..10)
- R5 P1-A / P1-B (fingerprints erased / failed pushes forget): moot, the skip index is no longer an input; the new-format push uses its OWN `SyncSkipDomain` (`nslot`, its own index key), so the legacy `nlog` index is never written by the new path (test + mutation: the new push writes the legacy key → reddens).
- R5 P2-1: `rebaselined` depends only on §14.2 steps finishing; a too-large slot is a push-time failure that never blocks it.
- R5 P2-5: no converter, no per-slot burst; the only puts after the re-baseline are real local changes and fresh rows.
- R5 P2-6: moot (no fingerprint recomputation).
- R5 P3-7: (b) above states the cross-slot duplicate of a pre-build move.
- R5 P3-8: local-only fresh rows are pushed by the normal push after step 5.
- R5 P3-9: moot (no migrator gate).
- Tests: re-baseline happy path (legacy rows → one synthetic entry each, ids equal on two devices); flush fails → nothing local changed, legacy mode, retried; read fails → nothing changed; user logs a meal mid re-baseline → kept and pushed, no double count; user edits a snapshotted row mid re-baseline → aborted, retried; a tombstoned slot (another device already on the build deleted it) → local rows of that slot gone; fresh device = restore; synthetic supersede (P2-2 scenario); owed rules (busy, budget-with-progress, failure-only); `isBusy` + `reset` on account swap; legacy-mode push identical to today (byte-identical requests, against the stub server). S15 random convergence starts every device from a legacy state, runs the re-baseline at a random point, then random ops.
- Mutations: rebuild without the snapshot-changed check; skip the flush; set `rebaselined` before step 5; owed on a failure-only pass; synthetic supersede off; the new push writes the legacy index key.

### 14.6 Round 5 → resolution (kept; §15 follows and REPLACES §14.2 steps, §14.3 supersede rule and §14.4 re-baseline scheduling)
P1-A, P1-B → §14.1/§14.5 (no fingerprint base; re-baseline). P1-C → §14.4 owed rule. P2-1 → §14.5. P2-2 → §14.3. P2-3, P2-4 → §14.4. P2-5 → §14.5. P2-6 → moot. P3-7 → §14.2 (b). P3-8, P3-9, P3-10 → §14.5.

## 15. Round 6 amendments (v7 — REPLACE §14.2's five steps, §14.3's synthetic-supersede rule and the re-baseline scheduling in §14.4)

**Why.** Round 6's P1s were both in the FLUSH (step 2): it could carry a row written after the snapshot into the cloud (double count), clobber a fuller cloud slot with one device's rows, and a crash between the rebuild writes made the next flush double the cloud. The flush existed only to save unpushed pre-build edits; before this build every meal write pushed at once (`nutrition_write_service.dart:175, 315, 378, 483, 582`), and every account is a testing account (CLAUDE.md §1). **v7 drops the flush.** The re-baseline never writes to the cloud.

### 15.1 Two kinds of local rows
- **Build rows**: carry `entry_id` (written by `logMeal` on this build, §11.1). Never in a legacy cloud row. The re-baseline never reads, deletes or sends them; the new push sends them after it.
- **Legacy rows**: `nlog_` rows with NO `entry_id`. The re-baseline replaces them with the cloud's content. Nothing else creates one after the re-baseline: `restoreLastDeleted` and `restoreFoodLog` refuse a payload with no `entry_id` once `rebaselined` is set (an undo of a pre-build row after the rebuild would re-add a meal the rebuild already restored), and the re-baseline clears the undo stash (R6 P2-5). Any other id-less row found later (a dev seed) is stamped with a fresh UUID by the owner-checked apply step before it is pushed.

### 15.2 Re-baseline (replaces §14.2 steps 1-5; never writes to the cloud)
Runs at the START of the pull body (inside the nutrition section, §14.4) on every pass until `nslot_meta.rebaselined` is true; until then the push body returns at once without sending anything (no legacy push, no new push: build rows wait locally, R6 P1-1), and the pull does nothing else. A restore entry point on a device that is not re-baselined runs the same body (waiting for the section), ignoring any `preFetched` rows (they carry no tombstones or server time, R6 P3-4).
1. `nutrition_server_now()`; then the full cloud history (`*, nutrition_log_items(*)`, keyset-paged on `(updated_at, id)`) and all tombstones. Any failure or owner change → stop; nothing local changed; retried at the next pass (launch, resume, restore).
2. In ONE synchronous run with no `await` from the read of the box to the start of both writes:
   - the legacy rows to remove = every `nlog_` key with no `entry_id` (read now, not earlier);
   - the entries to write = every cloud slot as entries (a new-format row → its entries by `entry_id`; a legacy row → one synthetic entry, deterministic id (§14.2), `logged_at` = the row's `created_at`, `source: 'cloud_restore'`, clamped by `clampRestoredNutritionRow`);
   - placement: an entry whose `entry_id` already exists locally (a re-run after a crash, or a build row the cloud already holds) is written at THAT key; else at `firstFreeLogKey(baseKey)` computed against (current keys − legacy keys being removed + keys placed so far) (R6 P3-2);
   - start `putAll(entries)` and `deleteAll(legacy keys)`, then await both.
3. Ledger := every cloud slot read, plus every tombstone (its `rev`, empty entries) (R6 P3-1); cursors := step 1's server time − 5 min; `rebaselined := true`; undo stash cleared; `NutritionWriteService.invalidateAfterSync()`. Then release, and schedule the push (`unawaited`).
- **Crash safety (R6 P1-2):** every write is idempotent by `entry_id` and the legacy-row set is re-read at each run. A kill after `putAll`: the re-run removes the still-present legacy rows and rewrites the same entries at the same keys. A kill after `deleteAll` and before step 3: the re-run reads, finds no legacy rows, rewrites the same entries in place, then sets the ledger. Nothing is ever sent to the cloud before `rebaselined`, so no partial state can reach another device. Tests: a crash at each boundary (after `putAll`, after `deleteAll`, before the ledger write), each followed by a re-run → the box equals a clean run's box; mutation: place by `firstFreeLogKey` even when the id exists → the crash re-run doubles → reddens.
- **A clamp that changes a value** leaves that entry's local signature different from the cloud's: it is dirty and the first push sends the clamped values (one put, intended) (R6 P3-3).
- **Results, stated** (testing accounts only, CLAUDE.md §1): (a) pre-build history becomes one card per meal slot on every device; (b) a meal deleted or moved before this build whose cloud row OI-281 kept comes back (in its old slot), once; (c) a pre-build change that never reached the cloud (its push failed and was never retried) is lost at the re-baseline. Nothing in the re-baseline mixes two sides or depends on the skip index.

### 15.3 Legacy rows after the re-baseline (replaces §14.3)
Old clients are unsupported after this build (§3.10). A legacy cloud row seen in steady state is one synthetic entry (deterministic id from the row). Base known + local clean → take it; local dirty → local wins the whole slot (one put; the old client's change is lost; LOW `nslot_legacy_overwritten`). The §14.3 "synthetic supersede" rule is REMOVED: every device that re-baselined from the same legacy row holds the same synthetic id, so an edit of it is an ordinary Phase B change of one entry (both sides edited → newer `logged_at` wins); two devices that read different versions of a legacy row converge through the clean/dirty rule above (R6 P2-4). The ledger entry shape is `{entry_id: signature}` with no flag needed.

### 15.4 Scheduling and state (adds to §14.4; R6 P2-3, P3-6)
- The re-baseline is part of the pull body (one body, one ticket); its read is paged like today's restore and runs under the pull's per-pass budget only after `rebaselined` is set (the re-baseline itself reads the whole history in one pass, as `_restoreNutritionLogs` does today under `_safeRestoreOp`; a timeout there = stop, nothing local changed, retried).
- `_nslotPushOwed` is a map keyed by user id; the holder's `finally` fires `syncNutritionData()` only for its own user id and only when that user is still the live owner.

### 15.5 Removed by v7
§14.2's snapshot, flush and abort-on-change rule; P2-1, P2-2 and P2-6 of round 6 are moot (no flush, the skip index is not read, nothing legacy is sent by a re-baselining device).

### 15.6 Round 6 → resolution
P1-1 → §15.1/§15.2 (build rows never touched; no flush). P1-2 → §15.2 crash safety. P2-1, P2-2, P2-6 → moot (§15.5). P2-3 → §15.2 first paragraph + §15.4. P2-4 → §15.3. P2-5 → §15.1. P3-1, P3-2, P3-3, P3-4 → §15.2. P3-5 → noted (new `SyncSkipDomain.nslot`, update the "(now 17)" comment at `simulation_service.dart:183`). P3-6 → §15.4. P3-7 → mutations listed in §15.2 plus §14.5.
