---
branch: workout-resume-banner
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-resume-banner-bpass.md
---

# Plan review — workout-resume-banner (⑦(b): session-time detraining resume banner)

Item ⑦(b), the second half of item ⑦ (⑦(a) phase-gen decay shipped `cb1ec3c6`). On starting a workout
after a training gap, show a non-shaming banner and apply a single blanket day-level % cut to THAT
session's suggested loads — session-only, not persisted, no plan regen. **Platform** tier (the D2 band
extraction edits `progression_resolver.dart` + the D5 kill-switch getter lands in `plan_engine_flags.dart`,
both `plan_engine/**`). Behind `enable_session_detraining_cut` (ship-dark default-OFF). Plan:
`docs/plans/resume-banner-batch.md`.

## Review rounds (≥2, before code)

- **Round 1 (context-blind) → harden, no split.** Ground-truth re-verified against code; D1 (double-count
  avoided), D2 (extraction byte-identical, decay test guards), provider-leak avoidance, banner slot all
  confirmed. Folded: **P1** — a SECOND `lastPerformanceProvider` reader I'd missed, the "TRY:
  {lastWeight+2.5}" hint line (`exercise_card.dart:559-578`), fires under the cut's exact condition and
  would tell a returning user to ADD weight while the field is prefilled lower → suppress TRY when cut
  active, keep the factual "LAST:". **P2** — tier is **platform** (plan_engine), not account. **P2** — D5
  flag polarity self-contradictory (`disable_…/!=true` is default-ON) → locked ship-dark `enable_…==true`,
  catch→false. **P3s** — D7 idempotency reframed (no run-once guard; would break swaps), IST/local
  band-boundary note, mis-fire test guards (-1/0 gap).
- **Round 2 (context-blind, on the hardened plan) → harden → converged after fold; do not split.** All 7
  round-1 fixes verified SOUND against code (TRY-suppression + overload compare-vs-target wireable via the
  card's `ref`; D1 disjoint — `lastWeight` is logged history ⑦a never mutates; ship-dark pattern exact;
  extraction byte-identical + decay test pre-pins bands; swap re-inits with the cut). ONE MEDIUM folded —
  **F1:** the round-1 decision to move the factor onto `ActiveWorkoutData` created an unguarded `copyWith`
  dependency — the 1×/sec timer's `copyWith(elapsedSeconds:)` + the mount post-frame `copyWith(setInputValues:)`
  would revert an un-threaded field to its ctor default (1.0) within a frame → banner vanishes, red↓ + TRY
  return; and a prefill-only test passes while the feature is broken. Fixed: thread
  `sessionDetrainingFactor` through `copyWith` (like the superset fields `:804-807`) + a REACTIVE test
  assertion. Impl notes F2/F3/F4 folded. The reviewer flagged the unit coherent — do NOT split; F1 is a
  one-field-threading + one-assertion fix matching an existing precedent, so no round-3.

## Ground-truth verification (true — self-verified against files at 266fa884)

`getDaysSinceLastWorkout()` (`workout_repository.dart:1173-1193`, local-now, `-1` sentinel, sole caller
`pattern_detector.dart:335`); the two disjoint prefill branches (`exercise_card.dart:81-90`), lastWeight
from logged `exlog_*` (⑦a-free) vs prescribed `exercise.weight` (⑦a-decayed); `_OverloadIndicator`
(`overload_indicator.dart:28-37`); the TRY/LAST hint Builder (`exercise_card.dart:531-584`); `copyWith`
(`train_provider.dart:781-809`) + the superset precedent; `_detrainingFactor` bands
(`progression_resolver.dart:323-326` = ≤7→1.0/≤21→0.925/≤35→0.825/else→0.5, self-read). No existing SoT
concept covers the active-workout prefill → new `session_detraining_cut` contract.

## Verdict: converged

×2 context-blind rounds complete, #2 on the hardened plan; every finding folded; residuals are impl
notes. Ready to implement per the plan. B-pass on the diff runs before merge (platform §4.3); this record's
`bpass: accepted` is finalized against `docs/reviews/workout-resume-banner-bpass.md`.
