# Batch 0 — Workout Generator Validation Harness (focused implementation plan)

**Parent plan:** `~/.claude/plans/ok-lock-1a-and-atomic-balloon.md` (VALIDATION FRAMEWORK section).
**Branch/worktree:** `wg-batch0-validation`. **Blast-radius tier:** `feature` (test/tooling only —
`test/**` per blast_radius.yaml) → requires a regression test; NO kill-switch, NO ×2 review needed
(but this focused plan exists per the discipline contract). **No production code changes** — this
batch only ADDS test-harness tooling. It touches ZERO `lib/` files, so it cannot break the app.

## Why Batch 0 ships FIRST (§4.11 gates-before-refactor)
It is the RULER. It baselines today's generator so every later batch can PROVE its improvement
and be blocked on any regression. Building it before any engine change means the baseline is the
true pre-overhaul state.

## What exists to build on
`test/plan_generator/sample_plans_report.dart` already sweeps experience × days (hardcoded
`build_muscle`/`full_gym`/`phase 1`) using pure-Dart `SplitResolver.selectV4` +
`VolumeFilter.filterDays` + `CascadeTracer.trace` (no Hive — fast). `CascadeTracer.trace` already
accepts an `injuries` param. We EXTEND this, we don't rebuild it.

## Deliverables

### D1 — Full-matrix sweep (`test/plan_generator/generator_matrix.dart`)
Enumerate synthetic personas across the input space and generate each plan via the existing
pure-Dart cascade path:
- goal ∈ {build_muscle, lose_fat, general_fitness, strength} (+ recompose if a distinct plan-goal)
- equipment ∈ {bodyweight, home_dumbbells, basic_gym, full_gym} (tiers; exclusion combos deferred
  to Batch 5 when the feature exists — noted, not silently skipped)
- days ∈ {3,4,5,6}; experience ∈ {beginner, intermediate, advanced}
- injuries ∈ {none, each single token (lower_back, knee, shoulder, wrist, hip, ankle), a couple of
  common combos} — uses LIBRARY tokens (the canonical vocab Batch 1 will align the UI to)
- phase ∈ {1, 2, 6}
Emit each generated plan as a structured record (persona + per-day slot picks + source).

### D2 — 7-dimension Plan Quality Scorecard (`test/plan_generator/plan_scorecard.dart`)
Pure functions: `score(plan, persona) → {coverage, balance, volume, progression, personalization,
safety, realism, overall}` (0-100 each). Grounded in the R1-R11 science notes (Appendix B of parent):
1. **Coverage** — each major muscle hit at adequate weekly frequency; penalize gaps.
2. **Balance** — push:pull ratio in range; no movement_pattern over its library pool depth.
3. **Volume** — direct sets/muscle/week vs the effective MEV≈8/MRV≈20 band for the level.
4. **Progression** — phase N+1 total volume/intensity ≥ phase N (checked across the phase axis).
5. **Personalization** — injuries→0 contraindicated; equipment⊆persona set; (body-focus/cardio
   dims light for now — those features don't exist until Batches 4/1; the scorer has the hooks).
6. **Safety** — HARD gate: any contraindicated exercise (main + warmup) = 0/100.
7. **Realism** — fits day count; no absurd session length; no `(none)`/universalPool picks.

### D3 — Baseline freeze (`test/plan_generator/baseline/` golden files)
Run D1+D2 against the CURRENT engine (no flags), write:
- `baseline_scorecard.json` — per-persona scores + aggregate (the frozen "before").
- `baseline_plans.md` — human-readable plans + scores for face-validity review.
Committed as golden files. Later batches diff against these.

### D4 — Regression gate (`test/plan_generator/scorecard_gate_test.dart`)
A `flutter test`-runnable test asserting the HARD invariants for every matrix persona (Layer 2):
safety 0-contraindicated, equipment⊆persona, volume∈band, 0 fallback picks. This is the
`test/**` regression test the tier requires. (The soft-dimension baseline-diff is a reporting
tool, run manually / in a later CI wiring; the hard invariants gate CI now.)

## Verification (how we know Batch 0 itself works)
- `dart run test/plan_generator/generator_matrix.dart` produces the report + baseline files.
- `flutter test test/plan_generator/scorecard_gate_test.dart` passes on the CURRENT engine (proves
  today's generator already satisfies the hard invariants — or surfaces pre-existing violations we
  then record as known-baseline, NOT silently pass).
- Human eyeballs `baseline_plans.md` for face validity.

## Explicitly deferred to owning batches (NOT silently dropped, per §4.2)
- Equipment-exclusion personas → Batch 5 (feature doesn't exist yet).
- body-focus / cardio-preference personalization scoring → Batches 4/1 (hooks stubbed now).
- CI wiring of the baseline-diff gate → when the first engine batch (Batch 1) lands, so its own
  scorecard delta is the first thing measured.

## BASELINE FINDINGS (frozen 2026-07-12 — the current-engine "before")

Ran 597 personas / 19,308 exercises. Mean scores: **coverage 88.6 · balance 67.6 · volume 70.4
· progression 100 · personalization 99.7 · safety 99.7 · realism 94.1 · overall 86.5.** The
harness quantified THREE real current-engine quality gaps (recorded honestly, NOT silently
passed — the owning batch drives each to 0):

1. **Equipment over-tier picks — 286 of 597 plans (→ Batch 5 / item ⑥).** The cascade's
   attempt-4 "drop equipment" hands lower-tier users exercises above their tier: `bodyweight`
   144/144 (100%), `home_dumbbells` 132, `basic_gym` 10, `full_gym` 0. A bodyweight user gets
   "Dumbbell Row"/"Barbell Overhead Press". This is the exact equipment-fidelity gap ⑥ fixes —
   now with a hard before-number.
2. **2 unsafe plans — universal-pool fallback BYPASSES the injury filter (→ Batch 1 / item ①).**
   A shoulder-injured full-gym user gets "Pike Push Up" (shoulder-contraindicated) because the
   cascade's attempt-5 universal pool (`_universalPoolV4`) is hardcoded and never injury-checked.
   Batch 1's injury work MUST also filter the universal pool (and warmup per WU-1), or safety
   can't reach a true 0. NEW finding — extends item ①'s scope; feed into Batch 1's focused plan.
3. **1,156 target-fidelity fallbacks (attempt3) — shallow bodyweight pool (→ Batch 5 / W3.4).**
   By tier: bodyweight 617 · home_dumbbells 379 · basic_gym 119 · full_gym 41.

Also empirically re-confirmed the plan's G5 correction: `equipment_needed` is free-text
("barbell on rack or trx") + 9 bare-String rows → unusable for item-level filtering until
Batch 5's data-quality pass. The baseline equipment invariant therefore uses `equipment_tier`
(what queryV4 actually filters on).

## Discipline checklist (this batch)
- [x] Own worktree (wg-batch0-validation).
- [x] Own focused plan (this doc).
- [x] Regression test (D4) green — 7/7 pass (`flutter test test/plan_generator/scorecard_gate_test.dart`).
- [x] `flutter analyze` clean on all 4 new files; golden files deterministic (identical md5 on re-run).
- [x] No `lib/` changes (test/tooling only → cannot break prod).
- [ ] Commit only on explicit founder ask; merge to main via integration folder.
