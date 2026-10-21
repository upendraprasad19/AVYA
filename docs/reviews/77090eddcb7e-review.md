---
reviewed_at: 2026-10-21T18:10:00+05:30
staged_against: pre-fix staged diff of l2-custom-repair (hash not recorded at dispatch)
renamed_to_final_hash: 77090eddcb7e
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 9
verdict: accepted
---

# Code Review — 77090eddcb7e (Batch 0b, diagnose c3e9a4)

Branch `l2-custom-repair`, stacked on Batch 0a (`l2-no-custom-autoadd`): the one-time
`L2CustomAppendRepairMigrator` strip of the customs the removed lever L2 put into planned
rows, the repeat-pin strip in `_buildRepeatPins`, and the shared predicate
`auto_appended_custom.dart`. One fresh read-only Sonnet reviewer, no file mutation allowed
(lens 6 reasoned from code). It ran `flutter analyze lib/` (60 infos, none new) and the six
named test files (all green).
Result: 0 P0, 0 P1, 2 P2, 7 P3. All nine are fixed in this commit. Each fix was then proven by
mutation: 15 mutations by script, restored by copy and sha1-checked, each turning only its
target red. The list is in the diagnose doc `bpass_fix_mutations`. The file is named for the
final staged hash, after the fixes.

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** lib/core/services/l2_custom_append_repair_migrator.dart (pre-fix :132, :167)
- **claim:** the migrator skipped today only while `ActiveWorkoutPersistence.readState() != null`.
  That `active_session` key is written only after a set is logged
  (`exercise_card.dart:626`, `:681`). A session started with no set logged therefore read as
  closed, and the background post-restore heal could rewrite today's row under it. Then
  `_persistSupersetGroups` would have indexed the session's longer list into the shorter stored one.
- **verification:** `git grep -n "ActiveWorkoutPersistence.writeState" lib`
- **suggested-fix:** never rewrite today in this pass (no latch), or use an in-memory session flag.
- **status:** fixed. Today's row is never rewritten. A pass that would have changed it sets
  `todayPending` and does not latch, and the row is past by the next launch. The import is gone.
  Test: "today's row is never rewritten and blocks the latch; the next day it is past and the
  pass latches" (mutation m1).

## Finding 2 — P2 — writer_reader_drift
- **file:line:** diagnose "Known limits" bullet 1; `plan_integrity_reconciler.dart:114`, `:183`;
  `workout_write_service.dart:678`
- **claim:** the multi-device limit was stated wrongly. On the repaired device the full-copy rewrite
  kept the old `arranged_at_ms`. An old-build device's newer swap then wins the merge. After that
  device updates, both carry the same stamp, the merge keeps local on a tie, and the latched device
  stays polluted.
- **verification:** `sed -n 180,186p lib/core/services/plan_integrity_reconciler.dart`
- **suggested-fix:** correct the doc; re-arm on `discardedLocalArrangement`, or re-stamp.
- **status:** fixed. A rewritten row that carries `arranged_at_ms` is re-stamped with the write
  time, so the stripped week is strictly newer. The diagnose limits are rewritten, including the
  re-stamp trade-off. Test: the re-stamp test (mutation m3).

## Finding 3 — P3 — guard_without_its_mirror (one-shot push)
- **file:line:** migrator pre-fix :194-195, :211-218
- **claim:** the push ran only when this pass wrote rows. A pass that stripped rows and then
  stopped, failed or withheld its push let the next pass (rows == 0) latch without pushing. The
  latch was also set when the push had been withheld.
- **status:** fixed. The push is issued after every completed scan, and the latch requires that it
  was issued. A no-op push is skipped by the plan skip index, and a failed one is re-sent, because
  the index confirms only after a successful upsert. Tests: "stripped every row but stopped before
  the push" (m6) and "push withheld … no latch" (m7).

## Finding 4 — P3 — asserted_fixture_value (masked tests)
- **file:line:** test/contracts/l2_custom_append_repair_migrator_test.dart
- **claim:** two parts.
  - The `completed` fixture was protected by the write service's own refusal, and the `rest`
    fixture by the never-empty guard, so dropping the status/type filter reddened nothing.
  - "Idempotent" passed because of the latch.
- **status:** fixed.
  - The never-written test records every attempted write through the override and asserts none.
    Its fixtures carry library + custom, and travel is added.
  - Idempotence clears the latch and asserts no write is attempted.

## Finding 5 — P3 — guard_without_its_mirror (paused/travel)
- **file:line:** migrator pre-fix :154
- **status:** fixed for `paused`, which is stripped (pending, not terminal). Test m2.
  - `travel` stays skipped: travel mode never sets a row back to `planned`, and a row is past
    within 7 days. Documented in the diagnose limits.

## Finding 6 — P3 — guard_without_its_mirror (two predicate holes)
- **file:line:** lib/core/services/auto_appended_custom.dart (pre-fix :27-33)
- **claim:** two holes.
  - (a) A repeat-pinned custom had no provenance, so the strip removed it.
  - (b) `libraryHas` counted a community-approved custom in `exerciseBox` as library.
- **status:** fixed.
  - (a) `_buildCustomExercise` stamps `customOrigin: 'repeat_pin'`. `PlannedExercise` carries it
    through `copyWith` and `toMap` writes `custom_origin`, and the predicate keeps it. Mutations
    m10–m13.
  - (b) `isLibraryRow`, where `source: 'community'` is not library. Mutation m9.
  - The author found the fix's own mirror. `getByExactName` returns the FIRST row of a name, so a
    community row sorting before a bundled row of the same name hid the bundled one. Both callers
    now use the new `ExerciseRepository.hasExactNameWhere`, which checks every row (m8, m14).

## Finding 7 — P3 — writer_reader_drift (stale read before lock)
- **file:line:** migrator pre-fix :154-175 with `workout_write_service.dart` `_acquireLock`
- **status:** fixed.
  - The new `upsertScheduled(ifUnchangedFrom:)` refuses with `rowChangedMessage` when the stored
    row is no longer the object the caller read. The migrator passes its row and does not latch on
    that refusal.
  - A real-lock concurrency test makes another writer hold the date while the pass reads stale:
    m4 and m15 redden it, and m5 reddens the changed-row tests.

## Finding 8 — P3 — docs
- **status:** fixed. The diagnose writer cite now points at `buildPinnedDays` (:719).

## Finding 9 — P3 — blast_radius_mismatch (process)
- **status:** fixed. `docs/plan-reviews/l2-custom-repair.md` lands in its own commit right after
  this one (the hash-fixed-point rule, SKILL.md §3).

## Clean lenses
2 function_exception_swallow, 4 secrets_in_tree and 5 unawaited_no_error_sink were clean. 7
missing_input was clean: every path, key and seam exists. 8 asserted_fixture_value was clean apart
from F4: the fixture names were checked against `assets/data/exercise_library.json`.

## Founder triage notes
None needed: no P0 or P1. Every finding was fixed in this batch and proven by mutation.
