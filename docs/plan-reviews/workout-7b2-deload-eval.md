---
branch: workout-7b2-deload-eval
scope: Batch 7-B-2 — triggered-deload EVAL + un-deload (W2.4), ship-dark; the production reader of the 7-B-1 stash
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-7b2-deload-eval-bpass.md
---

# Plan-review record — Batch 7-B-2 (triggered-deload eval + un-deload)

The eval/trigger half of the §4.12-split deload batch. At the week-3→4 rollover a dedicated
`DeloadEvaluator` decides KEEP (the SAFE default) vs LIFT week 4 to a working week, reading the
per-exercise `working_sets`/`working_reps` that 7-B-1 stashes on the deload week. Ship-dark
(`enable_triggered_deload` AND `enable_readiness`).

## Polarity reframe (the load-bearing correction, carried from the 7-B split)
The original design biased toward LIFTING on missing evidence (unsafe — lifting a fatigued user's
recovery). **Reframe: KEEP is the safe default; week 4 lifts ONLY on positively-confirmed no-fatigue.**
`shouldLift = notBackstop && notDeloadPhase && readinessGood && e1rmNoFatigue` — every clause requires
POSITIVE evidence; any false/unknown/missing → KEEP.

## ×2 review

### Round 1 (two context-blind reviewers on the initial plan) → needs-hardening
Both converged on the same themes; the key finding was that the reframe was applied to e1RM but NOT to
readiness or the backstop — both could still read TRUE on ABSENT data (the exact polarity failure the
reframe targets). Folded must-fixes: readinessGood must require positive evidence (empty window is
vacuously "not persistently red/yellow"); the backstop marker home was unachievable-as-written without
sync plumbing; the idempotency flag lived in the GLOBAL configBox (cross-account collision); F2 peak cue
unrecoverable; skip-set gap (shorten/travel); the "after auto-advance" ordering rationale is fiction.

### Round 2 (two context-blind reviewers on the HARDENED plan) → converged
Both: **"needs-hardening but NO re-split — the unit is appropriately scoped, the reframe has converged,
NO P0/unsafe findings."** That is convergence, not the split-signal. Round 2 verified the core design is
sound (keep-default polarity genuinely resolves every uncertainty to KEEP; the local-only marker never
syncs; the user-scoped write is structurally cross-account-safe; COACH-2 is genuinely required) and
caught the localized precision fixes Round-1's corrections had introduced — most importantly two D3
ground-truth errors (`_fieldContains` is EXACT not substring; `getByExactName` DOES exist) and the
unsafe heaviest-by-weight e1RM representative (a high-rep set can mask a decline → MAX Epley).

## Ground-truth verified (Opus read the files — not subagent prose)
- `configBox` is GLOBAL, not user-scoped (`hive_service.dart:214`); `workoutBox`/`healthBox` ARE
  user-scoped (`wrapUserScopedBox`). → the marker + idempotency flag live in the user-scoped workoutBox.
- `readinessEnabled` gates the FLAG not the data (`plan_engine_flags.dart:147`); `readinessHistory()`
  returns `[]` on no check-ins (`health_read_service.dart:97-108`). → readinessGood requires ≥3 entries.
- Eval seam: `_doRolloverWithRef` (`day_rollover_service.dart:137`) is the shared cold-launch + resume
  convergence; date-store `:170`, invalidation `:172-207` → the eval slots at ~:171 (repaint via the
  rollover's own invalidations). The rollover does NOT call auto-advance → `!isPhaseExpired()` is the anchor.
- `_fieldContains` (`exercise_repository.dart:204-208`) is EXACT-match; the generator's compounds-first
  sort uses it (`:341`). `getByExactName` exists (`:42-51`). → the e1RM scan mirrors both.
- `upsertScheduled` (`workout_write_service.dart:549-555`) FULL-replaces `{...entry,...}` + has the
  Theme-H completed-guard (`:539`) + fires its own unawaited sync (`:557-558`). → full-row RMW, unawaited durability.
- `archetypeForPhase` (`periodization_engine.dart:15-17`) maps phase 4/8/12 → 'deload'. `week_plans[3]`
  is always the deload week (`List.generate(4,…)`). `_waveCues`/`_waveNotes` peak strings are progression-
  overwritten / not-stashed → generic "Working week" cue is a deliberate accuracy choice.

## The design (all Round-1+2 corrections folded)
- **Eval placement:** dedicated `DeloadEvaluator.maybeEvaluate()` from `_doRolloverWithRef` ~:171,
  awaited, before the invalidation block; try/catch + `recordNonFatal` (mirrors the sibling streak blocks).
- **7 guards** (cheapest first): flags → user-scoped idempotency → `!isPhaseExpired()` → week>=4 →
  COACH-2 (`generated_via ∈ ai_coach_*` → keep) → still-'deload' char (a lifted week is 'working' → any
  re-eval is a no-op) → stash-presence.
- **Decide:** `notBackstop = marker!=null && marker<=phase && (phase-marker)<2` (null/overdue/future →
  keep, safe for all phases incl. 1); `notDeloadPhase`; readinessGood (≥3 in 14d, majority green);
  e1rmNoFatigue (≥1 compound with ≥2 dated sessions AND none declining, per-session MAX Epley).
- **Un-deload:** today-or-future PLANNED rows only (`status=='planned' && shortened_via==null &&
  is_swapped!=true`); per-exercise (only exercises carrying working_sets); FULL-row RMW via
  `upsertScheduled(planGenerator)` + a blob `week_plans[3]` dual-write; `week_character → 'working'`;
  durability UNAWAITED.
- **State (user-scoped, LOCAL-ONLY, never synced):** `last_actual_deload_phase` (seeded on a FIRM keep) +
  `deload_evaluated_for_phase_<N>` (idempotency, SET only on a firm decision — pure insufficient-data keep
  sets NEITHER → re-evaluable, self-healing the restore race).

## Verification
- `flutter analyze` clean on all touched files.
- `test/contracts/deload_eval_behavioral_test.dart` — 14 tests GREEN: flag-off (either flag) byte-
  identical; all-clauses-true LIFT (rows + blob → working, sets←working_sets); every polarity keep
  (empty/sparse readiness, zero-compound, **declining e1RM via the MAX-Epley pin**, unseeded backstop,
  intended deload phase); restore-race (keep AND flag NOT set); idempotency; per-exercise + completed/
  is_swapped/shortened row gates.
- SoT `triggered_deload_eval` with a behavioral_test_path. No migration (rides plan_json + local state).

## Verdict: converged. B-pass: accepted (see bpass_review).
