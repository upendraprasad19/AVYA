# Batch 0b — repair the custom exercises L2 already put into plans (+ repeat-pin strip)

**Date:** 2026-10-21 · **Branch:** `l2-custom-repair` (stacked on Batch 0a's branch `l2-no-custom-autoadd`, PR #138, while that PR awaited the founder's §4.6 waiver answer; merges after it) · **Tier:** L · **Execution mode:** inline.
**Revision:** r5 (final). Split from Batch 0a (`docs/plans/2026-10-21-l2-no-custom-autoadd.md`, diagnose d4b8e1) per §4.12.1.
Review history: r1 (1 P0, 6 P1), r2 (5 P1), r3 (0 P0, 3 P1 + 9 P2), r4 CONVERGED (0 P0, 0 P1, 12 P2) — the r5 section
at the end applies every round-4 P2 and overrides the body where they differ.

## Why it is needed after 0a

0a stops NEW generations from auto-adding customs. It does not touch plans already generated:
- upendraprasad19's Phase 4 (2026-10-12 → 2026-11-08) has 6 customs on every push day, 2 on pull, 1 on legs
  (cloud `user_progress.plan_json.schedules`, queried 2026-10-21; the only user with customs inside a plan).
- **Repeat pins**: `_buildRepeatPins` (`workout_schedule_read_service.dart:741-760`) reads the just-finished phase's
  week-1/2 ROWS (`_namesByDayIndex` :840 → `_exerciseNamesOfRow` :830); `buildPinnedDays.resolve`
  (`exercise_selector.dart:~746-776`) resolves a non-library name via `customs()`. Past Phase-4 rows keep the
  customs ⇒ a REPEAT advance would re-pin them. Every production caller (`:670`, `:780`,
  `pro_phase_advance.dart:858`) funnels through `_buildRepeatPins`.
- The plan blob `workoutBox['current_plan']` also holds them; nothing rebuilds rows from it (readers read
  metadata: `train_provider.dart:865`, `pro_phase_advance.dart:723`, `workout_schedule_read_service.dart:1538-1545`).
  Left untouched (a rewrite needs a direct `workoutBox.put` — Gate 49 — and risks `phase`/`week_character`).

## Changes

### 1. `ExerciseRepository.customNamesLower()` — the ONE new seam site
`Set<String> customNamesLower()` next to `getCustomExercises()` (`exercise_repository.dart:~427`), implemented by
calling `getCustomExercises()` (no `customBox.get(var)` — keeps Gate 16 green): trimmed lower-cased names.
`scripts/exercise_seam_lib.dart:106` (`exercise_repository.dart`) SeamEntry 1 → 2, reason ≥ 30 chars
(`test/scripts/exercise_seam_lib_test.dart:98-104`). No other seam pattern is hit.

