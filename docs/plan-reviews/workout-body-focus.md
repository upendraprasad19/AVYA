---
branch: workout-body-focus
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-body-focus-bpass.md
---

# Plan review — workout-body-focus (Batch 4 ⑤ body-focus bring-up, Option 1)

Item ⑤. Makes the user's `physique_focus` shape the generated plan by CENTRALLY translating the token →
real muscle-substring tokens at the `effectiveBodyFocus` seam, feeding the EXISTING periodization +1-set
nudge. Behind ship-dark `enable_physique_focus_bringup`. **Platform** tier (`plan_engine`). Plan:
`docs/plans/body-focus-batch.md`.

## Review rounds (≥2, before code)

- **Round 1 (context-blind) → SPLIT.** Verified against code that the originally-locked "trade-not-add
  isolation-slot" mechanic is INFEASIBLE: (P1-a) `VolumeFilter.filter` does a POSITIONAL `slots.take(N)`
  (`volume_filter.dart:52-57`), never priority-sorted (`priority` read only in the dead deload branch) →
  boosting `MuscleSlot.priority` is a no-op; (P2-b) split days are hardcoded priority-ordered literals
  (`split_resolver.dart:553-575`) → the focus muscle is already kept on its theme day / absent on others →
  a position-reorder is inert; a real dedicated slot needs ADDING one, which breaks the tested `targetCount`
  count-per-day invariant. Also folded: P1-b (caller fan-out under-enumerated → resolved by central
  sourcing), P1-c (flag must gate the whole seam), P2-a/breadth, P2-e/phase-1, translation table verified.
- **Founder decision 2026-07-13 (product fork):** ship the **+1-set emphasis** now; the dedicated focus
  slot is a **future advancement** ("we will do that later"). A founder-ratified §4.12 split — NOT a
  deferral. Re-scoped the plan to Option 1 (translation seam → existing +1-set).
- **Round 2 (context-blind, on the hardened Option-1 plan) → CONVERGED.** No P0/P1; the re-scope
  introduced no new defect (Option 1 routes into the already-working `weakMuscles` +1-set path). Confirmed:
  the seam is a genuine single funnel (`apply` has ONE production callsite `plan_generator.dart:154`); no
  callsite sources a non-empty `bodyFocus` (vestigial param); the +1-set path is live (`primaryMuscles`
  populated by the selector); translation table verified correct against the 258-exercise library
  (`delt`+`shoulder` dual-token both load-bearing); flag mirrors `gradedProgressionEnabled` ship-dark;
  existing tests stay green. Folded P2 implementation notes (binding): **P2-a** — put the profile read in a
  try/catch `TrainingHistoryAnalyzer.physiqueFocusMuscles()` helper (physique_focus is in `userBox['profile']`,
  a DIFFERENT box than `weakMuscles`' workout box; `plan_generator` imports no HiveService) so there's no
  new Hive coupling in `plan_generator` and degradation stays graceful; **P2-b** — the try/catch → [] is
  what makes flag-ON graceful (flag-OFF never reaches the read → crash-free by construction); **P2-c** — the
  behavioral test must Hive-boot + seed `exerciseBox` so the selector picks a `primaryMuscles:['Glutes']`
  exercise, with a flag-OFF baseline comparison, + expose the pure translation `@visibleForTesting`; **P3-a**
  — the stale-comment fixes must rewrite the MECHANISM (the comments describe the deferred SLOT mechanic →
  correct to "+1 set on matching exercises via periodization"); **P3-b** — `glutes_legs` optional `legs`
  token (safe under-match otherwise); **P3-c** — SoT cross-refs the upstream physique_focus writers.

## Ground-truth verification (true — self-verified)

`effectiveBodyFocus` seam (`plan_generator.dart:148-151`) + sole reader `apply` `:154`; `weakMuscles`
try/catch/telemetry/safe-empty pattern to mirror (`training_history_analyzer.dart:36-92`);
`TrainingHistoryAnalyzer` already imports HiveService + ErrorTelemetry (`:4-5`); periodization +1-set match
+ `break` (`periodization_engine.dart:96-104`); flag pattern (`plan_engine_flags.dart:47-54`); the 4
physique_focus tokens + stale comments (`lib/features/profile/screens/edit_profile_screen.dart`).

## Verdict: converged

×2 context-blind rounds complete (round-1 drove the split + founder decision; round-2 on the hardened
Option-1 plan). Every finding folded; residuals are the binding P2 implementation notes above. Ready to
implement. B-pass on the diff runs before merge (platform §4.3); `bpass: accepted` finalized against
`docs/reviews/workout-body-focus-bpass.md`.
