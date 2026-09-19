---
branch: workout-equipment-vocab
scope: ⑥ slice A — equipment_needed vocabulary normalization (EquipmentVocab + gate + owned-write normalize)
blast_radius: account
reviewer: context-blind adversarial B-pass (self-initiated, §4.3)
verdict: accepted
---

# B-pass — ⑥ slice A equipment_needed vocabulary normalization

Context-blind adversarial review of the staged diff. Every claim verified against files/data (byte-level
HEAD-vs-staged comparison + test run + generator `--check` + `flutter analyze`). **No P0/P1 defects.**

## Verified-clean

- **JSON data integrity.** 258 rows, valid JSON, 0 empty `[]`, 0 non-list, **0 non-canonical tokens** (11
  distinct canonical used + `smith machine` unused → confirms SUBSET-not-equality). HEAD-vs-staged with all
  258 `equipment_needed` blocks masked was **byte-identical** — floats (`5.0`), `equipment_tier` (untouched
  List on all 258), and every other field preserved. ONLY equipment_needed changed.
- **EquipmentVocab structural invariants.** `canonicalTokens` (12) == `_precedence` set exactly → `indexOf`
  never −1 for a mapped token; every one of the 70 `_aliases` values ∈ canonical; no dead/duplicate alias
  keys. Defuses the "precedence miss" + "alias→non-canonical" concerns.
- **normalize correctness.** No whitespace split; `" or "` collapses to ONE most-accessible token (no OR→AND
  flip); dedupe preserves order; unmappable→dropped→`[]`. Independently recomputed the tricky cases —
  "Box or Bench"→bodyweight, "Machine or Barbell"→barbell, E044 `["Dumbbell","Box or Bench"]`→
  `[dumbbells,bodyweight]` — all match the tests.
- **Owned-write seam.** `workout_repository.dart:1375` correctly wraps `<String>[equipment]`; the AI tool
  (`tool_dispatcher.dart`) feeds free-text in. `create_custom_exercise_sheet.dart:84` hardcodes `[]` (no
  equipment field) → genuine no-op, not a missed seam. `[]` safe downstream (coach snapshot, cloud upload).
- **Seed re-propagation.** `_exerciseLibraryVersion` 6→7 triggers the upgrade; `putAll` by id overwrites only
  `exerciseBox` (never customBox/user data) → non-destructive; restore never re-seeds the library, so old
  free-text tokens can't resurrect.
- **No live regression.** Live plan gen `plan_generator.dart:112 → queryV4` filters `equipment_tier` (:270),
  NOT equipment_needed; `ExerciseSelector.pick` (the only equipment_needed reader) has 0 callers. Only the
  dead V3 `== 'bodyweight'` exact-match exists (canonical, preserved). No test asserts a pre-normalization
  equipment value.
- **Gate fails-without-fix.** Proven: the HEAD (un-normalized) library has 80 non-canonical tokens →
  `expect(nonCanonical, isEmpty)` fails; a future raw "Treadmill" row fails identically.
- **Empirical.** `flutter test` on both contract files: **19/19 passed**, incl. the behavioral
  `createCustomExercise("Cable Machine")` → Hive read-back → `["cables"]` (genuinely drives the production
  seam). Generator `--check`: OK (committed asset == `EquipmentVocab.normalize(asset)`, idempotent).
  `flutter analyze` on all 4 changed Dart files: No issues.
- **Tier/process.** Blast-radius `account`; no `sync/**`/`plan_engine/**`/migration staged; plan-review
  record `review_rounds: 2`, `ground_truth_verified: true`, `verdict: converged`.

## Nits (P2, non-blocking)

- SoT `equipment_vocab` readers list omits the canonicalization-agnostic pass-through readers (swap_sheets,
  template_service, swap_service, train_provider) — defensible scoping (they parse any string shape-tolerantly,
  none exact-match a token); the entry does not claim reader-manifest-complete.
- Line-citation `:1370`→**:1375** for the owned-write normalize (4 comment lines shifted it) — **folded**
  (corrected across SoT + test + plan + record).
- Process reminder: `feat`/`refactor` slice ⇒ no diagnose-doc required (rule 22 gates only `^(fix|bug|regression)`);
  the commit must not be typed `fix:`.

## Verdict: accepted
Data fix byte-clean (only equipment_needed changed), the vocab is internally consistent, `normalize` has no
OR→AND-flip / whitespace-split / precedence-miss bug, the owned seam normalizes with a genuine write→read
behavioral test, the gate fails-without-fix, seed v7 is non-destructive, and there is no live plan-generation
regression. No P0/P1.
