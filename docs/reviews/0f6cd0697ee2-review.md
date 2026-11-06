---
reviewed_at: 2026-11-05T12:00:00+05:30
staged_against: 0f6cd0697ee2
reviewed_sha: d4cee2e8
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, asserted_fixture_value]
findings_count: 3
verdict: accepted
verdict_note: 0 P0, 0 P1, 3 P2, all three fixed in the follow-up commit (see each status)
---

# Code Review — 0f6cd0697ee2 (OI-458, the Upper day avoids its week's push / pull / shoulders_arms names)

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** `lib/shared/repositories/plan_engine/exercise_selector.dart` (`_pickCoreList` edits)
- **claim:** the ship-dark core-list copy of the avoid had no proof: no test set `enable_core_list_pool`, so every mutant hit only the cascade.
- **verification:** `grep -rn earlierPush test/` returned nothing.
- **suggested-fix:** a flag-ON sweep plus a mutant on the `_pickCoreList` guard, or weaken the wording.
- **status:** fixed. A flag-ON test over the real library (155 pairs without the avoid, 2 with it) and mutants C1, C3, F5, C5 all red. The B-variant guard (C2) and B seed (F6) are not killable on the shipped library (identical output with and without them), stated in the diagnose doc.

## Finding 2 — P2 — guard_without_its_mirror
- **file:line:** `exercise_selector.dart` `buildPinnedDays` `fresh()`
- **claim:** the repeat phase's Upper frame, when it falls into the fresh path, is a ONE-frame `pickV4` call whose earlier-day sets are empty, so it kept the old leftovers behaviour; the strength-goal 5-day Upper lead lift can also move to a lower-ranked sibling.
- **verification:** read `buildPinnedDays`; reproduced by a repeat-phase test (32 pairs without a seed).
- **suggested-fix:** pass the earlier feeder names into `fresh()`, or state the residue.
- **status:** fixed. `pickV4` takes `earlierFeederNamesA/B`, `buildPinnedDays` collects the feeder frames it built and passes them (32 -> 0 pairs, cascade and core-list). The strength lead-lift swap is accepted and stated (in-pattern, filters run before the tiebreak).

## Finding 3 — P2 — asserted_fixture_value
- **file:line:** `test/contracts/cross_day_variety_behavioral_test.dart`, `test/helpers/injury_floor_sweep_lib.dart`
- **claim:** no injured persona; the control was a lower bound (`>= 10`) blind to extra avoidance; the `kThinCeilings` history comment was not extended.
- **verification:** read the test and the lib comment.
- **suggested-fix:** one injured persona; an exact control; a dated sentence in the comment.
- **status:** fixed. Shoulder-injury sweep (52 -> 20 pairs, no contraindicated pick), the control is now exactly 10, the `kThinCeilings` comment carries the 2026-11-05 entry.

## Checked and clean (reviewer's own list)
Callers of `pickV4`; `previousPhaseNamesByDay` readers (names feed only the soft avoid); collection point is after the L6 pass; the golden key sets (326 changed keys, all 4d/5d); the test literals (2 of 2 pass); `kThinCeilings` 4 -> 2 is a real ratchet fall; `docs/blast_radius.yaml:112` marks the path `platform`; the board move removes only the OI-458 block from open and only appends to closed. Lenses 2, 4 and 5 do not apply.

## Founder triage notes
(none yet)

## Tuning entry
- **2026-11-05** - blast-radius platform - 3 findings; 0 false_alarm; tuning: none (the lens-6 "mirror of a new seed" case, a one-frame call that cannot see its siblings, was already covered by the guard_without_its_mirror method).
