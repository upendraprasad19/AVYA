---
reviewed_at: 2026-11-12T12:05:00+05:30
staged_against: generator-step1-1br b459c6da (the batch commit 67d39676 merged with origin/main e1becc8d), diff origin/main...HEAD, 37 files, CI green on the head
blast_radius: platform
reviewer: one fresh context-blind Sonnet seat (adversarial B-pass)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 2
verdict: accepted
---

# Code Review (B-pass) — Unit 1B-R, the loaded move wins for an equipped user (`generator-step1-1br`)

One fresh, context-blind Sonnet seat reviewed `git diff origin/main...HEAD` at `b459c6da` (CI green) read-only, with
an exhaustive command list (read-only git, file reads, read-only `python3`, `dart analyze` on changed files, four
named test files) and a mutation protocol limited to `core_list_selector.dart` and `exercise_selector.dart` (sha256
before, `git checkout --` after; it reported `sha256sum -c` OK and a clean `git status`). `dart run scripts/*`,
`scripts/*.sh`, network tools and database statements were forbidden.

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** lib/shared/repositories/plan_engine/exercise_selector.dart:187 (`walkedNames: avoidNames,`)
- **claim:** The caller-side wiring that tells `rankedPool` which names the walk will skip was unprotected: deleting
  the argument left all 28 tests green. T5 cannot see it because its walked row and the next loaded row match the slot
  equally, so a `topFit` that is the walked row produces the same pick. (The `topFit` side, M14 / M19, was pinned.)
- **verification:** the seat deleted the line (`grep -c` 0) and ran `loaded_wins_behavioral_test.dart`: `+28: All
  tests passed!`. Its second mutant (`walkedNames: avoid`) is equivalent: `rankedPool` already skips soft-avoided and
  demoted names itself.
- **suggested-fix:** a real-`pickV4` phase-1 test with a non-empty avoid set where the walked loaded row matches best
  and the next loaded row matches worse than a bodyweight row.
- **status:** accepted, fixed. T5b (`loaded_wins_behavioral_test.dart`): a Chest feeder day picks Dumbbell Bench Press;
  the Upper day walks past it; the next loaded row (an isolation-typed machine fly) misses the compound slot's type,
  Push Up hits it, so the Upper day takes Push Up. Green on the real code; with the argument deleted (M23, `grep -c` 0)
  T5b alone reddens (`+28 -1`); file restored, `sha256sum -c` OK. Recorded in the test header and diagnose `e4b7a2`.

## Finding 2 — P3 — missing_input (wording)
- **file:line:** lib/shared/repositories/plan_engine/core_list_selector.dart (the Ruling 3 comment above `byRest`);
  docs/sot_registry.yaml `core_list_pool`; docs/diagnoses/2026-11-12-generator-loaded-wins-e4b7a2.md
- **claim:** "the loaded row that will actually be picked" overstates: for an injured user whose pool holds curated
  substitutes, `_selectCandidate` filters to those and re-sorts them by the curated index, so `topFit` is not the pick.
  Benign: the new key changes neither that list's members nor its order.
- **verification:** read `exercise_selector.dart` `_selectCandidate` (:787-812; the author re-read it: membership by
  `prefs.contains`, order by `prefs.indexOf`).
- **status:** accepted, fixed: one sentence in the code comment, the registry description and the diagnose doc ("the
  key is inert there").

## Checked clean (seat's report, condensed)
- Skip-set parity: `topFit` skips demoted (exact), soft-avoided (exact) and `walkedNames` (lowercase), which equals
  `_preferNovel`'s set built in `_pickCoreList`; demoted names are non-empty only from phase 2 while `topFit` runs in
  phase 1 only.
- `byRest` vs the sort: same key order (demoted, soft, easier gap, new key, rest keys, id); the new key depends on the
  row and a constant, so the sort stays a total order. `byRest` ending `return 0` instead of the id tie-break is an
  equivalent mutant (rows tied on every rest key have equal `slotMatch`). Dropping `!fits(r) &&` from the new key
  reddens.
- Kill switch: old and new `rankedPool` compared line by line; with `loadedWins: false`, `fitApplies` is the old
  expression, `topFit` stays null, `topFitMatch` 4 makes the new key a constant 0, so the order is identical. One lib
  caller (`_pickCoreList`).
- Phase guard, core slots, null capability (tier items, as `needsImplementPreference`), a bodyweight tier (empty kit,
  no `topFit`), the emergency path (`easierGap` non-null for every pooled row).
- Lens 8: 870 rows, core levels 136 / 165 / 137 computed from the asset; G0355 `[beginner, intermediate, advanced]` in
  the asset and the source; `_meta` beginner 62; the cross-day pin 12 holds with `loadedWins` forced false (Ruling 1
  alone). The older seed tests' sha pins were not recomputed by the seat (they run in CI, green).
- Lens 1: registry ranges (255, 836-848, 484-489, 183) and the diagnose doc's cited lines match the code;
  `core_levels` is bundle-only.
- Lens 3: plan-engine ranking, seed version and one data row, consistent with `platform`.

## Founder triage notes
Both findings fixed in this batch by the author (no product trade-off); verdict accepted.

## Tuning entry
- **2026-11-12** - blast-radius platform - 2 findings; 0 false_alarm; tuning: the one gap was a caller-side wiring whose only test used a fixture where the wired and unwired values give the same answer (two loaded rows of equal match). For a new parameter that a caller must pass, brief the seat to delete the argument at the call site and run the tests, and require a fixture where the passed value changes the outcome; the author's mutation list had pinned only the callee side.
