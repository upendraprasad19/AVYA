---
branch: workout-resume-banner
batch: 3-⑦b
scope: ⑦(b) session-time detraining resume cut (train active-workout + shared band extraction)
blast_radius: platform
reviewer: context-blind adversarial B-pass (self-initiated, §4.3)
verdict: accepted
verdict_note: initial verdict changes-needed (1 P2 self-expiring test + 1 P3 cite); both fixed + re-verified → accepted
---

# B-pass — ⑦(b) session detraining resume cut

Context-blind adversarial review of the staged diff (13 files, +552/−11). Every claim verified by the
reviewer against the committed files; findings re-verified by me against the code before fixing.

## Verified-clean (all 8 focus areas — production logic sound)

- **D1 double-count — CLEAN.** The `* widget.data.sessionDetrainingFactor` multiply is inside the
  last-logged-weight branch ONLY (`exercise_card.dart:89`); the prescribed `exercise.weight` fallback
  (the `else`, already ⑦a-decayed) is untouched. Mutually-exclusive `if/else` → disjoint inputs, no
  double-count. Overload indicator + `_metaText` never combine the two.
- **F1 copyWith survival — PRESENT + genuinely pinned.** `train_provider.dart:817-818` threads
  `sessionDetrainingFactor: sessionDetrainingFactor ?? this.sessionDetrainingFactor`; survives the
  1×/sec timer `copyWith(elapsedSeconds:)` + `setElapsedSeconds`. The pure test asserts survival across
  a copyWith and FAILS if the threading line is deleted (time-independent).
- **D2 extraction — byte-identical.** `detrainingFactorForGap` bands reproduce ⑦a's inline bands
  exactly; `_detrainingFactor` keeps its IST-string→gap conversion and delegates;
  `progression_resolver_decay_test` boundaries 7/8/21/22/35/36 unchanged, stays green.
- **D3-i overload compare-vs-target — SAFE.** `target = lastWeight * factor`, identical multiplication
  to the prefill, same `lastPerformanceProvider.lastWeight` + same factor → `w == target` bit-for-bit
  (Dart `parse(d.toString())==d`). Unedited reduced prefill reads → (neutral), never red↓. factor 1.0
  → `target == lastWeight` (×1.0 IEEE identity) → byte-identical to pre-⑦b.
- **D3-ii TRY suppression — CORRECT.** TRY condition gained `&& factor >= 1.0` (hidden when cut);
  "LAST:" unchanged. `>= 1.0` safe (reduce-only max 1.0).
- **Banner + flag — CORRECT.** Banner iff `factor < 1.0`; non-shaming copy; `accentSoft`/`accent` +
  `monoXs` (Wardroom); `Container(color:)` no `decoration:` (gate-safe). `sessionDetrainingCutEnabled`
  = `enable_…==true` / catch→false (ship-dark, mirrors graded).
- **Writer + edges — CLEAN.** Factor computed only when flag on, else 1.0; `-1`/`0` gap → 1.0;
  `WorkoutRepository.instance` real singleton; swap re-init idempotent (constant×immutable); no provider
  leak (factor lives only on `ActiveWorkoutData`; the shared `lastPerformanceProvider` is unmodified).

## Findings + resolution

### P2 — integration test was wall-clock-coupled (self-expiring CI red) — FIXED
`getDaysSinceLastWorkout()` (`workout_repository.dart:1174`) read raw `DateTime.now()`, which does NOT
honor `setTestClockTo` (the `_clockOverride` seam reaches only `nowWall`/`istNow`/`istTodayStr`). My test
seeded the log date off the CONSTANT `fixedNow`, so the gap production saw = `realNow − (fixedNow −
daysAgo)`, growing with the calendar → the `3d→1.0` case would flip on 2026-07-18, the `25d→0.825` case
by ~2026-07-23 (rule 20 P0). **Fix (principled, in-convention):** migrated `getDaysSinceLastWorkout`'s
`DateTime.now()` → `nowWall()` — the seam this very file already uses at `:287/:418/:468` (it was missed
in that sweep). `setTestClockTo(fixedNow)` now reaches it, so both `now` and the seed derive from
`fixedNow` → gap deterministic forever; release-identical to `DateTime.now()` (the sole other caller,
`pattern_detector.dart:335`, gains time-travelability, behavior-preserving in prod). Re-verified: 17/17
green, analyze clean, parity PASS.

### P3 — `startWorkout` cite drift — FIXED
The train CLAUDE.md row cited `train_provider.dart:896`; after the field/ctor/copyWith insertions
`startWorkout` is at `:907`. Corrected.

## Verdict: accepted
Both findings fixed in `workout_repository.dart` + the CLAUDE.md cite and re-verified (17/17 tests green
+ now deterministic, `flutter analyze` clean, SoT parity/completeness/behavioral-paths PASS). All 8
production-logic focus areas held under adversarial review.
