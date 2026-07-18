---
branch: workout-plateau-12b
plan: docs/plan-reviews/workout-plateau-12b.md
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/PENDING-12b-review.md
---

# Plan Review — Batch 12-B (W3.5 plateau escalation · rung-3 exercise rotation)

- **Batch:** 12-B — the FINAL unit of the 13-batch workout-generator overhaul. Completes W3.5 (rung-3) after 12-A shipped rung-2 (`dc8f4880`, CI-green).
- **Branch:** `workout-plateau-12b` (off `dc8f4880`).
- **Blast radius:** `platform` (`lib/shared/repositories/plan_engine/**` wholesale pin, `docs/blast_radius.yaml:67`) — the Plan subagent mis-stated "feature/account"; corrected here. Full ceremony: kill-switch + behavioral test + B-pass + this converged record.
- **Kill-switch:** reuse `enable_plateau_escalation` (one flag governs the whole plateau ladder rung-2+rung-3) + `enable_readiness` gate + `phase>=2` + `applyPlateauEscalation` opt-in. DEFAULT OFF → byte-identical.

## 0. Scope + two founder-doctrine calls (flagged for visibility, proceeding per autonomous mode)

**rung-3 = exercise rotation.** When a plateau is detected, the plateaued COMPOUND is rotated out for a same-`movement_pattern` sibling in the next phase, by feeding the plateaued exercise NAMES as `avoidNames` into the 11-B cascade `_preferNovel` seam — under `enable_plateau_escalation` + PRO, INDEPENDENT of 11-B's `enable_cross_phase_variety`.

Two decisions the ground-truth forced (documented as terminal, NOT deferrals — §4.2):

1. **rung-2 and rung-3 both fire (no cross-gate).** rung-3 is a **SWAP, not an add**: `_preferNovel` changes *which* exercise fills a slot, never the slot COUNT (`exercise_selector.dart:971` loop untouched) — so it is **slot-count-neutral**. (It is NOT exact-set-neutral, per Round-1: the swapped-in same-pattern sibling carries its OWN base `default_sets` — `_buildExercise:1231`; library spread 25×1 / 106×3 / 118×4 — so a rotation can shift a slot's base sets by ±1. That swing is small, bounded, and a PRE-EXISTING property of the identical 11-B `_preferNovel` mechanism; the plateau +1 stays MRV-threshold-guarded at `volume_titration.dart:185` — `if (d>0 && weeklyBase < _mrvPerWeek)`, a threshold GUARD not a clamp-down, also pre-existing 11-B behavior.) Allowing both is safe: once rotated, the stuck lift is GONE from selection, so rung-2's +1 (`putIfAbsent`) lands on the FRESH sibling's group — "escalate one variable *on a specific stuck lift*" holds because that lift no longer exists; rung-2's safety (a declining group's −1 wins) is untouched. **Why not supersede (+set only if the lift didn't rotate):** an outcome-based supersede (check at Stage 4.5 whether the stuck lift survived rotation) IS feasible — so the earlier "ordering makes supersede impossible" framing was wrong (corrected Round-1). We choose "both fire" anyway (Round-2 P3-1 precision): in the HOLE (shallow pool, no sibling) supersede and both-fire AGREE — both give the +set fallback, nothing is lost there; they differ ONLY in the non-hole case, where both-fire adds the group's MRV-clamped +1 on top of the rotation. We take that extra bounded +set as a deliberate design choice — the simplest rule that guarantees hole coverage — verified safe in §3 (slot-count-neutral rotation + MRV-threshold-guarded +1 landing on the fresh sibling's group).
2. **rung-1 plateau explainability: NOT built (terminal won't-do — out of scope for a rung-3 rotation batch, and pursuing it breaks 12-B's pure-compute goal).** The deload "why" (`currentDeloadReason`) is written by `DeloadEvaluator` (`deload_evaluator.dart:143-160`), which has NO `plateau_scan` import (`:23-37`). The honest grounds for not adding a plateau mention (Round-1 correction — NOT the "provably dead" argument, which is about the keep DECISION, not the explanation TEXT): (a) **causal imprecision** — the deload fires *fatigue*-driven (readiness not-good), so attributing it to a plateau would be causally wrong; (b) **out of scope** — rung-1 explainability was never a committed deliverable of a "rung-3 rotation" batch (so this is NOT a §4.2 disguised deferral — nothing promised is being punted); (c) a coherent path DOES exist (stash `plateau_detected_phase_<P>` at GENERATION time — where 12-B already runs the scan — and compose it in the "why" READER, avoiding the `deload_evaluator → plateau_scan` coupling), but it is **rejected** because it adds a persisted Hive key, breaking 12-B's pure-compute (no-new-persistence) property, for a causally-imprecise cosmetic subtext. Terminal decision, flagged for founder visibility.

