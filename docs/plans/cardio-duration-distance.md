---
plan: cardio-duration-distance
revision: 12
date: 2026-10-22
blast_radius: account   # classifier on Batch 1a's file set (32 paths checked in round 3; no sync/**, schema or EF)
tier: L                 # §4.12.6 literal: the diff edits auth_session_bootstrapper.dart (the heal's per-set table, U8) and lib/features/train/CLAUDE.md (round 3 A P3-9). Same full pipeline as M.
execution_mode: inline  # §4.12.7; one worktree (.claude/worktrees/cardio-duration-distance)
closes_oi: [OI-380, OI-382]
advances_oi: [OI-389]   # the active-workout path and every reader; OI-389 stays OPEN until Batches 1b, 2 and 3 land
---

# Batch 1a: a cardio or distance exercise logged in the workout screen keeps its minutes and km, and every screen shows them

## Revision history

**rev 1 → rev 2.** Round 1 found 5 P1s. Fixed in rev 2:
- the hint for non-library names;
- the LogWorkoutSheet writer;
- §4.6;
- the order of live steps;
- the clamp parity test.

**rev 2 → rev 3.** Round 2 found 4 P1s in exposure (A converged):
- refusals were silent or showed raw codes;
- StatsGrid and graduation would print "1800 km";
- the coach prompt still routes cardio wrongly;
- rollback could not be run.

Rev 3 split the work into three batches: app, cloud cap, coach tool.

**rev 3 → rev 4.** Round 3 found 2 P1s (A):
- **P1-1:** the km total and the empty-set check run in the wrong order relative to the 60-second dedup. That
  double-counts on a retry.
- **P1-2:** a refused coach exercise counted as `skipped` makes the chat card say "Workout logged" when nothing was
  saved.

The two P1s sit in different halves of Batch 1: the core writer, and the coach paths that the new empty-set guard
feeds. **§4.12.1 again:** Batch 1 splits into **1a**, this plan, and **1b**.

- **1a (this plan):** the writer core, the active workout, every reader, and the boot heal (rev 6: only the heal's
  zeroing; see rev 5 → rev 6).
- **1b: coach paths.** Type hint, customBox lookup, empty-set guard, chat card, dispatcher, LogWorkoutSheet, confirm
  card. It gets its own plan and review rounds.

1a does not change the coach paths' behaviour for the worse (§3, "Coach paths in 1a"). The coach-side fixes from
rounds 1–3 are kept as inputs in §9.

**Batches 2 and 3** (cloud cap, `logCardio` tool) are unchanged from rev 3.

**rev 4 → rev 5.** Round 3 B (exposure) landed after rev 4 was written.
- **Its two P1s were already resolved by rev 4:**
  - the dedup order is in U3;
  - the `logSet` cardio refusal moved to 1b with the coach paths (§9.1 now carries B's before-APPLY design).
- **Its P2s are folded in:**
  - sub-km and zero-part rendering (U7);
  - the window when a >60 min set reads 60 min on a second device (§0, D8);
  - a mutation for every changed behaviour (§4);
  - board and ledger state (§5);
  - tracking for the snapshot switch (§5);
  - four more SoT concepts (§5);
  - every user-facing string written out (U5, U7);
  - the value-semantics sweep recorded (§2).
- B P2-4 (customBox vs slot precedence) belongs to 1b (§9.1). 1a has no customBox lookup.

**Board** (round 3 B P2-6):
- OI-389 stays OPEN for 1b, which ends its last defect.
- Batches 2 and 3 each get their own OI, minted at the start of this batch. Their "Blocked on" names only the founder
  action: the live migration apply for Batch 2, the ai-proxy deploy for Batch 3.
- The closure ledger marks 1b, 2 and 3 `blocked_on_user` and cites their OIs. Precedent:
  `docs/audit/active-workout-log-exercise.closure.yaml`, FOLLOW-ON-BATCHES.
- Each batch gets its own branch, because the plan-review record is keyed by branch.

**rev 5 → rev 6.** Round 4 found one P1 in each review, plus P2s:
- **A P1-1:** the restore-shape lift (U3 step 1) collapses a multi-set summary-only row into one set and breaks
  `reschedule_week_terminal_row_test.dart:429-503` (e8f4a3 B1, preserve-don't-shrink).
- **B P1-1:** U2's table clears reps on a `cardio`/`distance` set that carries neither minutes nor km. Coach `logSet`,
  `LogWorkoutSheet` and the chat card send exactly that for Farmers Carry or Sled Push, so 1a would erase the only
  figure the user gave (`4 sets · 40 reps · 40.0 kg` → `4 sets · 40.0 kg`).
- **B P2-2:** fixing the heal's cast (U8) makes a heal live on every sign-in with no kill switch, no aggregate
  recompute, no `sets_detail` rewrite and no `updated_at_ms`.

The lift has drawn findings in rounds 3 and 4, and the live heal in round 4. Neither is what OI-380/382 are about,
and neither has a live row to act on (round 4 B: 0 restore-shaped rows, 0 type-mismatched rows). **§4.12.1 again:**
both leave 1a.
- **The lift → OI-393 (d)**, "a set logged on top of a restore-shaped (or F5: sets lacking a field beside its
  top-level total) exlog row resets its totals". That loss exists
  today for every aggregate (`workout_write_service.dart:228-231`: `set_number` = `cleanedSets.length`), so 1a
  leaves it exactly as it is and does not add km to it by design (U3).
- **The live heal → OI-394 (e)**: cast fix, kill switch `disable_exlog_type_heal`, recompute, `sets_detail`,
  `updated_at_ms`, `keys.toList()`. 1a keeps the heal's footprint as today (the cast is unchanged) and only stops it
  zeroing cardio minutes where it does run (U8).
- **The reps rule (B P1-1)** is a one-line rule in U2: a `cardio`/`distance` set with neither minutes nor km keeps its
  weight and reps, as today. 1b converts those sets at dispatch.

Everything else from round 4 is folded in (§8): the U3 order, the reader's rounding, the formatter separator and empty
case, the per-side km in the move merge, `editLog` validation order, the split ratification (D10), the snapshot
switch's tracking, and the missing mutations (M26–M35).

**rev 6 → rev 7.** Round 5 A (ground truth) converged with eight P2s; round 5 B (exposure) found one P1 and five P2s.
Both are folded in. The A P2s that B did not also raise:
- **A P2-6:** U2's cardio row cleared a weight the coach can send with a duration (chat-card "Sled Push 3 × 30 s @
  100 kg"), and a distance set with a duration lost its reps. The table now never clears weight on cardio or distance,
  and clears reps only when the set carries its type's own field (U2).
- **A P2-1:** the heal must edit in place and must not go live by accident. A footprint pin now proves a disk row
  (`Map<dynamic, dynamic>`) is byte-unchanged (U8, T10b, M54).
- **A P2-5:** M34 could not redden T26 (old and new text matched). New fixture.
- **A P2-7:** the receipt's fallback `_exerciseDetail` (`workout_receipt_card.dart:810-830`) was not named and prints
  `0.0 km`. Now routed through the formatter pair.
- **A P2-8:** only the preview's cardio and distance branches delegate; its separator stays a plain space.

The B findings follow.
- **B P1-1:** rev 6's move-merge km term (`aggregateDistanceKm(existing) + aggregateDistanceKm(row)`) is invisible on
  the mixed shape T19(a) named. The reader prefers the per-set sum, and the merged per-set list holds only the
  per-set side's km, so every screen reads 3.0 while the cloud summary says 8.0. Fixed: the merge writes the sum over
  the merged per-set list when that list carries km; the per-side top-level sum only when **neither** side has a
  per-set list (the reader then falls through to it); otherwise no key. The mixed shape (one restore-shaped side,
  one per-set side) joins OI (d) with its duration twin. 0 live rows (round 5 B: the 55 summary-only cloud rows are
  all soft-deleted).
- **B P2-1:** `editLog` bounded the top-level TOTAL against a per-set limit, so 2 × 210 min would be refused forever.
  Bounds now apply to per-set values only; the legacy path bounds its total at the per-set limit × max(1, set count).
- **B P2-2:** the edit sheet writes `distance_km: 0` and erases an F5 top-level total. The sheet gets the same guard
  it already has for duration (`edit_workout_log_sheet.dart:986-996`), and sends km only when it means it.
- **B P2-3:** the legacy-path MIN box kept a seconds hint ("90" → "= 1m 30s"). The cardio hint now reads minutes.
- **B P2-4:** `exerciseLogDetail` had two set-count rules. Now one rule per type, and every expectation follows it.
- **B P2-5:** custom cardio in the active workout is still resolved `timed` from its data shape and loses km. 1a now
  passes the slot's type as a hint, consulted only when the library misses (U3 step 1). 1b keeps the
  customBox-vs-slot precedence.
- B's P3s are folded in (§8).

**rev 7 → rev 8.** Round 6 A (ground truth) converged with two P2s, folded in:
- **A P2-1:** the move merge's "else remove" branch dropped a km that today keeps and shows consistently (a
  restore-shaped or F5 side beside a per-set side without km). The second branch now applies whenever the merged
  per-set list carries **no** km, and writes the per-side top-level sum; the reader falls through to the top level in
  exactly that case, so the reader and the push still agree, and km is preserved (T19(e), M56).
- **A P2-2:** M53 (MIN box back to decimal) had no test that could redden. A widget test on `SetInputRow` now pins the
  cardio box's digits-only input.
- **Round 6 B** raised A's P2-1 as its P1 (same shape, same fix) plus two P2s:
  - **B P2-1:** the merge leaves the destination's stale `sets_detail`, which the push prefers
    (`sync_service.dart:2651-2664`), so per-set rows and the summary disagree. The merge now removes `sets_detail`
    whenever it writes `sets` (M58).
  - **B P2-2:** the hint was not sticky. A later same-day write without a hint (chat card, `logSet`) re-resolved a
    custom cardio row to `timed` and cleared its km. Resolution now consults the existing row's stored type after the
    hint, for `cardio`/`distance` only (T28b, M39b).
- A's P3s are folded in: the hint is consulted only when it is `cardio` or `distance`; 1b's W16 guard moves into 1a,
  because 1a now creates custom cardio rows; the legacy km box follows the duration twin's blank-text rule; mutation
  legs corrected (§8).

**rev 8 → rev 9.** Round 7: **A and B both CONVERGED** (no P0/P1; B one P2, A P3s). Folded in:
- **B P2-1 / A P3-1 (same finding):** the merge read each side from `sets` only, so removing `sets_detail` dropped a
  legacy destination whose per-set list lives only in `sets_detail` (pre-Test-#6, or the OI-50 `sets: []` +
  `sets_detail` shape). Each side's merge list is now the reader's own resolution: the longer of `sets` /
  `sets_detail` (`_perSetList`, made public as `perSetList`), with `duration_seconds` translated to `duration_sec` as
  `editLog` does (`workout_write_service.dart:1194-1203`). Removing `sets_detail` is then lossless (T19(g), M62).
