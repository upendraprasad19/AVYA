# Coach workout parity, slice 1c (OI-491) and its prerequisite Unit P: two landings in one plan file

- **Status:** rev 7 (final pass). Part P: converged after round 5 (`mechanical_only: true`), plus ONE recorded coordinator change (R6B-F2, below). Part 1c: converged after round 6 (`mechanical_only: true`; no P0/P1 in the design, every finding mechanical). Rounds 1-6 are folded in §0.
- **Structure (coordinator decision, §4.12.1: the unit was too large):**
  - **Part P** (the readers that filter exlog rows on a `type` field the device writer never sets, plus the badge PR rule) is its OWN landing: branch `exlog-type-filter-readers`, its own PR, its own record `docs/plan-reviews/exlog-type-filter-readers.md`. It lands FIRST.
  - **Part 1c** (OI-491, Active Workout opens coach-logged exercises as done) follows on branch `coach-workout-parity-1c`, cut after Part P merges, with its own record `docs/plan-reviews/coach-workout-parity-1c.md`.
  - Each part has its own tests, mutations, files list and diagnose doc below. Base for both: `main` 71f07c62 (1a + 1b merged as PR #240).
- **Tier (§4.12.6):** M for both. **Blast radius:** account for both (Part P: `lib/core/services/badge_service.dart`; Part 1c: `lib/core/services/workout_read_service.dart` and `workout_write_service.dart`, `lib/features/train/services/coach_day_completion.dart`). **Execution mode (§4.12.7):** inline, one worktree per part, decided at batch start.
- **Commit types:** Part P `fix(train):` with `closes-diagnose:`; Part 1c `feat(train):` with `closes-oi: OI-491`.
- **Founder decisions (2026-11-10, binding):**
  - B: a coach-logged exercise opens as DONE in Active Workout. Label `LOGGED IN CHAT`.
  - Done, can add sets: the card shows the coach's sets; the user may re-open and log MORE; FINISH saves ONLY the new sets, appended to the coach's `exlog_` row through the `logExercise` merge. The coach's sets are never saved again.
  - Partial coverage: ANY coach log marks the exercise done (the rule of `loggedPlannedExerciseCount`).
  - A day the coach already completed keeps today's behaviour. The zero-set block (OI-361) stays: COMPLETE stays disabled with no new set.
  - F1: PR badges count only a PR that beats an EARLIER log of the same exercise (Part P).
  - F2: the undo button copy is `KEEP AS LOGGED`.
  - F3: a fully chat-logged day shows a NEW FINISH line (Part 1c C6).
  - F4 (2026-11-11): a MIXED day (some chat-logged-done, not all, nothing new saved) shows a second NEW FINISH line (C6, B4-F4).
- **Not in scope:** OI-492 (server), OI-493 (nutrition), any change to `markCompleted`, the bookkeeping step, Train's rows or the chat card.

## 0. Changelog

### rev 7 (round 6: R6A = seat A, R6B = seat B)

| Id | Disposition |
|---|---|
| R6B-F2 (Part P, coordinator decision) | P2/P3/P4: the FINISH PR scan's best maps SKIP rows dated on the session date, so FINISH and the badge share ONE rule: a PR beats the best from STRICTLY earlier IST dates. Three tests; mutant P12. Part P stays converged; this is a recorded coordinator change. |
| R6A-F1 | T5: a `_completing` fixture through `ActiveWorkoutNotifier.debugBeforeMarkGate` (`train_provider.dart:1470`; pattern `test/contracts/coach_completion_counts_behavioral_test.dart:264-265`): a mixed day, Y session-logged, X chat; the gate held with a `Completer`; `isCompleting == true`; both methods return false with state untouched; release. |
| R6A-F2 | T5: the wrong-name fixtures written out explicitly; the slot's state is asserted unchanged. |
| R6A-F3 | C2: the `swapped_from` map is read only when the session date equals `formatDateKey(day.date)`; otherwise only the current-name rule applies. Past-dated-day fixture in T2. |
| R6A-F4 | T2: the bad row is a direct `workoutBox.put` carrying `source: 'ai_coach'` (or `coach_logged: true`) with `'bad'` in `sets[0].weight_kg`; that exercise opens plain. |
| R6A-F5 | C2/C5: `logSets` and `toggleSet` early-return for an `isChatLoggedDone` exercise (one line each); test and mutant M46. |
| R6A-F6 | M30 restated against `loggedNameForPlannedExercise`'s ordered lookup and the `!= null` composition; the differential test is the killer. |
| R6B-F1 | C5: one shared pure helper `hasCheckedRow(data, index)` (the `checkedSets` key-prefix predicate) is used by BOTH the card's KEEP visibility and the `keepChatLogged` guard; widget test and mutant M47. |
| R6B-F3 | T3(c) asserts `row['coach_logged'] == true` on the stored row right after the coach write (M10c's killer). |
| R6B-F4 | M36's variants are "base only (today)", "first only" and "middle only", with distinct `updated_at_ms` so the marked member stays in the middle after the sort. |
| R6B-F5 | C3: the stepper shows the new-row count while the meta text shows `plannedSets` (intended). C5: the chat re-open route stamps `_lastAdvanceAt` / `_lastAdvanceWindow` like `LogExerciseController.reopen`; test. R9 gains "a coach row edited to 0 sets opens DONE with `coachCount` 0". New residual R10 (flag flipped OFF mid-session). |

### rev 6 (round 5: A5 = seat A, B5 = seat B)

| Id | Disposition |
|---|---|
| Part P status | All round-5 findings on Part P were mechanical: marked "converged after round 5 (mechanical_only)". |
| A5-F1 (Gate 19) | P2: ONE helper `WorkoutReadService.exlogRows(Box)` owns the `startsWith('exlog_')` predicate; the three loops call it, so no `'exlog_'` literal lands in `badge_service.dart`. Gate read and verified (P2). Helper test and mutants P10, P11. For 1c: `coach_logged` joins the exlog emit set in `scripts/check_hive_map_field_drift.dart` in the same commit; the file is in the 1c files list (C10). |
| A5-F6 | P2: the per-set reps branch reuses `WorkoutReadService.bestPerSetReps` (`workout_read_service.dart:100`); fallback order unchanged. |
| B5-F5 | P2/P3: the P8 fixture is labelled hand-built; ONE "row max weight" definition for the scan and the badge, `bestPerSetWeight` (`:154`) with its fallback; the scan keys by `exerciseNameKey` on both sides, with a trailing-space test. |
| A5 note | P2/P4: `earlierMax > 0` and `w > earlierMax` stay two separate checks; P4 and P5 are redefined to match. |
| B5-F2 | C6: F4 applies when nothing saveable AND some live slot has a chat entry (chat-done OR re-opened) AND not every live slot is chat-done; F3 = every live slot chat-done; the old line only when no live slot has an entry. T9 adds the single re-opened X and the X-and-Y both re-opened cases; M39 re-derived, M44 added, M28 re-aimed. |
| B5-F1 (P1) | T3 chain coach, app, app, START; three per-clause fixtures (a), (b), (c); M10 replaced by M10a/b/c (one per clause of the carry-forward OR) and M9b (the `source` clause of `isChatLoggedRow`). |
| A5-F2, B5-F3 (P1) | T5: the wrong-name fixtures are split per method; the plan says which name each guard reads and checks each guard mutant for equivalence. |
| A5-F4, B5-F4 | T10/M35/M36: the collision OR ASSIGNS the boolean (true, or the key removed), so "marked existing + unmarked moved" kills M35; migrator mutants "base only (today's code)", "first only", "last only" with a 3-member group whose marked member is in the MIDDLE, plus an assertion that the marker survives when the marked member is the base. |
| A5-F5 | T2: the throwing `rawScheduleRow` fixture is a `schedule_<date>` value with a non-String key; `'bad'` sits inside `sets[0]` for the per-row fixture; M28 now aims at the F4 "any entry" clause. |
| B5-F6 | R1: a coach log removed after START leaves the card DONE until the next START; delete doors named. |
| B5-F7 | C5: `keepChatLogged` also clears `warmUpSets`, `setInputValues` and `suggestedInputs` for that index; test and mutant M45. |
| A5-F3, B5-F8 | C3: `_metaText` prints a set count only in `timed`, `bodyweight_reps`, `weighted_bodyweight` and the `weight_reps` default; `cardio` and `distance` print none and are unchanged. |

### rev 5 (round 4: A4 = seat A, B4 = seat B; founder decision F4)

| Id | Disposition |
|---|---|
| B4-F4, F4 | C6/C8: `finishBlockedLine` picks among THREE lines: all live exercises chat-done gives the F3 line; at least one but not all chat-done gives the NEW mixed line `No new sets logged this session (warm-ups don't count). Log one to complete, or cancel the workout.`; none chat-done gives `activeFinishZeroSetBlocked`. COMPLETE stays disabled. Tests for all three; a mutant for each predicate clause (M27, M28, M38, M39). |
| B4-F2, B4-F10 | P2: the PR scan's best maps use PER-SET maxima from `WorkoutReadService.perSetList(log)`; the fallbacks apply only to a row with no per-set list. Bodyweight test and a mutant that restores the average (P7, P8). |
| B4-F10 (design) | P2: badges no longer read the stored `is_pr`; `countBeatenPrs` walks rows by IST date and compares per-set max weights. Stale-`is_pr` fixture and a mutant that reads `is_pr` (P9). Part P no longer reads `is_pr`. |
| B4-F1 (P1) | T1: a case where BOTH the current-name row and the `swapped_from` row are chat-logged with different sets; `loggedName` is the current name and the chips are the current row's. It is M34's killer. |
| B4-F3 | C2: the WHOLE snapshot (flag read, `resolveSessionDate`, `rawScheduleRow`, the per-row loop) sits in an outer guard; the per-row guard stays inside. T2: a throwing `rawScheduleRow` gives `{}` and START still builds state. M32's test also asserts the current-name row maps when `day.date == null`. |
| B4-F5 | T2/T5 fixture rules (below), including the exact behaviour of the outer catch. |
| B4-F6 | C3: the planned set count applies in BOTH `_metaTextForLogMode` and `_metaText`; T5/M26 cover a timed and a `bodyweight_reps` card. |
| B4-F7 | C4: the introduced-name read takes `plannedSets` from the OVERRIDDEN sets (X's `plannedSets` when the outgoing slot is a re-opened chat exercise). T6 case and mutant M40. |
| B4-F8 | C3: review mode (`data.isSaved`): the chat branch has `onTap` null and no KEEP action; a card test. |
| B4-F9 | T10: the migrator fixture's marked member is NOT last; the collision case "unmarked existing + marked moved" is pinned as the direction that fails today; a mutant for the `source == ai_coach` OR clause (M41). |
| B4-F11 | R7 reworded; T8 pin. |
| A4-F1 (P2) | T10: the push-bundle test drives a real push through `SyncHarness` (`test/sync/sync_domain_skip_harness.dart`), following `test/sync/exlog_push_u3_behavioral_test.dart`, and compares the captured `workout_log_exercises` (and per-set) payloads with and without `coach_logged`. M37's file is `lib/core/services/sync/sync_workout.dart`. Whether the harness can do this is a coding-time check (§C12). |
| A4-F2 | Glossary gains `active_workout_chat_snapshot_failed`. |
| A4-F3 | `editLog` starts at `workout_write_service.dart:1255` (`:1377` is the `source` overwrite). New residual R9. |
| A4-F4 | C1 names the `ExerciseSet` to `WardSetChip` mapping helper. |
| A4-F5 | `ChatLoggedExercise.chatLogged` and the unreachable `LOGGED ✓` branch of `chatLoggedLabel` are dropped; M29 removed. |
| A4-F6 | See B4-F5 (M14). |
| A4-F7 | The prose distinguishes the header `'${saved} / ${total} SETS'` (`lib/features/train/screens/active_workout/header.dart:59`) from the dialog `{saved}/{total} sets logged`. |
| Seat A on Part P | Clean apart from A4-F1 and the design items above. |

### rev 4 (round 3: A3 = seat A, B3 = seat B)

| Id | Disposition |
|---|---|
| Structure | Part P is split out as its own landing (above). |
| A3-F1, B3-F8(e) | P3: a `BadgeService.instance.checkAll()`-level test with real Hive; device-shaped rows written through `logExercise` on two dates; `BadgeId.firstPr` unlocks for the heavier second log and not for a single first-ever log; the non-`exlog_` map case also goes through `checkAll`. P mutation (1) for the badge loop is named against it. `checkAll` stays synchronous. |
| A3-F6, B3-F5 | P2: the badge counts a row only if `is_pr == true` AND an EARLIER-dated `exlog_` row of the same `exerciseNameKey` with `weight_kg > 0` exists. Described as SIMILAR to FINISH's `bestPrevious > 0`, with the exact remaining difference. Tests for an earlier 0 kg row; a mixed-name lifetime-volume case. |
| A3-F2, B3-F2 (part) | C3: the "prefill new rows from the coach's last set" mechanism is REMOVED (rows keep today's prefill); its tests and mutants are deleted. The set-number offset stays. |
| B3-F2 | C1: `ChatLoggedExercise.coachCount = max(sets.length, aggregateSetCount(row))`, used for the header (both sides), the re-open row count and the numbering. Chips come from `sets` (none when empty). T5 case: empty per-set list with `set_number: 2`. |
| A3-F4, B3-F1 | C6: the new FINISH line shows only when `data.exercises.isNotEmpty` and EVERY exercise in the LIVE list is chat-logged-done. The `allExercisesLogged` and `loggedInChat.isNotEmpty` clauses are dropped. T9 and one mutant per case. |
| B3-F3 | C4: swap/add of a name NOT in `loggedInChat` does one synchronous, flag-gated, try/caught read of today's row for that name (the snapshot's accept predicate) and adds the entry in the same `copyWith`. Not a mid-session sync. Test and mutant. |
| B3-F4 | C1: lookup order is the current-name row if it passes `accept`, else the `swapped_from` row if it passes, else none. T8 pins the second-START R3 case. |
| A3-F3, B3-F6 | C1b: OR-semantics for `coach_logged` in the two merge paths that drop it: the `moveExerciseLogs` collision branch and the `ExlogKeyMigrator` multi-entry group. T10 covers both collision directions and a migrator group. `:1224`, `:1565`, `:1652` are removed from the plan (not exlog rows). |
| B3-F7 | C1b: the `coach_logged` writer is NOT flag-gated (local-only, harmless). Test: `_buildExlogPushBundle` output and `exlogPayloadFingerprint` are identical with and without the marker. |
| B3-F8(a-d) | C5/T-notes: (a) fixtures set `logged_at_ms` from the REAL clock; (b) the M24 test makes `widget.data` stale; (c) the M23 fixture forces a validation failure; (d) the `isComplete` guard test sets it directly. |
| B3-F9 | C5: index bounds are checked FIRST in the `reopenChatLogged` / `keepChatLogged` guards; a mutant. |
| B3-F10 | C2: `day.date == null` gives an empty `swapped_from` map. |
| B3-F11 | C2: the snapshot catches per ROW; a bad row is skipped; the telemetry event fires once per START with a count. T2 and M14 updated. |
| A3-F5 | C6: `workingSetCounts` returns `({int saved, int total})`; the plan says `saved`, and `workingProgress` / the `{saved}` template follow. |
| A3-F7 | C1: `!= null` (not `is Map`) stays in the `accept == null` path of `loggedPlannedExerciseCount`; C2: the duplicate-name branch has `logEvent` only; C3 lists the wiring edits. |
| A3 §10 | Settled and cleared from §10: the fingerprint covers only the pushed bundle (`lib/core/services/sync_service.dart:389-400`); the telemetry seam is `ErrorTelemetry.debugOnLogEventForTests` (`lib/core/services/error_telemetry.dart:61-70`), reset in `tearDown`; the card resize never seeds from the coach (moot, prefill removed). |

### rev 3 (round 2, founder F1-F3) and rev 2 (round 1), summary

Rev 3: F1 badge rule; F2 `KEEP AS LOGGED`; F3 new FINISH line; semanticsLabel on `_LogExerciseButton`; builders read the `data` parameter; the sticky `coach_logged` marker; the swap/add rule REVERSED (a mapped name opens DONE); per-guard mutants; the Red-day `plannedSets`; snapshot-failure telemetry; residuals R7, R8; full paths. Rev 2: the mid-session sync was deleted in favour of one snapshot at `startWorkout` (flag-gated, guarded); `keepChatLogged`; the re-open row count; the both-sides header count; the label helper; Unit P found.

---

# PART P: exlog readers that filter on `type` (landing 1, branch `exlog-type-filter-readers`; converged after round 5, mechanical_only)

## P1. Writers and readers (HEAD 71f07c62)

- **Writers.** The only writer of `type: 'exercise_log'` is the cloud restore, `lib/core/services/sync/sync_workout.dart:1082`. `WorkoutWriteService.logExercise` never writes it but writes `is_pr` (`lib/core/services/workout_write_service.dart:290`, stamped by `_rescanPrFor`).
- **Readers that filter on it:**
  - (a) the FINISH PR scan, `lib/features/train/providers/train_provider.dart:2078`. Its consumer needs `bestPrevious > 0` (`:2145`, `:2166`), so on device-logged history no PR line ever fires.
  - (b) the badge PR count, `lib/core/services/badge_service.dart:102-106`, which counts only restored rows.
  - (c) sibling sweep: `WorkoutRepository.getAllExerciseLogKeysForLifetimeSum`, `lib/features/train/repositories/workout_repository.dart:1916-1923`, read by `lib/features/profile/widgets/service_record_section.dart:208` (Profile lifetime volume).
- **Recurrence.** The same filter was fixed in `graduationStatsProvider` (`train_provider.dart:2552`, "10th writer/reader drift"): `docs/diagnoses/2026-05-22-graduation-total-sets-drift-89d56c.md`; related `2026-05-16-pr-cumulative-bug-cb1ab1.md`; the OI-39 note at `workout_read_service.dart:403-408`.

## P2. Design

- **Fix (all three loops) through ONE helper (A5-F1).** `WorkoutReadService.exlogRows(Box box)` (values-only: `Iterable<Map<String, dynamic>>`, defensive copies) owns the predicate: it iterates the box KEYS and yields only entries whose `key.toString().startsWith('exlog_')` and whose value is a `Map` (the predicate already at `workout_read_service.dart:377`). The PR scan, `BadgeService.checkAll` and `getAllExerciseLogKeysForLifetimeSum` call it instead of filtering on the `type` field, so no `'exlog_'` literal is added to `badge_service.dart`.
- **Gate 19 (`scripts/check_hive_map_field_drift.dart`), read and verified, not run.** The gate flags a file as an exlog reader when it contains `startsWith('exlog_')`, `box.get('exlog_` or the literal `'exlog_'` (lines ~214-222) and then reports every `['field']` access in that file that is outside the emit set (`_expectedEmitFields`, `:65`) and the baseline (`~:262-300`). `workout_read_service.dart` (`:377`), `train_provider.dart` (`:2571`) and `workout_repository.dart` (`:126`, `:903`) ALREADY carry the literal and are already scanned; the helper adds no `['field']` access. `badge_service.dart` carries no such literal today and, with the helper, still will not, so it stays unscanned and the gate stays green. Run the gate at coding time to confirm.
- **PR scan: per-set maxima (B4-F2).** Once device rows reach the scan, its best maps must not use the row-level shortcuts. ONE definition of a row's max weight serves both the scan and the badge: `WorkoutReadService.bestPerSetWeight(log)` (`:154`, per-set max, falling back to the top-level `weight_kg` as it already does). Best reps = `WorkoutReadService.bestPerSetReps(log)` (`:100`; a 12/10/8 row gives 12, not the average 10). When that returns 0 (no per-set list), the fallback order is unchanged: `best_single_set_reps`, then the old average (`reps_completed ~/ set count`, via `WorkoutReadService.aggregateSetCount`). The scan keys its maps by `exerciseNameKey(name)` on BOTH the write and the lookup side (not `toLowerCase()` only). Duration already uses `WorkoutReadService.bestPerSetDuration` (per-set; verified at `workout_read_service.dart:127`) and is unchanged.
- **Badge rule (founder F1), computed from the rows, not from the stored `is_pr` (B4-F10).** A pure, SYNCHRONOUS static `BadgeService.countBeatenPrs(Iterable<Map> exlogRows)`: group by `exerciseNameKey(exercise_name)`; take each row's IST date from `WorkoutReadService.istDateForExlogRow` (a row without a date is skipped); walk each group ordered by date. A row counts (+1, the same unit as before) when `w = bestPerSetWeight(row)` is greater than `earlierMax`, the max `bestPerSetWeight` over all STRICTLY earlier-dated rows of the same name key, AND `earlierMax > 0`. The two checks (`earlierMax > 0` and `w > earlierMax`) stay SEPARATE in the code, so a mutant can drop each on its own. **Part P no longer reads `is_pr` anywhere**, so a stale flag (an earlier heavier row back-filled later) cannot count. `checkAll` feeds it the `exlog_` rows. `checkAll` / `checkAndUnlock` stay synchronous (`test/contracts/badge_service_synchronous_invariant_test.dart`; no `await` is added).
- **FINISH and the badge share ONE rule (R6B-F2, coordinator decision).** A PR beats the best from STRICTLY earlier IST dates. The FINISH scan's best maps SKIP every row whose `WorkoutReadService.istDateForExlogRow(log)` equals the session date, the date `_persistCompletion` saves to (`resolveSessionDate`, `train_provider.dart:525`; the call is hoisted above the scan so the scan and the save use one value). Without the skip, a coach row logged today (or an earlier same-day log) would make the session's own day the baseline.

## P3. Tests (new `test/contracts/exlog_type_filter_reader_drift_behavioral_test.dart`, real Hive)

- **`checkAll` level (A3-F1, B3-F8(e)):** device-shaped rows (no `type`, `source: active_workout`) written through `WorkoutWriteService.logExercise` on two dates (100 kg, then 110 kg). `BadgeService.instance.checkAll()` unlocks `BadgeId.firstPr` for the heavier second log; for a single first-ever log (`is_pr` true) it does not. A map in the box under a non-`exlog_` key carrying `type: 'exercise_log'` and `is_pr: true` does not unlock it (also through `checkAll`).
- **`countBeatenPrs` pure cases:** first-ever log gives 0; a later heavier log gives 1; a restored-shape row (`type: exercise_log`, no `source`) counts the same as a device row; an earlier row at 0 kg then a weighted row gives 0; two different names do not earn each other's "earlier row"; a same-date earlier row does not count (the stated difference); **stale flag:** a row with `is_pr: true` but an earlier heavier row back-filled gives 0, and a row with `is_pr: false` that is heavier than every earlier row gives 1; a later LIGHTER log gives 0. **Helper (`exlogRows`):** keys not starting with `exlog_` and non-Map values are skipped; entries come back as copies. **Name key:** the scan matches `"Bench Press "` (trailing space) with the earlier row keyed `bench press`.
- **PR scan:** a finish with 110 kg after a logged 100 kg (earlier day) yields `Bench Press: 110.0kg (was 100.0kg)`; at 100 kg or less none. **Session-date skip (R6B-F2):** a coach row TODAY at 100 kg, no history, session 105 gives NO PR line; an earlier-day 100 gives the PR line `(was 100.0kg)`; an earlier-day 100 plus a same-day 110, session 105, gives the PR line `(was 100.0kg)`. **Bodyweight (B4-F2):** an earlier day of 12/10/8 reps; today a best set of 12 gives NO PR line; today 13 gives the PR line `(was 12 reps)`. A row with no per-set list still uses the fallbacks.
- **Lifetime volume (A3-F6):** a mixed-name fixture (two exercises, one device-shaped and one restore-shaped row) returns every `volume_kg`.

## P4. Planned mutations (confirm each applied with `grep -c`; a compile error is not proof)

| # | File: exact edit | Expected red |
|---|---|---|
| P1 | `lib/core/services/badge_service.dart`: REPLACE the `WorkoutReadService.exlogRows(...)` call with a `workoutBox.values` loop filtering `m['type'] == 'exercise_log'` | the `checkAll` device-row test |
| P2 | `lib/features/train/providers/train_provider.dart` PR scan (`:2077-2078`): REPLACE the helper call with the `values` loop and `log['type'] != 'exercise_log'` | the PR scan test |
| P3 | `lib/features/train/repositories/workout_repository.dart:1921`: REPLACE the helper call with the `type` condition | the lifetime-volume test |
| P12 | `train_provider.dart` PR scan: remove the session-date skip | the three session-date cases (today-only row gives a false PR baseline; same-day 110 changes `was`) |
| P10 | `workout_read_service.dart` `exlogRows`: drop the `startsWith('exlog_')` test | the helper test (non-`exlog_` key skipped) |
| P11 | `exlogRows`: drop the `Map` value check | the helper test (non-Map value skipped) |
| P4 | `badge_service.dart` `countBeatenPrs`: drop the `earlierMax > 0` check | the first-ever log tests (pure and `checkAll`) and the earlier 0 kg case |
| P5 | `countBeatenPrs`: drop the `w > earlierMax` check | the later LIGHTER log case |
| P6 | `countBeatenPrs`: use `<=` for the date comparison | the same-date case |
| P7 | `train_provider.dart` PR scan: restore the average (`totalReps ~/ setCount`) for a row that has a per-set list | the bodyweight 12/10/8 test |
| P8 | PR scan: take the weight from the row-level `weight_kg` instead of `bestPerSetWeight` | the per-set weight fixture. It is HAND-BUILT (writer rows have row weight == per-set max, so only a hand-built row can tell the two apart) |
| P9 | `countBeatenPrs`: read `m['is_pr'] == true` instead of comparing weights | the stale-`is_pr` fixture |

## P5. Files and docs

`lib/core/services/workout_read_service.dart` (the helper), `lib/features/train/providers/train_provider.dart`, `lib/core/services/badge_service.dart`, `lib/features/train/repositories/workout_repository.dart`, the new test (the PR scan fixtures use device-shaped rows with a `sets[]` list); registry: the concept for the PR / badge / lifetime-volume readers gains the key predicate and `countBeatenPrs`, with `behavioral_test_path:` this test (recompute `line_range` per commit); `lib/features/train/CLAUDE.md` pitfall row "do not filter exlog rows by `type`"; `docs/naming_conventions.md`: `countBeatenPrs`.

## P6. Existing tests and diagnose doc

- `graduation_stats_provider_field_test`, `workout_write_to_read_contract_test`, `edit_log_id_injection_test` and `load_all_exercise_prs_per_set_semantic_test` (all under `test/contracts/`) pin the ABSENCE of the filter in their own functions; none greps these three loops, so none needs repointing (grep before the edit, re-run after). `badge_service_synchronous_invariant_test.dart` greps `badge_service.dart`: check its pins against the new loop.
- Diagnose doc, FULL template (recurrence class): `docs/diagnoses/2026-11-10-exlog-type-filter-pr-badge-readers-<id>.md`, `related_bugs: [89d56c, cb1ab1]`, `recurrence:` citing the 2552 fix; `touched_layers_checked`: client code and Hive `fixed_in_this_batch`, restore `verified`.

---

# PART 1c: Active Workout opens coach-logged exercises as done (landing 2, branch `coach-workout-parity-1c`)

## C0. What happens today

`startWorkout` builds `ActiveWorkoutData` with `checkedSets: {}` and never reads an `exlog_` row. A chat-logged exercise opens as a fresh card; LOG then FINISH writes the sets a second time through the `logExercise` merge (the 60 s duplicate window only catches an identical set logged within a minute).

## C0b. Writers and readers (HEAD 71f07c62, file:line)

| What | File:line | Notes |
|---|---|---|
| Session start | `lib/features/train/providers/train_provider.dart:1479` `startWorkout`; Red-day set drop before the state build; state at `:1519`; timer `:1531-1537`; the duplicate-name branch `:1509-1512` | Only callers: `lib/features/train/widgets/readiness_sheet.dart:58,66`. RESUME returns at `:43-47` (diagnose `e8f4a1`). |
| Session data and its footgun | `train_provider.dart:1202-1291` `ActiveWorkoutData`, `copyWith :1254` | The timer calls `copyWith(elapsedSeconds:)` (`:1534`); a missing field resets within a second. |
| Name-keyed re-open set | `:1234` `reopenedExercises`; `unlogSets(reopened:)` `:1615`; `swapExercise :1712` (removes the outgoing name); `addExercise :1785`; `removeExercise :1793` | Name-keyed. |
| Done / save predicates | `:1394` `isExerciseDone`; `:1338` `wouldSaveSet`; `:1347` `saveableSetIndexes`; `:1364` `hasSaveableSet` | The save predicate is not touched. |
| Readers of `isExerciseDone` | `lib/features/train/services/log_exercise_logic.dart:448` (`supersetPartnerToReveal`), `:503` (LOG outcome after `logSets`), `:536` (`LogExerciseController.reopen`), `:680` (`allExercisesLogged`); `lib/features/train/services/exercise_move_logic.dart:17,106`; `lib/features/train/screens/active_workout/screen.dart:329`, `:608-615`, `:701-711`; `lib/features/train/screens/active_workout/exercise_card.dart:1645`, `:2077` | One change reaches them all. |
| Other derived readers | `log_exercise_logic.dart:689` `workingSetCounts` (consumers `screen.dart:449` -> `header.dart:59`; `finish_dialog.dart:230`), `:705` `workingProgress`, `:732` `finishGuard`, `:770` `_hasTypedUnloggedValue` | |
| Re-open wiring | `screen.dart:262` `_onReopenExercise` -> `log_exercise_logic.dart:521` `LogExerciseController.reopen` -> `train_provider.dart:1615` `unlogSets(reopened: true)` | |
| Save | `train_provider.dart:2027` `completeWorkout` (OI-361 block `:2032`); `:2055` `_persistCompletion`; `logExercise` call `:2237` fed ONLY by `state.saveableSetIndexes(exIdx)` | Not edited. |
| Merge writer | `lib/core/services/workout_write_service.dart:180-236` `logExercise`; row rebuilt at `:262-286` (`source` `:283`, `notes` only when passed) | `source` is the LAST writer's. A re-log drops old `notes` (R4). |
| Marker carriers | `workout_write_service.dart` `moveExerciseLogs` collision branch (`~:1105-1154`); `lib/core/services/exlog_key_migrator.dart` multi-entry group (`~:129-175`); `editLog` (`:1255`; `:1377` is its `source` overwrite) | C1b. |
| Source codes | `lib/core/services/write_result.dart:65,99` (`ai_coach`); coach callers `lib/features/ai_coach/services/conversational_log_handler.dart:390`, `lib/features/ai_coach/services/tool_dispatcher.dart:388` | |
| Cloud restore | exlog rows `lib/core/services/sync/sync_workout.dart:1080-1103`, NO `source` key; `wlog_` restore `:952`. The cloud table has no `source` column | R6. |
| Push bundle | `lib/core/services/sync_service.dart:389-400` `exlogPayloadFingerprint` covers only the pushed bundle | A local-only key does not change it (tested). |
| Session date | `train_provider.dart:525` `resolveSessionDate` | Same call as `_persistCompletion`. |
| Planned-exercise log rule | `lib/features/train/services/coach_day_completion.dart:98-113` `loggedPlannedExerciseCount`; `swapped_from` from `lib/core/services/swap_service.dart:587` | Predicate extracted (C1). |
| Per-set reads | `lib/core/services/workout_read_service.dart:204` `perSetList`, `:225` `aggregateSetCount`, `:319` `istDateForExlogRow` | |
| Chips | `lib/shared/widgets/wardroom/ward_set_chips.dart:44` | |
| Raw plan row | `lib/core/services/workout_schedule_read_service.dart:999` `rawScheduleRow` | |
| Flag | `lib/features/train/services/log_exercise_flags.dart` | `train_provider.dart` needs the import. |
| Card | `lib/features/train/screens/active_workout/exercise_card.dart`: `_metaTextForLogMode :975`, `_entryRows :1057`, `SetInputRow(setNumber: setIdx + 1) :1094`, `_buildLogRow :1196`, `_makeEntryHandle` (the viewer's closures), `_LogExerciseButton :1895` (logged label `:1931`); `lib/features/train/widgets/set_input_row.dart:19,159` | |
| Finish dialog | `lib/features/train/screens/active_workout/finish_dialog.dart:20,219-220,227`; `lib/core/copy/wardroom_copy.dart:269` | |

## C1. Which exercises are chat-logged, and the one list

- **`coach_day_completion.dart`** (account tier): extract the per-exercise predicate of `loggedPlannedExerciseCount` into `String? loggedNameForPlannedExercise(DateTime date, Map ex, {bool Function(Map row)? accept})`. Lookup order: the CURRENT-name row if it exists and passes `accept`; else the `swapped_from` row if it exists and passes `accept`; else null. In the `accept == null` path the existence test stays `box.get(key) != null` (NOT `is Map`), so `loggedPlannedExerciseCount` is byte-identical (differential test against a frozen copy of the old body).
- **`lib/features/train/services/chat_logged_exercises.dart`** (new, feature tier):
  - `class ChatLoggedExercise { String loggedName; String loggingType; List<ExerciseSet> sets; int coachCount; int plannedSets; }` (an entry exists only for a chat row, so there is no flag).
  - `sets` = `WorkoutReadService.perSetList(row).map(ExerciseSet.fromMap)` (possibly empty). `coachCount = max(sets.length, WorkoutReadService.aggregateSetCount(row))`. Chips come from `sets` (none when it is empty) through a pure helper `chatLoggedChips(List<ExerciseSet>) -> List<WardSetChip>` (`durationSec` maps to `durationSeconds`; `reps`, `weightKg` and `distanceKm` carry over, the field mapping of `lib/features/train/widgets/workout_receipt_card.dart:209-250`); every count uses `coachCount`.
  - `plannedSets` = `int.tryParse(exercise.sets) ?? 3` taken in `startWorkout` AFTER the Red-day set drop, only for snapshot entries.
  - `isChatLoggedRow(Map row) => row['coach_logged'] == true || row['source'] == WriteSource.aiCoach.code`; `chatLoggedSnapshot(...)` uses it as `accept` and reads the row with the new `WorkoutReadService.exerciseLogRow(String key)` (defensive copy; the caller builds the key with `WorkoutWriteService.exlogKey`). Map key `exerciseNameKey(session name)`.
  - The label is always `WardroomCopy.activeLoggedInChatLabel` for an entry, with `activeLoggedInChatSemantics`; non-chat cards keep their existing `LOGGED ✓` path (`wardroom_copy.dart:154`) untouched. There is no label helper with a second branch.

### C1b. The sticky marker

- `logExercise` writes `'coach_logged': true` when the existing row has it, or the existing row's `source == 'ai_coach'`, or the incoming `source == WriteSource.aiCoach`; otherwise the key is absent. The writer is NOT flag-gated: the field is local-only and harmless.
- OR-semantics where two rows meet:
  - `moveExerciseLogs` collision branch (`workout_write_service.dart ~:1105-1154`): `merged.coach_logged = existing.coach_logged || moved.coach_logged || either source == ai_coach`;
  - `ExlogKeyMigrator` multi-entry group (`exlog_key_migrator.dart ~:129-175`): the marker is set if ANY member of the group has it.
  `editLog` (starts at `workout_write_service.dart:1255`; `:1377` is its `source` overwrite) rewrites the existing row in place and keeps the key; a plain re-log carries it (both tested). `:1224`, `:1565` and `:1652` are not exlog rows and are out of scope. A coach row written BEFORE this ships has no marker, and an edit in the sheet overwrites its `source`, so it stops being a chat row (R9).
- Hive-local: no cloud column, not synced, the restore does not write it (R6). Test: the `_buildExlogPushBundle` output and `exlogPayloadFingerprint` are identical with and without the key.
- Registry: `hive_field_name_exlog` and `lib/features/train/CLAUDE.md` gain `coach_logged`; glossary entry.

## C2. Session state: one NAME-keyed snapshot, taken once

- `ActiveWorkoutData.loggedInChat`: `Map<String, ChatLoggedExercise>`, default `const {}`, threaded through the constructor, `copyWith` and the `startWorkout` state build. Derived: `isChatLogged(i)`, `isChatLoggedDone(i) = isChatLogged(i) && !reopenedExercises.contains(name)`; `isExerciseDone(i)` returns true first for `isChatLoggedDone(i)`.
- **`startWorkout`** fills it after the Red-day drop and before the state build: flag `LogExerciseFlags.logExerciseButtonEnabled` (OFF gives `{}`, byte-identical); date `resolveSessionDate(scheduledDate: day.date, now: nowWall())`; `swapped_from` map from `rawScheduleRow(day.date)` ONLY when the session date equals `formatDateKey(day.date)`; EMPTY (current-name rule only) when `day.date == null`, when `day.date` is a past date that `resolveSessionDate` replaced with today (the past plan row's `swapped_from` names belong to another day's logs), or when there is no row.
- **Outer guard (B4-F3).** The WHOLE snapshot (the flag read, `resolveSessionDate`, `rawScheduleRow`, the per-row loop) sits in one `try/catch`. On an outer failure the result is `{}` (any partial map built so far is DISCARDED, never merged into state), `debugPrint` runs, and ONE `unawaited(ErrorTelemetry.logEvent('active_workout_chat_snapshot_failed', message: 'outer:${e.runtimeType}'))` fires; START still builds state exactly as today.
- **Per-ROW guard (inside the outer one).** The read and the build for each exercise sit in their own `try/catch`. A bad row is skipped (its exercise opens plain); the other rows still map. After the loop, if any row failed (and the outer guard did not): `debugPrint` plus ONE `unawaited(ErrorTelemetry.logEvent('active_workout_chat_snapshot_failed', message: 'rows=$failedCount'))` per START (the duplicate-name branch at `train_provider.dart:1509-1512` has `logEvent` only; ours adds the `debugPrint`). Only a count and the error type are reported, never row values.
- No other writer at START or in the session, except the introduced-name read of C4. RESUME and the screen open never touch the field.
- `saveableSetIndexes`, `wouldSaveSet`, `hasSaveableSet`, `checkedSets` and `setInputValues` are NOT touched; the coach's sets live only in `loggedInChat`, so `_persistCompletion` cannot write them.

## C3. The card

All in `lib/features/train/screens/active_workout/exercise_card.dart`, inside `_entryRows` / `_buildLogRow`, which the logging viewer also hosts. The builders read the `data` PARAMETER (`data.loggedInChat[exerciseNameKey(widget.exercise.name)]`, `data.reopenedExercises`), never `widget.data`. LOG mode only. The chat branch is FIRST in both builders.

- **Not re-opened:** `WardSetChips` from `entry.sets` under an eyebrow with the helper label; `_LogExerciseButton` in the `logged` style with that label and `TAP TO RE-OPEN`; the stepper hidden. (When re-opened the stepper shows the NEW-row count while the meta text shows `plannedSets`; intended.) `_LogExerciseButton` gains `final String? semanticsLabel;` (used as `semanticsLabel ?? WardroomCopy.activeLoggedSemantics` at `:1931`); the card passes `chatLoggedSemantics(entry)`.
- **Re-opened:** eyebrow and chips stay above the editable rows; a `KEEP AS LOGGED` text action sits on the eyebrow row while no new set is checked. The meta text shows `entry.plannedSets` in BOTH `_metaTextForLogMode` (`exercise_card.dart:975`) and `_metaText` (`:985-1013`: only the `timed`, `bodyweight_reps`, `weighted_bodyweight` and `weight_reps` default branches print a set count; `cardio` and `distance` print none and are unchanged). New rows are numbered from `coachCount + 1` (`SetInputRow(setNumber: setIdx + 1 + coachCount)`; its semantics label follows, `set_input_row.dart:159`). The rows keep today's prefill (`_initControllers`); nothing is seeded from the coach's sets.
- **Review mode (`data.isSaved`, B4-F8):** the chat branch has `onTap` null (the existing `reviewMode ? null :` pattern) and no KEEP action; a card test.
- **Wiring edits:** `screen.dart:262` `_onReopenExercise` routes a chat-done exercise to `reopenChatLogged` through the controller's optional callback; a new `onKeepChatLogged` callback is passed from the screen to the card (and to `debugExerciseCardHostForTest`); the viewer host reaches it through the card's `_makeEntryHandle` closures, so `ExerciseEntryHandle`'s signatures are unchanged.
- Web: same widgets; tests at 360 dp and 1024 dp.

## C4. Swap, add, undo

- A name in `loggedInChat` opens DONE wherever it appears: swap TO it, add it, swap UNDO, re-pick of the same slot; re-open stays available. `swapExercise` already removes the outgoing name from `reopenedExercises`, so no extra marking is needed.
- Its `sets` is `entry.plannedSets`: in `swapExercise` and `addExercise`, when the incoming name is in the map, the incoming exercise's `sets` is set to `entry.plannedSets` in the same `copyWith`. `plannedSets` is never re-derived from an incoming exercise's `sets` for a mapped name.
- Swapping AWAY from a re-opened X: an unmapped Y gets `X.entry.plannedSets` (the slot's original count), not X's reduced `sets`; a mapped Y gets its own `plannedSets`. X's entry stays in the map, so X swapped back is DONE.
- **Introduced name not in the map (B3-F3):** when the incoming name is NOT in `loggedInChat`, `swapExercise` / `addExercise` do ONE synchronous, flag-gated, try/caught read of today's row for that name (the snapshot's `accept` predicate, `resolveSessionDate(state.workoutDay?.date, nowWall())`, no `swapped_from`) and, on a hit, add the entry in the same `copyWith`, with `plannedSets` taken from the OVERRIDDEN sets, i.e. `int.tryParse(effectiveSets) ?? 3` where `effectiveSets` is X's `plannedSets` when the outgoing slot is a re-opened chat exercise (else the incoming exercise's own `sets`); the exercise then opens DONE like any mapped name. On a miss or an error nothing is added. This reads only for the name being introduced; it is not a mid-session sync of the others.

## C5. Re-open, keep, row count, done rule

- Which name each guard reads: `wrong name` compares the PASSED `name` with `exercises[index].name`; `non-chat` looks up the SLOT's name key in `loggedInChat`; `already re-opened` / `not re-opened` read `reopenedExercises` for the SLOT's name.
- `reopenChatLogged(index, name)`: guards in this order: index bounds FIRST, then `_completing`, saved, complete, wrong name, non-chat, already re-opened. It adds the name to `reopenedExercises` and sets `exercises[index].sets = max(1, plannedSets - coachCount)` in one `copyWith`.
- Done rule: a non-re-opened chat exercise is done; a re-opened one uses the existing loop over its reduced `sets` (done when every new row is checked).
- `keepChatLogged(index, name)`: index bounds first, then `_completing`, saved, complete, wrong name, non-chat, not re-opened, and refuses if `hasCheckedRow(data, index)` — ONE shared pure helper (the `checkedSets` key-prefix `$index-` predicate) used by BOTH this guard and the card's KEEP visibility, so a checked warm-up-only new row hides KEEP and the guard refuses, with no drift between them; otherwise removes the name from `reopenedExercises`, restores `sets = plannedSets`, and clears `warmUpSets`, `setInputValues` and `suggestedInputs` for that index (nothing is checked, so no logged data is lost; stale typed values cannot leak into a later re-open or the typed-unsaved warning).
- `logSets` and `toggleSet` early-return when `isChatLoggedDone(exerciseIndex)` (one line each), so no path can check a hidden row of a done chat exercise.
- The chat re-open route stamps `_lastAdvanceAt` and `_lastAdvanceWindow = kRevealGuard` exactly as the existing `LogExerciseController.reopen` does after `unlogSets` succeeds (so the double-tap guard and the reveal scroll behave the same).
- `LogExerciseController.reopen` (`log_exercise_logic.dart:521`) gains OPTIONAL named parameters (`reopenChatLogged`, default null); existing callers and tests are unchanged.

## C6. Counts, FINISH and the guard

- **`workingSetCounts`** (`log_exercise_logic.dart:689`, returns `({int saved, int total})`) is the only count getter that changes (header and FINISH count line both read it). The coach's logged sets count on BOTH sides, with `coachCount`:
  - not chat-logged: `total += template working sets`, `saved += saveableSetIndexes(i).length` (as today);
  - chat-logged, not re-opened: `total += coachCount`, `saved += coachCount`;
  - chat-logged, re-opened: `total += coachCount + working new rows`, `saved += coachCount + saveableSetIndexes(i).length`.
  A fully chat-logged day reads `N/N SETS` (`WardroomCopy.activeFinishCountTemplate` `{saved}/{total}`) with a full bar (`workingProgress` consumes the same record; its code is unchanged). `hasSaveableSet`, `saveableSetIndexes`, `finishGuard` and `completeWorkout` do not read these counts, so the zero-set block holds. The doc comment on `workingSetCounts` is rewritten (`saved` is now "logged for the day").
- **`finishGuard`:** a chat-done exercise is skipped at the top of the loop; a re-opened chat exercise with 0 new checked sets is not put in `reopenedUnsaved` (that branch stays for non-chat exercises), the UNCHANGED typed check runs, and otherwise it is listed nowhere.
- **The blocked line (F3, F4).** `finish_dialog.dart` picks it with `finishBlockedLine(data)` among THREE lines, over the LIVE exercise list (`blocked`, `finish_dialog.dart:20`, already means `!hasSaveableSet`):
  - `data.exercises.isNotEmpty` and EVERY exercise `isChatLoggedDone(i)`: `activeFinishAllLoggedInChat` (F3);
  - some live slot has a chat ENTRY (`isChatLogged(i)`: chat-done OR re-opened) and NOT every slot is chat-done: `activeFinishNoNewSets` (F4; coordinator decision within the founder's mixed-day ruling);
  - no live slot has an entry: `activeFinishZeroSetBlocked` (unchanged).
  COMPLETE stays disabled in all three. The dialog's count line is `{saved}/{total} sets logged` (`WardroomCopy.activeFinishCountTemplate`); the screen header is a different string, `'${saved} / ${total} SETS'` (`header.dart:59`).

| Case | Header / count line | FINISH | Dialog | Written |
|---|---|---|---|---|
| No chat-logged exercise (empty map, flag OFF) | as today | as today | as today | as today |
| Some chat-logged (not re-opened), rest logged in session | coach + session / coach + template of the others | gold when the others are done | new totals; chat exercises in no list | session exercises only; chat rows byte-identical |
| Chat exercise re-opened, 0 new sets | coach on both sides; new rows add to `total` | outline | not `Not saved`, not `skipped`; a typed unlogged value still lists it | nothing for it |
| Re-opened (3 planned, 1 coach, 2 new rows), 2 checked | coach + 2 / coach + 2 | gold when the rest is done | no `partial` line | the coach's set (deep-equal) then 2; `set_number` 3 |
| Every exercise in the live list chat-done | `N / N SETS`, bar 100% | gold, `All exercises logged.` | `N/N sets logged`; COMPLETE disabled; the NEW line | nothing; `completeWorkout` returns on its first line |
| Chat X + session Y with only warm-ups checked | as today for Y | per `allExercisesLogged` | the NEW mixed line (F4) | nothing |
| X swapped out or removed, leaving a non-chat warm-up-only day (X's entry stays in the map) | as today | as today | the OLD zero-set line | nothing |
| One un-done non-chat exercise, others chat-logged, nothing new checked | with its template sets on `total` | outline | the NEW mixed line (F4) | nothing |
| A single re-opened chat X, 0 new sets | coach on both sides; X's new rows on `total` | outline | the NEW mixed line (F4); X is not listed as `Not saved` | nothing |
| X and Y both re-opened, 0 new sets | as above for both | outline | the NEW mixed line (F4) | nothing |

## C7. What is kept, and how

| Kept | How |
|---|---|
| Resume guard (`e8f4a1`) | `hasInProgressSession` and `beginWorkoutWithReadiness` are not edited; RESUME never calls `startWorkout`. Test: RESUME leaves every session field identical. |
| Session-date rule (`a3c8e2`) | the same `resolveSessionDate` call; test with a past-dated plan day. |
| Zero-set block (OI-361) | `completeWorkout`'s first line and the dialog's `blocked` stay; only the line text differs in the F3 case. |
| One name per day (OI-358) | the map is keyed by `exerciseNameKey`; dedupe and the swap/add refusals are not edited. |
| PR detection | not edited in this part (Part P fixes its filter first). |
| 1a/1b completion path | `afterCompletion`, `markCompleted`, `decideCoachDay`, `completeOnTap`, Train's rows and the chat card are not edited; `loggedPlannedExerciseCount` is byte-identical (differential test). |

## C8. Copy

| Where | Text | Status |
|---|---|---|
| `WardroomCopy.activeLoggedInChatLabel` | `LOGGED IN CHAT` | founder-approved |
| `WardroomCopy.activeLoggedInChatSemantics` | `Logged in chat` | derived |
| `WardroomCopy.activeKeepLoggedInChat` | `KEEP AS LOGGED` | founder-approved (F2) |
| `WardroomCopy.activeFinishAllLoggedInChat` | `Everything today is already logged in chat. Re-open an exercise to add sets, or cancel the workout.` | founder-approved (F3) |
| `WardroomCopy.activeFinishNoNewSets` | `No new sets logged this session (warm-ups don't count). Log one to complete, or cancel the workout.` | founder-approved (F4, 2026-11-11) |

## C9. Tests (rule 21)

Fixtures pin the test clock (`setTestClockTo`, reset in `tearDown` with `resetTestClock()`, `lib/core/utils/ist_date.dart:38`). The writer's 60 s dedup uses `DateTime.now()`, NOT the test clock, so fixtures set `logged_at_ms` relative to the REAL clock (`now - 120 s`). Coach rows are written through `WorkoutWriteService.logExercise(source: WriteSource.aiCoach)`. The telemetry seam is `ErrorTelemetry.debugOnLogEventForTests`, reset in `tearDown`.

New `test/contracts/active_workout_logged_in_chat_behavioral_test.dart` (real Hive, as `test/contracts/log_exercise_flip_behavioral_test.dart`):

- **T1 helper:** current-name hit; `swapped_from` hit; the lookup order (current-name row failing `accept` falls to the `swapped_from` row); case/whitespace via `exlogKey`; another date's row is no hit; a 1-set row of a 3-set plan is a hit; `loggedPlannedExerciseCount` differential against a frozen copy; a restored-shape row (`type: exercise_log`, NO `source`, no marker) is not a chat row but IS counted by `loggedPlannedExerciseCount`; **both rows chat-logged (B4-F1):** the current-name row AND the `swapped_from` row both carry the marker with DIFFERENT sets: `loggedName` is the current name and the chips are the current row's (M34's killer).
- **T2 `startWorkout`:** snapshot holds chat rows only; flag OFF gives `{}`; no rows gives `{}`; a past-dated day reads today's rows and does NOT read the past plan row's `swapped_from` (a fixture where the past row's `swapped_from` name has a log today: it must stay plain); `day.date == null` gives an empty `swapped_from` map, no throw, AND the current-name row still maps (M32); a throwing `rawScheduleRow` (the fixture stores a `schedule_<date>` value with a NON-String key, because `rawScheduleRow` does `Map<String, dynamic>.from(...)`) gives `{}`, ONE `outer:` telemetry event, and START still builds state; a duplicated stored name keeps one entry; a restored-shape row opens a plain card; **per-row failure:** two exercises, the BAD coach row FIRST (a direct `workoutBox.put` carrying `source: 'ai_coach'` (or `coach_logged: true`) with `'bad'` in `sets[0]['weight_kg']`, so `ExerciseSet.fromMap` throws inside the snapshot, Hive open, flag ON), the good one second: the good row still maps (the outer catch is NOT what saves it: it would discard the partial map), the bad exercise is plain, `active_workout_chat_snapshot_failed` fires ONCE with `rows=1`; a Red-day drop on a 3-set isolation exercise gives `plannedSets == 2`; name normalisation (`"Bench Press "` finds the row keyed `bench press`).
- **T3 marker and second START:** the chain coach, app, app, then START: coach logs X (2 sets), the user re-opens, adds 1, FINISH, then a second `startWorkout` opens X DONE with 3 chips; a row written only by Train/Active Workout opens plain. Per-clause fixtures for the carry-forward OR in `logExercise`: (a) a MARKED row whose `source` is an app source (after `editLog` or an app append), then a plain re-log: the marker survives (existing-marker clause); (b) a raw pre-ship row with `source: ai_coach` and NO marker: it opens DONE, and a re-log sets the marker (existing-source clause); (c) an `ai_coach` write onto an app-written row sets the marker (incoming-source clause); the test asserts `row['coach_logged'] == true` on the STORED row right after the coach write, before any START (M10c's killer).
- **T4 derived reads:** `isExerciseDone` true, false after `reopenChatLogged`, true after `keepChatLogged`; `allExercisesLogged`; `workingSetCounts` (chat-done `+coachCount` both sides, re-opened, fully chat day `N/N`, `hasSaveableSet` false); `finishGuard` for the C6 rows; `canMoveExercise` false for a chat-done exercise; superset: a chat-done partner is skipped by `supersetPartnerToReveal` (`:448`) and the `:503` LOG outcome treats it as done.
- **T5 re-open and keep:** row count (3 planned/1 coach gives 2; 3/3 gives 1; 2/5 gives 1); an empty per-set list with `set_number: 2` (`coachCount == 2`, no chips, row count and `N/N` use 2); the meta text shows `plannedSets`; the first new row is numbered `coachCount + 1` (widget); `keepChatLogged` refuses once any set is checked, restores `sets`, and clears `warmUpSets`, `setInputValues` and `suggestedInputs` for the index; each guard of both methods has its own refusal case: out-of-range index (the test asserts `false`, NOT a `RangeError`); separate `isSaved`-only and `isComplete`-only fixtures (set directly); wrong name, written out per method: `reopenChatLogged`: the passed name is chat-logged and NOT re-opened, and the slot holds a DIFFERENT chat-logged, NOT re-opened exercise; `keepChatLogged`: the passed name is chat-logged and re-opened, and the slot holds a DIFFERENT chat-logged, re-opened exercise with no checked set. Each fixture satisfies every other guard, so only the wrong-name guard can refuse; the test asserts the slot's state is UNCHANGED (without the guard the method would act on the slot or the passed name and state would change, so the mutants are not equivalent); **`_completing` (R6A-F1):** a mixed day (Y session-logged, X chat), `ActiveWorkoutNotifier.debugBeforeMarkGate` (`train_provider.dart:1470`) held with a `Completer` after `completeWorkout` starts (pattern `test/contracts/coach_completion_counts_behavioral_test.dart:264-265`), assert `isCompleting == true`, `reopenChatLogged` and `keepChatLogged` both return false with state untouched, then release the gate and reset it in `tearDown`; **chat re-open stamps the guard:** after a successful chat re-open a second `reopen` inside `kReopenGuard` is ignored, as for an ordinary exercise; `logSets` / `toggleSet` on a chat-done exercise leave state untouched; the `keepChatLogged` non-chat guard uses a non-chat name that IS in `reopenedExercises` (via `unlogSets(reopened: true)`); the meta text is asserted on a `timed` card and a `bodyweight_reps` card as well as `weight_reps`; `LogExerciseController.reopen` without the new callback behaves as before.
- **T6 swap/add:** swap AWAY from a re-opened X to an unmapped Y gives Y `X.entry.plannedSets`; swap back (UNDO) gives X DONE with `plannedSets` restored; swap TO a mapped name and add of a mapped name are DONE with `sets == plannedSets`; **introduced-name read:** swap/add of a name NOT in the snapshot that has a coach row today opens DONE with its entry (and a miss or a read error leaves a plain card); a re-pick of the same slot is DONE; a name logged today but not read stays plain when the flag is OFF; **introduced-name `plannedSets` (B4-F7):** swapping a re-opened chat X (3 planned, 1 coach, so `sets` 2) to an unmapped Y that has a coach row today gives Y an entry whose `plannedSets` is 3 (X's), not 2; a 1 s timer tick (fakeAsync) keeps `loggedInChat`.
- **T7 FINISH (no double entry):** one chat-logged and one session-logged exercise so `completeWorkout` really runs; (a) the chat row is byte-identical after the real save; (b) re-opened with 2 new sets: the coach's sets (deep-equal) then 2; (c) mixed day; (d) every exercise chat-logged: `completeWorkout` is a no-op.
- **T8 residual pins:** R3 (a `swapped_from` match: re-open + FINISH writes a SECOND row under the slot's name, and on a SECOND START the slot opens DONE showing the original name's sets, because the current-name row is not a chat row and the lookup falls to `swapped_from`); R4; R5; R7 (clock past 00:00 IST between START and FINISH: a snapshot entry for day D, an introduced-name entry read for day D+1 in the same session; new sets save to D+1; no set is written twice); R8.
- **T9 dialog:** `finishBlockedLine`: fully chat day gives the F3 line; chat X + session Y with only warm-ups gives the F4 mixed line; one un-done non-chat exercise with others chat-done gives the F4 line; a single re-opened X with 0 new sets gives F4; X and Y both re-opened gives F4; X swapped out or removed leaving a non-chat warm-up-only day gives the OLD `activeFinishZeroSetBlocked`; a day with no chat exercise gives the OLD line; an empty exercise list gives the OLD line.
- **T10 marker carriers:** `editLog`, a plain re-log, `moveExerciseLogs` collision in BOTH directions (marked existing + unmarked moved, and the reverse; and either `source == ai_coach`), and an `ExlogKeyMigrator` multi-entry group keep `coach_logged`: the collision OR ASSIGNS the boolean (true, or the key removed when false), so "marked existing + unmarked moved" and "unmarked existing + marked moved" are both pinned (the latter is the direction that fails today); one case with only `source == ai_coach` and no marker (the OR clause); the migrator fixture is a 3-member group whose marked member is in the MIDDLE, plus a case where the marked member is the base (the marker survives). **Push bundle (A4-F1):** a real push through `SyncHarness` (`test/sync/sync_domain_skip_harness.dart`), following `test/sync/exlog_push_u3_behavioral_test.dart`, compares the captured `workout_log_exercises` and per-set payloads for a row with and without `coach_logged`: identical.

Widget tests (`test/features/train/log_exercise/log_exercise_card_logged_in_chat_test.dart`, `card_harness.dart`): the button and `TAP TO RE-OPEN`; chips for `weight_reps`, `timed`, `cardio`; the stepper hidden; re-open shows rows, eyebrow, `KEEP AS LOGGED`; checking a set hides it; a checked WARM-UP-only new row hides KEEP and `keepChatLogged` returns false, the mirror with an UNCHECKED warm-up row shows KEEP and it works (both read `hasCheckedRow`); the chat branch wins over a FORCED validation failure (a blank weight controller); review mode (`isSaved`): the chat button has no tap and there is no KEEP action; the viewer host with a STALE `widget.data` (no chat entry) and a fresh `data` shows the chat state; Semantics via `semanticsLabel`; 360 dp and 1024 dp. Screen test: focus skips the chat card; header `N / N SETS`. Dialog test: the C6 rows.

### Planned mutations (confirm each applied with `grep -c`; a compile error is not proof)

| # | File: exact edit | Expected red |
|---|---|---|
| M1 | `train_provider.dart` `isExerciseDone`: delete the `isChatLoggedDone` early return | T4, card test |
| M2 | `train_provider.dart` `startWorkout`: also write each coach set into `checkedSets` and `setInputValues` | T7(a), T7(b) |
| M3 | `log_exercise_logic.dart` `workingSetCounts`: add `coachCount` to `total` but not `saved` for a chat-done exercise | T4 counts, dialog and screen tests |
| M4 | `log_exercise_logic.dart` `finishGuard`: drop the top-of-loop chat-done `continue` | T4, dialog test |
| M5 | `train_provider.dart` `copyWith`: remove the `loggedInChat:` line | T6 timer tick |
| M6 | `train_provider.dart` `startWorkout`: date from `day.date` instead of `resolveSessionDate` | T2 past-dated |
| M7 | `coach_day_completion.dart` `loggedNameForPlannedExercise`: remove the `swapped_from` branch | T1 swapped fixture, differential |
| M8 | `chat_logged_exercises.dart`: drop `accept: isChatLoggedRow` | T1, T2 plain-card row, T3 |
| M9 | `chat_logged_exercises.dart` `isChatLoggedRow`: remove the `coach_logged` clause | T3 |
| M10a | `workout_write_service.dart` `logExercise`: drop the existing-marker clause of the carry-forward OR | T3 fixture (a) |
| M10b | `logExercise`: drop the existing `source == 'ai_coach'` clause | T3 fixture (b) |
| M10c | `logExercise`: drop the incoming `source == aiCoach` clause | T3 fixture (c) |
| M9b | `chat_logged_exercises.dart` `isChatLoggedRow`: remove the `source == ai_coach` clause | T3 fixture (b), T1 |
| M11 | `train_provider.dart` `reopenChatLogged`: remove each guard in turn (bounds, `_completing`, saved, complete, wrong name, non-chat, already re-opened): seven mutants | the matching T5 refusal case, one each |
| M12 | `reopenChatLogged`: do not add the name to `reopenedExercises` | T4, T5 |
| M13 | `reopenChatLogged`: do not reduce `sets` | T5 row-count cases |
| M14 | `train_provider.dart` `startWorkout`: remove the PER-ROW `try/catch` (the outer guard only; it discards the partial map) | T2 per-row failure (bad row first: the good row is lost) |
| M15 | `train_provider.dart` `keepChatLogged`: remove each guard in turn (bounds, `_completing`, saved, complete, wrong name, non-chat, not re-opened, checked-set): eight mutants | the matching T5 case, one each |
| M16 | `keepChatLogged`: do not restore `sets = plannedSets` | T5 |
| M17 | `swapExercise`: do not override the incoming `sets` with `entry.plannedSets` | T6 |
| M18 | `addExercise`: do not override the incoming `sets` with `entry.plannedSets` | T6 add |
| M19 | `swapExercise`: re-derive `plannedSets` from the incoming exercise, or give Y the reduced `sets` when swapping away from a re-opened X | T6 swap away / UNDO |
| M20 | `workingSetCounts`: drop `coachCount` from the re-opened branch's `saved` | T4 counts |
| M21 | `workingSetCounts`: drop `coachCount` from the re-opened branch's `total` | T4 counts |
| M22 | `chat_logged_exercises.dart`: key the snapshot map by the raw name | T2 normalisation |
| M23 | `exercise_card.dart` `_buildLogRow`: move the chat branch after the validation scan | card test (forced validation failure) |
| M24 | `exercise_card.dart`: read `widget.data` instead of the `data` parameter in a builder | viewer-host stale-data test |
| M25 | `exercise_card.dart`: `setNumber: setIdx + 1` without `+ coachCount` | T5 numbering |
| M26 | `exercise_card.dart`: reduced `sets` for a re-opened chat card in `_metaTextForLogMode`, and again in `_metaText` (two mutants) | T5 meta text (`weight_reps`; `timed` and `bodyweight_reps`) |
| M27 | `finish_dialog.dart` `finishBlockedLine`: `any` chat-done instead of `every` for the F3 line | T9 (chat X + session Y warm-ups gets the F3 line) |
| M28 | `finishBlockedLine`: evaluate the F4 "any entry" clause with `data.loggedInChat.isNotEmpty` instead of the live list | T9 (X swapped out or removed leaves a non-chat warm-up-only day: must be the OLD line) |
| M38 | `finishBlockedLine`: drop the `exercises.isNotEmpty` clause of the F3 line | T9 empty list |
| M39 | `finishBlockedLine`: drop the "some live slot has a chat entry" clause of the F4 line (every non-F3 case gets F4) | T9 no-chat day |
| M44 | `finishBlockedLine`: test `isChatLoggedDone` instead of `isChatLogged` in the F4 clause | T9 single re-opened X, X and Y re-opened |
| M45 | `keepChatLogged`: do not clear `warmUpSets` / `setInputValues` / `suggestedInputs` for the index | T5 keep-clears test |
| M30 | `coach_day_completion.dart` `loggedNameForPlannedExercise`: break the ordered lookup / the `!= null` composition (for example `&&` for the two names, or `is Map` in the `accept == null` path) | the T1 differential test (killer), `test/contracts/coach_day_completion_behavioral_test.dart` |
| M46 | `train_provider.dart`: remove the `isChatLoggedDone` early return from `logSets` (then from `toggleSet`; two mutants) | T5 `logSets` / `toggleSet` case |
| M47 | `exercise_card.dart`: KEEP visibility switched to `saveableSetIndexes(i).isEmpty` instead of `hasCheckedRow` | the warm-up-only widget test |
| M48 | `train_provider.dart` chat re-open route: do not stamp `_lastAdvanceAt` / `_lastAdvanceWindow` | the T5 guard-stamp case |
| M31 | `chat_logged_exercises.dart`: `coachCount = sets.length` only | T5 empty-per-set-list case |
| M32 | `train_provider.dart` `startWorkout`: call `rawScheduleRow(day.date!)` without the null guard | T2 `day.date == null` |
| M33 | `swapExercise` / `addExercise`: drop the introduced-name read (two mutants) | T6 introduced-name case |
| M34 | `loggedNameForPlannedExercise`: check `swapped_from` before the current name | T1 both-rows-chat-logged case (B4-F1), T8 R3 second START |
| M35 | `workout_write_service.dart` `moveExerciseLogs` collision: drop the existing side, then the moved side, of the assigned OR (two mutants) | T10: "marked existing + unmarked moved" kills the first, "unmarked existing + marked moved" the second |
| M36 | `exlog_key_migrator.dart` group merge: three mutants, "base only (today)", "first only", "middle only" (take the marker from that member alone) | T10 3-member group, distinct `updated_at_ms` so the marked member stays in the MIDDLE after the sort; the base-marked case stays green under "base only" |
| M37 | `lib/core/services/sync/sync_workout.dart` (`_buildExlogPushBundle`): include `coach_logged` in the pushed bundle | T10 `SyncHarness` payload test |
| M40 | `swapExercise`: take the introduced entry's `plannedSets` from the incoming exercise's own `sets` instead of the overridden sets | T6 introduced-name `plannedSets` |
| M41 | `moveExerciseLogs` / migrator: drop the `source == ai_coach` clause of the OR | T10 source-only case |
| M42 | `exercise_card.dart` chat branch: give the review-mode button an `onTap` (or show KEEP in review mode) | card review-mode test |
| M43 | `startWorkout`: remove the OUTER guard (only per-row guards remain) | T2 throwing `rawScheduleRow` |

Existing tests to keep green (repoint only, never loosen): `active_workout_resume_guard_behavioral_test`, `session_date_and_home_start_behavioral_test`, `active_workout_set_logging_behavioral_test`, `log_exercise_flip_behavioral_test`, `coach_completion_counts_behavioral_test`, `active_workout_exercise_order_behavioral_test`, `exercise_name_unique_in_day_behavioral_test`, `train_provider_reads_set_number_dual_name_test`, `coach_day_completion_behavioral_test`, `coach_day_completion_rule_writer_to_reader_test` (all under `test/contracts/`) and everything in `test/features/train/log_exercise/`. Before any move or rename grep `test/` and `docs/` for source pins on `train_provider.dart`, `active_workout/`, `reopenedExercises`, `workingSetCounts`, `finishGuard`, `activeFinishZeroSetBlocked`. Whole gate loop before each review dispatch (§4.12.5/8).

## C10. Docs, registry, gates

- **SoT registry:** new concept `active_workout_logged_in_chat` (writers: the `startWorkout` snapshot, the introduced-name read, `reopenChatLogged`, `keepChatLogged`, the swap/add `sets` override, `chatLoggedSnapshot`, and `logExercise` plus the two merge paths for the marker; readers: `isExerciseDone`, `allExercisesLogged`, `workingSetCounts`, `finishGuard`, `finishBlockedLine`, the card), `behavioral_test_path:` the T-file. Update `active_workout_set_logging` (near `:13520`), `coach_day_completion_rule` (near `:6669`), `hive_field_name_exlog` (`coach_logged`). Recompute `line_range` per commit.
- **Nested CLAUDE.md:** `lib/features/train/CLAUDE.md` (new concept row; `hive_field_name_exlog` gains `coach_logged`); `lib/core/services/CLAUDE.md` (`WorkoutReadService.exerciseLogRow`, the marker). `docs/architecture/train-detail.md`: detail.
- **Glossary (`docs/naming_conventions.md`):** `loggedInChat`, `ChatLoggedExercise`, `coachCount`, `chatLoggedSnapshot`, `isChatLoggedRow`, `chatLoggedLabel`, `reopenChatLogged`, `keepChatLogged`, `loggedNameForPlannedExercise`, `exerciseLogRow`, `coach_logged`, `finishBlockedLine`, `chatLoggedChips`, `active_workout_chat_snapshot_failed`, `LOGGED IN CHAT`, `KEEP AS LOGGED`.
- **Copy:** five constants in `lib/core/copy/wardroom_copy.dart`.
- **Gate 19 (A5-F1):** `scripts/check_hive_map_field_drift.dart` — add `coach_logged` to the `'exlog'` emit set (`:65`) in the SAME commit (the writer, the snapshot and `chat_logged_exercises.dart` read or write it).
- **Files touched (Part 1c):** `lib/core/services/workout_read_service.dart`, `lib/core/services/workout_write_service.dart`, `lib/core/services/exlog_key_migrator.dart`, `lib/features/train/services/coach_day_completion.dart`, `lib/features/train/services/chat_logged_exercises.dart` (new), `lib/features/train/services/log_exercise_logic.dart`, `lib/features/train/providers/train_provider.dart`, `lib/features/train/screens/active_workout/{exercise_card,screen,finish_dialog}.dart`, `lib/core/copy/wardroom_copy.dart`, `scripts/check_hive_map_field_drift.dart`, the tests, the registry, the nested CLAUDE.md files, the glossary.
- **Diagnose doc:** none (feature commit); a slim one only if a review round forces a `fix(...)` commit.
- **B-pass** `/code-review` before the merge.
- **Device check before the merge:** log 2 of 3 sets of one exercise in chat; START: `LOGGED IN CHAT` with those sets; re-open (1 new row numbered 3), log it, FINISH: 3 sets, none doubled; START again: DONE with 3 chips; `KEEP AS LOGGED` restores DONE; a fully chat-logged day shows the new dialog line and COMPLETE disabled; web too.

## C11. Accepted residuals

| # | Residual | Pin |
|---|---|---|
| R1 | A chat log made while Active Workout is open does not appear until the next START (no re-sync). A coach log REMOVED after START leaves its card DONE until the next START too. Delete doors: `WorkoutWriteService.deleteLog` (`workout_write_service.dart:1446`) has no caller in `lib/` (grep), so no UI delete is reachable mid-session; the coach tool that moves a day's logs (`lib/features/ai_coach/services/tool_dispatcher.dart:780`, `moveExerciseLogs`) can relocate them. FINISH still saves only the newly checked sets, so no set is written twice; the worst case is the user entering that exercise again by hand, which appends to the coach's row. | T7 with a row added after START |
| R2 | A fully chat-logged day is not completed from Active Workout (zero-set block stays). | T7(d), T9 |
| R3 | A `swapped_from` match: the card shows the original name's sets under the slot's name; a re-open + FINISH writes a SECOND row under the slot's name; a second START opens the slot DONE showing the original name's sets. | T8 |
| R4 | `logExercise` rebuilds the row and drops old `notes`: an Active Workout append drops a coach note. | T8 |
| R5 | The completion sheet (`N SETS LOGGED`) and `liveVolumeKg` count only this session's sets (the header and FINISH count line include the coach's). The receipt reads Hive and includes the coach's. | T8 |
| R6 | Cloud-restored rows carry no `source` and no `coach_logged` (the cloud table has no such column; the exlog restore writes neither), so on a device that restored the day they open as a plain card: no regression versus today; a cross-device label would need a schema column. A row the app wrote and the coach then appended to carries `coach_logged` and opens DONE with the app's sets too. | T1, T2, T3 |
| R7 | A session that crosses 00:00 IST can hold entries from two days: snapshot entries for day D, an introduced-name entry read for day D+1; new sets save to the new day's row. Never a double save. | T8 |
| R9 | A coach row written BEFORE this ships has no `coach_logged` marker; if it is then edited in the sheet (`editLog` overwrites `source`) it stops being a chat row and opens plain. A coach row edited down to 0 sets opens DONE with `coachCount` 0 (no chips, `0` on both sides of the count). | T10 |
| R10 | If the `enable_log_exercise_button` flag is flipped OFF mid-session (debug only), `loggedInChat` keeps its snapshot for the rest of that session. | none (debug-only) |
| R8 | The writer's 60 s exact-duplicate dedup can drop an identical real set logged within at most 60 s of the chat log. | T8 |

## C12. Open questions

None. Settled by the coordinator (2026-11-11): `SyncHarness` captures pushed rows through `h.server.writesTo('workout_log_exercises')` (used at `test/sync/exlog_push_u3_behavioral_test.dart:100`), so the T10 push test compares those captured rows (and the per-set table's, via the same `writesTo`) with and without `coach_logged`. There is no fallback: `_buildExlogPushBundle` is library-private and cannot be called from a test.
