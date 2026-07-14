---
branch: workout-equipment-exclusions
scope: Batch 5 crash-fix slice — equipment_needed bare-String swap crash (diagnose e9d1c7)
blast_radius: account
reviewer: context-blind adversarial B-pass (self-initiated, §4.3)
verdict: accepted
---

# B-pass — equipment_needed bare-String swap crash fix

Context-blind adversarial review of the staged diff. Every claim verified against files. **No P0/P1/P2
defects.**

## Verified-clean

- **Data fix COMPLETE.** `assets/data/exercise_library.json`: 258 rows, 100% List `equipment_needed`, 0
  bare Strings, JSON structurally valid (no comma/bracket damage). The 9 corrected values match existing
  conventions (`["Bodyweight"]` / `["Dumbbells"]`); all of E252–E260 present. `equipment_tier` stays a
  List on all 258 → `queryV4` (filters on `equipment_tier`) genuinely unaffected.
- **Reader completeness — no other crash site.** Swept all 14 `equipment_needed` occurrences + a
  broadened `equipment.{0,40}(as List|.cast<)` regex. Only `swap_sheets.dart:28` + `:130` were unguarded
  (both fixed via the helper). Every other reader is pre-guarded `is List`
  (`exercise_selector.dart:727/907`, `exercise_repository.dart:129`, `sync_community.dart:259`) or a
  no-cast pass-through (`ai_snapshot_builder`, `template_service`, `swap_service`). The fix's completeness
  claim is TRUE.
- **Helper correct + reachable.** `ExerciseData.parseEquipmentNeeded` (`train_provider.dart:166-170`): all
  three branches return `List<String>`, no throwing input (tolerates null/non-String list elements);
  `static`, reachable at both swap sites (`swap_sheets` is `part of screen.dart` which imports
  train_provider).
- **Re-seed reaches existing users.** `_exerciseLibraryVersion = 6`; gate `storedExVersion < 6` fires for
  v5 (and legacy v0) users; `_seedExercises` `putAll` overwrites by id; version written only on success
  (retries on failure). Pre-reseed window / persistent failure → the defensive helper keeps swap crash-free.
- **No regression.** List path byte-identical to the old `_parseExerciseMaps` branch; swap_sheets:130
  null→original preserved; the `const []` empty case is never mutated (all usages are reads/ctor args).
- **Test fails-without-fix.** `equipment_needed_shape_test` (4/4): the JSON data-quality test FAILS without
  the data fix (9 offenders) + catches a re-introduced bad row; helper tests cover the bare-String crash
  case + null/empty/bad-type. SoT `equipment_needed_shape` accurate (does not falsely claim
  reader_manifest_complete). Diagnose `e9d1c7` verified accurate.

## Nits (P3, non-blocking)

- Diagnose `readers:` originally omitted the second fixed site `swap_sheets.dart:130` → **folded** (added).
- SoT `equipment_needed_shape` readers list only the 2 fixed readers (not the 6 pre-guarded/pass-through) —
  acceptable; it does not claim `reader_manifest_complete: true`. No change.

## Verdict: accepted
Data fix exhaustive, every remaining `equipment_needed` reader crash-safe, the helper never throws,
re-seed reaches existing users, tests fail-without-fix. No P0/P1/P2.