- The P3s: the legacy km box's emptied-prefill case sends `null`; T8's cleared leg asserts on `editSheetUpdatesFor`'s
  output, plus a legacy leg where `0` vs `null` reaches the row; T19 names its payload seam; short cardio under 30 s
  sends `duration_sec` to the coach instead of nothing; missing assertions for the Sled Push count, the partial-failure
  invalidation and the coach weight × reps log on a custom cardio row; the SEC box's 4-digit limit recorded; F5 named
  in OI (d)'s scope; two misplaced sentences moved.

**rev 9 → rev 10: founder decisions (2026-10-22).** The founder approved the plan and answered §6:
- **D2 changed:** cardio minutes may be typed with decimals. Seconds are the stored unit, so "12.5" min is stored as
  exactly 750 s and nothing is lost. U5 (box, validator, conversion), U7 (display in decimal minutes) and the tests
  change accordingly; a delta review round covers it.
- **D8 accepted**, **D10 confirmed** (order 1a → 1b → Batch 2 → Batch 3; (d) and (e) planned separately),
  **D9 go** to mint the four OIs. D4 is explained to the founder and awaits a yes.

**rev 10 → rev 11.** The D2 delta round: **A and B both NOT CONVERGED on one shared P1.** Rev 10 changed the
validator and the converter but not the path between them: the workout card captures the MIN box with
`int.tryParse` into `SetInputValues.durationSeconds` (`exercise_card.dart:699`, field `int?` at
`train_provider.dart:1213`), so "12.5" was captured as null and saved silently with no minutes. Fixed in U5 by
**converting at capture**: `durationSeconds` now always holds true seconds, for every type, through one shared parser.
Set inputs are session-only (`active_workout_persistence.dart` does not serialise `SetInputValues`), so nothing stored
is reinterpreted. Also folded in: the edit sheet's cardio fields take decimals and use the same parser (B P2-1); the
sheet prefills decimal minutes even under 60 s (B P2-2, A P3-2); the snapshot sends one-decimal minutes, so the coach
and the screen agree (A P3-3, B P3); no trailing-dot trim (A P3-1); a message for a value that rounds to 0 s; a stale
"digits only" line fixed.

**rev 11 → rev 12.** Delta round 2: **A and B both CONVERGED.** B's one P2 (malformed or sub-second minutes in the
edit sheet saved as 0) and both reviewers' P3s are folded in (§8, "Delta 2" rows).

## 0. Evidence

**OIs:**
- **OI-389:** cardio minutes are zeroed, and km is never stored.
- **OI-380:** a distance row reads `N sets · 0 reps · X kg`.
- **OI-382:** negative duration or km is accepted.

**Live data** (read-only, `dedsavbjuwgarrhphgnl`):
- 0 rows of type cardio or distance, ever.
- 0 rows with km.
- `workout_log_sets` has 715 rows; `duration_secs` ranges 1..60.
- `wls_duration_secs_realistic` is `0..3600 NOT VALID`.

**Library names:**
- cardio: `Running (Treadmill)`, `Cycling (Stationary)`, `Rowing Machine`, `Assault Bike`, `Sled Push`,
  `Prowler Push`;
- distance: `Farmers Carry`, `Suitcase Carry`, `Zercher Carry`, `Yoke Walk`.

**No cloud repair is needed.** Phone rows stored as 0 cannot be recovered. These are test accounts, pre-launch.

**Before Batch 2:** a set longer than 60 min is clamped to 3600 in the cloud per-set row (telemetry
`wls_duration_out_of_range`). Hive keeps the full value.
- **Any other device on the same account** (web plus Android, not only a reinstall) restores 3600. It reads 60 min
  everywhere, because `aggregateDurationSeconds` prefers the per-set sum.
- An edit or re-log on that device makes 3600 permanent for that row.
- Batch 2's clamp change re-pushes only rows whose Hive still holds the full value: the fingerprint covers the bundle
  (`sync_workout.dart:461-463`).
- The on-device check deliberately tests one >60 min set on a single device and records the result (D8).

## 1. Writers and readers (main `cbfa8884`)

### Writers in 1a

| # | Where | Defect |
|---|---|---|
| W1 | `workout_write_service.dart:337-361` `_normalizeSetsByLoggingType` | non-`timed` ⇒ `durationSec: 0` (`:357`) |
| W2 | `write_result.dart:108-158` `ExerciseSet` | no distance; dedup ignores distance |
| W3 | `workout_write_service.dart:212-237` entry | no `distance_km`. (It also rebuilds from scratch, so it drops a restored row's top-level aggregates and resets `set_number`. That is today's behaviour for every aggregate and goes to OI-393 (d); rev 6.) |
| W4 | `workout_write_service.dart:150,168,343,353,384,394` | hand copies |
| W5 | `train_provider.dart:2222-2236` `completeWorkout` | drops km |
| W6 | `exercise_card.dart:699` + `set_input_row.dart` cardio MIN | minutes stored as seconds |
| W7 | `workout_receipt_card.dart:224-236` | minutes as seconds; phantom reps on distance slots |
| W10 | `workout_write_service.dart:1205-1222` `editLog` | per-set distance dropped |
| W11 | `auth_session_bootstrapper.dart:1208-1217` heal | zeroes cardio duration. **It never runs on a row read from disk:** `.cast<Map<String, dynamic>>()` throws on Hive's `Map<dynamic, dynamic>`, and the outer catch swallows the error (round 3 A, probed). It does run on a row still held in memory as `Map<String, dynamic>` in the same process (a row restored or written earlier in that run). 1a fixes only the zeroing (U8); making it live is OI-394 (e) |
| W15 | `workout_write_service.dart:1029-1048` move merge | keeps the destination side's top-level km only (`Map.from(existing)`) |

### Readers in 1a

- **expanded row:** `expanded_exercises.dart:72-97`
- **week selector:** `week_selector.dart:847-858`
- **chips:** `ward_set_chips.dart:89-93`
- **receipt:** both builders, `workout_receipt_card.dart:224-236,416-446`; `_buildSetChips` `:783-790`; the chip
  `fallbackLabel` `_exerciseDetail` `:810-830` (renders every restore-shaped cardio/distance row; today prints
  `30 min · 0.0 km`), routed through the formatter pair (round 5 A P2-7)
- **preview:** `exercise_preview_sheet.dart:150-175` (cardio branch `:172-175`)
- **edit sheet:** `edit_workout_log_sheet.dart:164,184-188,505,671,864-867,983,1043`
- **PR:** value `workout_repository.dart:869-895`, formatter `:49-56`, `ExercisePR` `:29` (const constructor)
- **StatsGrid:** `stats_grid.dart:51-66,166-195,385`
- **graduation:** `train_provider.dart:2648`
- **AI snapshot:** `ai_snapshot_builder.dart:1164-1197`

**Push (unchanged):**
- The summary `distance_km` is the top-level value (`sync_workout.dart:455`).
- Per-set values come from `_resolvePerSetList` (`sync_service.dart:2644`).
- Restore writes both (`sync_workout.dart:1115-1116,1147-1148`).
- **No reader treats seconds as minutes.**
- Swap carries no phantom value (`train_provider.dart:1752-1778`; `exercise_card.dart:340-343`).

## 2. Bug history (§4.1.5)

- **a4c7d1:** its else-branch is the root cause. Its test is a placeholder, which T3 replaces.
- **e8f95e:** type guessed from data shape. That fix is 1b's.
- **d4e7c2**, by path `docs/diagnoses/2026-08-02-restored-exlog-aggregate-read-d4e7c2.md`: two writers write
  different field subsets. W3 is a new instance: a merge over a restore-shaped row drops its aggregates.
- **6e1b45:** a field dropped by a copy.
- **OI-382** seam: see T22.
- **New in round 3:** W11 has been **dead in production** for rows read from disk, because of the cast. The
  diagnose-doc records it, and OI-394 (e) carries the live heal.
- **Verified, no change** (round 5 A P3-1): `logging_type_repair_migrator.dart` (library cardio/distance fall through
  its switch, `:221-424`, label only); `exlog_restore_rules.dart:149`; the push's summary `duration_seconds` is computed
  for `timed`/`cardio` only (`sync_workout.dart:400-410`), so a distance row's duration travels per set only;
  `train_provider.dart:2105` `bestDurationMap` is unused for cardio; `pr_snapshot.dart:214` splits `formattedValue` on
  a space. Cardio durations now print as one token in decimal minutes (`12.5 min`, U7), so the split is correct.
- **`exlog_key_migrator.dart` is not a 1a writer.** It only regroups keys in the pre-W-key format, which no
  distance writer has ever produced; its `...base` spread keeps a top-level `distance_km` and its concatenated sets keep
  per-set `distance_km` verbatim (raw maps). Recorded, no change (rev 6; it was W15 in rev 5).
- Full template.
  `related_bugs: [a4c7d1, e8f95e, 6e1b45, docs/diagnoses/2026-08-02-restored-exlog-aggregate-read-d4e7c2.md]`.

## 3. The fix (Batch 1a)

### U1: `ExerciseSet` (`write_result.dart`)

- Add `double? distanceKm`. `toMap` writes `distance_km` when non-null; `fromMap` reads it.
- **A km ≤ 0 is stored as null** (`exerciseSetFromInput`, the normaliser and `fromMap` all canonicalise), so `0.0` and
  absent never differ in dedup or on the push (round 4 A P3).
- `isDuplicateWithin` compares distance.
- `copyWith({…, bool clearDuration = false, bool clearDistance = false})`.
- Every rebuild in `workout_write_service.dart` goes through it. A presence-only source-grep guard checks this.

### U2: validation and normalisation (`workout_write_service.dart`)

**Validation**, with weight and reps (closes OI-382):
- `durationSec` must be 0..21600 (`kMaxSetDurationSec`).
- `distanceKm` must be 0..300 (`kMaxSetDistanceKm`).
- A failure returns a new `WriteResult.invalid(code, message)`. `WriteResult` gains a `code` field. Codes:
  `duration_out_of_range`, `distance_out_of_range`.
- Validation reads the **raw** values, before km ≤ 0 is canonicalised to null, so a negative km is refused and never
  silently dropped (round 5 A P3-4). In `logExercise` it reads the incoming `ExerciseSet` fields; in `editLog`, the raw
  update maps.
- `editLog` validates the same bounds, **per set** (round 5 B P2-1). The check runs **after** the `sets_detail` →
  `sets` translation (`workout_write_service.dart:1179-1222`), so a value arriving through `sets_detail` is validated
  too (round 4 A P3).
  - With a per-set list in the update: every set's `duration_sec` ≤ 21600 and `distance_km` ≤ 300. The top-level
    totals the sheet sends alongside (`edit_workout_log_sheet.dart:158-166`) are **not** bounded, so 2 × 210 min
    saves.
  - Legacy path (top-level only, no per-set list): the total is bounded at the per-set limit × max(1,
    `aggregateSetCount`).

