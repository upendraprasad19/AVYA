---
review: B-pass (context-blind, adversarial)
branch: workout-titration-9
scope: Batch 9 · W2.7 volume titration — phase-boundary per-major-group ±1 weekly-set adjustment (ship-dark)
blast_radius: platform
verdict: accepted
---

# B-pass — Batch 9 (W2.7 volume titration)

Self-initiated ≥platform B-pass (§4.3) on the implemented, staged diff BEFORE the `--no-ff` merge.
A context-blind adversarial reviewer verified the implementation against code, ran `flutter analyze`
(clean, 10 items) and the tests (the 4 targeted: 47 passed; the broader `plan_engine_v4` +
equipment-exclusion byte-identity regression set: 165 passed).

## Verdict: accepted — no P0, no P1.

## Bug classes hunted → all CLEAN (reviewer verified against code)
1. **Inertness (P0)** — SOLID. `resolveDeltas` returns `const {}` at its first statement
   (`!volumeTitrationEnabled || phase < 2`) before any Hive read; `applyToWeeks` first statement is
   `if (deltas.isEmpty) return weeks;` (SAME reference — pinned by the `identical(...)` test). The
   orchestrator gate `if (applyVolumeTitration)` defaults false. `shared_contracts_test` + archetype
   wave tests confirm the generator is unchanged flag-OFF.
2. **Opt-in threading (P0/P1)** — CORRECT, no hole. `generateAndScheduleFromDate` (edit-profile),
   coach-regen (`regenerate_plan_planner`), both previews (`preview_plan_provider:94`, graduation
   dry-run `generateV4:342`), hotel (`:116`), onboarding all default false. Both advance callers use
   `pins == null` as the fresh-vs-repeat discriminant (`workout_schedule_read_service.dart:503` +
   `graduation_screen.dart:658`). The facade `WorkoutScheduleService.generateAndSchedule` does NOT
   declare the param → structurally cannot leak; graduation calls the read service directly.
3. **Shared-Epley extraction (P0)** — VERBATIM. `sessionMaxE1rm` + `_toDouble`/`_toInt` are
   character-identical to the removed `DeloadE1rmScan._sessionMaxE1rm`; deload_e1rm_scan compiles +
   calls it; `deload_eval_behavioral_test` passes; no lingering refs to the removed privates.
4. **muscleGroupOf delegation (P0)** — content byte-identical (34 tokens, key-by-key), same
   `.toLowerCase().trim()`; `scorecard_gate_test` passes with the frozen D3 baseline (mean 86.7,
   fallbacks 1178) UNMOVED.
5. **applyToWeeks (P1)** — clamp holds in [8,20] (each bump moves the aggregate by exactly ±1;
   shared-exercise inflation only makes the clamp MORE conservative); dedup keyed `"di:xi"`; the
   `next < 1` floor rolls to the next candidate; deload branch adjusts `workingSets`, leaves visible
   `sets` untouched.
6. **resolveDeltas (P1)** — trend top-2 distinct dates desc, strict `latest < prior`; readiness
   `_recovered` = n≥3 AND `beatUp < max(2, ceil(0.4n))`; multi-group evidence Set-aggregated (no
   double-count); try/catch → `{}`; reads the SAME boxes the app writes (`workoutBox`/`healthBox`).
7. **Deload composition (P1)** — `workingSets != null` self-gates (workingBase==0 → skip); symmetric
   with the 7-B-1 stash so a 7-B-2 un-deload restores the titrated peak.
8. **Other** — `WeekPlan`/`WorkoutDay`/`PlannedExercise` reconstruction preserves every field;
   `(int,int)` records destructured correctly; Sequencing/Superset don't write `sets`; no existing test broken.

## P2 notes — all NON-defects (documented design choices; no change)
- **P2-1** dead `weeklyBase` accumulation on the deload path (`volume_titration.dart` `_titrateWeek`) —
  harmless wasted work on 1 of 4 weeks; the deload branch correctly uses `workingBase`. Not worth changing.
- **P2-2** a "repeat" choice whose pin-builder returns null (repeat not faithful → fresh fill) gets
  titration ON via `pins == null`. Not a defect — titration is evidence-gated and, with readiness
  ship-dark, only ever TRIMS, the correct direction for a low-adherence user.
- **P2-3** a well-recovered user with N held groups gets +1 on all N at once — each per-group
  MRV-clamped + ship-dark; a documented design choice.
