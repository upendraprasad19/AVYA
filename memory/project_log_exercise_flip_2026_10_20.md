# Flip batch: one LOG per exercise goes live (RE-OPEN, faded prefill, FINISH guard, OI-361) · 2026-10-20

Branch `log-exercise-flip` (base `main` a909cdb) · plan `docs/plans/log-exercise-flip.md` (rev 9) · record
`docs/plan-reviews/log-exercise-flip.md` (7 rounds, 12 context-blind reviews, converged) · closure
`docs/audit/log-exercise-flip.closure.yaml` · diagnose `e3a6c1` (OI-361, zero-set completion credit).

## What shipped

`enable_log_exercise_button` reads default ON (a stored `false` is the debug kill switch; the OFF path stays until
its removal OI). In LOG mode:
- **RE-OPEN** (founder: "amend log"): tap LOGGED to uncheck the exercise with its values kept; guarded by
  `kReopenGuard` (1200 ms after an advancing LOG) and followed by a `kRevealGuard` (700 ms) LOG window; announced to
  TalkBack.
- **Faded prefill:** app-filled weight/duration/distance render at 62% parchment until typed (`suggestedInputs`,
  three-part keys); reps always normal; a tap selects all; subline `{kg} KG · PREFILLED` while the source is
  app-filled. One card writer `recordCardEdit` per event; LOG mode captures every keystroke.
- **FINISH guard:** one save predicate (`wouldSaveSet` / `saveableSetIndexes`) shared by `completeWorkout`, the
  header counts and the dialog lines (re-opened, typed-not-logged, skipped, partial).
- **OI-361 (both flag paths + the coach chat card):** nothing saveable ⇒ COMPLETE / CONFIRM disabled with the reason,
  and the writers refuse.

## Things worth carrying forward

**1. A plan claim about "the other callers" is a claim to verify by reading each one.** Round 7 found that "the
coach path always has a set" held for two of three completion callers; `submitWorkoutDraft` completed a no-set chat
draft. Name every caller of the guarded writer before writing "untouched".

**2. fakeAsync does not fake `DateTime.now()`.** A timer whose tick reads the wall clock never advances in a test;
assert `fa.periodicTimerCount` instead (R7-03).

**3. The real Active Workout screen is pumpable.** `card_harness.dart` `pumpScreen` (seeded notifier, overridden
`lastPerformanceProvider`, Hive opened in `runAsync`) drives FINISH and the dialog end to end. Two traps: the list
builds FINISH lazily (jump the controller to `maxScrollExtent` until it exists; `scrollUntilVisible` ran out of
drags at 2.0 text scale), and the cards behind a dialog have TextFields too (scope finders to the `AlertDialog`).

**4. The screen's own FINISH/CANCEL `WardButton` row overflows at 320 dp × 2.0 text** (pre-existing, not this
batch). Dialog layout tests lay the list end out first and take that report before opening the dialog.

**5. Two golden tests (`ward_rank_pill_*`) fail by 10 px in this cloud container on clean `main` too** —
environmental (font rasterisation); CI is the source of truth.

## Still open after the merge

- A12 on OI-348: the release-build device walk (flip precondition 3 as amended by the founder).
- OI-362: the OFF-path removal (blocked on A12).
- OI-363: the FINISH/CANCEL `WardButton` overflow at 320 dp × 2.0 (item 4 above).
