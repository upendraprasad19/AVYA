# Plan — L1a-2 "exercise-log day, restore and delete correctness" (OI-313 day drift, OI-218, OI-307 restore side)

**Version:** v9 (2026-10-06), after plan-review round 11 (R11C: `max` confirmed sound; one P2 notification edge → founder decision, one P3 text fix, §18); v8 was after round 10 (R10C: one P1, the pushed `completed_at` is now the latest local write, §17); v7 was after round 9 (R9C; dispositions §16) and the founder's CORRECTED decision §10 ("newest action wins"); v6 was after round 8 (R8C, R8T; dispositions §15) — **U1.5 (server day clamp + backfill) WITHDRAWN**: `completed_at` keeps its meaning (the write time) and every reader takes the day from `workout_log_id` (L1b B3, U2(c)); rewriting `completed_at` to the workout day's midnight created future-dated rows for forward moves, which rounds 6–8 kept chasing through the recency readers. v5 was after round 7 (R7C; dispositions §14) — **U6 and U2(e) moved to L1a-3** (`docs/plans/coach-history-correctness-sync-passes.md`, §4.12.1: they produced new P1s in rounds 5–7 and are not needed for correctness once L1a-1 is applied); v4 was after round 6 (R6C; dispositions §13); v3 was after round 5 (R5CA, R5CB; dispositions §11) and the founder decision in §10; v2 was after round 4 (R4CA mechanics, R4CB truth/process; dispositions §9). v1 was split out of L1a v3 (§4.12.1, after round 3) — it carries old U1.5 (redesigned) and old U2, U3, U4, U6 with every round-3 finding applied (§8). The units keep their old numbers so earlier review findings still resolve. Earlier-round dispositions that concern these units are in `docs/plans/coach-history-correctness-sync.md` §9–§10.
**Umbrella:** `docs/superpowers/specs/2026-10-03-progress-review-design.md` v3.1, landing L1. **Depends on L1a-1** (`docs/plans/coach-history-correctness-sync.md`) being applied: U2's selector and U4's all-count drain assume one live summary row per key and the fixed delete path.
**Execution branch / worktree:** `coach-history-correctness-client`. **Mode (§4.12.7):** inline, one coordinator.
**Blast radius:** `platform` (`lib/core/services/sync/**`; `workout_write_service.dart` is `account`, `blast_radius.yaml:308`). No migration since v6 (a one-statement data migration only if the founder marks rows under D4's pre-landing check, §7).
**Status:** v9 — CONVERGED (round 11; notification edge accepted by the founder 2026-10-06). No code.

---

## 0. Live verification (cited from L1a-1 §0 unless new)
V3: true day from `workout_log_id` (UUID v5, namespace `6ba7b810-9dad-11d1-80b4-00c04fd430c8`, name `workout_<istDate>`) vs IST(`completed_at`): 226 of 226 match today. V13: `workout_log_sets.workout_log_id` is `uuid` and the table has `completed_at` but no `deleted_at` (`019_workout_log_sets.sql:14-31`). V2: when the OLDEST-by-`completed_at` summary is taken as current, 92 per-set rows in 39 groups sit above its count. V14 (L1a-1 §0): the only 45 `workout_log_sets` rows whose day mismatches their `workout_log_id` are unreachable orphans (left untouched). V15: 0 rows in the missing-date bucket. V16: 0 live count-0 summaries, 0 per-set rows under them.

## 1. Bug history (§4.1.5)
| Defect | Prior | Class |
|---|---|---|
| D2 restore picks the oldest summary, joins over-count and removed sets, echoes back | e6a2d4, oi83 (`docs/plan-reviews/oi83-restore-monotonic.md`) | Restore completeness/monotonic class. FULL, `related_bugs: [e6a2d4]`. |
| D3 exlog `completed_at` = last write, not the workout day (OI-313) | APK Test #12.7 | Partial recurrence. FULL. |
| D4 a moved-out day's cloud row stays live (OI-218, exlog half) | OI-246 / e1c8b4; e8f4a3 (accepted this residual) | Same class as OI-246 (local delete never reaches the cloud). FULL, `related_bugs: [e1c8b4, e8f4a3]`. |
| D5 cross-account drain (the overlapping-passes half moved to L1a-3) | debugging class 2.44 | Recurrence of 2.44 (in-flight op + account swap). FULL. |

## 2. Writer / reader map
**D2.** Reader `_restoreExerciseLogs` (`sync_workout.dart:861-1030`): rows sorted ascending `completed_at` (`:866-869`), put-if-absent at `:1024-1025` (the oldest row wins); per-set join `:875-887,975-1000` takes every per-set row; it never reads `PendingExlogDeletes` (only a comment at `:908`). Writers of the skip index `sync_exercise_log_payload_hash_index`: `_syncExerciseLogs` only (`docs/sot_registry.yaml:2334-2343`; `lib/core/services/CLAUDE.md:50` says "sole writer AND reader"). `SyncSkipIndex.recordConfirmed` (`sync_skip_index.dart:306-311`) has one caller (`sync_workout.dart:1455`, a different domain) and none for exlogs; it reads and rewrites the whole map per call. A push pass snapshots the index at construction (`:130`) and writes it back in `commit` (`:258`).
**D3.** Writers: `logExercise` (`workout_write_service.dart:204-221`), `editLog` (`:1118,1136`), `moveExerciseLogs` (`:960-994`; non-collision branch keeps `updated_at_ms`, collision branch stamps now), `ExlogKeyMigrator` (`exlog_key_migrator.dart:123`); resolver `sync_workout.dart:581-612` turns `updated_at_ms` into `completed_at`; `workoutLogId` from `log['date'] ?? ''` (`:278-279` — a missing date gives one shared `v5('workout_')` bucket). Readers: restore (`:911-929`), server (L1b). `moveExerciseLogs` is called by the coach reschedule (`tool_dispatcher.dart:815`), usually moving FORWARD.
**D4.** Writer `moveExerciseLogs` deletes the source Hive key without queueing a cloud delete; reader: restore and every server reader (OI-218, `open_issues.md:3971`).
**D5.** `_syncExerciseLogs` entry points `sync_service.dart:1348`, `sync_workout.dart:63,2661`; drain `:216-247` has no owner check; `SerialSlot` (`serial_slot.dart:24-43`) queues callers and `reset()` lets already-queued tickets run.

## 3. Units

**U1.5 · withdrawn (v6).** No server clamp, no backfill, no migration in this landing. The day of a summary row is the date whose UUID v5 equals its `workout_log_id` — for every reader (L1b B3) and for restore (U2(c)); `completed_at` is the write time, as installed APKs already push it. OI-313's "day drift" is therefore fixed on the read side for every APK.

**U2 · restore (Dart, `_restoreExerciseLogs`).**
- (a) One live summary per `(workout_log_id, exercise_id)`: the highest `set_number` (after L1a-1 there is one; the selector replaces iteration order; local-wins at `:1024` stays).
- (b) **Per-set join by rank (R3SB-1):** sort the key's per-set rows by `set_number` and take the first `count` (`count ≤ 0` ⇒ take all, mirroring L1a-1 U1.4's exemption; V16 = 0 today — R4CB-4). This keeps gapped legacy {1,2,4} at count 3 (a `set_number ≤ count` filter would drop set 4, and the next push — `summarySetCount = resolvedSets.length` — would then delete it in the cloud) and still trims over-count 1..7 at count 4 to 1..4.
- (c) **One day per row drives everything (R4CA-1, R4CB-5):** the day = the map hit for `workout_log_id` (precomputed `_deterministicId('workout_<d>') → d` from 2020-01-01 to IST today + 400 days, the same horizon as L1b B3, so forward-rescheduled rows resolve — R4CA-2), else IST(`completed_at`). `dateForKey` is set to that day's IST midnight built as `DateTime.utc(y, m, d).subtract(const Duration(hours: 5, minutes: 30))` — never a local `DateTime(y, m, d)`, which maps to the previous IST day on a device east of IST and which a `TZ=Asia/Kolkata` CI cannot catch (R5CA-5); the test builds its instant with `DateTime.utc`, so the Hive key `exlogKey(day, name)` (`:931`), `date`/`dateStr` (`:932`), the `wlogKey` fallback (`:950`), `addToExlogIndex` (`:1027`) all use it.
- (d) **Skip queued deletes (R3SB-2):** a cloud row whose `(workout_log_id, exercise_id)` is in `PendingExlogDeletes` (any count) is not written and gets no fingerprint. Without this, delete → failed drain → restore puts the row back, U4's drain then tombstones it in the cloud, and once L1a-3 M2 records restore fingerprints its re-push would be silenced: deleted in the cloud, present on the device, permanently.
- (e) moved to L1a-3 M2 (restore records its fingerprints through a merging index write). Until then a restored row is pushed back once — harmless after L1a-1 (an identical push is suppressed or leaves one live row).
- Kill-switch `configBox['disable_exlog_restore_dedupe']` covering (a)–(d), adopting the oi83 precedent EXPLICITLY (`docs/plan-reviews/oi83-restore-monotonic.md:115-122`): an on-by-default emergency switch kept permanently, not a ship-dark flag, no scheduled old-path removal and no ledger row for one (R4CB-7).
- **PR list reader (R9C-2):** `WorkoutRepository.loadAllExercisePRs` reads `log['created_at'] ?? log['date']` as the PR date (`lib/features/train/repositories/workout_repository.dart:763-764`) — only restored rows carry `created_at` (the cloud write time, `sync_workout.dart:940`), so a restored edited or moved log shows its PR on the write day. It switches to `WorkoutReadService.istDateForExlogRow` (`workout_read_service.dart:244-253`), which prefers `date`. Restore keeps writing `created_at` unchanged (rewriting it would re-introduce the withdrawn clamp through the push resolver, `sync_workout.dart:587`).
- Tests through the public seam `restoreExerciseLogsForSyncDomain()` (`sync_workout.dart:2664`) with `SyncStubServer.getResponders` (`test/helpers/sync_stub_server.dart:87,182-185`) — `_restoreExerciseLogs`' `preFetched*` parameters are library-private (R4CB-3): duplicates where the newest is not last; over-count sets; gapped {1,2,4}; an edit-day `completed_at` restores onto the workout day **and the Hive key equals `exlogKey(workoutDay, name)` and the day index holds it, and `loadAllExercisePRs` dates its PR to the workout day**; a forward-rescheduled (future-day) row restores onto its day; queued delete ⇒ not written, no fingerprint; Ripple: `restore_local_wins_additive_test.dart`, `exlog_tombstone_delete_writer_to_reader_test.dart`.