**Normaliser table** (`_stripPhantomFields` mirrors it):

| type | keeps | clears |
|---|---|---|
| `timed` | duration | weight 0, reps 0, distance |
| `cardio` | duration, distance, weight | reps 0 **only when** the set carries a duration or a km |
| `distance` | distance, weight, duration if given | reps 0 **only when** the set carries a km |
| weight types | weight, reps | duration (as today), distance |

**The reps rule** (round 4 B P1-1, round 5 A P2-6): weight is never cleared on a `cardio` or `distance` set, and reps
are cleared only when the set carries its type's own field (cardio: a duration > 0 or a km > 0; distance: a km > 0).
A set without that field keeps its weight and reps unchanged, which is what today's else-branch does for it. So no
route loses a figure it keeps today: "Sled Push 3 × 30 s @ 100 kg" from the chat card keeps 100 kg and now also keeps
the 30 s (today it zeroes the 30 s). Coach `logSet`,
`LogWorkoutSheet` and a chat-card draft not typed `cardio` produce exactly that set for Farmers Carry, Sled Push and
Prowler Push. 1b converts those sets at dispatch; until then 1a must not erase the figure the user gave.
`_stripPhantomFields` applies the same rule. Test T23, mutation M31.

**No empty-set guard in 1a.** It belongs with the coach paths that can reach it (1b). The active workout cannot
produce an empty set: `validateSetInputs` requires each type's field.

### U3: order of operations and the km total in `logExercise`

**Order** (round 3 A P1-1, round 4 A P2-2):
1. **Resolve the type**: library → `loggingTypeHint` (consulted **only** when it is `cardio` or `distance`; round 6
   A P3-5, so a custom `weighted_bodyweight` slot or a same-day coach row keeps today's resolution) → **the existing
   row's stored `logging_type`, when it is `cardio` or `distance`** (round 6 B P2-2; mirrors the sticky `exercise_id`,
   `workout_write_service.dart:133-134`) → data shape over existing ∪ incoming sets. So a custom cardio row logged from
   the workout and then again from the chat card stays `cardio` and keeps its km (T28b, M39b). The library always wins
   over both: T28c, M39c. For a library
   exercise the library wins, so neither the hint nor the set list matters. `logExercise` gains an optional
   `loggingTypeHint`; in 1a only `completeWorkout` passes it (the slot's `logging_type`, the type whose boxes the user
   just filled). So a custom "Cardio" exercise (`create_custom_exercise_sheet.dart:151-156`) logged 30 MIN 3 KM stores
   1800 s and 3.0 km as `cardio`, not `timed` with km cleared (round 5 B P2-5; T28, M39). 1b adds the customBox lookup
   and its precedence over the slot.
   - **W16 guard, pulled into 1a** (round 6 A P3-6): 1a now creates custom `cardio` rows, and
     `LoggingTypeRepairMigrator._dataDrivenRepair` (`logging_type_repair_migrator.dart:442-485`) would retype one
     (duration, no weight) to `timed` when its per-device v3 flag is still unset at `_ensureLocalUser`
     (`auth_provider.dart:1253`). `_dataDrivenRepair` now leaves a stored `cardio` or `distance` row alone (T31, M57).
   - For a custom exercise the data-shape step resolves over the same list today's code uses (`mergedSets`), except
     for a duplicate, which has the same shape as the set it duplicates.
2. **Normalise and strip both sides** by that type: the existing sets and the incoming sets. Existing sets already go
   through the normaliser today, because `mergedSets` does (round 4 B), so this changes no stored row by itself.
3. **Dedup** the incoming sets against the existing ones (60 s). Both sides are now in the same shape, so a phantom
   field on one side cannot hide a real duplicate (round 4 A P2-2).
4. Merge.
5. Recompute every aggregate from the merged sets:
   - `set_number`, `reps_completed`, `weight_kg`, `volume_kg` as today (e8f95e rule);
   - `distance_km` = Σ per-set km, rounded to 0.001. It is written for `cardio`/`distance` **only when Σ > 0**. With no
     km the key is left off, so the cloud keeps NULL rather than 0 (round 4 B P3-5).

A retry within 60 s adds no set and no km.

**No restore-shape lift** (rev 6, round 4 A P1-1). A row with top-level aggregates and no per-set list keeps today's
behaviour: a set logged on top of it resets every aggregate to the merged sets, km included. That loss is today's for
`set_number`, reps, weight and volume, and it goes to OI-393 (d) as one fix for all of them. 0 such rows exist live
(round 4 B). Recorded in the diagnose-doc as a known limit.

**Also recorded as known, not worse than today** (round 5 B P3):
- `editLog` does not apply the U2 table. Adding km in the sheet to a reps-rule Farmers Carry row keeps the hidden
  reps, so it reads `1 set · 40 m · 40 reps · 40.0 kg`. 1b converts those rows at dispatch.
- `completeWorkout` swallows a refused `logExercise` (`train_provider.dart:2244-2251`). Only a session persisted before
  the upgrade, holding values over the new bounds, can reach it: `validateSetInputs` blocks LOG for every new value.

**Reader:** `WorkoutReadService.aggregateDistanceKm(log)`, mirroring `aggregateDurationSeconds`:
- Σ per-set km over `_perSetList(log)` (the longer of `sets` / `sets_detail`) if > 0;
- else the top-level `distance_km` (a legacy or restored row that no writer has touched; the OI-50 F5 shape where
  per-set entries lack the field);
- else 0.

The result is rounded to 0.001 (round 4 A P2-3).

