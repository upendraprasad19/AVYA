---
branch: workout-equipment-exclusions
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-equipment-exclusions-bpass.md
---

# Plan review — workout-equipment-exclusions (Batch 5 crash-fix slice)

Batch 5 ⑥ ("equipment tier + exclusions") turned out to require a library-wide equipment normalization the
plan didn't anticipate, and its ground-truth surfaced a **live pre-existing crash**. Per the founder's
decision (2026-07-14) this branch ships the **crash-fix slice first**, then the ⑥ A→B→C slices land as
their own branches this release. This slice = the `equipment_needed` bare-String crash fix only (diagnose
`e9d1c7`); the exclusions FEATURE is NOT in this branch.

## Review rounds (≥2, before code)

- **Round 1 — the ⑥ equipment ground-truth (context-blind investigation).** Mapped the equipment
  pipeline against code and FOUND the crash: 9 library rows (E252–E260) store `equipment_needed` as a bare
  String, and `swap_sheets.dart:28`/`:130` cast it `as List?` → `_CastError` on selection. Also corrected
  the brief's premise: `queryV4` filters on `equipment_tier` (not `equipment_needed`), so the tier path was
  unaffected and this is a swap-UI crash, not a generation bug.
- **Round 2 — adversarial B-pass on the implemented fix** (`docs/reviews/workout-equipment-exclusions-bpass.md`):
  verified the data fix is complete (0 bare-String rows remain, JSON parses), the shared shape-tolerant
  `ExerciseData.parseEquipmentNeeded` covers every unguarded cast site, the seed-version bump re-seeds, and
  there is no regression for the 249 good rows.

## Ground-truth verification (true — self-verified against code)

`swap_sheets.dart:28` cast (`(exerciseData['equipment_needed'] as List?)` — throws on a non-null String,
the `?? []` never runs); `queryV4` filters on `e['equipment_tier']` (`exercise_repository.dart:268-277`),
NOT `equipment_needed`; `seed_service.dart:81` `_exerciseLibraryVersion` re-seed gate; the 9 corrected JSON
rows parse (258 exercises, 0 bare Strings).

## Verdict: converged

The crash-fix slice is complete + verified: data corrected at source + a defensive shape-tolerant reader,
diagnose-doc `e9d1c7` (validated), behavioral test `equipment_needed_shape_test` (helper + a JSON
data-quality guard) 4/4, `flutter analyze` clean, SoT `equipment_needed_shape`. B-pass accepted
(`docs/reviews/workout-equipment-exclusions-bpass.md`). The ⑥ exclusions feature (A normalization → B
engine → C UI) ships as separate branches this release.
