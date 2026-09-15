---
branch: workout-titration-9
scope: Batch 9 · W2.7 volume titration — phase-boundary per-major-group ±1 weekly-set adjustment (ship-dark)
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-titration-9-bpass.md
---

# Plan-review record — Batch 9 (W2.7 volume titration)

Plan: `docs/plans/batch9-volume-titration.md` (full ground-truth + ×2 review detail). §4.12
TWO context-blind review rounds (2 parallel lenses on the original plan → 1 Round-2 on the
hardened plan). **Converged.** PLATFORM tier (`lib/shared/repositories/plan_engine/**`). NOT a
`fix:` (new ship-dark capability) → no diagnose-doc. No migration / no restore entry
(Hive-read-only; exlog + readiness already sync+restore). **INERT while
`enable_volume_titration` OFF** (resolveDeltas `{}` → applyToWeeks identity → byte-identical)
AND inert on every non-fresh-advance caller (opt-in `applyVolumeTitration: pins == null`).

## Ground-truth verified (against code, file:line — both Round-1 reviewers independently)
- bodyFocus +1-set seam `periodization_engine.dart:100-109`; 7-B-1 deload stash `:126-147`;
  `apply()` returns weekPlans `plan_generator.dart:207-218` before sequencing `:221` / superset `:224`.
- Phase-boundary flow `autoGenerateNextPhaseIfNeeded:443 → generateAndSchedule:97/483 → generate:120`
  (`workout_schedule_read_service.dart`).
- e1RM scan (reuse) `deload_e1rm_scan.dart:45-140` (trailing-35d, MAX-Epley, top-2 distinct, compound-only).
- **Soreness is a single GLOBAL daily axis** `readiness.dart:16-77` — full-lib sweep found NO
  per-muscle soreness anywhere (the plan's original per-muscle assumption CORRECTED to a global damper).
- MEV/MRV=8/20 exist `plan_scorecard.dart:46-47` but Volume there is a SOFT `default_sets` proxy, not a hard gate.
- `workingSets` written ONLY at `periodization_engine.dart:146` → `workingSets != null` is a sound
  deload-stash proxy; muscle-token vocab is the SAME both sides (library `primary_muscles`), case-sensitive.

## ×2 review (context-blind) — converged
**Round-1 (2 parallel lenses — correctness/composition + ground-truth/decision):** both `needs-changes`,
convergent. GT G1–G9 all verified correct. Findings folded (plan §6):
- **[P0] Seam-reach** — titration wired in the SHARED `generateV4` would fire on coach-regen /
  edit-profile / previews (all phase≥2), not just the phase boundary; §2c "coach-regen hardcodes phase"
  REFUTED. → opt-in `applyVolumeTitration` bool.
- **[P1] Fragmented-token clamp** — [8,20] on raw `primary_muscles` sub-tokens (chest→4) → +1 fires
  per sub-token (group gains +K), −1 never fires. → aggregate to MAJOR GROUP (shared `muscleGroupOf`).
- **[P1] Dead damper / unsafe polarity** — readiness ship-dark (0 rows) → systemicFatigue always false
  → +1 rides e1RM alone, "no data"=="recovered". → +1 requires POSITIVE recovery evidence; −1 on drop alone.
- **[P2×5]** multi-token double-bump (dedup) · Epley co-extract deps (`_toDouble`/`_toInt`; 3rd Epley left) ·
  wk-3 workingSets clamp symmetry · determinism (sorted groups) · case-lowercase · naming glossary.

**Round-2 (on the hardened plan — the corrections can introduce new defects, §4.12):** verified the
opt-in default-false neutralizes every non-advance caller, polarity fix correct, determinism /
deload-symmetry / byte-identical inertness all hold. One new material finding + 2 P2 folded (plan §8):
- **[P1] R2-1** — BOTH `generateAndSchedule` flip-sites ALSO serve REPEAT advances;
  `autoGenerateNextPhaseIfNeeded` is NOT unconditionally fresh (`pro_phase_advance.dart:86` feeds a
  low-adherence `repeatContent`). Hardcoding `true` → a low-adherence repeat gains volume (violates the
  plan's own invariant). → **`applyVolumeTitration: pins == null`** at both call sites (`:483` + `:644`).
- **[P2] R2-2** — `muscleGroupOf` leaves ~17 qualifier-tagged isolation lifts + 8 empty-primary rows
  unmapped → conservatively untitrated (safe — small groups below MEV). Map kept identical to preserve
  the frozen D3 baseline; behavioral test seeds bare-token lifts.
- **[P2] R2-3** — `muscleGroupOf` must `.toLowerCase().trim()` so `_groupOf` delegates without baseline drift.

Round-2 reviewer: "surgical fix, not a split signal — converges without a third full round." No forbidden
5th-review. Unit stays ONE coherent W2.7 slice.

## Converged design (to implement)
- **Shared `muscle_groups.dart`** `muscleGroupOf(token)` (`.toLowerCase().trim()`; content == scorecard
  `_muscleToGroup`; `_groupOf` delegates).
- **Shared `e1rm.dart`** `sessionMaxE1rm(Map)` + coercers, extracted from `deload_e1rm_scan.dart` (byte-identical).
- **`volume_titration.dart`**: `resolveDeltas(phase)` (flag+phase≥2 gate; per-group e1RM trend; readiness
  recovery evidence for +1; −1 on drop alone; sorted-group deterministic) + `applyToWeeks(weeks, deltas)`
  (empty→`identical` early-return; per-group ±1 clamped [8,20] on weeks 0-2 with per-week dedup; wk-3
  `workingSets` symmetric bump when present).
- **`plan_engine_flags.dart`** `enable_volume_titration` (default OFF). **Orchestrator** `plan_generator.dart`
  post-pass after `apply` gated on `applyVolumeTitration && phase≥2 && flag`. **Callers** pass
  `applyVolumeTitration: pins == null` at `workout_schedule_read_service.dart:483` + `graduation_screen.dart:644`;
  thread the bool through `generate`/`generateV4`/`generateAndSchedule` (default false).
- **SoT** `volume_titration`; **naming glossary** entries; **behavioral test**
  `volume_titration_behavioral_test.dart` + `e1rm_test.dart`; scorecard imports `muscleGroupOf` + adds a titration persona.

## Verdict: converged
Self-initiated ≥platform B-pass runs on the implemented diff BEFORE the `--no-ff` merge (§4.3);
`bpass:`/`bpass_review:` filled on acceptance. Merge gated on CI green.
