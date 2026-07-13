# Batch 3b-i — ⑦(a) detraining WEIGHT decay (progression_resolver)

Split from Batch 3b per the round-1 ×2 review (VERDICT: split): ⑦(a) shares **zero** refactor with
W2.1 (it needs only the single most-recent `lastSession[name]`, already present), so it ships as the
smallest converged piece (§4.12). **W2.1 graded progression = Batch 3b-ii** (next sub-batch, own focused
plan + ×2 review — its binding notes captured at the end). Blast radius **platform**
(`progression_resolver.dart` prescribes phase-2+ starting weights). Worktree
`workout-progression-resolver` off `fcc198d0`. `feat` (closes the phase-regen "resume ignores gaps"
gap — no pre-existing bug ID; behavioral test is the contract).

## Ground truth (self-verified + round-1-review-confirmed, rule 11)

`ProgressionResolver.resolve({phase, exerciseNames}) → Map<String,double>` (`progression_resolver.dart:41`,
phase≥2) keeps ONE `_SessionTop` per exercise = the most-recent logged top set + its REAL date
(`lastSession[name]`, set in the loop `:76-79`; note `_topSet` returns a placeholder `DateTime(0)` at
`:157` — the real date is the loop's, not `_topSet`'s). Then the 3-band reps-rule (`:93-105`) + Epley
1RM ceiling (`:89-90,108`). ⑦(a) needs only `lastSession[name].date` → NO signature change.

## Change (weight-decay only — Finding B: set-halving is OUT, it would force a return-type change → its own future item)

In `resolve()`, before the existing reps-rule, compute a decayed baseline `base = top.weight × factor`
by the IST day-gap:
- ≤7d → 1.0 (none) · 8–21d → 0.925 (−7.5%) · 22–35d → 0.825 (−17.5%) · >35d → 0.50 (−50%).
**F3 (P2 — the decayed `base` REPLACES `top.weight` in ALL FOUR reps-rule references** — progress
`base+inc` (`:96`), hold `base` (`:99`), back-off `base−backoff` (`:103`), AND the `<=0` floor which
resets to `base`, NEVER the original (`:104`). Only `est1rm` (`:90`) keeps the ORIGINAL `top.weight`.
Without this, a light lower-body lift at >35d/<5-reps would decay 2.5→back-off 0→floor-reset to the
original 5 kg = weight goes UP, inverting "decay only reduces.")
**Epley ceiling stays on the LAST-DEMONSTRATED 1RM** (`top.weight`×reps, pre-decay) — decay lowers the
START, never the cap; a decayed→progressed weight is strictly ≤ the un-decayed case so the existing
clamp still holds.
**F5 (P2 — zone-canceling IST gap):** carry the RAW `log['date']` string into `_SessionTop` (a new
`dateStr` field); compute `gapDays = DateTime.parse(istTodayStr()).difference(DateTime.parse(dateStr)).inDays`
— both parsed date-only so the device zone cancels. Do NOT run `top.date` back through
`istDateStr`/`istDateOf` (it is ALREADY an IST date-only value → re-zoning double-shifts east-of-IST
devices, the Test #11.1 class per `ist_date.dart:16-19`). `resolve()` gains two imports (F1):
`core/utils/ist_date.dart` + relative `plan_engine_flags.dart`.
Kill-switch `disable_detraining_decay` (default ON = decay active, matching the shipped plan-engine
convention U2/U3/④: kill-switch + behavioral test + safe/reduce direction → default-ON, which the
founder-ratified precedent already applies over §4.6's literal ship-dark for safe-direction plan-engine
changes — VALID given F3 is fixed, since only then is "reduce-only, never over-loads" actually true).
OFF → verbatim pre-⑦a weights.

## Verification (Finding A — the scorecard is VACUOUS here; behavioral test is the SOLE proof)

The Batch-0 scorecard CANNOT measure ⑦(a): `generator_matrix.generatePlan` stops at `CascadeTracer`
(never invokes `resolve()`/PeriodizationEngine), seeds NO `exlog_*` history (resolve would return `{}`),
and `computeProgression` scores library `default_sets` non-decreasing across phases — never
`suggestedWeight`. So decay structurally cannot move the scorecard (it stays green trivially — a
no-selection-regression check only). **`progression_resolver_decay_test.dart` is the sole proof**
(drives "now" with `setTestClockTo(...)`, `resetTestClock()` in tearDown — both honor the override):
- **F7 — prove decay in the HOLD band** (`5≤reps<10` → `suggested = base`, where the Epley clamp NEVER
  fires) so the assertion measures the band % exactly and isn't masked by the ceiling (in the PROGRESS
  band at low weights the clamp can make decayed == un-decayed → a false pass). Assert the HOLD output
  == `top.weight × factor` for 8–21d, 22–35d, >35d;
- **F4 — pin the boundary days** 7, 8, 21, 22, 35, 36 (catch a future `<`/`<=` slip);
- ≤7d gap → NO decay (verbatim `top.weight`);
- **F3 — inversion guard:** a light lower-body lift (e.g. 5 kg) at >35d with `<5` reps → output `< base`
  and STRICTLY `< top.weight` (never resets up to the original via the `<=0` floor);
- kill-switch `disable_detraining_decay=true` → verbatim pre-⑦a weight (non-vacuity: proves the decay,
  not luck, changed it).

## Discipline

Platform-tier → this focused plan → round-1 review DONE (split) → round-2 review on THIS hardened
⑦(a)-only plan → `docs/plan-reviews/workout-progression-resolver.md` (review_rounds:2, converged,
bpass:accepted) → self-B-pass before merge (§4.3) → kill-switch (§4.6) → behavioral test (rule 21) →
scorecard no-regression (trivially, per Finding A). SoT: extend the progression writer/reader entry
(`resolve` writer gains the decay seam; PeriodizationEngine reader unchanged). Terminal in this batch.

## W2.1 = Batch 3b-ii (next — NOT deferred, an explicit §4.12 split; binding notes from round-1 review)

- **Read experience + training-age INSIDE resolve()** via `UserRepository.instance.getProfile()`
  (`onboarding_completed_at` + `fitness_experience` both live in `userBox['profile']`), NOT a 6-caller
  fan-out. Signature change is then ONLY `Map<String,String?> repRanges` (genuinely from `populated`).
- **Use RAW `fitness_experience`** for the beginner-linear window — NOT `effectiveExp` (which widens
  beginner→intermediate at phase≥3, silently closing the window). Reading the profile key sidesteps it.
- **top-2 tracking:** insert-then-sort-desc-take(2) (keys iterate arbitrary order), and **de-dupe
  same-day** (a re-log must not fill both "2 most recent" slots → the 2-consecutive gate would fire on
  one bad day). Take the top set per DISTINCT calendar day.
- **Set-halving** (⑦(a)'s ">22d halve wk-1 sets") lands here or in its own item: it needs resolve() to
  return a record `{weights, firstWeekSetMultiplier}` + a new `PeriodizationEngine.apply` param applied
  at `weekIdx==0` (the seam is clean — beside the body-focus +1-set block, `periodization_engine.dart:106-112`).
- Kill-switch `disable_graded_progression`; behavioral test `progression_resolver_graded_test.dart`.

## NOT in scope (Batch 3b-i)

W2.1 (above), ⑦(b) session-resume banner (separate active-workout surface), set-halving (needs the
return-type change — Batch 3b-ii). No change to selection/cascade/injuries/cardio/periodization-wave.
