# Batch 3b-ii — W2.1 graded double progression (progression_resolver)

Item W2.1, the second half of Batch 3b (3b-i ⑦a detraining decay shipped `cb1ec3c6`). Makes
`ProgressionResolver.resolve()`'s progress/hold/back-off rule **rep-range-aware** with a
**2-consecutive-below-range** back-off gate and a **beginner auto-linear** window. Blast radius
**platform** (core weight prescriber). Worktree `workout-graded-progression` off `cb1ec3c6` (has ⑦a).
`feat`. Binding notes from Batch 3b's round-1 ×2 review are folded here.

## Ground truth (self-verified, rule 11)

Post-⑦a, `resolve({phase, exerciseNames})` computes `base = top.weight × decayFactor` then the FIXED
3-band rule (`top.reps>=10`→progress +5/+2.5 · `>=5`→hold · `<5`→back-off, from `base`; Epley clamp).
- Each `populated` exercise is a `PlannedExercise` carrying `repRange` (e.g. "8-12", `models.dart:120`) —
  threadable as a name→repRange map from the call site (`plan_generator.dart:124-135`).
- `UserRepository.instance.getProfile()` (`user_repository.dart:44`) returns `userBox['profile']` with
  `fitness_experience` (String, RAW — e.g. 'beginner') and `onboarding_completed_at` (UTC ISO8601 ts,
  `onboarding_provider.dart:398`). Training-age = `DateTime.now().difference(DateTime.parse(...)).inDays`.
- `resolve()` already reads Hive directly (workoutBox) → reading the profile + configBox inside is
  consistent + testable (seed `userBox['profile']`).

## Change

0. **P1 (critical) — flag-OFF is BYTE-IDENTICAL.** Structure the per-exercise banding as
   `if (gradedEnabled) { …rep-range-aware incl. the profile read… } else { …verbatim fixed 10/5… }`.
   The profile read + training-age parse live ONLY inside the ON branch, so a null/malformed
   `onboarding_completed_at` can NEVER touch the flag-OFF path (which must not regress the shipped ⑦a
   decay + 10/5 rule for live users). `enable_graded_progression` getter = `configBox.get('enable_graded_progression') == true`
   (**default OFF**, ship-dark §4.6 — NOT the `disable_*` `!= true` default-ON shape; W2.1 can INCREASE
   load (progress at `hi`; beginner-linear) so it is not the safe direction — round-1 confirmed).
1. **Signature:** `resolve({phase, exerciseNames, Map<String,String?> repRanges = const {}})` — repRanges
   built at the call site from `populated` (name→`repRange`). Experience + training-age read INSIDE
   resolve() via `getProfile()` (RAW `fitness_experience` — stored lowercase 'beginner', NOT `effectiveExp`
   which widens at phase≥3). **Training-age via `DateTime.tryParse` (P1):** null/unparseable
   `onboarding_completed_at` ⇒ `beginnerLinear = false`, continue the range rule — NEVER throw (it is
   realistically null for pre-self-heal restored phase-2+ profiles → a throw would empty the whole map).