## 1. GROUND TRUTH (verified against the `dc8f4880` worktree code, this session)

### 1.1 The 11-B avoidNames cascade seam (the reuse target)
- `pickV4` (`exercise_selector.dart:513-537`) reads `previousPhaseByDay?[i]?.a/.b` per day-index and builds `final avoidA = (…?.a ?? const <String>[]).toSet();` / `avoidB` (`:559-560`), passed to `_fillSlots(avoidNames:)` (`:567`/`:580`).
- `_fillSlots → _cascadeFill → _selectCandidate → _preferNovel` all carry `Set<String> avoidNames`.
- `_preferNovel(pool, avoidNames)` (`:1029-1040`): `if (avoidNames.isEmpty) return pool.first;` else the first pool candidate whose lowercased `name` ∉ avoidNames, else `pool.first`. **SOFT + bounded — runs on an already-non-empty pool, can NEVER empty a slot or force a wrong pattern.** Consumed only at attempts 1-4; attempt-5 (universal bodyweight floor) never sees it. **Verified by direct read.**

### 1.2 The 12-A plateau detector (the source of names)
`PlateauScan.plateauedGroups({phase})` (`plateau_scan.dart:79-115`) iterates the shared `buildE1rmByDate` map; per exercise it applies `dated.length >= _minSessions`, `repo.isCompoundByExactName(name)`, span `>= _minSpanDays`, `isFlat(values)` — then aggregates to groups. A `plateauedExerciseNames({phase})` is a near-clone collecting `name.toLowerCase()` instead of groups, with the IDENTICAL gates (flag + `readinessEnabled` + `phase<2` + `_fatiguePresent` + crash-safe `{}`).

### 1.3 Ordering + opt-in
Stage 2 selection (`plan_generator.dart:167-197`, the `pickV4` branch) runs BEFORE Stage 4.5 (`:261-272`). `applyPlateauEscalation` is already threaded to `generateV4` (`:113`) by 12-A. The `buildPinnedDays` branch (`:168`, pins) is NOT wired (pins ⟂ plateau; `applyPlateauEscalation` is already false whenever `pins != null`).

## 2. IMPLEMENTATION SPEC

### 2.1 `plateau_scan.dart` — new `plateauedExerciseNames`
```dart
/// The plateaued COMPOUND exercise NAMES (lowercased) for rung-3 rotation — the
/// per-exercise sibling of plateauedGroups (same scan, same gates). `{}` when the
/// flag/readiness flag is OFF, phase<2, fatigued, or no evidence. Crash-safe.
static Set<String> plateauedExerciseNames({required int phase}) {
  try {
    if (!PlanEngineFlags.plateauEscalationEnabled) return const <String>{};
    if (!PlanEngineFlags.readinessEnabled) return const <String>{};
    if (phase < 2) return const <String>{};
    if (_fatiguePresent()) return const <String>{};
    final box = HiveService.instance.workoutBox;
    final cutoff = istDateStr(nowWall().subtract(const Duration(days: _windowDays)));
    final byExercise = buildE1rmByDate(box, cutoff: cutoff);
    if (byExercise.isEmpty) return const <String>{};
    final repo = ExerciseRepository.instance;
    final names = <String>{};
    byExercise.forEach((name, dated) {
      if (dated.length < _minSessions) return;
      if (!repo.isCompoundByExactName(name)) return;
      final dates = dated.keys.toList()..sort();
      final span = DateTime.parse(dates.last).difference(DateTime.parse(dates.first)).inDays;
      if (span < _minSpanDays) return;
      final values = [for (final d in dates) dated[d]!];
      if (!isFlat(values)) return;
      names.add(name.toLowerCase()); // _preferNovel compares lowercased
    });
    return names;
  } catch (_) {
    return const <String>{};
  }
}
```
(Two-call form kept — the double scan runs only on a fresh PRO advance, ~monthly; both crash-safe over the same synchronous Hive state. A combined record method would force a signature change to the shipped `mergePlateauSetDeltas` + 12-A re-verification — not worth it.)