**U3 · exlog push dated by the workout day; per-set numbers made unique.** Effective day = `date`, else `_dateFromKey(key)`, else skip the push (logged); the SAME day derives `workoutLogId` (a missing `date` no longer lands in the shared `v5('workout_')` bucket); `completed_at` is the LATEST local write time — readers take the day from `workout_log_id`. **Latest write (R10C-1):** the shared resolver (`sync_workout.dart:581-612`) returns `created_at` before `updated_at_ms`; restore stamps `created_at` = the cloud `completed_at` (`:940`), and `editLog` (`workout_write_service.dart:1118,1136`) and the collision move branch (`:966,984`) keep it, so an edit made after a cross-device delete would push a time from before the delete and U4's `completed_at <= deleted_at` drain would tombstone it. The exlog push bundle (`_syncExerciseLogs` `:301`, and L1a-3's `buildExlogPushBundle`, which is extracted from it) sends `max(resolved, updated_at_ms)` when `updated_at_ms` is present; the shared resolver is NOT changed (it also feeds `workout_logs`, `:152`). The non-collision move branch (`:987-993`) stamps `updated_at_ms` (a move is a write). `ExlogKeyMigrator` stamps `updated_at_ms` = the migration time (`exlog_key_migrator.dart:123`), so a migrated restored row pushes the migration time — consistent with U4 treating the migrator as a re-create (`cancelFor`); reach is devices upgrading from before v8 (`:31`) (R11C-2). The user exlog writers stamp `updated_at_ms` (`workout_write_service.dart:220` logExercise, `:984` collision move, `:1136` editLog, plus the non-collision move added here) and restore stamps `created_at`; the PR rescan (`:1200`) and the repair migrators re-put rows without stamping, so the date-midnight fallback (`:603-611`) stays unreachable for current writers. Effect: an edited restored row re-pushes once (fingerprint changes once); a restored, unedited row keeps its fingerprint. **Per-set numbering (R3SA-7):** if `_resolvePerSetList` returns duplicate explicit `set_number`s, renumber the whole list 1..N in list order before the push (no duplicates ⇒ numbers kept, so gapped legacy sets stay gapped). Fixtures: `logExercise` merge into a restored entry, `editLog` on a past day, `moveExerciseLogs` both branches (forward and backward), `ExlogKeyMigrator`, missing `date`, a `sets_detail` with two `set_number: 2`. Ripple: `test/sync/completed_at_preservation_test.dart`, `test/sync/workout_logs_null_ts_test.dart`. Latest-write tests (R10C-1): a restored row edited after `deleted_at_ms` is pushed with `completed_at` > `deleted_at` and the U4 drain (stub) leaves it untouched; the same for a restored row moved into the deleted day (both move branches); a restored unedited row's payload is byte-identical to today's. Mutation: drop the `max` ⇒ the edit-after-delete test reddens. **Notification edge (R11C-1, founder ACCEPTED 2026-10-06):** pr-detection celebrates by `completed_at` recency, and L1b B3 adds a resolved-day = IST yesterday/today rule; a move or edit of an old PR row INTO today/yesterday now pushes a fresh `completed_at` and can trigger one extra "New PR" push that day (one per user per IST day, `_shared/proactive_dedup.ts`). Collision moves (`:984`) and edits of device-logged rows already do this today; the non-collision move and restored-row edits are new. The cloud cannot tell a moved row from a fresh log, Founder accepted it (2026-10-06; the alternative was a `moved` marker column, a schema change). Ledger row `verified_clean`, evidence "founder decision 2026-10-06"; the L1b plan carries the same row.

