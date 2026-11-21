# Plan — L1a-1 "exercise-log cloud rows: one live summary, deletes that land" (OI-312, OI-307 writer side)

**Version:** v10 (2026-10-06), after plan-review round 9 (R9S, P2 text only, design confirmed sound); v9 was after round 8 (R8S); v8 was after round 7 (R7S, P2 only); v7 was after round 6 (R6S, P2 only); v6 was after round 5 (R5S) and three founder decisions (§11); v5 was after round 4 (R4S; v4 was after round 3, R3SA DB mechanics, R3SB client/process). **Split (§4.12.1):** three rounds in a row surfaced new P1s in v1–v3 of L1a, so it is split. This plan keeps ONLY the server migration whose core mechanics R3SA verified (U1.1–U1.4). The day clamp (old U1.5) and the client units (old U2, U3, U4, U6) move to `docs/plans/coach-history-correctness-client.md` (L1a-2), reviewed and shipped separately after this one. Round-9 dispositions §8f; round-8 §8e; round-7 §8d; round-6 §8c; round-5 §8b; round-4 §8a; round-3 §8; round-2 §9; round-1 §10.
**Umbrella:** `docs/superpowers/specs/2026-10-03-progress-review-design.md` v3.1, landing L1. Siblings: L1a-2 (above), L1b `docs/plans/coach-history-correctness-tools.md`.
**Execution branch / worktree:** `coach-history-correctness-sync`. **Mode (§4.12.7):** inline, one coordinator.
**Blast radius:** `platform` (`supabase/migrations/**`). No `lib/` change. Migration name and comments avoid the definer-rights keyword pair that `blast_radius_content_rules_lib.dart:37-38` escalates; every trigger function is SECURITY INVOKER.
**Standalone value:** after this lands, deletes reach the cloud and every cloud write leaves one live summary row per `(user, workout_log_id, exercise_id)` — for installed APKs too. Restore needs no client change for that: with one live row per key, today's put-if-absent restore has nothing to choose between.
**Status:** v10 — converged pending the record (§8f). No code. Nothing committed.

---

## 0. Live verification (coordinator, 2026-10-06; read-only unless marked)