### 2.2 `plan_generator.dart` — compute + pass at the pickV4 branch
Compute as a STATEMENT before the `final populated = pinnedExercisesByDay != null ? buildPinnedDays(...) : pickV4(...)` ternary (`:167`) — a statement can't live in the ternary's else arm — guarded on `pinnedExercisesByDay == null` so **pins ⟂ plateau is STRUCTURAL, not caller-convention** (Round-1 P2-B: a hypothetical caller passing both `applyPlateauEscalation:true` AND `pinnedExercisesByDay!=null` would otherwise run a wasted Hive scan `buildPinnedDays` ignores):
```dart
final plateauAvoid =
    (applyPlateauEscalation && pinnedExercisesByDay == null)
        ? PlateauScan.plateauedExerciseNames(phase: phase)
        : const <String>{};
```
and add `plateauAvoidNames: plateauAvoid,` to the `ExerciseSelector.pickV4(...)` args at `:183-197`. (The `buildPinnedDays` branch never receives it.)

### 2.3 `exercise_selector.dart` — new `pickV4` param + union
- Add param `Set<String> plateauAvoidNames = const {}` to `pickV4` (`:513-537`, after `previousPhaseByDay`).
- At `:559-560` union it into BOTH variants (a stuck lift is avoided wherever it would be picked — GLOBAL, not per-day):
```dart
final avoidA = {...(previousPhaseByDay?[i]?.a ?? const <String>[]), ...plateauAvoidNames};
final avoidB = {...(previousPhaseByDay?[i]?.b ?? const <String>[]), ...plateauAvoidNames};
```
`_fillSlots`/`_cascadeFill`/`_selectCandidate`/`_preferNovel` UNCHANGED. **Byte-identical when `plateauAvoidNames` empty:** `{...listA, ...{}}` ≡ `listA.toSet()` (same set). The only production `pickV4` caller is generateV4 (`:183`); `buildPinnedDays`' internal `pickV4` fresh-fill does NOT receive it.