### 2. Pure predicate — `lib/core/services/auto_appended_custom.dart`
- `bool isAutoAppendedCustom(Map exercise, {required Set<String> customNamesLower, required bool Function(String) libraryHas})`
  — order: (a) has a `swapped_via` key → false (coach swap, `swap_service.dart:543`, the only exercise-level
  provenance stamp); (b) trimmed lower `exercise_name` ∉ `customNamesLower` → false; (c) `libraryHas(name)` → false
  (library wins a collision; checked against the bundled 292 rows: no collision with the founder's six names);
  else true. `libraryHas` runs only for names already in the custom set.
- `List<Map<String, dynamic>> stripAutoAppendedCustoms(List exercises, {...})` — returns a NEW list, order
  preserved, never mutates its input.
- `Map<String, dynamic> stripRow(Map row, {...})` — returns `{...row, 'exercises': stripAutoAppendedCustoms(...)}`
  (a NEW map; `getWeek` rows are shallow copies whose `exercises` list is Hive's in-memory object, so in-place
  `removeWhere` would corrupt the Hive cache).
- Gate 19: every exercise-level key read (`exercise_name`, `swapped_via`) lives in THIS file, which contains no
  `schedule_` literal outside comments (`check_hive_map_field_drift.dart:96-134` emit set, `:216-220` prefix-reader
  heuristic).

### 3. Read side — repeat pins (`_buildRepeatPins`)
- Before `repeatPinsFrom`, map the `getWeek(1)` / `getWeek(2)` rows through `stripRow`.
- `customNamesLower()` is computed ONCE per call inside try/catch. On ANY throw: fail OPEN (pins built from the
  unstripped rows = today's behaviour) + `ErrorTelemetry.recordNonFatal(e, st, reason: 'repeat_pins_custom_strip')`.
  A strip failure must never abort a phase advance.
- `libraryHas = (n) => ExerciseRepository.instance.getByExactName(n) != null` (import
  `../../shared/repositories/exercise_repository.dart` into `workout_schedule_read_service.dart`).
- `repeatPinsFrom` stays pure and unchanged. `previousPhaseNamesByDay` (avoid-names only) unchanged.
- Tests that reach this path already open `customBox` via `HiveUserSession.openForUser`
  (`pro_phase_advance_behavioral_test.dart:121-122`, `repeat_content_scheduling_test.dart:195`).

### 4. Repair migrator — `lib/core/services/l2_custom_append_repair_migrator.dart`
`L2CustomAppendRepairMigrator.runIfNeeded()`:
1. **Re-entrancy:** static `_running` guard (the CONTINUE escape can attach the heal twice,
   `heal_after_restore.dart:93-101`).
2. **Restore-settled gate:** `SyncService.instance.restoreSettledForCurrentUser` (`sync_service.dart:1886-1890`,
   pure; set only by `_settleRestoreMarker` :1929-1946 after a successful restore for uid == live user == Hive
   owner; cleared by `_onUserChanged`). False → `ErrorTelemetry.logEvent('l2_custom_repair_withheld', message:
   'reason=${SyncService.instance.lastRestoreWithheldReason}')`, return (no scan, no latch, no push). Every cold
   start runs a restore (`splash_screen.dart:312` → `/restoring` → `_kickoffRestore` → `restoreFromCloudForUser`),
   so a withheld run retries next launch.
3. **Latch:** `workoutBox.get(_flagKey) == true` → return. `_flagKey = 'l2_custom_repair_v1_done'` (const; never
   `workoutBox['…']` bracket syntax — Gate 19 candidate; never a `schedule_` prefix, cf.
   `schedule_hybrid_repair_migrator.dart:82-86`). The latch is KEPT (not a latch-free pass) so a future explicit
   "add exercise" feature that persists a custom to a planned row without `swapped_via` can never be stripped by a
   repeated pass.
4. `customs = ExerciseRepository.instance.customNamesLower()`; empty → return WITHOUT latching.
5. **Scan:** `schedule_<date>` keys; take the suffix, require `^\d{4}-\d{2}-\d{2}$`, compare as a STRING with
   `istTodayStr()` (`ist_date.dart:76`) — `suffix >= today`. Row must be `status == 'planned'`, `type == 'workout'`,
   not a template (`type == 'custom_template'` or `template_id != null`, `template_service.dart:147-148`). Hotel
   (`generated_via: ai_coach_hotel`, `hotel_workout_planner.dart:220`) and regenerate (`ai_coach_regenerate`,
   `regenerate_plan_planner.dart:381, 460`) rows are generator output ⇒ in scope. Row keys read: `status`, `type`,
   `template_id`, `exercises` (all in the schedule emit set).
6. **Per row:** `copy = stripRow(row)`. Nothing removed → next. New list EMPTY → skip, count `skipped_empty` (an
   empty list refills from the snapshot, `plan_integrity_reconciler.dart:122-125`).
7. **Write:** `WorkoutWriteService.instance.upsertScheduled(date: DaySwapRules.utcDate(suffix), entry: copy,
   source: WriteSource.planGenerator)` — the date comes from the KEY suffix via `DaySwapRules.utcDate`
   (`day_swap_rules.dart:43-46`), NEVER `DateTime.parse`/`tryParse` of `row['date']` (device-local midnight on an
   east-of-IST device maps to the previous IST day and would overwrite the neighbouring row —
   `tool_dispatcher.dart:1878-1884` documents the trap). `arranged_at_ms` survives via the full copy
   (`workout_write_service.dart:670-675`; `carriesArrangement` :713-723 returns false when the key is present).
   Row-level `source` becomes `plan_generator` — no reader exists.
8. **Results:** `upsertScheduled` never throws (`workout_write_service.dart:~692-700`). `success` → count row +
   exercises. `errorMessage == WorkoutWriteService.completedDayRefusedMessage` → benign skip (a mid-run race; the
   scan already filters `planned`). Any other fail → `hadFailure = true`.
9. **New constant:** `static const String completedDayRefusedMessage = 'refusing to overwrite completed day from
   planGenerator';` beside `daySwapRefusedMessage` (`workout_write_service.dart:728`), used at `:665-666` (grep:
   the literal exists only there). Test mirrors `swap_scheduled_days_test.dart:71`.
10. Re-check `restoreSettledForCurrentUser` before the push and before the latch (account change mid-loop → stop,
    no push, no latch).
11. Rows stripped > 0 → `unawaited(SyncService.instance.pushWorkoutPlanForSyncDomain().catchError((Object e,
    StackTrace st) => ErrorTelemetry.recordNonFatal(e, st, reason: 'l2_custom_repair_push')))`
    (`upsertScheduled` fires only `syncWorkoutData()`/`pushSnapshot()`, `:684-685`, which never reach
    `_syncWorkoutPlan`, `sync_workout.dart:1461`; its fingerprint covers `schedules`, `:1501-1506`). Safe
    post-restore (OI-189, `workout_schedule_read_service.dart:196-208`). Precedent `deload_evaluator.dart:~286`.
12. Telemetry: `logEvent('l2_custom_strip', message: 'rows=$r exercises=$e skipped_empty=$z failed=$f')` — counts
    only, never exercise names (user text).
13. Latch `_flagKey = true` only if `!hadFailure`.

### 5. Wiring
- Helper `_runL2CustomRepair()` in the part file `restoring/heal_after_restore.dart` (try/catch +
  `recordNonFatal(reason: 'bg_heal_l2_custom_repair')`).
- (i) `_healAfterRestoreInBackground`: after the `PlanIntegrityReconciler.reconcile` block (`:42-49`), before
  `refillIfNewWeek` (`:50-54`) — `background_restore_test.dart:185-190` requires refill before reckon.
- (ii) `_ensureOwnershipBeforeHome` (`restoring_screen.dart`): after its `PlanIntegrityReconciler` block
  (`~:492-505`), before `runRolloverNow` (`~:532-540`). The restore-settled gate makes it a no-op after a
  failed/cancelled restore (`:341` ignores the `RestoreResult`).
- `restoring_screen.dart` +1 import (the migrator file; the part file shares the head's imports) +1 call = 798 of 800 (Gate 43,
  `check_god_screen_max_lines.dart:30, 109`); no comment lines in the head.

### 6. Gates / registries / docs (same commit)
- `scripts/check_writeservice_only.dart` `allowedClasses` (`:33-70`) += `L2CustomAppendRepairMigrator` (flag write).
- `scripts/exercise_seam_lib.dart` — `exercise_repository.dart` 1 → 2.
- `dart run scripts/check_hive_map_field_drift.dart` passes with NO baseline change.
- `docs/sot_registry.yaml` — concept `l2_custom_autoappend_repair` with `key_prefix: ""` (Gate 9 then needs no
  `<concept>_writer_to_reader_test`), `behavioral_test_path`, writers/readers with method names (parity gate).
- `lib/core/services/CLAUDE.md` — list the migrator (§5 row).
- `docs/naming_conventions.md` (~:116) — migrator, predicate file, `customNamesLower`, `completedDayRefusedMessage`, flag key.
- Diagnose doc: SIBLING with its own id, `related_bugs: [d4b8e1, e7b2d4]`, FULL template.

### 7. Tests (rule 21 — one mutation per protection, `grep -c` each applied)
Test seams: `SyncService.debugSetRestoreSettledUserIdForTest` (`sync_service.dart:1897`),
`HiveUserSession.debugCurrentUidResolverForTests`, `SyncService.debugPlanPushOverride` (`:1903`).
- `test/contracts/auto_appended_custom_test.dart` — predicate + `stripRow` (custom stripped; library collision kept;
  `swapped_via` kept; case/whitespace; input list and map NOT mutated). **Mutation:** drop the `swapped_via` clause.
- `test/contracts/l2_custom_append_repair_migrator_test.dart` — fixture = founder's live 2026-10-21 row (8 library +
  6 customs, `arranged_at_ms` present): strips the 6 and stores under the SAME key it was scanned from;
  `arranged_at_ms` value unchanged; `swapped_via` custom kept; completed / past / template rows untouched; never
  empties a row; idempotent; push counted once. **Mutations:** (a) remove the restore-settled gate → "withheld: no
  scan/latch/push" RED; (b) force `upsertScheduled` fail → "flag unset" RED; (c) empty customs → "no latch" RED.
  **Presence-only (stated in the diagnose doc):** a comment-stripped source-grep that the migrator contains no
  `DateTime.parse`/`tryParse` — `TZ=Asia/Kolkata` cannot redden the east-of-IST case behaviourally.
- `test/workout_write_service/completed_day_refused_message_test.dart` (or extend `swap_scheduled_days_test.dart`) —
  the refusal returns `errorMessage == completedDayRefusedMessage`.
- `test/contracts/l2_repeat_pins_strip_test.dart` — a repeat advance whose week-1 rows hold an un-swapped custom does
  not pin it; a `swapped_via` custom IS pinned; a throwing custom read fails OPEN (pins still built). **Mutation:**
  remove the §3 map. Also run `pro_phase_advance_behavioral_test.dart`, `repeat_content_scheduling_test.dart`,
  `advance_choice_test.dart`, `background_restore_test.dart`.
- `test/contracts/l2_custom_repair_wired_test.dart` — both call sites + order after `PlanIntegrityReconciler`.

## Known limits (diagnose doc)
- Old-build device re-pushing polluted rows with a NEWER `arranged_at_ms` wins wholesale on a repaired device
  (`plan_integrity_reconciler.dart:186-231, 256-286`); the latched device won't re-run. Fixed by updating that device.
- A custom DELETED after L2 added it is not in `customNamesLower` → stays in the row (optional hardening: also match
  `exercise_id` against custom ids — not taken: restored custom rows carry the id but generated rows store
  `exercise_id: c['id']` only when present).
- `displaced_<date>` backups: verified clean, not written by the migrator (r5 item 12).
- A coach-swapped custom pinned once loses `swapped_via` and is dropped from the SECOND consecutive repeat (r5 item 5).
- `restore_custom_exercises` is not streak-critical (`sync_restore_failure_collector.dart:32-41`): a partially
  restored custom list can latch a partial strip.

## Verification
Full gate loop (§4.12.8) + the tests above; B-pass; after deploy the founder's 2026-10-21+ planned days show only
library exercises and cloud `plan_json.schedules` no longer lists the customs on them.

---
## r5 — round 4 = CONVERGED (0 P0, 0 P1, 12 P2); every P2 applied here (these override r4 where they differ)

1. **Write-time re-read:** snapshot only KEYS; per key re-read `workoutBox.get(key)`, re-check `planned` / `workout` / not
   template, recompute `stripRow`, write immediately. Re-check `restoreSettledForCurrentUser` before EACH write (a mid-loop
   account swap would write A's rows into B's box). Skip TODAY's row while `ActiveWorkoutPersistence.readState() != null`
   (`_persistSupersetGroups` writes by index, train_provider.dart:1950-1966) and do NOT latch when it was skipped.
2. **Registry:** add the migrator to `scheduled_workouts_mutations.reader_allow_files` (sot_registry.yaml ~:634, like
   `schedule_hybrid_repair_migrator.dart`). The new constant in workout_write_service.dart adds ≤ 5 lines above
   `wlogKey` (:1557) / `scheduleKey` (:1586), else re-pin both `ist_sites` cites (sot_registry.yaml :413, :649) in the
   same commit (parity window line-6..+5).
3. **Failure seams:** `@visibleForTesting static Future<WriteResult> Function(...)? debugUpsertOverride` on the
   migrator (null in prod) for mutation (b); `@visibleForTesting` custom-set provider override for the fail-open
   repeat-pin test. `SyncService.pausedForSimulation` must be false in the migrator test (else
   `pushWorkoutPlanForSyncDomain` returns before `debugPlanPushOverride`, sync_workout.dart:2946-2947).
4. **Date helper, behavioural:** `@visibleForTesting static DateTime? writeDateForSuffix(String s)` = shape regex AND
   round-trip `DaySwapRules.format(DaySwapRules.utcDate(s)) == s` (rejects `2026-13-45`), else null → skip. Test:
   `isUtc == true` and `istDateStr(d) == s`. Replaces the presence-only source-grep.
5. **Known limit (documented):** the read-side strip has no latch, so a coach-swapped custom pinned once (rebuilt via
   `_buildCustomExercise`, no `swapped_via`) is dropped from the SECOND consecutive repeat. Rare.
6. **Push safety:** before the push, require that no `planned` workout row dated ≥ today is exercise-less (else
   skip the push + `logEvent('l2_custom_repair_push_skipped')`); the push's real failure surface is
   `_reportSyncFailure('sync_workout_plan')` (sync_workout.dart:1516-1523) — the extra `.catchError` stays as a guard.
7. **Order + noise:** latch check → customs-empty check → settle gate. Log `l2_custom_repair_withheld` only when the
   withheld reason is non-null (precedent day_rollover_service.dart:173-176). `_running` in `try/finally`; a second
   caller awaits the in-flight future.
8. **Strip edge cases:** non-Map list elements kept verbatim; "nothing removed" = equal lengths → no write.
9. **Gate traps:** migrator is a plain `class` (Gate 49 regex `^\s*class\s+`, check_writeservice_only.dart:139); no
   method named `log*`/`upsert*`/`complete*`/`delete*`/`_sync*`/`_restore*` (Gate 7); the migrator file reads only
   emit-set row keys; `exercise_name` only in the predicate file, which has no quoted `'schedule_'`.
10. **Housekeeping:** seam entry is `exercise_seam_lib.dart:108`; re-baseline `lib/core/services/CLAUDE.md` after the
   §5 row (`check_context_artifact_budget.dart --record`); add `docs/plan-reviews/l2-custom-repair.md`; `package:`
   import for exercise_repository (rule 15); `unawaited(ErrorTelemetry.recordNonFatal(...))`.
11. **Kill switch (§4.6):** `SyncFlags`-style local flag `disable_l2_custom_strip` (configBox) — when set, the migrator
   and the repeat-pin strip are skipped (byte-identical to today). Default ON (strip runs). Sibling heals do the same.
12. **`displaced_<date>` backups — terminal `verified_clean`, migrator does NOT write them.** Verified 2026-10-21:
   a backup is a verbatim copy of the schedule row, written only when a template is assigned over it
   (template_service.dart:120-123) and restored on unassign (:234-258); it is LOCAL-ONLY (no plan_json /
   scheduled_workouts carrier — grep of lib/core/services/sync*). No WriteService method writes a single
   `displaced_` key (only `swapScheduledDays`), so stripping them would widen Gate 49. Live cloud: across all 7 users
   with customs, 23 template-assigned rows, the latest dated 2026-10-09, i.e. none on or after the only polluted plan's
   start (2026-10-12) — so no synced device can hold a backup of a polluted row. After 0a no new polluted rows are
   generated, and the migrator strips the live row before any later template backup copies it.

## r6 — B-pass on the built diff (0 P0, 0 P1, 2 P2, 7 P3); every finding fixed (overrides r5 where they differ)

1. **F1 today:** the open-session test (`ActiveWorkoutPersistence.readState`) is gone: `active_session` is written only
   after a logged set, so a started session with no set read as closed. TODAY's row is never rewritten; a pass that
   would have changed it does not latch, and the row is past by the next launch.
2. **F2 multi-device:** a rewritten row that carries `arranged_at_ms` is re-stamped with the write time, so the
   stripped week wins the restore merge (strictly newer). The diagnose doc's limit is corrected.
3. **F3 push:** the plan push is issued after every completed scan, not only when rows were written; the latch needs
   it issued. `_syncWorkoutPlan`'s skip index keeps a no-op push cheap and re-sends a failed one.
4. **F4 tests:** no write is attempted for completed / rest / travel / template rows (recorded, not inferred from the
   write service's own refusal); a re-scan with the latch cleared attempts none.
5. **F5 paused:** status `paused` (pending, not terminal) is stripped too; `travel` is not (never reverts, past in ≤7 days).
6. **F6a provenance:** `buildPinnedDays`' custom fallback stamps `custom_origin: 'repeat_pin'`
   (`PlannedExercise.customOrigin`, carried by `copyWith`, written by `toMap`); the predicate keeps it.
   **F6b community:** `isLibraryRow` (a `source: 'community'` row is not library), applied by the new
   `ExerciseRepository.hasExactNameWhere` to EVERY row of the name — `getByExactName` stops at the first, so a
   community row sorting first would hide a bundled row of the same name (the F6b fix's own mirror).
7. **F7 stale read:** `upsertScheduled(ifUnchangedFrom:)` refuses with `rowChangedMessage` when the stored row is no
   longer the object read before the lock; the migrator passes the row it read and does not latch on that refusal.
8. **F8** diagnose writer cite → `buildPinnedDays` (:719). **F9** `docs/plan-reviews/l2-custom-repair.md` lands in its
   own commit after this one (the code-review hash-fixed-point rule).