| # | Check | Result |
|---|---|---|
| V1 | live summary groups `(user, workout_log_id, exercise_id)` with > 1 row | 44 groups / 99 rows / 1 account (`d7a67a37…`; not the project-owner email, but labelled "upendra" in `test/sql/rls_initplan_ab_verify.sql:20` — the founder's own main account (confirmed by the founder 2026-10-07; the earlier "not the founder's" was wrong)); rows differ by `set_number`; latest 2026-09-29 |
| V1b | groups whose rows share `completed_at` | 44 of 44 |
| V1c | groups with a PR row | 24 |
| V1d | case/whitespace name variants per day | 0 |
| V4 | tombstoned summary rows | 0 |
| V10 | **rolled-back live probe**: live row at set 4 + drain-shaped upsert (`… deleted_at … ON CONFLICT (…, set_number) DO UPDATE`) | live=1, tombstones=1, total=2 (OI-312) |
| V11 | per duplicate group: sibling `xmin` distinct; frozen; which row has the youngest `xmin` | 44 of 44 distinct, 0 frozen; the youngest-`xmin` row is the highest-`set_number` row in 44 of 44 (greatest `created_at` agrees in only 5). **Meaning (corrected, R3SA-6):** migration 149's no-op suppression was applied 2026-09-28 14:00 IST (`backups/applied_migrations.json:1128`) but the duplicates date from 2026-05-02, so before 149 an identical re-push also bumped `xmin`. Youngest `xmin` = **last push**, not "last real write". That is still the founder's rule ("last sync or write wins", §4). |
| V12 | per-set rows above the count of the youngest-`xmin` row | **0 today** — so today the cleanup deletes no per-set row; any created before the go-#2 re-select are snapshotted (§7 step 3); a lowering push landing in the seconds between that re-select and the body's `LOCK TABLE` is not (same effect as U1.4 at runtime) |
| V13 | `workout_log_sets.workout_log_id` type | `uuid` (`019_workout_log_sets.sql:18`); `workout_log_exercises.workout_log_id` is `text` |
| V14 | `workout_log_sets` rows whose IST(`completed_at`) day ≠ their `workout_log_id` day; orphan per-set rows (no summary row at all for their key) | 45 of 559, and they are exactly the 45 orphans: 3 groups, 1 user, `created_at` 2026-05-07..09, no summary row under any state, no `workout_logs` row. The only reader of `workout_log_sets` is restore (`restore-user-snapshot/index.ts:200-202` ⇒ `_restoreExerciseLogs`, which joins through a summary row), so they are unreachable. Ledger `verified_clean` (no reader; not deleted — deleting user rows needs a reason). Cause not established (pre-150 era). |
| V15 | rows in the shared missing-date bucket `v5('workout_')` | 0 in both tables |
| V16 | live count-0 summaries; per-set rows under them | 0; 0 |

## 1. Bug history (§4.1.5)

| Defect | Prior | Class |
|---|---|---|
| D0 deletes never reach the cloud (OI-312) | e1c8b4 (OI-246, migrations 150/151) | Recurrence of e1c8b4's own fix (its live-verify never upserts onto an existing live row). FULL template, `related_bugs: [e1c8b4]`. |
| D1 superseded summary rows (OI-307) | 3f8a91 (`cloud_upsert_natural_key_contract`), the 2026-06-02 `user_id` key fix, a3e8f1, e6a2d4 | Same concept as 3f8a91; extends debugging class 2.4. FULL, `related_bugs: [3f8a91, e1c8b4]`. |

## 2. Writer / reader map

**D0.** Writer: `_drainPendingExlogDeletes` (`sync_workout.dart:216-247`) upserts a tombstone keyed with `set_number`, `deleted_at` = drain time (`:228`); the queue is written by `deleteLog` (`workout_write_service.dart:1241-1246`) with **the local count at delete time** (`resolveSummarySetCount(m)`, `:1245` — corrected, R3SA-3; it is not the last pushed count). Trigger `workout_log_exercises_delete_final_rename` (151) suffixes on INSERT before the arbiter (V10). Readers: every server reader (L1b) and `_restoreExerciseLogs` (`:910` skips tombstones only).

**D1.** Writer: `_syncExerciseLogs` summary `set_number = resolvedSets.length` (`:289-293,379`) upserted on a key that includes it (`:481-484`); per-set rows `:494-496`. Readers: `_restoreExerciseLogs` (`:866-869` ascending `completed_at`; `:1024` put-if-absent ⇒ the OLDEST row wins locally; `:875-887,975-1000` joins every per-set row); server readers: L1b. (The restore-side defects — selector, per-set join, echo push, queued deletes — are L1a-2 U2.)

## 3. Unit U1 · one migration `NNN_wle_single_live_summary.sql`

`sh scripts/mint_migration.sh <slug>` — WITHOUT `--stub`, which would write `NNN_<slug>.sql` into `supabase/migrations/` (`mint_migration.sh:54,280-287,414`) and turn Gate 14 red; without it the number is reserved and the header template goes to stderr (R5S-3). The body lives in the session scratchpad until step 5 of §7 (R4S-2); header `Destructive?: yes` (tombstones the superseded rows; its trigger tombstones/deletes at runtime). **The body is ONE statement — a single `DO $mig$ … $mig$` block that `EXECUTE`s each step with nested dollar-quote tags (R4S-4)**, whose first statements are `perform set_config('lock_timeout','5s',true)` and `LOCK TABLE public.workout_log_exercises, public.workout_log_sets IN ACCESS EXCLUSIVE MODE` (R7S-1: no push or drain can commit between the repair/cleanup and the new triggers through the old trigger set; taking the strongest lock first avoids a later upgrade; bounded by the 5 s `lock_timeout`, after which the apply fails cleanly and is retried): atomic whether or not `apply_migration` wraps the file in a transaction (the oi-182 plan, step 5, calls that unverified), and the same text the dry-run executes. In this order:

1. **Preconditions — first statement, abort atomically (R3SA-8):** one `DO $$ … IF … THEN RAISE EXCEPTION '…'; END IF; … $$`. A raise aborts the whole migration: nothing is written, no `supabase_migrations` row exists, and the coordinator commits neither the ledger entry nor the snapshot. Checks: (a) every tombstoned summary row is 151-suffixed (its `exercise_id` matches the strip pattern below) — any other shape aborts (V4 = 0 today; ordinary installed-APK deletes until the apply create exactly the V10 shape, R4S-4, R5S-1); (b) **V11 re-measured (R3SA-6, narrowed by R7S-4):** in every duplicate group sibling `xmin`s are distinct (`age(xmin)` — `xid` has no ordering operator and a `::bigint` cast breaks across wraparound). "The youngest row is the highest `set_number`" is NOT asserted: a plain edit that lowers the count on an installed APK legitimately leaves {4, 3} with 3 youngest, and the cleanup rule (keep the youngest, §4) is right for it. (c) dropped (R7S-4): per-set rows above the kept row's count are now handled by the cleanup (step 2). **(b) is evaluated AFTER step 2a**, still inside the same `DO` block (R5S-1). The number of duplicate groups is **not** asserted (it may grow before the apply); the cleanup is generic over whatever groups exist.
2a. **OI-312 repair (R4S-4, widened by R5S-1):** strip = `regexp_replace(exercise_id, ' ' || chr(8249) || 'del:[0-9a-f]{8}' || chr(8250) || '$', '')` (151's suffix is `' ‹del:' || left(id::text,8) || '›'`, `151_…sql:75`; the angle quotes are built with `chr()`, never typed, per the §4.9 invisible-character row). For each suffixed tombstone T, tombstone EVERY live row L at the same `(user_id, workout_log_id, strip(T.exercise_id))` — any `set_number` — with `age(L.xmin) > age(T.xmin)` (written before the delete reached the server); live rows written after T (a re-log) stay. This covers a delete inside a duplicate group, where the drain's count matches only the newest sibling. Snapshot every affected row first.
2. **Cleanup (before any new trigger exists):** per duplicate group keep the youngest-`xmin` row (last push, §4), `UPDATE … SET deleted_at = now()` on the others (151's BEFORE UPDATE renames them; no new trigger is installed yet, so nothing sweeps the kept row). Then delete the `workout_log_sets` rows above the kept row's `set_number` for that key (unless it is 0) — exactly what U1.4 does at runtime; V12 = 0 today, so this touches rows only if a count was lowered before the apply (R7S-4); they are in the snapshot. Before the apply, the coordinator snapshots the rows to be tombstoned and the per-set rows to be deleted (all columns + `xmin`) to `backups/wle_single_live_cleanup_snapshot.json`, committed with the migration. Rollback recipe in the header: un-tombstone (disable trigger, strip suffix, null `deleted_at`) and re-insert the deleted `workout_log_sets` rows from the snapshot (R8S-3).
3. **D0 fix — replace `workout_log_exercises_delete_final_rename`:** UPDATE branch unchanged. INSERT branch with `new.deleted_at is not null`: take the per-key lock (step 5); if a live row exists at the same `(user_id, workout_log_id, exercise_id, set_number)`, `UPDATE` it `SET deleted_at = new.deleted_at` (renamed by the UPDATE branch) and `RETURN NULL`; otherwise suffix and insert as 151. Same `set_number` only — an installed APK's late drain then cannot kill a re-log at another count; the cost is residual (R2), §5.
4. **D1 fix — new `BEFORE INSERT` trigger `workout_log_exercises_single_live`** `WHEN (new.deleted_at is null)`: take the per-key lock; tombstone live siblings `(user_id, workout_log_id, exercise_id)` with `set_number <> new.set_number`; unless `new.set_number = 0`, `DELETE FROM workout_log_sets WHERE user_id = new.user_id AND workout_log_id::text = new.workout_log_id AND exercise_id = new.exercise_id AND set_number > new.set_number`. The comparison casts the **uuid column to text**, never the incoming text to uuid, so non-uuid fixture ids (`'sql_verify_wlog_2026_09_28'`, 150/151 verify file `:39`) do not throw (R3SA-4). The summary is upserted before its sets (`:481` then `:494`), so a new-shape push renumbers 1..N and a legacy push re-inserts its own numbers right after. BEFORE INSERT, not AFTER: PostgREST upserts are always `INSERT … ON CONFLICT`, so it fires on every push, including an identical re-push that migration 149's `trg_suppress_redundant_updates` later cancels (round-2 P0).
5. **U1.5 = per-key lock (R3SA-5)** — not the withdrawn L1a-2 day clamp that once shared this number: at the top of both trigger bodies above, `perform pg_advisory_xact_lock(hashtextextended(new.user_id::text || '|' || new.workout_log_id || '|' || new.exercise_id, 0))`. Two concurrent pushes for one key serialise; under READ COMMITTED each later statement in the second transaction takes a fresh snapshot after the wait, so it sees and supersedes the first. A hash collision only serialises two unrelated keys (no correctness effect).
6. Rollback (header): drop the new trigger + function, restore 151's function body verbatim; data effects listed with the un-tombstone recipe.

Trigger order on INSERT is by name (R3SA verified): `…_delete_final_rename` < `…_single_live`. In the drain path U1.3 returns NULL, so `single_live` and the arbiter never run for that row.

**Tests:**
- Extend `test/sql/workout_log_exercises_delete_final_rename_live_verify.sql` with case 5 (live row + drain-shaped upsert at the same count ⇒ 0 live rows, no extra row) and case 6 (live row at count 4 + drain at count 3 ⇒ row 4 stays live — the documented same-count rule, §5 R2).
- New `test/sql/wle_single_live_summary_live_verify.sql`: push 4 → 7 → 4 ⇒ one live row (the last write); identical re-push of the current row with a stale sibling present ⇒ sibling tombstoned; 7 → 4 then sets push ⇒ per-set rows 1..4 only; legacy gapped {1,2,4} at count 3 ⇒ end state after the summary AND the sets push is {1,2,4}; count 0 ⇒ sets untouched; a non-uuid `workout_log_id` fixture runs without error; the advisory lock is held (`pg_locks` inside the transaction shows an `advisory` row).
- **U1.2a and preconditions (R5S-2, R6S-1, R6S-3):** these four cases run only in the "before" phase (before step (ii); after (ii) U1.3 makes the OI-312 shape unbuildable). Each runs in its own rolled-back sub-block: fixtures are written under `authenticated`, each fixture write in its own `BEGIN <write>; EXCEPTION WHEN OTHERS THEN RAISE; END;` block (only a block WITH an exception clause opens a subtransaction, so each write gets its own, increasing xid); the case then asserts `age(L.xmin) > age(T.xmin)` and distinct xmins (order proven, not assumed), `RESET ROLE`, and `EXECUTE`s the migration text as the owner (CREATE TRIGGER and the all-user precondition/cleanup reads need it). Case (4) builds the unsuffixed tombstone by `ALTER TABLE … DISABLE TRIGGER workout_log_exercises_delete_final_rename` as the owner inside its own sub-block (as the existing verify file's negative control does, `:175-182`). The migration text runs again in each rolled-back sub-block (each case's rollback removes its trigger), but it is NOT re-runnable after a committed apply: the kept rows are older than the tombstones the cleanup wrote, so a second run's 2a would tombstone them (B-pass 2026-10-06) — the body refuses with `ALREADY_APPLIED` when the `single_live` trigger exists (harness case R8). Mutations: the migration text without step 2a ⇒ cases (1), (3) red and case (2) green (the cleanup alone keeps L2, the youngest, and tombstones L — R9S-2); 2a without its `age(L.xmin) > age(T.xmin)` guard ⇒ case (2) red (L2 tombstoned) (R8S-2; the earlier "(b) before 2a" mutation cannot redden now that (b) only checks distinct `xmin`s). Cases: (1) live L at 4, then tombstone T at 4 ⇒ L tombstoned; (2) live L at 4, then T at 4, then a re-log L2 at 3 (three subtransactions) ⇒ L tombstoned, L2 stays live, precondition (b) does not abort; (3) duplicate group {3, 4} then T at 4 ⇒ 0 live rows; (4) an unsuffixed tombstone ⇒ the precondition message.
- Every case runs under `set local role authenticated` with `request.jwt.claims` for a fixture user (RLS: `wle_update_own`, `workout_log_sets_delete_own`, `100_…sql:173-180`).
- Fixture user: both files keep `select id from auth.users limit 1` and RAISE a distinct `'NO_FIXTURE_USER'` when it is empty, so "must fail before the migration" can only pass for the stated reason (R3SA-1).
- **Order of proof — prod rolled-back `DO` block, not a Supabase branch (R3SA-1; deviation for founder sign-off).** `docs/plans/oi-182-202-subscription-state.md:92` records that this repo's migrations do not replay from scratch (125/139 applied raw), so a branch cannot be built faithfully, and a branch holds no production rows (the preconditions and the cleanup would run against nothing). Following that plan's step 3: ONE `DO $$ … $$` block on prod, no explicit `BEGIN…ROLLBACK`, `SET LOCAL lock_timeout='5s'`, `SET LOCAL statement_timeout='30s'`. **Harness (R4S-1):** (0) as the owner role: look up the fixture user, `set_config('request.jwt.claims', …, true)`, and capture a prod-only baseline (duplicate groups, tombstones, OI-312 pairs, V12); (i) each "before" case runs in its own sub-block `BEGIN <SET LOCAL ROLE authenticated; case; RESET ROLE>; RAISE EXCEPTION 'CASE_PASSED'; EXCEPTION WHEN OTHERS THEN v_log := v_log || <case> || SQLERRM; END;` — so every case's writes roll back whether it passed or failed, and its outcome and reason are logged (a `NO_FIXTURE_USER` or 42501 reason fails the dry-run); (ii) `RESET ROLE`; assert the baseline is unchanged; `EXECUTE` the migration text, whose `sha256` must equal the scratch file's hash (so what was dry-run is byte-identical to what is applied); assert the counts the cleanup touched equal the baseline; (iii) every case again, each in the same rolled-back sub-block form, all must pass, plus 150/151 cases 1–4 and case 6; the lock assertion is `locktype='advisory' AND pid=pg_backend_pid()`; (iv) `RAISE EXCEPTION 'DRYRUN_OK …'` with the log and counts, so the transaction always rolls back. **Expected outcome per phase (R7S-3):** (i) the new file's cases and case 5 must FAIL for their stated reason; the four 2a/precondition cases must PASS (they execute the migration text inside their own rolled-back sub-block). (iii) the new file's cases, case 5, case 6 and 150/151 cases 1–4 must PASS; the 2a/precondition cases are NOT run (after (ii), U1.3 makes their shape unbuildable). The result is read from the error text and pasted into the diagnose-docs.
- `backups/applied_migrations.json` + hash (Gate 14 / Gate 39). Ripple: `test/contracts/sync_noop_trigger_tables_test.dart` (trigger inventory), `test/sql/onconflict_live_arbiter.sql` + `scripts/check_onconflict_live_arbiter.dart` (its upserts now fire the new trigger — fixture rows must be distinct keys).

## 4. Founder decision — DECIDED 2026-10-06: last sync/write wins
**"Yes last sync or write wins."** Applied: (a) the cleanup keeps each group's last push (V11, corrected meaning); (b) U1.4 lets the latest push supersede its siblings; (c) two concurrent pushes for one key are serialised by U1.5, so the SUMMARY that commits last wins — for installed APKs and across devices. The per-set push is a separate request outside the lock, so an interleave (A summary 7, B summary 4, A sets) can leave B's count with A's set values and A's extra set rows (R4S-3b) — residual (R5) in §5, accepted by the founder (§11).

## 5. Residuals for installed APKs (no force-update exists, umbrella F27)
R1–R4 are `upstream_blocked` in the closure ledger with blocker "installed APKs run the old delete/push code; no minimum-version gate exists" and `reopen_when`: a minimum-version gate ships. All are tracked under **OI-313**, re-titled to "installed-APK residuals of L1a". For new APKs: L1a-2 U4 removes (R2) and the single-device (R1); L1a-2 U3 removes (R3); the cross-device form of (R1) is the founder rule (L1a-2 §5).
- **(R1) Delete, failed drain, then re-log at the SAME count** before the next successful sync: the late drain tombstones the re-log.
- **(R2) Stale-count delete (R3SA-3):** push at count 4, add a set offline, delete before the next sync ⇒ the queue holds 5, U1.3 finds no live row at 5 and inserts a suffixed tombstone; row 4 stays live. "Tombstone every count" instead would turn (R1) into "a failed drain kills a re-log at ANY count", and the drain's `deleted_at` is drain time (`sync_workout.dart:228`), so no timestamp can arbitrate. The same-count rule is kept; (R2) is its price.
- **(R4) Stale-device resend after a skip-index reset (R4S-3a):** a `sync_epoch` bump (`sync_service.dart:1566-1572`, runbook `docs/operations/SYNC_EPOCH_RESYNC.md`) or the skip-index kill switch (`sync_workout.dart:256`) makes every device resend everything; a second device holding a stale count (restore is put-if-absent) then supersedes the newer row — whichever device resends last wins (the founder rule). **Real cost (R5S-5):** the newer summary survives as a renamed tombstone, but U1.4 hard-deletes the per-set rows above the stale count (per-set rows have no tombstone), and the newer device's skip index then suppresses its own re-push — so the cloud copy of those sets is lost until that device edits the exercise again; a new-device restore shows the stale count. Only an operator `sync_epoch` bump reaches this (the kill switch is per-device Hive config, `sync_service.dart:384-390`), hence the runbook caveat. Mitigation in this landing: the runbook gains "do not bump `sync_epoch` for a user signed in on more than one device" (unconditional — corrected during implementation 2026-10-06: the earlier "until L1a-2 U2 ships" contradicted the next sentence, since restore stays put-if-absent on every APK). Installed APKs: `upstream_blocked` as above; new APKs: the same — restore stays put-if-absent (local wins), so the runbook caveat is the mitigation for every APK (R9P-2: the earlier "U2 + U6" mitigation no longer exists).
- **(R5) Cross-device per-set interleave (R4S-3b):** not installed-APK-only. The summary is serialised (U1.5), the per-set push is not; an interleave leaves the latest summary with the other device's set values. Requires two devices pushing the same exercise on the same day within the same second. Ledger `verified_clean`, evidence "founder decision 2026-10-06: accepted under 'last sync or write wins' (§11)"; per-set rows are not deleted here (A's sets re-insert above B's count; restore's rank join shows B's count).
- **(R3) A per-set push that always fails (R3SA-7)** — duplicate explicit `set_number`s in a legacy `sets_detail` (21000) — leaves the summary pushed and the sets not; on each pass the trigger deletes per-set cloud rows above the count, which the failing sets push cannot re-insert. Effect: the cloud copy of those above-count sets is lost; Hive keeps them and keeps retrying.

## 6. §4.6 decision
No flag — a switch cannot restore tombstoned rows. Protection = preconditions, snapshot, prod `DO`-block dry-run, order of proof, founder sign-off, rollback recipe.

## 7. Process — sequence (R3SB-8)
1. Code + tests + diagnose-docs in the worktree, the migration body in the scratchpad (a file in `supabase/migrations/` without a ledger entry fails Gate 14, `check_migrations_applied.dart:120-145` — R4S-2); full gate loop (§4.12.8) green; B-pass on the scratch body + its `sha256`; plan-review record.
2. **Founder go #1:** the prod `DO`-block dry-run (§3), including sign-off on the branch deviation.
3. Snapshot the rows to be tombstoned AND the `workout_log_sets` rows above each kept row's count (read-only `SELECT`), write the JSON; under go #2, re-run the same `SELECT` immediately before `apply_migration` and append any new rows (R8S-3).
4. **Founder go #2:** check the live migration list as the oi-182 precedent does (step 5): `select version, name from supabase_migrations.schema_migrations order by version desc limit 5` — `version` is a 14-digit timestamp, not the NNN number (`supabase/migrations/CLAUDE.md:174`) — assert no `name ~ '^NNN_'` exists and the newest NNN-prefixed name is below the reserved number (the mint does not consult live, OI-272, `mint_migration.sh:409-411`); record the real `version` as the ledger's `cloud_version` (R6S-2); `apply_migration` with `name: NNN_<slug>`; the body's first statement inside `DO $mig$` is `perform set_config('lock_timeout','5s',true)` so the trigger DDL (ACCESS EXCLUSIVE on `workout_log_exercises`) cannot queue behind pushes unbounded (R5S-4); then the rolled-back post-apply verify under the same go, which asserts the END STATE — live duplicate groups = 0, and every OI-312 pair's L — identified by `id` in the step-3 snapshot plus its go-#2 re-select, the only place the pre-apply pairs survive after a single-`DO` apply (R9S-1) — now has `deleted_at is not null`; inside the body the same check runs atomically: the pairs are captured before 2a and the body `RAISE`s if any is still live after step 2 (R7S-1 as corrected by R8S-1: a generic "no suffixed tombstone with an older live row" check would match every tombstone the cleanup itself creates, and every later R2 drain; the same two assertions run in dry-run step (ii)) — and also selects every row whose `deleted_at` equals the apply's `now()` (2a and step 2 share it inside one `DO`) and appends any row missing from the step-3 snapshot (rows created between snapshot and apply).
5. **Then** move the body (same `sha256`) into `supabase/migrations/`, re-run the full gate loop on that tree, and make the migration commit (it also carries the `docs/operations/SYNC_EPOCH_RESYNC.md` caveat for R4, R5S-5): migration file + `backups/applied_migrations.json` entry with the hash of the file **as applied** (`check_migration_ledger_paired.dart` needs them staged together, `supabase/migrations/CLAUDE.md:70`) + snapshot + SQL tests + diagnose-docs, trailers `closes-diagnose:` for D0 and D1. Then the board + closure ledger commit.
6. Push, PR, CI, merge.
- **Closure ledger** `docs/audit/coach-history-correctness-sync.closure.yaml`: D0, D1 `closed_in_commit` (after the apply); V1d, V14 `verified_clean`; R1–R4 `upstream_blocked`, R5 `verified_clean` (founder decision, §5). `closed_count` recomputed from entries.
- **Board:** OI-312 flips here. OI-313 is re-titled (§5) and stays open. **OI-307 flips only when L1a-1's apply row AND every L1b deploy row are closed** (writer half here, reader half in L1b; whichever closes last flips it — stated in both plans and in OI-307).
- **SoT registry:** new concept `wle_single_live_summary` (writers = the trigger + `_syncExerciseLogs`; readers = restore + L1b) with `behavioral_test_path` = the extended 150/151 file and `behavioral_test_path_live` = the new SQL file (`check_sot_behavioral_test_paths.dart:44,192`).
- Debugging skill, same commit: extend class 2.4; red flags "a BEFORE INSERT trigger that rewrites the conflict key defeats ON CONFLICT" and "an AFTER trigger never fires on an update a BEFORE trigger suppressed".

## 8f. Round-9 dispositions
| Finding | Disposition |
|---|---|
| R9S-1 (post-apply check cites an unstored baseline) | L ids from the snapshot + re-select; atomic in-body check. |
| R9S-2 (no-2a mutation prediction) | Corrected: (1), (3) red, (2) green; the age-guard mutation reddens (2). |
| R9S notes (V12 window; U1.5 naming) | V12 states the seconds-wide window; U1.5 labelled as the per-key lock. |

Round 9 found no P0/P1 and confirmed the design; its two P2s are text corrections applied above. Rounds 6–9 found only P2s plus P1s in text this plan's coordinator had added (R7S-1 → R8S-1 → R9S-1, each a verification-step wording). **Verdict: converged** (`mechanical_only` for round 9).

## 8e. Round-8 dispositions
| Finding | Disposition |
|---|---|
| R8S-1 (end-state check matches the cleanup's own tombstones) | Assertion restated over the baseline OI-312 pairs only. |
| R8S-2 (unreddenable mutation) | Replaced by "2a without its age guard ⇒ case (2) red". |
| R8S-3 (per-set delete not snapshotted / restorable) | Snapshot + re-select before apply + rollback re-insert; V12 wording. |

## 8d. Round-7 dispositions
| Finding | Disposition |
|---|---|
| R7S-1 (writes between cleanup and new triggers; no end-state check) | `LOCK TABLE … ACCESS EXCLUSIVE` first, under the 5 s `lock_timeout`; end-state assertions in dry-run (ii) and the post-apply verify. |
| R7S-2 (case 2 ambiguous; mutation prediction) | Case 2 fixed to L@4, T@4, L2@3; no-2a ⇒ (1)(2)(3) red; (b)-before-2a mutation. |
| R7S-3 (phase (iii) contradicts before-only) | Per-phase expected-outcome table. |
| R7S-4 ((b)/(c) abort on a legitimate count reduction) | (b) narrowed to distinct `xmin`s; (c) dropped; cleanup deletes per-set rows above the kept count (snapshot). |

## 8c. Round-6 dispositions
| Finding | Disposition |
|---|---|
| R6S-1 (plain sub-blocks share one xid) | Each fixture write in an exception-clause block; xmin order asserted before the migration runs. |
| R6S-2 (`max(version)` is a timestamp) | oi-182 step-5 name-based check; real `cloud_version`. |
| R6S-3 (where/how the 2a cases run) | Before-phase only; fixtures as `authenticated`, migration as owner; case 4 disables 151's trigger; re-executable text; no-2a mutation. |
| R6S note (`statement_timeout` inside the `DO`) | Accepted: only `lock_timeout` is relied on. |

## 8b. Round-5 dispositions
| Finding | Disposition |
|---|---|
| R5S-1 (pair repair misses duplicate-group siblings; (b) aborts on a lower re-log; (a) ambiguous; strip unspecified) | 2a across every `set_number` by `age()`; (b)/(c) after 2a; (a) reworded; strip expression with `chr()`. |
| R5S-2 (no test for 2a / preconditions) | Four harness cases with deterministic subxact order. |
| R5S-3 (`--stub` writes into migrations/) | Mint without `--stub`. |
| R5S-4 (apply protections) | Live top-number check, `name:`, in-body `lock_timeout`. |
| R5S-5 (R4 cost misstated; runbook commit) | R4 restated with the per-set loss; runbook edit in the step-5 commit. |
| R5S minor (snapshot gap) | Post-apply diff by `deleted_at = now()` of the apply. |

## 8a. Round-4 dispositions
| Finding | Disposition |
|---|---|
| R4S-1 (dry-run harness unworkable) | §3 harness: rolled-back sub-blocks per case, owner-first lookup, baseline, pid-scoped lock check, `sha256` match. |
| R4S-2 (Gate 14 red at step 1) | Body in scratch until step 5; loop re-run on the step-5 tree; B-pass on the hashed body. |
| R4S-3 (epoch resend; per-set interleave) | R4, R5 in §5; runbook caveat; §4(c) narrowed to the summary. |
| R4S-4 (precondition abort; atomicity) | U1.2a pair repair; the body is one `DO` statement. |
| (coordinator, live) 45 day-mismatched `workout_log_sets` rows | V14: they are unreachable orphans; `verified_clean`. |

## 8. Round-3 dispositions
| Finding | Disposition |
|---|---|
| R3SA-1 (branch dry-run unbuildable, empty fixture) | Prod `DO`-block dry-run per the oi-182 precedent; `NO_FIXTURE_USER` guard; founder sign-off (§3, §7). |
| R3SA-2, R3SB-6 (clamp searches backwards only) | Clamp moved to L1a-2 and redesigned there (both directions). |
| R3SA-3 (queue holds the local count) | §2 corrected; residual (R2) in §5 with its reasoning. |
| R3SA-4 (uuid vs text; `WHEN` on `workout_log_sets`) | U1.4 casts the uuid column to text; the `workout_log_sets` clamp moved to L1a-2. |
| R3SA-5 (concurrent pushes) | U1.5 advisory lock + test. |
| R3SA-6 (`xid` ordering; "last real write") | `age(xmin)`; V11 meaning corrected; precondition (b). |
| R3SA-7 (always-failing sets push) | Residual (R3) in §5; removed for new APKs by L1a-2 U3. |
| R3SA-8 (precondition form) | `DO … RAISE` first statement; no group-count assertion. |
| R3SB-1..4, R3SB-6 (move), R3SB-7 | L1a-2 (client units). |
| R3SB-5 (board vs plan) | §7 board line; OI-313 re-titled; "one-time re-push" removed from OI-307. |
| R3SB-8 (commit/apply order) | §7 sequence. |

## 9. Round-2 dispositions (still valid)
R2SA-1/R2SB-1 → U1.4 BEFORE INSERT + identical re-push case; R2SA-2 → trim `set_number > count`; R2SA-4 → V11 + cleanup in U1.2; R2SB-3 → §4(c) + §5; R2SB-8 → role `authenticated`; R2SB-9/10 → §7, header; R2TB-12 → precondition (a). R2SA-3/5/6, R2SB-2/4/5/6/7 → L1a-2.

## 10. Round-1 dispositions (still valid)
L1A-1/L1B-1/L1D-1 → U1.2 before any new trigger; L1B-2 → OI-312, U1.3; L1A-2 → same-count rule; L1A-4/L1B-4 → V11; L1A-6 → `verified_clean`; L1A-8 → §1; L1B-3 → trim rule; L1B-8/L1D-2 → `Destructive?: yes`, snapshot, recipe; L1D-3 → §6; L1D-5 → §4; L1D-8 → order of proof; L1D-9 → split; L1D-10 → §7; L1D-12 → ledger. Client-side round-1 items → L1a-2.

## 11. Founder decisions — DECIDED 2026-10-06
1. **Prod `DO`-block dry-run in place of a Supabase branch (§3): yes.** Each live step (dry-run, apply) still needs its own go.
2. **R5 (same-second cross-device upload): accepted** under "last sync or write wins"; no per-set lock.
3. (L1a-2 §10, corrected 2026-10-06) **The newest action wins:** a late-arriving delete removes only versions written before it; another device's later re-log survives.
