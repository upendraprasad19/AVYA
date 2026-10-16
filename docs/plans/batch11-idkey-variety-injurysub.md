# Batch 11 — ID-keyed history (W3.3) + Variety engine (W3.4) + Injury-sub map (①.1d)

> Branch `workout-idkey-variety-11` (off main `15c3975a`, includes Batches 9+10). Blast radius
> **platform** (`plan_engine/**` + sync seam). Ship-dark. Item bundle W3.3 + W3.4 + ①.1d.
> **SPLIT into 3 sequential sub-units on ONE branch** (ground-truth-recommended — like Batch 7).

## 0. SPLIT decision + sequencing (ground-truth-recommended)

Three items, each its OWN ship-dark flag, implemented as 3 sequential sub-units (self-B-passed
commits) on this one branch, merged once with one plan-review record:

- **11-A = W3.3 ID-keyed history.** INDEPENDENT of the cascade; HIGHEST cross-tier risk (Hive write +
  cloud onConflict + 3 name-matching readers). FIRST + isolated.
- **11-B = ①.1d curated injury-substitution map.** Mutates `_cascadeFill` (the PRIMARY re-ranker —
  injury-safety is higher-stakes). SECOND.
- **11-C = W3.4 cross-phase variety.** Mutates the SAME `_cascadeFill` seam (SECONDARY re-ranker,
  applied AFTER the injury-sub preference). THIRD.

No hard A↔B↔C dependency (W3.3's id history does NOT feed the cascade; B+C don't read exlog ids).
B+C compose at `_cascadeFill`: **injury-curated substitute first, then variety** (safety before novelty).

## 1. Ground truth (subagent-reported; ★ = re-verified by me against code)

### 11-A (W3.3)
- ★ `WorkoutWriteService.logExercise` (`workout_write_service.dart:55-70`) takes `exerciseName`, NO
  `exercise_id`; entry map fields `:166-179` (no exercise_id). Key `exlogKey(date, name)` `:1056-1063`
  (UUID-v5 of the name — W3.3 must NOT change the key).
- ★ **CLOUD-SAFETY INVARIANT (VERIFIED):** `sync/sync_workout.dart:198-199` —
  `final exerciseId = (log['exercise_name'] as String?) ?? key;` populates the cloud `exercise_id`
  column with the NAME; onConflict `:308` = `user_id,workout_log_id,exercise_id,set_number` (partial
  UNIQUE, comment `:225-229`). **The Hive library-`exercise_id` field must NEVER flow into `:198-199`**
  — else old (name-keyed) + new (id-keyed) rows for the same exercise land under different keys →
  DUPLICATE cloud rows. Cloud `workout_log_exercises` has both `exercise_id`+`exercise_name`;
  `workout_log_sets` has `exercise_id` but no `exercise_name` (`live_schema_columns.json:55-56`).
- id availability at the log site: `ExerciseData` (`train_provider.dart:136-161`) has NO id field; the
  schedule map DOES carry `exercise_id` (read `:331,:365`) but it's DROPPED at `ExerciseData` build
  (`:378-394`). Coach `logSet`: id in hand at `tool_dispatcher.dart:287`, discarded (passes name `:332`).
- Readers (name-match): `ProgressionResolver` (`progression_resolver.dart:82,:90-92,:131-132`),
  `TrainingHistoryAnalyzer` (`:63`). `swap_service` is ALREADY id-aware but on SCHEDULE rows
  (`:204-206,:243-246`), NOT exlog → orthogonal.
- `exlog_key_canonical_test.dart` pins the KEY string only → a new field needs a NEW behavioral
  writer→reader test + the `hive_field_name_exlog` SoT field-list update (`sot_registry.yaml:1293-1296`).

### 11-B (①.1d)
- Injury filter proper = `exercise_repository.dart:324-334` (NOT `~285-294` which is equipment/tier).
  Refill = the `_cascadeFill` attempts. `_isContraindicated` `exercise_selector.dart:1092-1104`.
- `InjuryVocab.canonicalTokens` = 9 tokens (`injury_vocab.dart:28-38`).

### 11-C (W3.4)
- Cascade seam: `pickV4` (`exercise_selector.dart:512`) → `_fillSlots` (`:934`) → `_cascadeFill`
  (`:967`); each attempt returns `candidates.first` (`:993,:1006,:1017,:1030`). The variety/injury
  preference replaces `.first` with a soft "prefer a non-`.first` candidate" pick (fallback `.first`
  → zero pool-depth regression). Thread new params like `injuries`/`exclusions` (`:519,:528,:940-943,:973-976`).
- Prev-phase picks readable via the EXISTING `repeatPinsFrom`/`_buildRepeatPins`
  (`workout_schedule_read_service.dart:522-540,:574-616`, `getWeek(1)/getWeek(2)` per-day names).
- Composition SAFE: repeat-content bypasses the cascade (`buildPinnedDays`); variety/injury-sub only
  apply when `pins == null` (fresh advance, `plan_generator.dart:152`). Mutually exclusive by construction.
- Sweep gap: `sample_plans_report.dart` (phase 1 only) + `generator_matrix.dart` (phases 1/2/6
  INDEPENDENT) never feed phase-N→N+1. `CascadeTracer` (`test/plan_generator/v4_diagnostic/
  cascade_tracer.dart`) hand-mirrors `_cascadeFill` (`.first` at `:117-199`).

## 2. Designs (all ship-dark; default-OFF flags)

### 11-A — W3.3 ID-keyed history (flag `enable_exercise_id_history`, reader-switch)
- WRITE (additive, can ship unflagged — a null id is harmless): add optional `String? exerciseId` to
  `logExercise`; write it into the entry map ONLY when non-null. Thread `exerciseId` onto `ExerciseData`
  + from the schedule map at `train_provider.dart:378-394` (id already at `:331/:365`); coach path passes
  the id already at `tool_dispatcher.dart:287`. Name-only callers → null (reader falls back to name).