### 2.4 SoT + tests + docs
- **SoT `docs/sot_registry.yaml`:** new concept `plateau_rotation` (writer `PlateauScan.plateauedExerciseNames` + the `plan_generator.dart` pickV4 compute + `exercise_selector.pickV4` union; reader `_preferNovel`; `behavioral_test_path: test/contracts/plateau_rotation_behavioral_test.dart`). `plateau_scan.dart` already registered as an `exlog_*` reader indirectly via `e1rm_history.dart` (12-A) — no new exlog manifest entry (plateau_scan calls `buildE1rmByDate`, the file holding the literal `exlog_`).
- **`test/contracts/plateau_rotation_behavioral_test.dart`** — reuse the 12-A harness (`seedFlatPlateau`/`seedReadiness`, clock seam, guarded boxes, seeded library), `full_gym`/`advanced` deep-pool persona. **Seed NO swap/custom history** so the L6 post-pass (`_applyHistoryAdjustments`, `:588`, phase≥2, gated on `demoted`/`customs` non-empty) is SKIPPED → the rotation assertion is deterministic (Round-1 P2-A).
  1. **Rotation (the headline — non-vacuous target derivation, Round-1 P1-2 / rule 21):** do NOT reuse the 12-A "first group-mappable compound" discovery (that exercise may not be in the persona's plan → a vacuous "absent" pass). Instead: generate a BASELINE plan (`applyPlateauEscalation:false`); from THAT plan's exercises pick a target COMPOUND that is (a) actually in the plan AND (b) has ≥1 same-`movement_pattern` sibling in its selectable pool (`expect` such a target exists — fail loud otherwise). Seed a flat plateau for THAT name; regenerate ON → assert the target's SLOT is now filled by a DIFFERENT same-pattern exercise (or the plan's occurrence-count of that name STRICTLY DECREASES). OFF → target PRESENT. (Assert a SPECIFIC-slot change, NOT global absence — `_preferNovel` falls to `pool.first`=the stuck lift on a shallow slot, so global absence is fragile.)
  2. **Independence (the hard 12-B requirement):** `enable_cross_phase_variety` OFF, `enable_plateau_escalation` ON → the target is STILL rotated (same specific-slot assertion).
  3. **Ship-dark:** flag OFF → plan identical to `applyPlateauEscalation:false`.
  4. **Slot-count-invariance (pins doctrine-1's neutrality claim, Round-1 P2-2):** titration OFF + rotation ON → TOTAL slot/exercise COUNT identical ON vs OFF (only identities differ). Assert SLOT count, NOT total sets (sets may legitimately differ ±1 via `default_sets`).
  5. **Shallow-pool retention (soft-bias graceful degradation, Round-1 P2-2):** a slot whose pattern pool = {stuck lift only} → `_preferNovel` returns `pool.first`=the stuck lift → RETAINED, no crash, no empty slot.
  6. **Injury-safe:** rotation + a shoulder injury never surfaces a contraindicated exercise.
  7. **Fatigued plateau → NO rotation** (`_fatiguePresent` true → names `{}` → target PRESENT).
  8. **Both-coherence:** `enable_volume_titration` + `enable_plateau_escalation` ON → the stuck lift is rotated out AND its group's weekly sets stay MRV-bounded.
  9. **`plateauedExerciseNames` gates (Round-1 P2-1 — need Hive, so they live HERE, not the pure file):** flag OFF → `{}`; readiness OFF → `{}`; phase<2 → `{}`; fatigued → `{}`; a seeded flat compound → its lowercased name present.
- **`test/plan_generator/plateau_scan_test.dart`** — UNCHANGED scope (stays `isFlat`-only / Hive-free); the `plateauedExerciseNames` gate tests live in the behavioral harness (they require Hive), mirroring how `plateauedGroups`' gates are tested behaviorally.
- **Cascade-tracer mirror — NO update.** `cascade_tracer.dart:102-113` `_preferNovelName` + `trace(avoidNames:)` already implement the soft mirror; rung-3 only feeds MORE names into the existing set. `generator_matrix.dart` stays unwired (`trace` passes no avoidNames → frozen D3 baseline unmoved). **Verify both at implement time.**
- **`lib/shared/repositories/plan_engine/CLAUDE.md`** — a "Plateau rotation (W3.5 — Batch 12-B)" paragraph.

### 2.5 Explicitly OUT of scope (terminal, not deferred)
- **rung-1 plateau explainability** — §0 decision 2 (out of scope for a rung-3 rotation batch; the deload is *fatigue*-driven so a plateau attribution is causally imprecise; the coherent stash-at-generation path is rejected because it adds a persisted Hive key, breaking 12-B's pure-compute goal). Terminal won't-do. (Round-2 P2-1: aligned with §0.2 — dropped the retracted "architecturally incoherent / would re-couple" framing.)
- **No new flag** — reuses `enable_plateau_escalation`.
- **No scorecard/mirror wiring** — frozen D3 baseline unmoved.

## 3. Invariants / risk
- **Ship-dark / byte-identical-off:** flag OFF or opt-in false → `plateauAvoid = {}` → union is a no-op → `pickV4` byte-identical.
- **Bounded/safe:** `_preferNovel` is a SOFT bias on a non-empty pool → never empties a slot, never a wrong pattern, never disturbs the attempt-5 injury-safe floor. **Slot-count-neutral** (a swap, not an add; a rotated-in sibling may carry ±1 base `default_sets` — bounded, pre-existing 11-B behavior). **L6 soft-undo:** `_applyHistoryAdjustments` (`:588`, phase≥2, runs only when `demoted`/`customs` non-empty) doesn't consult `avoidNames`, so it can re-introduce a rotated-out lift when the rotation sibling is itself demoted — consistent with rung-3 being a SOFT bias (the test seeds no swap/custom history → L6 skipped → deterministic).
- **PRO / phase gate:** inherited (only the two PRO advance callers pass `applyPlateauEscalation: pins == null`) + `phase>=2` self-gate in `plateauedExerciseNames`.
- **Drift (#1 class):** `plateauedExerciseNames` reuses the shared `buildE1rmByDate` + `isCompoundByExactName` + `isFlat` (no new hand-rolled scan).
- **12 tiers:** Tier 1 (client) + Tier 2 (Hive read-only) only — no migration/schema/EF/cron/RLS/cloud. exlog+readiness already sync+restore.

## 4. REVIEW ROUNDS

### Round 1 — two context-blind reviewers (COMPLETE) — both `accept-with-fixes`, no P0/P1-logic

**Reviewer A (correctness):** CONFIRMED byte-identical-off (`{...listA, ...{}}` ≡ `listA.toSet()`; `_preferNovel` reads membership only), rotation-actually-happens (soft/bounded on a guaranteed-non-empty pool → never empties a slot, same-pattern), `plateauedExerciseNames` gates identical to shipped `plateauedGroups` + `.toLowerCase()` correct, ordering + no PRO leak, composition with 11-B/11-C safe, D3 baseline unmoved. Fixes: **P2-A** L6 (`_applyHistoryAdjustments` `:588`) can re-introduce a rotated lift + Test-1 needs no-swap-history precondition; **P2-B** compute `plateauAvoid` as a statement guarded `&& pins == null`; **P2-C** both-rungs is a founder flag (restated).

**Reviewer B (design/safety):** CONFIRMED independence-from-variety-flag ACHIEVED (the hard requirement), byte-identical-off, ordering, pure-compute (no new persistence, no reader-manifest entry), no gate trips, frozen D3 baseline. Fixes: **P1-1** "volume-neutral" is imprecise — rotation is SLOT-count-neutral but shifts base sets ±1 via `default_sets` (`:1231`); **P1-2** headline tests risk a rule-21 VACUOUS pass (12-A's "first group-mappable compound" may not be in the persona's plan) → derive the target from a baseline plan with a same-pattern sibling + assert a specific-slot change; **P2-1** `plateauedExerciseNames` gate tests need Hive → behavioral file, not the pure file; **P2-2** add slot-count-invariance + shallow-pool-retention tests; **P2-3** re-ground the rung-1-drop on causal-imprecision + out-of-scope + pure-compute (not "provably dead"); **P2-4** lead the supersede rejection with the HOLE argument (not ordering); **P3-1** don't ship a hollow record.

**Resolution (ALL folded into §0–§3, self-verified where load-bearing):** §0.1 reworded — rotation is slot-count-neutral (±1 base sets via `default_sets:1231`, verified by direct read; bounded 11-B behavior), supersede rejected on the HOLE not ordering. §0.2 reworded — rung-1-drop grounded on causal-imprecision + out-of-scope + pure-compute (stash-at-generation alternative acknowledged + rejected), NOT "provably dead". §2.2 compute guarded `&& pinnedExercisesByDay == null` as a pre-ternary statement. §2.4 tests redesigned: non-vacuous baseline-derived target + specific-slot assertion (P1-2), gate tests moved to the behavioral file (P2-1), slot-count-invariance + shallow-pool-retention added (P2-2), no-swap-history precondition (P2-A). §3 slot-count-neutral + L6 soft-undo note. This record's sections are populated (P3-1); `bpass_review` is updated to the real file at B-pass time.

### Round 2 — one reviewer on the hardened plan (COMPLETE) — `converged-with-nits`

The reviewer verified all 5 hardened areas ACCURATE against code: §0.1 slot-count-neutral + ±1 `default_sets:1231` + MRV-threshold-guard `volume_titration.dart:185` + the ordering-correction; §0.2 rung-1-drop is a genuine terminal won't-do (not a §4.2 deferral — `deload_evaluator.dart:23-37` has no plateau_scan import; the stash alternative fairly rejected); §2.4 tests genuinely non-vacuous (rule 21) — the L6-skip precondition verified (`:588` guard; no seeded swaps/customs → `demotedExercises()`/`_eligibleCustomExercises` empty → L6 skipped → deterministic), test-1 cannot false-green (broken rotation → ON==OFF → target present → RED); the gate-test relocation matches the shipped 12-A pattern; §2.2 compute guard well-formed + byte-identical-off (all vars in scope, `PlateauScan` imported `:11`). No new P0/P1 code or test defect; no vacuous test.

**One material finding + nits, all folded in:**
- **P2-1 (material, fixed):** §2.5 still carried the retracted "architecturally incoherent / would re-couple" rationale, contradicting the reworded §0.2 → §2.5 aligned (out-of-scope + causal-imprecision + pure-compute).
- **P3-1 (nit, fixed):** §0.1's supersede rejection sharpened — supersede and both-fire AGREE in the hole; "both fire" is a deliberate design choice for the extra bounded +set, not forced by the hole.
- **P3-2 (nit):** frontmatter reflects TARGET terminal state; `verdict: converged` is now true (Round-2 converged); `bpass: accepted` + `bpass_review` are made true at B-pass (the placeholder is replaced with the real `docs/reviews/<sha>-review.md` BEFORE the merge the keystone gate checks).
- **Test-author implementation notes (applied at implement time):** (1) test-1 target must have a same-pattern sibling in the actual CASCADE POOL for its slot (equipment-tier/experience/foundational-gated `queryV4`), not merely another library row — else a singleton-pool target won't rotate (fail-loud, never false-green). (2) tests #4/#5 (slot-count-invariance / shallow-pool) must reuse test-1's genuinely-ROTATING seed, else a trivially-equal count is a vacuous pass.

### Convergence — CONVERGED

Two Round-1 context-blind reviewers (correctness + design/safety) both `accept-with-fixes`, no P0; every fix folded into §0–§3. Round-2 on the hardened plan found NO new material defect — only a one-line record-consistency fix (P2-1) + nits. Per §4.12 the absence of any new material issue on the hardened plan IS the convergence signal, and the unit is already minimal (one new `plateauedExerciseNames` scan method + one `pickV4` param/union + tests; no split warranted). `verdict: converged` → implement.