**U4 · deletes: cancel on re-create, reach every count, cover moves.**
- `PendingExlogDeletes.cancelFor(workoutLogId: SyncService.workoutLogIdForDate(dateStr), exerciseName)` (the exact queue key, `workout_write_service.dart:1242-1246`) called from `logExercise`, `moveExerciseLogs` (into the target day) and `ExlogKeyMigrator`.
- **Moves queue the source (R3SB-6, closes OI-218):** both branches of `moveExerciseLogs` add a `PendingExlogDeletes` entry for the source day's key (count = the moved row's local count).
- **New drain — the newest action wins (founder, 2026-10-06, §10).** `PendingExlogDeletes.add` records `deleted_at_ms` (the delete time) with each entry. The drain sends one filtered `UPDATE workout_log_exercises SET deleted_at = now() WHERE user_id = … AND workout_log_id = … AND exercise_id = … AND deleted_at IS NULL AND completed_at <= <deleted_at>` with `.select()` — all counts, but only versions written before the delete: `completed_at` is the write time (`_resolveCompletedAtOrNull`, `sync_workout.dart:581-612`; U1.5 withdrawn), so a re-log on another device or on this one after the delete has a later `completed_at` and survives everywhere, while the device's own older rows — including a stale count (L1a-1 §5 R2) — are tombstoned. An entry queued before this landing (no `deleted_at_ms`) uses the drain time, which is the old all-count behaviour. **The old fallback tombstone upsert is removed:** under this rule it would tombstone a newer same-count re-log through L1a-1 U1.3; with 0 rows touched there is nothing older to delete. Residuals: (i) device clocks that disagree by minutes can misjudge a log made within that skew of the delete; (ii) a push already in flight when the delete happened can land after the drain and stay live — the same race exists today. RLS allows the UPDATE (`100_…sql:173-180`). §4.6 flag: `configBox['disable_exlog_allcount_drain']` falls back to the old same-count upsert; dev-panel only, no RemoteConfig (OI-95) (R5CB-2).
- **Re-read the queue at every sink (R8C-1):** passes are not serialised (`weeklyFullSync`, `sync_service.dart:1348`, and `pushExerciseLogsForSyncDomain`, `sync_workout.dart:2658-2661`, can overlap a coalesced per-write pass), and the drain iterates a copy of the queue (`pending_exlog_deletes.dart:30-41`); so immediately before the UPDATE the drain re-reads `PendingExlogDeletes` and skips the entry if `cancelFor` has removed it. Test: an entry cancelled after the drain's `read()` ⇒ no PATCH and no POST. A request already on the wire when the re-log happens is harmless under §10: the re-log's `completed_at` is later than the delete time, so the UPDATE does not touch it (R9C-1).
- **Owner check at every sink (R4CA-4, R5CA-3):** `if (ownerChangedSince(userId)) return;` immediately before the UPDATE and before each local `PendingExlogDeletes.remove` (the queue key is user-independent — `v5('workout_<date>')` + exercise name — so a late remove would delete the next account's identical entry) inside the drain loop (`ownerChangedSince` doc, `sync_service.dart:606-611`: at the write sink, never at function entry).
- Tests: delete → failed drain → re-log ⇒ re-log stays live; move into a day with a queued delete; move A→B queues A, cloud A tombstoned; move A→B→A before sync ⇒ A not tombstoned; drain with an older cloud row at a different count ⇒ tombstoned; a re-log written after the delete (later `completed_at`) ⇒ untouched; an entry without `deleted_at_ms` ⇒ drain-time cutoff; no fallback POST is ever sent — `SyncStubServer` gains a `writeResponders` hook in this batch so a write can return rows, and its DEFAULT reply to a write carrying `Prefer: return=representation` becomes `200 []` for a list-shaped request and `200 {}`/the echoed row for an object-shaped `Accept` (`application/vnd.pgrst.object+json`, used by `.single()` callers at `sync_service.dart:877`, `sync_coach.dart:132`, `sync_profile.dart:303`), as real PostgREST answers (today every write answers 204/201 with no body, `:186-187`, which postgrest-dart turns into a null body — a test would exercise the network-failure catch instead of the 0-rows branch; R5CA-4); a 0-row PATCH answered `[]` removes the entry and sends nothing else; cross-device: a re-log on another device after the delete ⇒ untouched; an older row on another device ⇒ tombstoned; kill-switch ON ⇒ same-count upsert only; an account switch between two queue entries ⇒ the second is not sent; an account switch during the UPDATE ⇒ no local `remove`. Ripple: `test/contracts/reschedule_week_terminal_row_test.dart` (drives `moveExerciseLogs` via ToolDispatcher), the drain source-grep in `exlog_tombstone_delete_writer_to_reader_test.dart:260-273`.

**U6** withdrawn: passes stay unserialised (L1a-3 v2 replaced the slot with a merging skip-index commit). The drain owner checks and queue re-reads stay here (U4).

## 4. Founder decision applied
"Last sync or write wins" (2026-10-06): U2(a) follows it on the device; U3 changes only which `workout_log_id` a write lands on.

## 5. Residuals
- **Cross-device late delete (R4CB-1, R9C-1):** decided by the founder (§10, corrected): the newest action wins; the clock-skew and in-flight-push residuals (U4) are recorded in the D4 diagnose-doc; ledger row `verified_clean`, evidence "founder decision 2026-10-06 (corrected)" for (i), and (ii) `verified_clean` as pre-existing behaviour unchanged by this landing.
- Installed APKs (no force-update, umbrella F27) keep L1a-1 §5 R1–R4 and the exlog half of OI-218 (their moves never queue a source delete). Ledger rows `upstream_blocked`, blocker "installed APKs run the old code; no minimum-version gate", `reopen_when`: a minimum-version gate ships; tracked under OI-313. The day drift itself is fixed for installed APKs on the read side (L1b B3, U2(c)).

## 6. §4.6 decisions
U2: on-by-default permanent kill-switch (oi83, adopted explicitly — no removal row). U4's all-count drain: switch `disable_exlog_allcount_drain` (oi83 precedent; dev-panel only, no RemoteConfig — OI-95). U3, U4's other parts: no flag — the old path is the defect (precedent `docs/plans/auth-recovery-code-length.md:11`).

## 7. Process
- Sequence: code + tests + diagnose-docs → full gate loop → B-pass → plan-review record → U2, U3, U4 one `fix(...)` commit each with `closes-diagnose:` → board + ledger commit → push, PR, CI, merge. The APK carrying U2–U4 is built by the founder after the merge.
- **Closure ledger** `docs/audit/coach-history-correctness-client.closure.yaml`: D2 (restore half a–d), D3 (U3 + read-side day, with L1b B3), D4, D5 (cross-account drain) `closed_in_commit`; the device restore check `blocked_on_user` (reason: founder-initiated APK build + restore on a device);  installed-APK residuals `upstream_blocked` (§5); `closed_count` recomputed.
- **Board (R4CB-2):** OI-218 holds two defects — the exlog source-day delete (fixed here, D4) and restore-recreated terminal schedule rows losing `moved_to`/`moved_via`/`moved_at`/`dropped_*` (the push sends only `status`, `sync_workout.dart:2098`). It does NOT flip: it is re-titled to the schedule-metadata half, which stays open with its own `Blocked on: none`, and gains a line recording that the exlog half closed in this landing. The ledger row for D4 says so, with evidence for the rows moved BEFORE this landing (R5CB-6): a non-collision move pushes the source day's `completed_at` under the target day's `workout_log_id`, so V3 (226 of 226 rows match) shows no such row is live today; the coordinator re-runs V3 read-only before the D4 commit and puts the count in the row. **Collision-branch gap (R6C-4):** a collision move pushes the TARGET row's own timestamp, so V3 cannot see a still-live source row. Direct measurement, read-only, before the D4 commit, from CLOUD STATE (R7C-2 — the coach tool is `rescheduleWeek`, logged only as `queued` with `{daysAvailable, weekStart?}` args, `_shared/tool-loop.ts:588-592`, `tools/workout/rescheduleWeek.ts:6-20`; the moves are computed and executed on the device, `tool_dispatcher.dart:770-818`, so the tool log cannot identify them): every `moveExerciseLogs` execution also writes a terminal source schedule row `status='moved'` (commit 9fec098d), which reaches the cloud through `_syncScheduledWorkouts` (`sync_workout.dart:2098` sends `status`). Count live `workout_log_exercises` rows whose `workout_log_id = v5('workout_' || scheduled_date)` for that user's `scheduled_workouts` rows with `status = 'moved'` — covers both branches. Zero ⇒ D4's pre-landing evidence. Non-zero ⇒ NO automatic tombstoning (R8C-2: the cloud cannot tell a leftover pre-move row from a log made on that day after the move — `scheduled_workouts` has no `moved_at`/`moved_to`, and a moved day can still be logged on): the coordinator snapshots the rows and lists each one (`exercise_id`, `created_at`, whether the same exercise is live on another day that week) for the founder; any row the founder marks is tombstoned by a one-statement migration using the L1a-1 harness, each live step under its own go. Ledger: D4's pre-landing half is `verified_clean` at zero, or `blocked_on_user` (reason: founder reviews the listed rows) when non-zero. OI-313 stays open for the residuals. OI-307's restore side is covered here, but its flip rule is L1a-1 §7's (apply row + L1b deploy rows).
- **SoT (R4CB-6, R5CB-1):** NEW concept `pending_exlog_deletes` (userBox key `pending_exlog_deletes`; no such concept exists today — `sot_registry.yaml:62` is a `deleteLog` note inside `workout_receipt_rendering`): writers `deleteLog`, `moveExerciseLogs` (add), `cancelFor` (from `logExercise`, `moveExerciseLogs`, `ExlogKeyMigrator`); readers `_drainPendingExlogDeletes`, `_restoreExerciseLogs` (U2(d)); `behavioral_test_path` = `test/contracts/exlog_tombstone_delete_writer_to_reader_test.dart`, extended with the U4 cases; the `exercise_logs_read_path` note "LOCAL-ONLY — cloud exercise_logs residual tracked on OI-174" (`sot_registry.yaml` ~:368) and `moveExerciseLogs`' doc comment "LOCAL-ONLY by design" (`workout_write_service.dart:872-877`) are corrected in the same commit.
- **SoT:** `wle_single_live_summary` gains U2 as a reader test; new concept `exlog_workout_day` (writer U3 — the day that derives `workout_log_id`; readers restore U2(c) + L1b B3) with `behavioral_test_path` = the U3 test. (The `sync_exercise_log_payload_hash_index` second-writer row moved to L1a-3 with U2(e), R8C-3.)
- Every new Dart test mutation-proven (rule 21); debugging skill: class 2.44 gains the drain-sink owner-check case.

## 8. Round-3 findings answered here
| Finding | Disposition |
|---|---|
| R3SA-2, R3SB-6 (clamp direction; moved-out day) | U1.5 both directions; U4 queues the source day (OI-218). |
| R3SA-4 (`workout_log_sets` clamp) | Own function, no `WHEN`, uuid comparison. |
| R3SA-7 (duplicate explicit set numbers) | U3 renumbers only when duplicated. |
| R3SB-1 (gapped legacy sets lost) | U2(b) rank-based join. |
| R3SB-2 (restore resurrects queued deletes) | U2(d). |
| R3SB-3 (fingerprint exactness, O(n²), lost update) | U2(e) shared bundle builder, `recordConfirmedAll`, inside the slot. |
| R3SB-4 (queued ticket after account switch) | U6 owner checks. |
| R3SB-7 (SoT second writer; §2 claim) | §7 SoT; §2 corrected (one caller, not for exlogs). |

## 9. Round-4 dispositions
| Finding | Disposition |
|---|---|
| R4CA-1, R4CB-5 (key/index stay on the old day) | U2(c): one day drives key, date, index, wlog fallback, bundle key; test asserts key + index. |
| R4CA-2 (map stops at today) | Map to today + 400; future-day test. |
| R4CA-3 (record under the restore ceiling; no owner check) | Unawaited record task with owner check and value re-check; test. |
| R4CA-4 (drain owner check at entry) | Checks at each write sink; test between two entries. |
| R4CA-5 (149 ordering reason) | Reason corrected; `xmin`-unchanged SQL case. |
| R4CB-1 (all-count drain across devices) | Founder rule, stated + test + permanent switch + ledger row; founder confirmation requested (§10). |
| R4CB-2 (OI-218 has a second half) | OI-218 re-titled to the schedule-metadata half, stays open. |
| R4CB-3 (test seams) | `restoreExerciseLogsForSyncDomain` + `getResponders`; `writeResponders` hook added. |
| R4CB-4 (count ≤ 0) | Take all; V16 = 0. |
| R4CB-6 (SoT, related bugs, ripple) | §7 SoT rows; e8f4a3; ripple tests. |
| R4CB-7 (old-path row) | oi83 adopted explicitly; row removed. |
| R4CB note (`workout_log_sets` backfill) | V14 measured: the 45 mismatches are unreachable orphans. |

## 10. Founder decision — CORRECTED 2026-10-06: the newest action wins
Case: a delete on one device whose upload failed, then a re-log of that exercise for that day on another device (or the web app), then the first device's late upload. **First answer ("delete always wins") was given on a wrong description:** I said the exercise "ends deleted"; in fact the re-logging device keeps showing it (its skip index never re-pushes, restore is local-wins) while the cloud and the coach treat it as deleted — a silent split (R9C-1). **Corrected answer: "Newest action wins"** — the delete removes only versions written before it (U4), so the later re-log survives on every device and in the coach; the stale-count delete is still fixed. Accepted risk: device clocks that disagree by minutes.

## 12. Round-6 change carried from L1b
R6T-1/2/4 (L1b): the 400-day reader widening was removed; U1.5 gained a one-time backfill — SUPERSEDED by v6, which withdrew U1.5 entirely.

## 11. Round-5 dispositions
| Finding | Disposition |
|---|---|
| R5CA-1 (hung pass holds the slot) | Bounded hold, `abandoned` predicate, ceiling clock after `turn`; test. |
| R5CA-2 (record ticket order; release; catch) | Synchronous `enter()`; returns inside `try`; `catch` + telemetry; tests. |
| R5CA-3 (local `remove` sink) | Owner check before each `remove`; test. |
| R5CA-4 (stub default reply) | `200 []` default for representation writes. |
| R5CA-5 (IST midnight on east-of-IST devices) | `DateTime.utc(...) - 5:30`. |
| R5CB-1 (no `pending_exlog_deletes` concept) | New concept with writers, readers, test path. |
| R5CB-2 (decision after merge; switch is debug-only) | Founder decided before coding (§10); OI-95 cited. |
| R5CB-3 (migration handling) | L1a-1 §3/§7 applied to U1.5. |
| R5CB-4 (cases that pass before) | Must-fail vs invariant groups. |
| R5CB-5 (OI-313 overstated) | Board text fixed (R1–R4 mapping). |
| R5CB-6 (pre-landing moved rows) | V3 inference + re-measure in the D4 row. |

## 13. Round-6 dispositions
| Finding | Disposition |
|---|---|
| R6C-1 (whole-pass timeout starves newest rows) | Per-call bound; first timeout ends the pass early but commits; test. |
| R6C-2 (late completion after abandonment) | No abandoned passes any more; the late-landing request is a pre-existing platform limit, `upstream_blocked` with blocker and `reopen_when`; per-set sink check kept. |
| R6C-3 (ceiling clock) | `_runExlogPass` wrapper awaits the turn before the ceiling starts; test. |
| R6C-4 (collision-branch moves invisible to V3) | Direct read-only measurement from `coach_tool_invocations_v`; repair step in U1.5 if non-zero. |
| R6C caveat (`.single()` callers) | Stub default keyed on the `Accept` shape. |

## 14. Round-7 dispositions
| Finding | Disposition |
|---|---|
| R7C-1 (slot released on the ceiling, not the body) | U6 moved to L1a-3; fixed there (release on the body future; `:2661` behaviour change stated). |
| R7C-2 (tool log cannot identify moves) | Measurement from cloud `scheduled_workouts` `status='moved'` rows. |
| R7C-3 (always-timing-out key starves newer keys) | Moved to L1a-3 P3 (skip and continue, stop after 2). |
| R7C-4 (late-landing residual labelled upstream) | Moved to L1a-3 §3 with a founder choice. |

## 15. Round-8 dispositions
| Finding | Disposition |
|---|---|
| R8C-1 (overlapping pass drains a cancelled delete) | Re-read the queue at each sink; test; the on-the-wire window recorded under §10. |
| R8C-2 (moved-row repair could tombstone real logs) | No auto-tombstoning; per-row list for the founder; `blocked_on_user` when non-zero. |
| R8C-3 (leftovers from U2(e)/U6) | SoT second-writer row, 2.44 queued-ticket case and `sync_skip_index` ripple removed (live in L1a-3). |
| R8C-4 (gap between backfill and clamp trigger) | Moot: U1.5 withdrawn. |
| R8C-5 (L1b ledger row closed by U1.5) | Moot: the L1b transitional row is withdrawn with U1.5. |
| R8T-1, R8T-2 (L1b; clamp-created future dates vs recency readers) | Root cause removed: no clamp, so `completed_at` is never future-dated; L1b's recency readers filter on the resolved day instead. |

## 16. Round-9 dispositions
| Finding | Disposition |
|---|---|
| R9C-1 ("late delete wins" end state misdescribed) | Founder re-asked with the true end state; answer "newest action wins"; U4 filters by `completed_at <= delete time`; fallback removed; residuals stated. |
| R9C-2 (PR list dates restored rows by `created_at`) | Reader switched to `istDateForExlogRow`; test assertion. |
| R9C-3 (stale clamp/U6 text) | §12 marked superseded; umbrella row, L1b header and L1a-1 R4 corrected. |
| R9C note (exact-triple `remove` vs re-queue) | Moot: entries now carry `deleted_at_ms`; a re-queued delete is a new entry with a later time. |
| (coordinator, live, read-only) | 0 rows with null/unresolvable `workout_log_id`; 0 `scheduled_workouts` with `status='moved'` ⇒ D4 pre-landing half `verified_clean`. |

## 17. Round-10 dispositions
| Finding | Disposition |
|---|---|
| R10C-1 (an edit or move of a restored row after a cross-device delete pushes the restore-time `created_at`, so the late time-filtered drain tombstones the newer version — the R9C-1 split again) | U3: the exlog push sends `max(resolved, updated_at_ms)`; the non-collision move stamps `updated_at_ms`; the shared resolver is unchanged (it also feeds `workout_logs`); tests + mutation. The midnight-fallback variant is unreachable: every exlog writer stamps `updated_at_ms` or `created_at` (coordinator check of `workout_write_service.dart`). |

Round 10 otherwise verified: legacy queue entries (drain-time cutoff) acceptable as stated; the fallback-upsert removal loses nothing (migration 151 already frees the natural key on INSERT; `completed_at` NOT NULL); the PR-list reader change is display-only.

## 18. Round-11 dispositions
| Finding | Disposition |
|---|---|
| R11C-1 (a move or edit of an old PR row into today/yesterday re-triggers one "New PR" push) | U3 names pr-detection as a reader; the edge is stated with its pre-existing share (collision moves, device-logged edits); founder ACCEPTED (2026-10-06); ledger row `verified_clean`. |
| R11C-2 (migrator "keeps its stamps" false; mixed cites) | Corrected: migrator stamps the migration time (`exlog_key_migrator.dart:123`); cites limited to the exlog writers. |

Round 11 verified: every user exlog write goes through `WorkoutWriteService`; `max` makes every post-delete user write later than the delete (except clock skew, accepted in §10); no future-dating beyond skew; restored unedited rows keep their fingerprint; L1a-3 M2 parity holds; leaving the shared resolver unchanged is correct.