- READ (behavior change → GATED on `enable_exercise_id_history`, default OFF): `ProgressionResolver` +
  `TrainingHistoryAnalyzer` key by `log['exercise_id'] ?? log['exercise_name']` and match the plan
  exercise's id-first-name-second. Flag OFF → name-only (verbatim) → byte-identical.
- **CLOUD-SAFETY (non-negotiable):** `sync_workout.dart:198-199` STAYS `exercise_name`. A source-grep
  gate/test pins that line so the Hive id can never leak into the onConflict key (the dup-row bug).
- SoT `hive_field_name_exlog` field-list + `exercise_id`; new `test/contracts/exlog_exercise_id_*` behavioral
  (log-with-id → resolver matches by id; log-without-id → name fallback; + the sync-line pin).

### 11-B — ①.1d curated injury-substitution map (flag `enable_injury_substitution_map`)
- New `lib/core/utils/injury_substitutions.dart`: const `Map<String /*injury token*/, Map<String
  /*movement_pattern*/, List<String> /*preferred exercise names*/>>` (pattern-scoped to stay slot-correct),
  keyed on the 9 canonical `InjuryVocab` tokens. Pure, unit-testable.
- In `_cascadeFill`, after the injury-safe `candidates` are computed: if the user has an injury AND a
  curated substitute for (injury × this slot's movement_pattern) is present in `candidates`, prefer it
  over `.first`. Flag OFF → `.first` (verbatim). Thread the injury set (already in scope) + the flag.
- Curated data is exercise-science content — keep the initial map SMALL + safe (a few high-confidence
  shoulder/lower_back/knee substitutes), never forcing a wrong-pattern pick.
- Mirror: update `CascadeTracer` + `QueryV4Mirror` in the SAME commit. New scorecard assertion that the
  curated substitute WINS when available (`generator_matrix.dart:242-253` drives all 9 tokens today).

### 11-C — W3.4 cross-phase variety (flag `enable_variety_engine`)
- Thread `Set<String> lastPhasePicks` (or per-slot) through `pickV4 → _fillSlots → _cascadeFill`. In
  `_cascadeFill`, AFTER the injury-sub preference (11-B): prefer a same-`movement_pattern` sibling NOT in
  `lastPhasePicks` — `candidates.firstWhere((c) => !lastPhasePicks.contains(c.name), orElse: () => <injury-sub-or-.first>)`.
  Bounded, no random churn; fallback keeps pool-depth safety.
- Source `lastPhasePicks` at the phase-boundary generation (fresh advance only) from the just-finished
  phase's picks via the existing `getWeek(1)/getWeek(2)` name read (reuse `repeatPinsFrom`'s read shape).
  Flag OFF / phase-1 / pins!=null → empty set → `.first` → byte-identical.
- Mirror `CascadeTracer` + `QueryV4Mirror` in the SAME commit. NEW **two-phase test harness**: generate
  phase N → capture picks → feed as `lastPhasePicks` into phase N+1 → assert (a) still 0
  universalPool/(none) AND (b) the pick changed where a same-pattern sibling existed.

## 3. Ship-dark / inertness
All three flags default OFF → each seam is verbatim (name-only reader / `.first` cascade) → byte-identical.
Cloud-sync line unchanged regardless of any flag. No migration (11-A is Hive-forward-only; B/C are pure
selection). Composition: repeat-content bypasses the cascade so B/C never fight a repeat; A is orthogonal.

## 4. Mandatory drift gates (this batch's §4.11 obligations)
1. **11-A:** a source-grep test pinning `sync_workout.dart` exlog `exerciseId = ... exercise_name` (never
   the library id) — prevents the duplicate-cloud-row regression the founder flagged.
2. **11-B + 11-C:** the `CascadeTracer` + `QueryV4Mirror` mirrors updated in the SAME commit as
   `_cascadeFill` (else the sweep silently validates stale logic).
3. **11-C:** a genuine cross-phase (2-phase) harness (the existing sweeps are single-/independent-phase).

## 5. SoT + tests + docs
- SoT: `hive_field_name_exlog` (add exercise_id) + new `exercise_id_history`, `injury_substitution_map`,
  `variety_engine` concepts with behavioral_test_path.
- Tests: `exlog_exercise_id_behavioral_test.dart` (11-A + the sync-line pin), `injury_substitution_test.dart`
  (11-B pure map + cascade-prefers), `variety_engine_two_phase_test.dart` (11-C). Mirror updates.
- Naming glossary: `variety_engine`, `injury_substitution` if new domain terms. plan_engine/CLAUDE.md notes.
- No diagnose-doc (all `feat:`). No migration.

## 6. Open questions for the ×2 reviewers (verify against code)
1. Confirm the CLOUD-SAFETY invariant + that the write-side id NEVER reaches `sync_workout.dart:198-199`
   (trace `ExerciseData.exerciseId` → logExercise → the Hive map → the sync read). Is a source-grep pin sufficient?
2. Confirm `ExerciseData` threading (`:378-394`) + that flag-OFF readers are byte-identical.
3. Confirm the `_cascadeFill` preference order (injury-sub THEN variety) + that both fall back to `.first`
   with zero pool-depth regression; confirm the mirror(s) that MUST be updated in-commit.
4. Confirm `lastPhasePicks` sourcing at the fresh-advance boundary + that it's empty for phase-1/pins!=null.
5. Is the 3-sub-unit split right, or should 11-A ship as its OWN merge (higher cross-tier risk)? Any
   NEW inter-sub-unit coupling?