**Routed through it:**
- the expanded row;
- the week selector (`week_selector.dart:848,857`: km read and printed through `formatDistance`; the cardio and
  distance minutes through `formatSetDuration`; timed and weight rows keep today's expression, round 4 A P2-3);
- both receipt builders;
- the PR value;
- the preview fallback: only its cardio and distance branches (`exercise_preview_sheet.dart:172-175`) delegate to
  `exerciseLogDetail`, with a plain-space separator as today. Its timed and weight branches are unchanged (round 5 A
  P2-8);
- the edit sheet's legacy top-level path (`edit_workout_log_sheet.dart:1043`; round 4 A P3).

**`editLog`:**
- Rebuilds through U1, so per-set km survives.
- Recomputes `distance_km` = Σ per-set when the edited sets, **or the sets before the edit**, carry any km. The key is
  removed when that Σ is 0, so clearing every km clears the total.
- Otherwise the top-level value is left as it is. That covers a row whose sets lack km beside a top-level total (the
  OI-50 F5 shape): an unrelated edit does not erase it. T8, M38.
- A row edited through the sheet's legacy path (no per-set list) keeps the sheet's top-level value.

**`moveExerciseLogs` collision** (W15; round 5 B P1-1). The merge keeps `merged['sets'] = mergedSets` as today, and
sets `distance_km` so that what the reader shows and what the summary pushes agree:
- `mergedSets` carries any per-set km → `distance_km` = Σ over `mergedSets`, rounded to 0.001;
- else (`mergedSets` carries **no** km) → `aggregateDistanceKm(existing) + aggregateDistanceKm(row)`, rounded,
  written only when > 0 (e8f4a3 B1 shape; with no per-set km on either side each term is that side's top level, F5
  included). The reader falls through to the top level exactly when the merged per-set sum is 0, so it shows that sum.
  This keeps a restore-shaped or F5 side's km beside a per-set side without km, as today does (round 6 A P2-1);
- else → no key.

The mixed shape (a restore-shaped side with a top-level km beside a per-set side **that carries km**) loses the restore-shaped side's km
on screen, as its duration already does today (`merged = Map.from(existing)`, `:1042`). It goes to OI (d) with the
re-log reset.

**Each side's list** (round 7 B P2-1, A P3-1): the merge builds `existingSets` and `movedSets` from
`WorkoutReadService.perSetList(side)` (the longer of `sets` / `sets_detail`, today's private `_perSetList`), translating
`duration_seconds` to `duration_sec` as `editLog` does. Today it reads `sets` only (`:970-977`), so a legacy
`sets_detail`-only side was missing from `mergedSets`.

**Stale `sets_detail`** (round 6 B P2-1): whenever the merge writes `sets`, it also removes `sets_detail`. The
sheet's per-set path always leaves `sets_detail` on a row (`edit_workout_log_sheet.dart:186`), and the push prefers it
(`sync_service.dart:2651-2664`), so without this the per-set rows pushed for a merged row cover only the destination
side. Because each side's list already came from the longer of the two, `sets` holds every set and no reader loses
one. Tests: T19(f), a sheet-edited destination; T19(g), a `sets_detail`-only destination. M58, M62. Nothing else in
the merge changes, so `reschedule_week_terminal_row_test.dart:429-503` stays green
**unchanged** (T19, M28).

**Gate test `no_top_level_distance_km_reads_test.dart`:**
- Pattern `log\s*\[\s*['"]distance_km['"]\s*\]`.
- Scan roots `lib/features/train`, `lib/core/services` (as the duration gate).
- Whole-file exemptions, each with a reason:
  - `workout_read_service.dart` (the helper);
  - `workout_write_service.dart` (writer);
  - `sync/sync_workout.dart` (summary push of the total, `:455`).
- No exemption for the edit sheet: `:1043` now goes through the helper (round 4 A P3).

**Docs:** the `lib/features/train/CLAUDE.md` field list and SoT `hive_field_name_exlog` are updated.

### U5: active workout, receipt, input bounds

**Helper:** `exerciseSetFromInput(SetInputValues v, String loggingType, int loggedAtMs)` in
`log_exercise_logic.dart`. It applies U2's table. It does **not** convert minutes: `SetInputValues.durationSeconds`
already holds seconds (capture, below).

**Capture contract (rev 11; delta round A P1-1 / B P1-1).** One pure parser pair in `log_exercise_logic.dart`:
- `cardioMinutesToSeconds(String text) → int?`: `double.tryParse(text.trim())` (no trailing-dot trim: Dart parses
  "12." as 12.0, and "." stays null), then `(min × 60).round()`. Null when unparseable.
- `secondsToMinutesInput(int secs) → String`: decimal minutes with at most 2 decimals and trailing zeros trimmed
  (750 → "12.5", 735 → "12.25", 30 → "0.5", 45 → "0.75", 1800 → "30").

Every consumer, by name:
- **`_valuesOf`** (`exercise_card.dart:696-700`): for a `cardio` slot the duration is
  `cardioMinutesToSeconds(_durationControllers[s].text)`; other types keep `int.tryParse` (timed SEC is seconds).
  The flag-OFF path captures through the same `_valuesOf`, so it is covered too.
- **Restore** (`exercise_card.dart:212-213` LOG mode, `:223-224` flag OFF): a cardio slot writes
  `secondsToMinutesInput(captured.durationSeconds)` back into the box, never raw seconds.
- **`validateSetInputs`** (cardio): uses `cardioMinutesToSeconds`; null → `outOfRange` "Fix time"; empty, or parsed
  minutes == 0 ("0", "0.0", "0.00") → `empty` "Add time"; a value that rounds to 0 s ("0.001") → `outOfRange` with `kSetMinimumSecondMessage`
  "At least 1 second per set."; over 21600 s → `outOfRange` with `kSetMinutesMaxMessage`.
- **`exerciseSetFromInput`**, **`fromActiveWorkout`** (`workout_receipt_card.dart:226`), **`liveVolumeKg`**,
  **`_hasTypedUnloggedValue`** (`log_exercise_logic.dart:684`), equality (`train_provider.dart:1698`) and the debug
  log (`:2211`) all read `durationSeconds` as seconds, unchanged; the ×60 that rev 10 put in `exerciseSetFromInput` and
  `fromActiveWorkout` is not added. Today's W7 bug (the receipt reading minutes as seconds) disappears with it.
- `_mirrorFrom` and `seedForAddedSet` copy box text verbatim, then re-capture through `_valuesOf`: covered.
- After a re-init an unlogged set's text is re-rendered from seconds ("12." → "12", "12.333" → "12.33"); the value
  is stable. Recorded (delta round 2 A P3-5).
- `regression_logic_test.dart:197-209` (R-L7b/R-L7c) stores and reads the field unchanged; it stays green, and 1800
  now truly means 1800 s.

**Used by:**
- `completeWorkout`;
- `fromActiveWorkout` (the whole set);
- `liveVolumeKg`.

**`validateSetInputs` bounds**, as `outOfRange`, so LOG is blocked with "Fix …":

| Box | Max |
|---|---|
| cardio MIN | 360 |
| timed SEC | 21600 |
| km | 300 |

- No box accepts a minus sign: whole-number boxes are digits-only (`set_input_row.dart:240-243`), and the cardio MIN
  and KM boxes accept digits and "." (`:244-246`). So no negative value can be typed.
- The timed SEC box keeps its 4-digit limit (`set_input_row.dart:240-243`), so it accepts at most 9999 s. Its 21600
  bound and "Up to 6 hours per set." are reachable only from the edit sheet. Recorded (round 7 B P3).
- The flag-OFF validator (`exercise_card.dart:788-797`, debug-only) is recorded as not bounded.
- **New out-of-range messages** go in `lib/core/copy/`, never reusing `kEnterDurationMessage`, which at
  `log_exercise_logic.dart:76-79` is wrong for 400 MIN. The strings go through the Wardroom copy pass:

  | Constant | Text |
  |---|---|
  | `kSetMinutesMaxMessage` | "Up to 360 min per set." |
  | `kSetSecondsMaxMessage` | "Up to 6 hours per set." |
  | `kSetMinimumSecondMessage` | "At least 1 second per set." (a typed value that rounds to 0 s) |
  | `kSetKmMaxMessage` | "Up to 300 km per set." |

**D2 (founder, 2026-10-22): decimal minutes.** The cardio MIN box keeps today's decimal input
(`set_input_row.dart:178`, formatter `[\d.]`, 6 chars, `:244-246`). Seconds stay the stored unit.
- **Validator** (`validateSetInputs`, cardio only; timed SEC stays whole seconds): the text is parsed with
  `cardioMinutesToSeconds` (see the capture contract above for every outcome).
- **Conversion** happens once, at capture (`_valuesOf`) and in the edit sheet, through `cardioMinutesToSeconds`:
  "12.5" → 750 s; "12.25" → 735 s; "0.5" → 30 s; "12." → 720 s.
- **Repoint:** `log_exercise_logic_test.dart:66-70` ("12.5 is outOfRange") becomes "12.5 is ok, and LOG stores 750 s".
  New legs: "1.2.3" and "0.001" → `outOfRange`; "12." → ok, 720 s.
- **The flag-OFF validator** (`exercise_card.dart:788-797`, debug-only) keeps `int.tryParse`; recorded.

### U7: readers

**One formatter pair** (`lib/core/utils/cardio_format.dart`, pure). Chips, the expanded row, the preview fallback,
the receipt and `formattedValue` all use it.

Both take `{String space = ' '}`, the character between number and unit (round 4 A P2-4). The chips and the preview pass the
plain space (pin `ward_set_chips_test.dart:78`; preview `:172-175`); the expanded row passes NBSP, as it does today.

- **`formatSetDuration(int secs, {space})`**, for `cardio` and `distance` only, in **decimal minutes** to match how
  they are typed (D2):
  - under 60 s: `'${s}s'` (the pin `15s · 2.0 km` stands);
  - otherwise `(secs / 60).toStringAsFixed(1)` with a trailing `.0` dropped, then `${space}min`: 1800 → `30 min`,
    750 → `12.5 min`, 1830 → `30.5 min`, 735 → `12.3 min` (display rounds; the stored 735 s does not), 3597 → `60 min`.
  - One token before the unit, so the PR tile's split on a space (`pr_snapshot.dart:214`) renders `12.5` + `min`
    correctly; the old `30m 30s` two-part problem (§2) no longer arises.
- **`formatDistance(double km, {space})`:** `m = (km * 1000).round()`.
  - `m < 1000`: metres, e.g. `40${space}m`;
  - otherwise one decimal, e.g. `5.0${space}km`. The boundary is on the rounded metres, so 0.9996 km reads `1.0 km`,
    never `1000 m` (round 4 A P3).
- **Timed formatting is unchanged** (round 4 A P2-4, B P3-4). `60 secs` (`ward_set_chips_test.dart:65`) and the timed
  `Xm Ys` expanded row stay as they are; the pair is never called for `timed`.
- **Parts and their order** for a cardio or distance row or set: duration, km, reps, weight. **A zero part is
  omitted.** With a blank KM the expanded row reads `30 min`, not `30 min · 0.0 km`. A set kept under U2's reps rule
  reads `40 reps · 40.0 kg`, as today.
- **The set count, per type** (round 5 B P2-4):
  - **`exerciseLogDetail`, cardio:** no set count, as today's cardio branch (`expanded_exercises.dart:86-89`):
    `20 min · 5.0 km`, `30 min`. A reps-rule cardio row (no duration, no km) leads with the count like the weight
    branch, so its sets stay visible: `3 sets · 20 reps · 100.0 kg` (round 6 B P3).
  - **The receipt fallback** (`workout_receipt_card.dart:810-830`) uses the same per-type rule as `exerciseLogDetail`.
  - **`exerciseLogDetail`, distance:** leads with the count, like the weight branch (OI-380):
    `1 set · 40 m · 40.0 kg`, a reps-rule row `4 sets · 40 reps · 40.0 kg`.
  - **The week selector** keeps its own leading `N set(s)` for every type (`week_selector.dart:852`):
    `1 set · 30 min · 4.0 km`.
  - **The chips** are per set, with no count. The reps part is shown for cardio and distance sets when > 0 (today
    `ward_set_chips.dart:96-100` omits it for distance), so a reps-rule set reads `40 reps · 40.0 kg`.
- **The empty case** (round 4 A P2-4, B P3-2): a chip or a cardio detail whose parts are all zero shows `—`, as the
  chips already do (`ward_set_chips.dart:94,99`). A distance detail with every other part zero reads `1 set`.

Round 3 B P2-2.

**Receipt:** `ReceiptSet.distanceKm` in both builders and in the chips.

**Expanded row:**
- extract the pure `exerciseLogDetail(Map log)`;
- add a distance branch, `N sets · X.X km · Y kg` (OI-380), with the part rules above. The `expanded_exercise_log_row_test.dart:274`
  repoint is exactly `20${nb}min` (round 4 A P2-4).

**Edit sheet (cardio and distance), km** (round 5 B P2-2). Mirror the existing duration guard
(`hadPerSetDuration` in `_save`, `edit_workout_log_sheet.dart:192-196`; `hasAggregateDur` / `hadPerSetDur` in
`fromLog`, `:984-996`) as `hasAggregateDistance` /
`hadPerSetDistance`:
- the per-set boxes sum to > 0 → send `distance_km` = that sum;
- the sum is 0 and the original per-set entries carried km → send `distance_km: null` (the user cleared it; readers
  and the push treat null as absent, so the cloud gets NULL);
- the sum is 0 and they did not (F5 shape, or km never entered) → leave `distance_km` out of the update, so a
  top-level total survives an unrelated save of the day.
- The legacy path follows its duration twin's blank-text rule (`edit_workout_log_sheet.dart:258-261`): a blank km box
  leaves `distance_km` out when the row had no aggregate km; an explicit `0`, or a box that was prefilled with a km and
  then emptied, sends `distance_km: null` and clears it (round 6 A P3-7, round 7 A P3-3 / B P3).
- The update map is built by an extracted pure `editSheetUpdatesFor(...)`, so T8's F5 leg runs through the sheet's
  own logic (M38 now targets it).

**Edit sheet (cardio):**
- MIN in and out on **both** paths: the per-set path and the legacy top-level path for a restored row, whose label is
  `Duration (s)` today (`edit_workout_log_sheet.dart:671`; round 4 B P3-3). ×60 on save, written only when changed.
- MIN takes decimals (D2) on both paths: the per-set field (`_compactField(setRow.durationCtrl)`, `:563`) and the
  legacy field (`_numField(row.durationCtrl, …)`, `:668`) get `allowDecimal: true` (today both are digits-only,
  `:595`, `:743`), and `_save`'s `int.tryParse` (`:113`, `:205`) is replaced by `cardioMinutesToSeconds` inside
  `editSheetUpdatesFor` (delta round B P2-1).
- The per-set prefill needs the row's type: `EditLogSetRow.fromSetDetail` (`:852-880`) takes only the set map, so
  the minutes conversion is applied per row after construction, for `cardio` only. A `distance` row keeps its hidden
  `durationCtrl` in seconds (its layout, `:567-574`, has no duration box), so a 120 s distance set round-trips as 120 s
  (T8 leg; delta round 2 A P3-3).
- Prefill is always decimal minutes through `secondsToMinutesInput`, **including under 60 s** (30 s → "0.5", 45 s →
  "0.75"), never `formatSetDuration`'s `'${s}s'` (delta round B P2-2, A P3-2). A field whose text equals its prefill
  writes nothing, so an unchanged 735 s (prefill "12.25") stays 735.
- **Malformed or sub-second minutes are refused, never saved as 0** (delta round 2 B P2-1). The sheet's decimal
  formatter (`[0-9.]`, `:593`) admits "12.5.", "1..2" or ".". In `editSheetUpdatesFor`, a cardio minutes field whose
  text is non-empty, is not "0", and for which `cardioMinutesToSeconds` returns null or 0 refuses that row: a field
  error, the failure copy ("Not saved: enter the minutes as a number, like 12.5." / `kSetMinimumSecondMessage`), and
  the sheet stays open. A deliberate "0" still clears the duration, as today. T8 leg "12.5." → refused, 750 s
  unchanged; M72.
- Re-init and prefill render 2 decimals, so a typed "1.01" (61 s) reappears as "1.02"; the stored seconds do not
  change because the text parses back to the same value. Recorded (delta round 2 B P3).
- The cardio box shows **no** seconds hint: `_buildDurationHint` (`:708-731`) reads the text as seconds, and a minutes
  box needs no hint, so "90" no longer shows "= 1m 30s" (round 5 B P2-3; T8, M40).
- **On a failure the sheet stays open** with the typed values, instead of popping at `:291` (round 5 B P3). The
  provider invalidation that today sits before the pop (`:271-279`) still runs, so the rows that did save show at once
  (round 6 B P3).
- Per-set km.
- `distance_km` = Σ per-set.
- On a failure it stops showing "Workout log updated" and shows failure copy (`edit_workout_log_sheet.dart:280-306`).
- `toFailureCopy(code)` is a small pure function. Its signature is `{bool debug = kDebugMode}`, so release copy can
  be tested.
- **Strings**, in `lib/core/copy/`, through the Wardroom copy pass:

  | Code or case | Text |
  |---|---|
  | `duration_out_of_range` | "Not saved: a set can be up to 360 min." (cardio) / "Not saved: a set can be up to 6 hours." (timed) — the same unit as the box the user typed in (round 5 B P3) |
  | `distance_out_of_range` | "Not saved: a set can be up to 300 km." |
  | any other or catch-all (`WriteResult.fail(e.toString())`, `workout_write_service.dart:268`) | "Not saved. Try again." The raw error is shown only when `debug`. |
  | multi-row sheet with some rows failed | "Partly saved. Not saved: {names}. {reason}" — the shape of `coachWorkoutLogPartialTemplate` (`wardroom_copy.dart:256`), naming only the failed exercises, with no counts (the sheet re-saves every row of the day, so a count would include untouched rows). `{reason}` is the matching per-set limit sentence; with mixed codes, the first. Round 4 B P3-6, round 5 B P3. |

**PR:**
- `ExercisePR` gains a named parameter `String? unit` stored as `final String? _unit` through the initializer
  `: _unit = unit` (a named parameter cannot be private), plus a getter `unit => _unit ?? defaultUnitFor(loggingType)`.
  The constructor stays const; `regression_logic_test.dart:260` compiles.
- `loadAllExercisePRs` makes **two passes** for cardio. Pass 1: does any log of this exercise have km? Pass 2:
  compute the best value in that unit only.
- `formattedValue` uses the unit; the magnitude guess goes.
- StatsGrid renders through `formattedValue`.
- Graduation top-3 puts `kg` PRs first by value, then fills from others by date.
- A distance type's `is_pr` stays weight-based (recorded).

**AI snapshot:**
- adds `duration_min` (one decimal: 750 s → 12.5, matching the screen at 60 s and above; 20 s → 0.3, where the screen
  shows `20s`) and `distance_km` for
  cardio and distance rows, plus `top_set_weight_kg` for distance. The values
  come from `aggregateDurationSeconds` (`(secs / 60).round()`) and `aggregateDistanceKm`, never from `log['sets']`
  directly (`ai_snapshot_builder.dart:1175`); each is omitted when 0 (round 6 B P3, round 7 A P3-5, delta round A
  P3-3 / B P3: the coach and the screen now agree on 12.5, not 13). The prompt size trim
  (`:282-320`, budget 8500 vs the server's 10000) already covers the extra keys (round 5 B P3);
- kill switch `disable_snapshot_cardio_fields`, debug-only (configBox), pinned byte-identical;
  - It is default-ON, so it is **not** a `ship_dark_pending_review.yaml` entry (that file's schema is for default-OFF
    flags; round 4 B P3-7).
  - The old path's deletion is tracked on Batch 3's minted OI instead (§4.6 step 4 allows the OI board). Batch 3
    already changes the coach's cardio inputs.
- recorded: a log on a day with no schedule row is not in the snapshot (today's behaviour).

### U8: boot heal (W11), the zeroing only

- **The cast is not changed** (rev 6, round 4 B P2-2). The loop keeps its `.cast<Map<String, dynamic>>()`
  (`auth_session_bootstrapper.dart:1210`) and passes `healedExlog` only what that cast yields, so the heal keeps
  today's footprint. Precisely (round 5 A P2-1): the cast is lazy and throws when the first set is read, so a disk
  row with at least one set throws and the first such row ends the loop (today's behaviour); a disk row with an empty
  or missing `sets` list is retyped (label only); a row still in memory as `Map<String, dynamic>` (restored in the
  same sign-in: the heal runs after the restore, `:1107`) is healed.
- **Footprint pin** (T10b, M54): a type-mismatched `Map<dynamic, dynamic>` row with one set is byte-unchanged after
  `_healMismatchedExerciseLogs`. Mutation: drop the cast, so the heal goes live; T10b must redden.
- **Where it does run, it no longer zeroes cardio minutes.** Extract the pure `healedExlog(Map log, String correctType)`.
  It edits each set map **in place**, clearing exactly the fields U2's table clears for the type. Clearing a duration
  writes `duration_sec: 0`, as today's heal does; readers resolve `duration_sec ?? duration_seconds`, so the restored
  `duration_seconds` key stays but is shadowed (round 6 A P3-4). The table is read
  through one shared pure function, `fieldsClearedFor(type, {hasDuration, hasKm})`, which the normaliser uses too, so
  there is one table and not a third copy. Every other key (`set_number`, `duration_seconds`, `logged_at_ms`) is left
  as it is, so the heal's footprint is today's minus the cardio zeroing (round 5 B P3; T10 asserts the untouched keys).
- T10 tests `healedExlog` on a `Map<String, dynamic>` fixture (the shape it can actually meet). M5.
- **New OI (e)** carries the live heal: the cast fix, kill switch `disable_exlog_type_heal` with a pinned off-state
  no-op, recomputing aggregates, rewriting `sets_detail`, stamping `updated_at_ms`, iterating `keys.toList()`, and
  registering the heal as a SoT writer. Round 4 B lists its footprint: 0 cloud-backed rows today, and every row of an
  exercise after any future library retype, on every sign-in.

### Coach paths in 1a (not changed; no regression)

| Path | Before | After 1a |
|---|---|---|
| Chat card, library cardio (e.g. "Rowing Machine" 20 min) | 0 min | **20 min** (km arrives in 1b) |
| Chat card, non-library "Walking" | `timed`, seconds | same |
| `logSet` on library cardio | 0/0 junk row | same, still junk (1b fixes it) |
| `logSet` / `LogWorkoutSheet` / chat card (not typed cardio), "Farmers Carry" 4 × 40 @ 40 kg | `4 sets · 40 reps · 40.0 kg` | **same** (U2 reps rule; T23) |
| same routes, "Sled Push" with reps only | reps kept | **reps kept** (U2 reps rule; T23) |
| Chat card (not typed cardio), "Sled Push" 3 × 30 s @ 100 kg | 100 kg, 0 s | **100 kg, 30 s** (U2; T23) |
| Chat card, a distance draft with a duration and reps, no km | reps kept, duration zeroed | reps and duration kept (U2; T23) |
| Chat card, cardio draft over 360 min | saved as 0 min under "Workout logged" | refused; the card shows its existing "Not saved. Fix the sets or tap CONFIRM to retry." (`wardroom_copy.dart:259`). An improvement; how the card lets the user fix minutes is 1b's |
| `logSet` on library timed | 0-second row | same (1b converts reps to seconds) |
| `LogWorkoutSheet` | weight×reps | same |

Nothing gets worse. The chat card gains minutes, and an over-long cardio draft is refused instead of saved as 0.

### §4.6 for 1a

- 1a is account tier, so no flag is required.
- Only the snapshot change (AI input) has a switch.
- The writer has none: the old normaliser deletes data.
- Kill switches are debug-only, so a release rollback is a client revert.

## 4. Tests (Batch 1a)

**Main file:** `test/contracts/cardio_duration_distance_writer_to_reader_test.dart` (real Hive).

| # | What | Asserts |
|---|---|---|
| T1 | `logExercise` "Rowing Machine" 1200 s + 5.0 km | per-set 1200/5.0; top 5.0; cardio; `exerciseLogDetail` → `20 min · 5.0 km` (cardio: no count) |
| T2 | second log 600 s + 3.0 km; then the same 600 s + 3.0 km set again within 60 s; then 600 s + 4.0 km within 60 s | top 8.0 then **8.0** (retry adds nothing, result ok, set count 2) then 12.0 (different km not deduped); per-set km list asserted |
| T3 | **replaces the a4c7d1 placeholder**: weight row with phantom duration and km; timed row with weight and km | phantoms cleared |
| T4 | "Farmers Carry" 0.04 km + 40 kg; and 1.2 km + 40 kg | `1 set · 40 m · 40.0 kg`; `1 set · 1.2 km · 40.0 kg` |
| T4b | cardio 30 min with no km (expanded row, preview fallback, chips); the same as a restore-shaped row through `WorkoutReceiptData.fromExerciseLogs` (receipt fallback) | `30 min` everywhere; no `0.0 km`; the stored row has **no** `distance_km` key |
| T5 | active workout: "Running (Treadmill)" 30 MIN 4 KM → `completeWorkout` | 1800 s, 4.0 km |
| T32b | card level (`log_exercise_card_test.dart`, `pumpNew(type: 'cardio')`): type "12.5" in MIN → LOG → `completeWorkout`; re-init the card; type "12.5" without LOG and press FINISH; mirror from a "12.5" set 1 | 750 s stored; the box reads "12.5" after re-init; the FINISH guard lists the exercise as typed-not-logged; the mirrored set stores 750 s |
| T6 | receipt from active (T5) and from logs (T1) | `30 min · 4.0 km`; volume equals the stored row |
| T8 | `editLog` with per-set km; sheet cardio MIN round-trip 30 → 1800; unrelated edit on a 45 s row (prefill "0.75"); a 750 s row (prefill "12.5") saved unchanged; a 735 s row (prefill "12.25") saved unchanged; "13.5" typed into the 750 s row; a 30 s row's prefill; "12.5." typed into the 750 s row; a distance set with 120 s saved through the sheet; a cardio set with no duration saved with its box blank; legacy-path edit on the T9 row (MIN label, ×60); `editLog` with a 301 km value arriving through `sets_detail`; an `editSheetUpdatesFor` save that changes one set's reps on a row whose sets lack km beside a top-level 4 km; a save that clears every per-set km on a row whose sets carried km; a legacy-path save with the prefilled km box emptied, and one with a blank box on a row with no km | km survives; 1800; 45 s unchanged; 750; 735; 810; "0.5"; refused, 750 kept, sheet open; 120 s kept; no `duration_sec` key; T9 km and minutes unchanged; refused `distance_out_of_range`; 4 km kept; `distance_km` null, pushed as NULL; legacy: null, and no `distance_km` key |
| T9 | reader on an untouched restored row (top 5 km, 600 s, `set_number` 1, no per-set list); a row with `sets: []` and a populated `sets_detail` carrying km; a row whose sets lack km beside a top-level 5 km; a per-set sum of 0.1 + 0.2 | `aggregateDistanceKm` 5.0; the `sets_detail` sum; 5.0; exactly 0.3 |
| T10 | `healedExlog` on a `Map<String, dynamic>` stale-typed cardio row whose sets carry `set_number`, `duration_seconds` and no `logged_at_ms`; and a weight-type row with a restored `duration_seconds` | cardio: duration and km kept; `set_number` and `duration_seconds` kept; no `logged_at_ms` added. Weight type: `duration_sec: 0` written, `duration_seconds` untouched |
| T10b | `_healMismatchedExerciseLogs` over a box holding a type-mismatched row written as `Map<dynamic, dynamic>` with one set | the row is byte-unchanged (today's footprint) |
| T11 | chips 1200 s + 5 km; 15 s + 2 km | `20 min · 5.0 km`; `15s · 2.0 km` |
| T16a | PR: 5.0 km log then a duration-only 1800 s log | PR `5.0 km` |
| T16b | StatsGrid fallback (no key lifts in Hive), duration-only cardio PR 1800 s | `30 min`, never `1800 km` |
| T16c | graduation top-3 with 100 kg and an 1800 s cardio PR | 100 kg first |
| T17 | snapshot cardio row with `disable_snapshot_cardio_fields = true` | fields; byte-identical old map |
| T18 | `logExercise` −1 s, 21601 s, −0.1 km, 301 km; `editLog` with a per-set 301 km; `editLog` with 2 × 12600 s (sum 25200) and with 2 × 200 km through the sheet's update map; legacy-path `editLog` with 1 set and a top-level 301 km; legacy-path `editLog` with 3 sets and a top-level 500 km; `validateSetInputs` 361 MIN, 21601 SEC, 301 km | `WriteResult.invalid` codes; refused; **both saved**; refused; **saved**; blocked |
| T19 | move collision: (a) both sides restore-shaped (top 5 + 3 km); (b) both sides per-set (2 + 3 km); (c) neither side carries km; (d) mixed: restore-shaped 5 km + per-set 3 km; (e) restore-shaped 5 km + a per-set side with no km; (f) see result | asserted through `aggregateDistanceKm(merged)` and the summary payload's `distance_km`, which must agree: (a) 8.0; (b) 5.0; (c) no key; (d) 3.0 on both (the OI (d) limit, pinned so it cannot silently diverge); (e) 5.0 on both; (f) a sheet-edited destination (`sets_detail` present) + a per-set moved row: no `sets_detail` left, the payload's per-set rows cover both sides; (g) a destination with only `sets_detail` (3 sets, 2 km) + a per-set moved row (1 set, 1 km): `sets` holds 4 sets, km 3.0 on the reader and the payload. Payload assertions run through `SyncHarness` + `pushExerciseLogsForSyncDomain` with the stub server (`test/sync/exlog_push_u3_behavioral_test.dart:87-110`). `reschedule_week_terminal_row_test.dart:429-503` runs unchanged and green |
| T20 | edit sheet failure path; `toFailureCopy(code, debug: false)` | no "Workout log updated"; generic copy, no raw code |
| T23 | U2 reps rule: "Farmers Carry" 4 × 40 @ 40 kg and "Sled Push" 20 reps, logged with no duration and no km; "Sled Push" 30 s @ 100 kg with 3 reps; a distance set with 120 s and 10 reps, no km | reps and weight kept, `4 sets · 40 reps · 40.0 kg` (reps rendered as the per-set max, as the weight branch at `expanded_exercises.dart:57`); 100 kg and 30 s kept, reps 0; reps and 120 s kept; a later set with km clears reps on the km set only; Sled Push 3 × 20 @ 100 kg with no duration reads `3 sets · 20 reps · 100.0 kg` |
| T24 | U3 order: a stored set seeded directly into Hive with a phantom duration on a weight exercise; the same weight × reps re-sent within 60 s **without** the phantom | deduped (count unchanged). Today it is appended; recorded in the diagnose-doc as the one behaviour change of the order, and no existing test depends on the old outcome (round 5 A Q2) |
| T25 | formatters: 0.9994 / 0.9996 km; 1800 / 1830 / 750 / 735 / 3597 / 45 s; separator NBSP vs space; every part zero | `999 m` / `1.0 km`; `30 min` / `30.5 min` / `12.5 min` / `12.3 min` / `60 min` / `45s`; exact characters; `—` and `1 set` |
| T26 | week selector line for a cardio row 1830 s with 0.04 km per set only (no top-level km); and a timed 45 s row | `1 set · 30.5 min · 40 m` (the old expressions give `31 min` and no km, so M34 reddens); the timed row as today |
| T28 | `completeWorkout` with a custom "Cardio" exercise (not in the library), 30 MIN 3 KM | `logging_type` cardio; 1800 s; 3.0 km |
| T29 | PR card for a 0.04 km distance PR; chips for a reps-rule distance set; `liveVolumeKg` for a cardio set with weight 20, reps 30 (the hidden prefill) and 1800 s; a distance set with duration given; a 0 km input | `40 m`; `40 reps · 40.0 kg`; 0; duration kept; per-set `distance_km` absent |
| T28b | the T28 row, then a same-day chat-card log of the same custom name with 600 s; separately, the T28 row then a coach `logSet` weight × reps for the same name | still `cardio`; km 3.0 kept; 2400 s. `logSet`: still `cardio`, stored durations and km kept |
| T28c | `completeWorkout` for library "Plank" (timed) with a slot hint `cardio` | `timed` (library wins) |
| T31 | `LoggingTypeRepairMigrator._dataDrivenRepair` over a stored custom `cardio` row (1800 s, no weight, reps 0) | still `cardio`, duration and km kept |
| T32 | D2: `SetInputRow` for a cardio slot, type "12.5" in MIN, then LOG through `validateSetInputs` + `exerciseSetFromInput`; also "1.2.3", "0.001", "12.", "1.01", "0.0" | the controller holds `12.5`; ok; 750 s stored. `outOfRange`, `outOfRange`, ok (720 s), 61 s, `empty`. PR tile for a 750 s best reads `12.5` / `min` |
| T30 | sheet partial failure: 3 rows, 1 refused | "Partly saved. Not saved: Rowing Machine. …"; the sheet is still open; the providers were invalidated (the saved rows show) |
| T27 | snapshot with `disable_snapshot_cardio_fields` unset (default) | the cardio fields are present (the default) |
| T22 | **OI-382 seam move:** `badPlank()` → `[DraftSet(durationSecs: 60), DraftSet(durationSecs: -100)]`. `draftExerciseSets` filters the negative set; `_draftExerciseDurationSec` still makes `markCompleted` fail | the three dependent tests in `workout_log_confirm_card_saved_signal_test.dart` keep their status |

**Repoints:**
- `expanded_exercise_log_row_test.dart:222-274` now expects minutes; `:274` is exactly `20${nb}min`.
- `reschedule_week_terminal_row_test.dart:429-503`: **no repoint**. It must stay green unchanged (rev 6 drops the
  lift).
- `ward_set_chips_test.dart:68` stays.
- `regression_logic_test.dart:260` compiles unchanged.
- `grep -rn` every touched literal in `test/` and `docs/` first.

**Mutations (§4.4 rule 21).** Each is applied, confirmed with `grep -c`, and run; reddened counts are recorded.

| M | Mutation | Must redden |
|---|---|---|
| M1 | cardio `durationSec: 0` back | T1, T5 |
| M2 | `toMap` drops km | T1, T2 (per-set list), T8 |
| M3 | `cardioMinutesToSeconds` drops the ×60 | T5, T6, T32b |
| M66 | `_valuesOf` back to `int.tryParse` for cardio | T32b |
| M67 | the restore writes raw seconds into the cardio box | T32b (re-init leg) |
| M68 | the sheet's cardio fields back to digits-only | T8 ("13.5" leg, typed through the rendered field with `tester.enterText`, not the pure builder) |
| M69 | the sheet parses cardio with `int.tryParse` | T8 (750 unchanged and "13.5" legs) |
| M70 | the sheet prefills `formatSetDuration` under 60 s | T8 (30 s leg) |
| M71 | the snapshot rounds `duration_min` to whole minutes | T17 (750 s → 12.5) |
| M72 | the sheet saves an unparseable minutes field as 0 | T8 ("12.5." leg) |
| M73 | the "0.001" refusal uses the generic message | T32 ("0.001" leg asserts `kSetMinimumSecondMessage`'s text) |
| M4 | dedup ignores distance | T2 (4.0 km set) |
| M5 | heal zeroes cardio | T10 |
| M8 | `copyWith` ignores `clearDistance` | T3 |
| M9 | PR compares km against seconds | T16a |
| M10 | reader ignores the top level for legacy rows | T9 (untouched row reads 0; the setup asserts the row has no per-set list first) |
| M11 | km summed before dedup | T2 (retry gives 11) |
| M12 | StatsGrid back to `_unitForLoggingType` | T16b |
| M13 | snapshot switch ignored | T17 |
| M17 | `toFailureCopy` shows the raw code when `debug: false` | T20 |
| M18 | `logExercise` duration/distance bounds removed (OI-382) | T18 |
| M19 | `validateSetInputs` upper bounds removed | T18 (UI leg) |
| M20 | distance branch removed from `exerciseLogDetail` (OI-380) | T4 |
| M21 | `formatDistance` sub-km metres removed | T4 (`40 m`) |
| M22 | zero parts printed | T4b |
| M23 | `editLog` rebuild drops per-set km | T8 |
| M24 | a blank cardio box on a set with no duration writes a `duration_sec` key on save (retargeted: the 2-decimal prefill round-trips exactly, so "write only when changed" is no longer observable; delta round 2 A P3-1) | T8 (blank-box leg) |
| M25 | edit sheet shows "Workout log updated" on failure | T20 |
| M26 | `fromMap` ignores `distance_km` | T2, T8 |
| M27 | graduation sorts by `bestValue` across units | T16c |
| M28 | move merge back to rev 6's per-side sum on every shape | T19 (d) |
| M56 | move merge's second branch back to "neither side has a per-set list" | T19 (e) |
| M57 | `_dataDrivenRepair` guard for cardio/distance removed | T31 |
| M58 | the merge keeps the stale `sets_detail` | T19 (f) |
| M62 | the merge reads each side from `sets` only | T19 (g) |
| M39b | the stored-type step removed | T28b |
| M39c | the hint consulted before the library | T28c |
| M59 | the legacy total bound drops "× max(1, set count)" | T18 (3-set legacy 500 km saves) |
| M60 | the sheet sends `0` instead of `null` when the user clears every km | T8 (cleared leg, asserted on `editSheetUpdatesFor`'s output; and the legacy leg, where `{distance_km: 0}` would reach the stored row) |
| M61 | the snapshot sends `duration_min: 0` for a 0 s row | T17 (a cardio row with no duration has no `duration_min`) |
| M29 | `editLog` bounds removed | T18 (`editLog` leg), T8 (`sets_detail` leg) |
| M30 | `editLog` validates before the `sets_detail` translation | T8 (`sets_detail` leg) |
| M31 | U2 reps rule removed | T23 |
| M31b | cardio clears weight | T23 (100 kg leg) |
| M63 | reps-rule cardio row without the set count | T23 (Sled Push line) |
| M64 | partial failure skips the invalidation | T30 |
| M32 | `aggregateDistanceKm` rounding removed | T9 (0.3) |
| M33 | `formatSetDuration` prints `12m 30s` instead of decimal minutes | T25, T32 (PR tile) |
| M34 | week selector back to `log['distance_km']` and `/60` for cardio | T26 |
| M35 | snapshot fields omitted when the switch is off | T27 |
| M36 | dedup runs before normalising the existing sets | T24 |
| M37 | `distance_km` written when Σ = 0 | T19 (c), T4b |
| M49 | receipt `_exerciseDetail` keeps its own `0.0 km` text | T4b (receipt leg) |
| M50 | `liveVolumeKg` ignores the type | T29 (`liveVolumeKg`) |
| M51 | `ReceiptSet.distanceKm` dropped in `fromActiveWorkout` | T6 |
| M52 | legacy-path MIN not converted through `cardioMinutesToSeconds` | T8 (legacy leg) |
| M53 | cardio validator back to `int.tryParse` (decimals refused) | T32, `log_exercise_logic_test.dart` repointed leg |
| M65 | conversion truncates instead of rounding (`(min × 60).toInt()`) | T32 ("1.01" min → 61 s; truncation gives 60) |
| M54 | the heal loop loses its cast (heal goes live) | T10b |
| M55 | the partial copy names every row | T30 |
| M38 | `editSheetUpdatesFor` sends `distance_km: 0` when the sum is 0 | T8 (F5-shape leg: the builder's output goes through `editLog`, so the 0 would overwrite the stored 4 km) |
| M39 | `completeWorkout` stops passing `loggingTypeHint` | T28 |
| M40 | the cardio box keeps the seconds hint | T8 (hint leg: no hint text under the MIN box) |
| M41 | `editLog` bounds the top-level total | T18 (2 × 12600 s saved) |
| M42 | `validateSetInputs` timed SEC bound removed | T18 (21601 SEC) |
| M43 | km ≤ 0 stored as `0.0` | T29 (0 km) |
| M44 | chips omit reps for a distance set | T29 (chips) |
| M45 | PR `formattedValue` prints km for a sub-km distance | T29 (`40 m`) |
| M46 | the sheet pops on failure | T30 |
| M47 | `exerciseSetFromInput` drops a distance set's duration | T29 |
| M48 | the heal rebuilds sets through `ExerciseSet` (drops untouched keys) | T10 |

## 5. Process (Batch 1a)

**Closure ledger** `docs/audit/cardio-duration-distance.closure.yaml`:
- 1a units are `closed_in_commit`.
- 1b, 2, 3, (d) and (e) are `blocked_on_user`. Each `reason:` names only the founder action and cites its OI:
  - 1b: "founder-sequenced follow-on batch (split ratified D10, <date>); OI-389 stays OPEN for it" (round 4 B P2-3).
  - (d): "founder-sequenced follow-on (D10, <date>); OI-393, restore-shaped exlog totals reset on a re-log".
  - (e): "founder-sequenced follow-on (D10, <date>); OI-394, the live exlog type heal".
  - 2: "founder go for the live migration apply; OI-391".
  - 3: "founder go for the ai-proxy deploy; OI-392".
- Precedent: `active-workout-log-exercise.closure.yaml` FOLLOW-ON-BATCHES.
- The four OIs are minted at the start of the batch with `mint_oi.sh`. Minting pushes, so the founder's go comes first
  (§6 D9).
- The Batch 1b, 2 and 3 plans are written straight after this batch, on their own branches.

**Reviews:**
- plan-review record;
- self-initiated `/code-review` B-pass before the merge.

**Diagnose-doc:** full template. `touched_layers_checked`:

| Tier | Status |
|---|---|
| 1, 2 | fixed_in_this_batch |
| 12 | fixed_in_this_batch; device evidence added after the run |
| 4 | verified |
| 3 | verified (the constraint was read live; 1a makes its boundary reachable, §0) |
| 5, 6 | not_applicable in 1a |
| 7 | not_applicable (no cron reads these) |
| others | not_applicable |

**SoT registry:**
- `hive_field_name_exlog`;
- `exercise_personal_records`;
- `ai_snapshot_building`;
- new `cardio_duration_distance` (`behavioral_test_path`: the T-file);
- `workout_log_edit_surface` (`:215`: MIN editing, failure copy; T8, T20);
- `active_workout_set_logging` (`:12805`: `validateSetInputs` bounds, D2; T18);
- `workout_receipt_rendering` (`:47`: `ReceiptSet.distanceKm`; T6);
- `exercise_logs_read_path` (`exerciseLogDetail`; T1, T4).

Each entry carries a `behavioral_test_path` (Gate 42).

**Diagnose-doc path:** `docs/diagnoses/2026-10-22-cardio-duration-distance-<6-hex>.md`.
- The id is minted at write time.
- The commit carries `closes-diagnose: <id>`.
- It records the value-semantics sweep over `supabase/functions` (round 3 B P2-10):
  - `weekly-report` selects `duration_seconds` but does not use it;
  - `pr-detection` is weight-only;
  - `getPRTimeline` now passes non-zero cardio `duration_seconds` / `distance_km` through to the model;
  - no server code branches on `logging_type` cardio or distance.
  - Verdict: verified clean.

**Naming:**
- functions: `exerciseSetFromInput`, `aggregateDistanceKm`, `exerciseLogDetail`, `formatSetDuration`,
  `formatDistance`, `toFailureCopy`, `healedExlog`;
- reserved for OI (e), not used in 1a: `disable_exlog_type_heal`;
- constants: `kMaxSetDurationSec`, `kMaxSetDistanceKm`, `kSetMinutesMaxMessage`, `kSetSecondsMaxMessage`,
  `kSetKmMaxMessage`, `kSetMinimumSecondMessage`;
- functions (rev 11): `cardioMinutesToSeconds`, `secondsToMinutesInput`;
- fields and parameters: `WriteResult.invalid`, `WriteResult.code`, `ExercisePR.unit`, `ReceiptSet.distanceKm`,
  `clearDuration`, `clearDistance`;
- kill switch: `disable_snapshot_cardio_fields`.

**Also:**
- memory pair;
- skill red flags: a normaliser's else-branch, and a cast that throws on Hive maps.

**On-device check** (web and Android):
- active workout cardio;
- Farmers Carry;
- edit sheet;
- PR card;
- StatsGrid;
- graduation (if reachable);
- chat card with "Rowing Machine" 20 min, which now shows minutes;
- cardio with KM blank (shows `30 min`, no `0.0 km`);
- a 40 m carry (shows `40 m`);
- a cardio set typed "12.5" MIN in the workout, then opened in the edit sheet (shows `12.5 min`, prefill "12.5");
- coach `logSet` "Farmers Carry" 4 × 40 @ 40 kg (reps kept, round 4 B P1-1);
- on the second device, per-set km comes back after restore (L11);
- a restored cardio row reopened in the edit sheet and saved (MIN label, minutes unchanged);
- one deliberate 70-min set on a single device, then a second device: expect 60 min there until Batch 2 (D8,
  recorded).

**OI board:**
- close OI-380 and OI-382;
- OI-389 "Blocked on": Batch 1b; then OI-391 (Batch 2) and OI-392 (Batch 3).

## 6. Founder decisions (Batch 1a)

- **D2 (decided 2026-10-22):** decimal minutes allowed; stored as `(min × 60).round()` seconds (U5).
- **D4 (asked 2026-10-22, explained):** send cardio minutes and km to the coach (debug-only kill switch).
- **D8 (accepted 2026-10-22): the window before Batch 2.**
  - **The issue:** a single cardio set over 60 min reads 60 min on any other device of the same account.
  - **Recommended:** accept and record it. Batch 2 follows.
  - **Alternative:** cap the cardio MIN box at 60 until Batch 2, with "log the rest as a second set".
- **D9 (go 2026-10-22; minted OI-391 Batch 2, OI-392 Batch 3, OI-393 (d), OI-394 (e)): mint four OIs** at the start of the batch: (Batch 2) cloud cap, (Batch 3) coach `logCardio` tool,
  (d) restore-shaped exlog totals reset when a set is logged on top, (e) the live exlog type heal. `mint_oi.sh` pushes,
  so it needs your go.
- **D10 (confirmed 2026-10-22): ratify the split and its order** (round 4 B P2-3): 1a now; then 1b (coach paths); then 2 (cloud cap, live
  apply) and 3 (`logCardio`, deploy); (d) and (e) planned separately, each on its own branch. The ledger's `reason:`
  lines cite this decision and its date.

## 7. Questions for delta round 2 (answered: both CONVERGED, §8 Delta 2 rows)

- **Q1.** Does every place that reads or writes cardio minutes (active workout, mirror/prefill, edit sheet both
  paths, receipt, PR, StatsGrid, graduation, week selector, chips, snapshot) handle a fractional-minute value
  correctly under rev 10?
- **Q2.** Is any existing test or pin broken by decimal-minute display or input that the plan does not name?

## 8. Finding map

| Round, finding | Severity | Disposition |
|---|---|---|
| R1, R2 (all) | P1–P3 | folded in revs 2–3. Coach-path items move with 1b (§9.1) |
| **R3 A P1-1 dedup order** | **P1** | U3 order; T2; M11 |
| **R3 A P1-2 skipped ⇒ "Workout logged"** | **P1** | the empty-set guard and chat-card accounting move to 1b (§9.1), with the T21b design |
| R3 A P2-1 unitemised km, dropped aggregates | P2 | rev 5 lift; superseded in rev 6 by the per-side move merge and OI (d) |
| R3 A P2-2 heal cast throws | P2 | rev 5 cast fix; superseded in rev 6: cast unchanged, OI (e) |
| R3 A P2-3 sheet ignores schedule type | P2 | 1b (§9.1) |
| R3 A P2-4 Retry and release seam | P2 | `toFailureCopy(debug:)` in 1a (edit sheet); tool-card Retry in 1b |
| R3 A P2-5 gate exemptions | P2 | U3 gate spec |
| R3 A P3-1..12 | P3 | `WriteResult.invalid`; payload rules → 1b; PR getter and two passes; T16 split; T2 assertions; T12a → 1b; T22; existing-set note → 1b; tier label L; flag-OFF validator; editLog legacy validation; 12.5 |
| R3 B P1-1 dedup counts discarded km | P1 | already U3 (rev 4); T2; M11 |
| R3 B P1-2 `logSet` cardio refusal dead end | P1 | 1b (§9.1): decided before APPLY, no Retry, copy points to a working route |
| R3 B P2-1 walk via `logSet` | P2 | 1b (§9.1) |
| R3 B P2-2 `0.0 km` / zero parts | P2 | U7 formatter pair; T4, T4b; M21, M22 |
| R3 B P2-3 >60 min on a second device | P2 | §0; D8; on-device leg |
| R3 B P2-4 customBox vs slot in `completeWorkout` | P2 | 1b (§9.1); 1a has no customBox lookup |
| R3 B P2-5 missing mutations | P2 | M18–M25 (W16 test → 1b with U4) |
| R3 B P2-6 board and ledger | P2 | §5 ledger reasons; D9 mint OIs; branches |
| R3 B P2-7 snapshot switch tracking | P2 | on Batch 3's OI (rev 6, round 4 B P3-7) |
| R3 B P2-8 SoT concepts | P2 | §5, four more |
| R3 B P2-9 copy strings | P2 | U5 and U7 tables |
| R3 B P2-10 sweep record | P2 | §5 diagnose-doc |
| **R4 A P1-1 lift collapses multi-set rows** | **P1** | lift dropped from 1a (§4.12.1) → OI (d); move merge per-side km (U3); T19; M28; `reschedule_week_terminal_row_test` unchanged |
| R4 A P2-1 per-field lift, "no sets" definition | P2 | moot with the lift gone; the reader uses `_perSetList` and falls back per row (U3); T9 |
| R4 A P2-2 order | P2 | U3 steps 1–3; T24; M36 |
| R4 A P2-3 rounding, week selector | P2 | U3 reader; T9, T26; M32, M34 |
| R4 A P2-4 separator, timed out, `—` | P2 | U7; T25; repoint `:274` |
| R4 A P2-5, P2-6 heal recompute and seam | P2 | the live heal → OI (e); 1a's U8 touches only the zeroing |
| R4 A P2-7 missing mutations | P2 | M26–M37 |
| R4 A P3s | P3 | km ≤ 0 → null (U1); 0.9996 boundary (U7, T25); edit-sheet exemption dropped (U3); `editLog` order (U2, T8, M30); preview fallback (U3) |
| **R4 B P1-1 distance reps erased on coach routes** | **P1** | U2 reps rule; coach table rows; T23; M31; on-device leg |
| R4 B P2-1 lift shapes | P2 | lift dropped (see R4 A P1-1) |
| R4 B P2-2 live heal without a switch | P2 | cast unchanged; OI (e) carries the switch and the full rewrite |
| R4 B P2-3 split not ratified | P2 | D10; ledger reasons cite it |
| R4 B P2-4 missing mutations | P2 | M26–M37 |
| R4 B P3-1..9 | P3 | chat-card refusal recorded (coach table); empty case (U7); legacy MIN label (U7, T8); timed unchanged (U7); km key only when Σ > 0 (U3, M37); partial copy names exercises (U7); snapshot switch tracked on Batch 3's OI (U7); restored `logged_at_ms` stamping → OI (d), same restore-shape family; on-device legs (§5) |
| **R5 B P1-1 move-merge km invisible on the mixed shape** | **P1** | merge rule by shape (U3); mixed shape → OI (d); T19 through the reader and the payload; M28 retargeted |
| R5 B P2-1 `editLog` bounds a total | P2 | per-set bounds, legacy total × set count (U2); T18; M41 |
| R5 B P2-2 sheet writes km 0, erases F5 total | P2 | `hasAggregateDistance` / `hadPerSetDistance` guard, `editSheetUpdatesFor` (U7); T8; M38 |
| R5 B P2-3 seconds hint on the MIN box | P2 | minutes hint (U7); T8; M40 |
| R5 B P2-4 set-count rule contradicts itself | P2 | one rule per type (U7); T1, T4b, T26, `:274` aligned |
| R5 B P2-5 custom cardio still `timed` | P2 | `loggingTypeHint` from `completeWorkout` (U3 step 1); T28; M39 |
| R5 A P2-1 heal goes live / rewrites keys | P2 | in-place edit (U8); footprint pin T10b; M48, M54 |
| R5 A P2-2, P2-3, P2-4 | P2 | same as R5 B P2-1, P2-2, P2-4 |
| R5 A P2-5 M34 vacuous | P2 | T26 fixture 1830 s / 0.04 km |
| R5 A P2-6 cardio weight erased | P2 | U2 table: weight never cleared, reps by the type's own field; coach rows; T23; M31b |
| R5 A P2-7 receipt fallback reader | P2 | §1; routed; T4b; M49 |
| R5 A P2-8 preview scope and separator | P2 | cardio/distance branches only, plain space (U3, U7) |
| R5 A P3s | P3 | verified-clean list (§2); fixtures (T24, T8, T4b); M50–M53, M55; raw-value validation (U2); custom cardio (U3 step 1); offsets; T17/T27 by flag value |
| R6 A P2-1 move merge drops km | P2 | second branch on "merged per-set list carries no km" (U3); T19(e); M56 |
| R6 A P2-2 M53 vacuous | P2 | T32 widget test |
| R6 B P1-1 rule 3 deletes km | P1 | same as R6 A P2-1 (U3); T19(e); M56 |
| R6 B P2-1 stale `sets_detail` | P2 | merge removes it (U3); T19(f); M58 |
| R6 B P2-2 hint not sticky | P2 | stored-type step for cardio/distance (U3 step 1); T28b; M39b |
| R6 B P3s | P3 | T18 3-set legacy leg (M59); cleared-km leg (M60); library-over-hint T28c (M39c); reps-rule cardio count (U7); invalidation on partial failure (U7); snapshot `duration_min` omitted at 0 (M61); receipt fallback rule (U7). Legacy-total copy kept per set: the box is labelled per set |
| **Delta A P1-1 / B P1-1 capture drops decimals** | **P1** | convert at capture through `cardioMinutesToSeconds`; restore via `secondsToMinutesInput`; every consumer named (U5); T32b; M66, M67 |
| Delta B P2-1 sheet digits-only and int parse | P2 | `allowDecimal` on both cardio fields; shared parser (U7); T8; M68, M69 |
| Delta B P2-2 / A P3-2 prefill under 60 s | P2 | always decimal minutes (U7); T8; M70 |
| Delta 2 A P3s | P3 | M24 retargeted; M68 through the widget; per-row cardio prefill, distance stays seconds (T8); "0.0" → `empty` (T32); offsets; re-init re-render recorded |
| Delta 2 B P2-1 malformed minutes saved as 0 | P2 | refuse the row (U7); T8; M72 |
| Delta 2 B P3s | P3 | M68 through the rendered field; "1.02" re-render recorded; snapshot wording; M73 for the minimum-second copy |
| Delta P3s | P3 | no trailing-dot trim; "At least 1 second per set."; snapshot one decimal (M71); stale digits-only line; on-device decimal leg (§5) |
| R7 B P2-1 / A P3-1 `sets_detail`-only destination | P2 | each side from `perSetList` (U3); T19(g); M62 |
| R7 A P3s, B P3s | P3 | emptied legacy km box → null (U7); M60 targets the builder output + legacy leg; T19 payload seam; short cardio `duration_sec` (U7, M61); Sled Push count (T23, M63); partial-failure invalidation (T30, M64); coach weight × reps on custom cardio (T28b); SEC 4-digit limit recorded (U5); F5 in OI (d); misplaced sentences moved |
| R6 A P3s | P3 | M28 → (d); M38 via `editLog`; M50 fixture; heal clears with `duration_sec: 0` (U8, T10); hint only for cardio/distance (U3); W16 guard into 1a (T31, M57); legacy blank-text rule (U7); offsets |
| R5 B P3s | P3 | heal edits in place (U8, M48); snapshot reads the helpers (U7); copy unit per box and partial shape (U7, T30); sheet stays open (U7, M46); mutation gaps M42–M47; `editLog` U2 table and `completeWorkout` refusal recorded (U3); `ExercisePR` initializer (U7); chat-card retry → 1b |
| R3 B P3-1..9 | P3 | tier 3 verified; release seam; naming; custom cardio copy → 1b; sheet `isComplete` → 1b; D5 note → 1b; on-device list; diagnose path; `_PrTile` split noted (pre-existing timed behaviour, unchanged) |

## 9. Inputs for the later batches

### 9.1 Batch 1b: coach paths

These are kept from rounds 1–3, for that batch's own plan:
- **Type resolution:** `logExercise(loggingTypeHint:)`, resolved library → customBox → hint → distance-aware
  shape.
  - `LoggingTypeRepairMigrator` leaves cardio and distance alone.
  - A custom `weight_reps` exercise with 0 kg stays `weight_reps` (recorded).
- **Empty incoming sets:** dropped after normalisation and before dedup; refused (`all_sets_empty_after_type`) when
  none remain.
- **Chat card:** a refused exercise is `skipped` (named). When nothing was saved, the card shows a non-saved status,
  never "Workout logged". The saved list is filtered by outcome indices. This is T21b, round 3 A P1-2.
- **Dispatcher:**
  - payload `durationMin`/`durationSec`/`distanceKm`;
  - the null check depends on type;
  - library timed with reps only → seconds (the shim at `workout_repository.dart:1384`);
  - library cardio with nothing → refusal copy;
  - `toolFailureCopy`.
- **Tool card:** no Retry on non-retryable codes.
- **Library or custom cardio through `logSet`** (round 3 B P1-2):
  - decided **before APPLY**, as a terminal "not logged" state with no Retry;
  - copy points to a route that works, e.g. "Not logged. Send the minutes (and km if you have them) and I'll queue it,
    or use LOG MY WORKOUT." This follows the coach-log-truth "queue" wording;
  - or treat reps as minutes, with the summary shown before APPLY. That is the founder's choice in 1b.
- **Walk through `logSet`** (round 3 B P2-1). Both cases show their interpretation before APPLY:
  - an unresolved id comes back as `bodyweight_reps` "45 reps";
  - "Slow Walking" reps come back as 45 s.
- **`completeWorkout`** (round 3 B P2-4): the slot type the user saw wins over customBox. The failure branch gets
  `ErrorTelemetry` and a visible note.
- **W16 test:** a stored `cardio` custom row is not re-typed by `_dataDrivenRepair`.
- **`LogWorkoutSheet`:** type resolved library → customBox → the schedule row's `logging_type`; MIN/KM, KM/KG,
  SEC; per-type summaries.
- **Confirm-card summaries** by type.
- **`draftExerciseSets`** carries km and keeps distance-only sets.
- **`submitWorkoutDraft`** passes the type.

### 9.2 Batch 2: cloud cap

Unchanged from rev 3:
- **Order:** migration (re-issue the 061 comment; one transaction), founder go, apply and verify, then the
  `.clamp(0, 21600)` literal.
- **Kill-switch fallback:** through a named constant.
- **Rollback:** never re-tighten.

### 9.3 Batch 3: coach `logCardio` tool

Unchanged from rev 3:
- `requiresCapability: "log_cardio"` as a literal;
- capability-routed captain manual line plus a golden test;
- tool-count repoints (21 → 22);
- deploy by skill §6.13;
- the walk smoke test.