2. **top-2 session tracking (F1 — ADDITIVE, does NOT touch base/est1rm):** keep the EXISTING
   `lastSession` (single most-recent, VERBATIM `date.isAfter` first-seen tie-break) as the **SOLE** source
   of `base`/`est1rm`/⑦a-decay ABOVE the flag branch — unchanged, so flag-OFF stays byte-identical and ⑦a
   is untouched. SEPARATELY collect a top-2-distinct-CALENDAR-DAY structure (`Map<String,List<_SessionTop>>`)
   consumed ONLY by the ON-branch 2-consecutive gate. **P2: de-dupe by `(year,month,day)`** (NOT
   `DateTime`/string equality — legacy rows may carry full timestamps; two same-day logs must not fill both
   slots and trip the gate on one bad day); sort desc-by-day, take 2. (No "heaviest tie-break feeds
   base/est1rm" — that clause was dropped, F1: it would change base on legacy same-day dupes.)
3. **Rep-range-aware banding** (replaces fixed 10/5), from the ⑦a `base`, via a **SHARED parser (F2 —
   verified behavior-preserving on real data):** add `parseRepRange(String?) → (int lo, int hi)?` in a
   NEUTRAL util (`models.dart` / a plan_engine helper — so `periodization_engine` takes NO dependency on
   `progression_resolver`; require both parse to positive ints, `lo ≤ hi`, else null), used by BOTH
   `resolve()` AND `PeriodizationEngine._applyWave` (today hand-rolls the same `split('-')` at `:177-199`
   — a 2nd parser = writer/writer drift, #1 bug class). Round-2 verified EVERY real library `rep_range`
   reaching `_applyWave` is a clean "N-M" (lo<hi: 5-8/8-12/12-15/12-20/20-30/10-12/…; timed "30-60"
   early-returns before parse), so old==new for all real inputs (the shared parser also removes a latent
   `clamp(lo>hi)` throw). **§4.11 GATE:** ship a periodization regression test pinning `_applyWave` reps
   UNCHANGED for {5-8,8-12,12-15,12-20,20-30} × 4 archetypes × 4 weeks BEFORE/with the refactor — the proof
   it is inert. `_applyWave` maps null → its existing `else` baseReps path (`:198`). Null/unparseable in
   `resolve()` ⇒ the verbatim fixed-10/5 semantics.
   Bands: `reps ≥ hi` → progress (`base+increment`, incr `_isLowerBody?5.0:2.5`); `lo ≤ reps < hi` → hold
   (`base`); `reps < lo` → back-off ONLY if the top-2 most-recent DISTINCT-day sessions are BOTH below `lo`
   (2-consecutive), else hold (F5: back-off reuses today's `_isLowerBody?2.5:1.25` + the `<=0 → base` floor).
4. **Beginner auto-linear window:** `fitness_experience == 'beginner'` AND training-age `< 120` days →
   always progress (`base + increment`), skipping the range gate. Epley clamp STILL applies (never
   bypassed). **P3 composition note:** a returning beginner (large ⑦a decay) inside the window progresses
   off the DECAYED base (`base×0.5 + increment`) — Epley-capped, net still below pre-gap; documented in
   the test matrix (not suppressed — decoupled from ⑦a's gap tier for simplicity + testability).

## Verification (rule 21 — behavioral; scorecard is vacuous for resolve(), per 3b-i Finding A)

`progression_resolver_graded_test.dart` (drives now with `setTestClockTo`; flag ON):
- rep-range aware: a "8-12" exercise at 13 reps → progress; at 10 → HOLD (would progress under the old
  fixed `>=10`); at 7 → back-off candidate;
- 2-consecutive gate: one below-range session → HOLD; two consecutive below-range → back-off;
- beginner-linear: `beginner` + <120d training-age + mid-range reps → progress (vs hold without the
  window); `beginner` + ≥120d → normal range rule; intermediate → normal;
- kill-switch OFF (default) → verbatim fixed-10/5 (non-vacuity: a "8-12"@10 gives hold ON, progress OFF);
- ⑦a decay still composes (a gapped + below-range user decays AND holds).
- **§4.11 gate — `periodization_wave_reps_invariant_test.dart`:** pin `_applyWave` reps output UNCHANGED
  for {5-8,8-12,12-15,12-20,20-30} × {strength,hypertrophy,metabolic,deload} × weeks 0-3 — proves the
  shared-parser refactor of periodization is inert (the refactor touches the #1 bug-class file).
- same-day-dupe: two below-`lo` logs on ONE calendar day ⇒ HOLD (not back-off) — the (y,m,d) dedupe.
- null `onboarding_completed_at` + beginner + flag ON ⇒ resolve() still returns range-based weights
  (no empty-map regression — the F3/tryParse path).

**F6 implementation notes:** (a) `enable_graded_progression` getter wraps `configBox.get(...) == true` in
its OWN `try/catch` returning **false** on catch (a Hive-unavailable throw must NOT propagate into
resolve()'s outer try and nuke ALL progression). (b) Read profile + experience + training-age ONCE before
the exercise loop (inside the ON gate + the existing try), not per-exercise. (c) `parseRepRange` lives in a
neutral util, not `progression_resolver`. (d) test `seedExlog` keys by `exlog_${dateStr}_$name` — the
same-day-dupe case needs a key suffix tweak.

## Discipline

Platform → this plan → ×2 review → `docs/plan-reviews/workout-graded-progression.md` (rounds:2,
converged, bpass:accepted) → B-pass → kill-switch → behavioral test → scorecard no-regression. SoT:
new `graded_progression` concept (or extend `detraining_decay`'s resolve writer). Terminal in this batch.

## NOT in scope

Set-halving (⑦a ">22d halve wk-1 sets" — needs resolve() to return a record `{weights,
firstWeekSetMultiplier}` + a `PeriodizationEngine.apply` param; its own item). ⑦(b) session banner.
Difficulty tap (W2.2, deferred by design). No change to selection/injuries/cardio/wave shape.
