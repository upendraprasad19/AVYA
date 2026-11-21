---
reviewed_at: 2026-10-21T16:14:14+05:30
staged_against: 1a478dd07bd5
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 5
verdict: accepted
---

# Code Review — 1a478dd07bd5 (branch `swap-move-design`)

Reviewed diff `1a478dd07bd5` (pre-fix); this file is named by the post-fix staged hash
`215812fec86a`. One fresh, read-only Sonnet reviewer with an exhaustive command list (no tests: the
full suite was running on the same tree). Mutations were proposed, not applied; the author ran them.
No P0. The reviewer found no wrong-exercise attribution of logged sets on the save path and no
index-keyed `ActiveWorkoutData` field left un-remapped.

## Finding 1 — P1 — guard_without_its_mirror
- **file:line:** lib/features/train/screens/active_workout/screen.dart (move toast UNDO `onPressed`)
- **claim:** UNDO tapped while a NEW move is picked reorders the list but leaves the controller's
  source index, which now names a different exercise (the bar and MOVING jump to it).
- **verification:** `git grep -n "_move.cancel" lib/features/train/screens/active_workout/screen.dart`
- **suggested-fix:** cancel move mode in the UNDO's `setState`.
- **status:** accepted — fixed (`_move.cancel()` in the applied-UNDO `setState`). Test:
  `swap_move_screen_test.dart` "UNDO while a new move is picked leaves move mode". Mutation (the
  `cancel` line deleted) → that test RED.

## Finding 2 — P2 — guard_without_its_mirror
- **file:line:** lib/features/train/services/superset_persist_logic.dart (`applySupersetGroupsByIdentity`)
- **claim:** Swap C→E (session-only) then pair E with D: the identity write stores the group on D
  alone (half a pair), where the old index write stored C+D.
- **verification:** session `[E g1, D g1]` over stored `[C, D]` → `[null, 1]`.
- **suggested-fix:** do not store a group that lands on one stored row.
- **status:** accepted — fixed: a session group of ≥2 that lands on exactly one stored row is written
  as null; a group already single in the session is written as it is. Tests (with both mirrors: both
  partners stored; partner an untouched stored row): "a pair whose partner has no stored row is not
  half-stored". Mutation (threshold `>= 2` → `>= 99`) → that test RED.

## Finding 3 — P2 — guard_without_its_mirror
- **file:line:** lib/features/train/services/superset_persist_logic.dart
- **claim:** one-pass matching lets an id-less entry claim the row a later entry owns by id.
- **verification:** stored `[Row x2, Row x1]`, session `[Row(no id) g5, Row x2 g3]` → x2 gets 5.
- **suggested-fix:** id-to-id pass first, then the name fallback.
- **status:** accepted — fixed (two passes). Test: "an id match is never taken by an earlier
  name-only entry". Mutation (the two passes swapped) → that test RED.

## Finding 4 — P2 — writer_reader_drift
- **file:line:** lib/features/train/screens/active_workout/screen.dart (`Column(children: [?supersetLabel, _ExerciseCard(…)])`)
- **claim:** a move that flips the SUPERSET label rebuilds the card State (unkeyed children paired
  by position).
- **verification:** screen test reading `tester.state(...)` of the moved card before and after.
- **status:** false_alarm — Flutter's `updateChildren` matches unkeyed children from BOTH ends, so
  the trailing `_ExerciseCard` keeps its element when the leading label slot appears or disappears.
  Measured: with an always-present slot reverted to `?supersetLabel`, the State-identity test stays
  GREEN. The test is kept as a guard of the real mechanism: removing the Column's `GlobalKey`
  reddens it ("a moved superset member keeps its card State").

## Finding 5 — P2 — guard_without_its_mirror
- **file:line:** lib/features/train/providers/train_provider.dart (`applyExerciseMove`)
- **claim:** the only staleness check is the list length; a result computed before a same-length
  change (a set toggled) would silently revert it.
- **verification:** compute r, `toggleSet(0,0)`, apply r → the toggle is lost.
- **status:** accepted — fixed: `ExerciseMoveResult.basedOn` is the exact state it was computed
  from; `applyExerciseMove` refuses unless `identical(r.basedOn, state)`. Test: "refuses a result
  computed before a later change (no silent revert)". Mutation (the identity check deleted) → RED.

## Lenses that returned clean (reviewer's evidence, summarised)
- writer_reader_drift: every `ActiveWorkoutData` field classified (5 remapped, grouping mode reset,
  `reopenedExercises` name-keyed, the rest not index-keyed); `completeWorkout` and the exlog/wlog
  writers use the moved list consistently and stamp by name/id; `ActiveWorkoutPersistence` stores no
  order.
- function_exception_swallow: 0 added `.invoke(`.
- blast_radius_mismatch: max tier account (`lib/core/**`), matching.
- secrets_in_tree: 0 hits.
- unawaited_no_error_sink: 1 added (`markSwapMoveHintSeen`), `MigratedKey.write` catches + reports.
- missing_input / asserted_fixture_value: no unguarded path or key; weak spots noted, not findings.

## Founder triage notes
Triage by the author (account tier: advisory). 4 accepted and fixed in the batch, each with a test
that reddens under its mutation; 1 false alarm, disproved by measurement.
