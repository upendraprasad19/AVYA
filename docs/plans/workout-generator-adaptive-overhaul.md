---
branch: claude/workout-generator-improvements-hfepih
date: 2026-07-10
status: draft-pre-review          # §4.12: requires ×2 context-blind review before ANY implementation
review_rounds: 0
verdict: not-yet-reviewed
blast_radius: platform            # touches plan_engine + onboarding + train + profile
---

# Workout Generator — Adaptive Overhaul (3 waves)

Brainstorm-converged plan (founder session 2026-07-10). Grounded in (a) a full code audit of the
plan engine + all 10 generator call sites, (b) competitor research (Fitbod, JuggernautAI, Dr. Muscle,
RP Hypertrophy, Alpha Progression, Boostcamp, Freeletics, Hevy, cult.fit, HealthifyMe), and
(c) an exercise-science pass producing 11 cited "if X in logs → do Y" rules (R1–R11, reproduced in
Appendix B).

## Why (one paragraph)

The engine is a deterministic local expert system — the same architecture as every "feels like a
real coach" market leader (JuggernautAI / RP / Dr. Muscle / Alpha Progression; notably **no leader
uses an LLM as the plan engine**). What we're missing is not architecture but (1) **inputs consumed**
— the app collects injuries / session duration / preferences and then throws them away before the
plan the user actually trains on — and (2) **feedback loops** — selection, structure, volume, and
phase timing are 100% performance-blind; only suggested weights adapt. Strategic gap: **no app on
the market combines real progressive-overload programming with Indian equipment realities**
(mismatched dumbbells, bands, home training); cult.fit / HealthifyMe do video matching, not
programming. ₹349/mo undercuts HealthifyMe's ₹799 AI plan with real programming.

## Ground-truth findings this plan is built on (verified against code 2026-07-10)

| # | Finding | Evidence |
|---|---|---|
| G1 | Injuries reach the generator on only 3 of 10 call paths — and NONE of the paths that write the plan the user trains on. Onboarding passes none (`onboarding_provider.dart:453`); graduation's *preview* passes them (`graduation_screen.dart:338`) but its *real* generate does not (`graduation_screen.dart:588`). | Call-site audit |
| G2 | `sessionDuration` is threaded through the facade (`workout_schedule_service.dart:88/115/141`) but **dead in V4** — `generateV4` receives it and never reads it; the V3 `resolveMaxPerDay(sessionDuration)` path (`exercise_selector.dart:157-168`) is orphaned. | Code read |
| G3 | `cardioPreference` is never passed by any caller → `cardio_finisher.dart:21` defaults every user to `'hate_cardio'`. | Grep of all callers |
| G4 | `bodyFocus` is never user-chosen; only auto-derived phase ≥ 2 via `TrainingHistoryAnalyzer.weakMuscles()` (`plan_generator.dart:129-132`). | Code read |
| G5 | The 4 equipment tiers are presets: `_getEquipmentList` (`plan_generator.dart:203-223`) expands the tier to a hardcoded **item list**, and the whole selector filters on items. An equipment checklist is therefore a small engine change. | Code read |
| G6 | Phase advance + deload are pure calendar (28-day expiry, deload hardwired week 4 of the periodization wave). Science: fixed deloads can *cost* strength (Coleman 2024); triggered deloads + 8-week backstop are the defensible model (R7). | `workout_schedule_read_service.dart:601`, periodization engine |
| G7 | Two adaptive levers are built but unwired: `demotedExercises()` (`training_history_analyzer.dart:107` — reads the `swapped_from` stamp written by `swap_service.dart:281`) and `bodyweightTrendSignal()` (`:162`). No caller in the plan_engine. | Grep |
| G8 | AI-coach `regeneratePlanBlock` hardcodes `phase=1` (`regenerate_plan_planner.dart:170-176`) — a phase-6 user asking the coach to regen is demoted to Foundation. | Code read |
| G9 | Progression history is name-keyed — a swapped/renamed exercise silently loses its weight history (`progression_resolver.dart`, name-matched). | Code read |
| G10 | Current weight rule is binary (≥10 reps → +2.5/5kg, <5 → back off). ACSM/APRE support a graded table with load *cuts* on undershoot (R1). | `progression_resolver.dart:41+` |

---

## Wave 1 — "The plan respects you" (wire existing inputs; FREE tier)

> Theme: everything here is connecting plumbing that already exists, plus two outright bugs.
> Each unit lands with regression test + diagnose-doc (bugs) per §4.4 rules 21–22.

### W1.1 Injuries into every generate path + pattern-based substitution (R9) — SAFETY, FREE
- **What:** every call site passes profile `injuries` (filtered `!= 'none'`); selector excludes by
  `injury_contraindications` AND substitutes **within the same `movement_pattern`** with a
  lower-joint-stress variant (shoulder → OHP replaced by landmine/neutral-grip press class), never
  leaving a slot empty or dropping pattern balance.
- **Touchpoints:** `onboarding_provider.dart:453`, `train_provider.dart:466` (auto-gen),
  `edit_profile_screen.dart:1795`, `graduation_screen.dart:588`, `auth_session_bootstrapper.dart:379`,
  `regenerate_plan_planner.dart:170`; engine: `exercise_selector.dart` (verify current depth of
  injury filtering in `queryV4` during implementation — preview paths already pass injuries so some
  filter exists; the substitution-within-pattern upgrade is new).
- **Copy discipline:** comfort-based substitution framing; never medical advice.
- **Tests:** contract — plan generated with `injuries:['shoulders']` contains zero contraindicated
  exercises across all 4 weeks AND slot count is preserved; per-call-site source assertion that
  injuries are threaded. Diagnose-doc for the graduation preview/real mismatch (G1 — this is a bug,
  not a feature).

### W1.2 Session-duration fitter (R10) — FREE
- **What:** new engine stage after superset pairing: estimated duration = Σ(sets × (rest + ~4s×reps))
  + warmup/cardio overhead. To fit budget (30/45/60/75): (1) superset non-competing pairs,
  (2) trim isolation sets (protect compound volume), (3) shorten rest on isolation only. Never cut a
  muscle below the volume floor (R5). Reuses the trim logic concept from `SwapService.shortenDay`.
- **Touchpoints:** new `lib/shared/repositories/plan_engine/time_budget_fitter.dart`;
  `plan_generator.dart` stage wiring (§4.4 rule 14: plan_generator edits are authorized by this
  approved plan); all call sites pass `session_duration_minutes` from profile; onboarding
  `details_screen.dart` gains a duration chip row (30/45/60/75, default 60).
- **Kill-switch:** `configBox['disable_time_fitter']` (§4.6).
- **Tests:** contract — generated day durations within budget ±10% across goal×equipment×days grid;
  volume-floor never violated; `sample_plans_report.dart` extended with duration column.

### W1.3 Cardio preference collected + wired (fixes G3) — FREE
- **What:** collect (onboarding Details + Edit Profile: loves / tolerates / hates cardio) and pass
  through; `CardioFinisher` already implements the behaviors.
- **Touchpoints:** `details_screen.dart`, `edit_profile_screen.dart`, profile map + sync fan-out,
  all generate call sites. New profile field ⇒ naming check (§4.7) + `live_schema_columns.json`
  regen if a cloud column is added (same commit as migration).
- **Tests:** contract — `cardio_preference:'loves_cardio'` yields finishers on fat-loss plan;
  writer/reader pair asserted.

### W1.4 "Bring-up" muscles — explicit bodyFocus (G4) — FREE input
- **What:** optional onboarding/Edit-Profile picker (max 2 muscle groups) → threads as `bodyFocus`
  (engine already consumes it: +1 set bias in `periodization_engine.dart:96-104`). Explicit user
  choice takes precedence over auto-derived `weakMuscles()`; auto-derivation remains the phase ≥ 2
  fallback (PRO insight surfaces around it come in Wave 3).
- **Tests:** contract — bodyFocus muscle receives +1 set/week vs baseline plan.

### W1.5 Equipment checklist (G5) — FREE; India differentiator
- **What:** new profile field `equipment_items: List<String>` (vocabulary = the item tokens already
  in `_getEquipmentList` / library `equipment_needed`). If present, engine uses it verbatim;
  else falls back to tier expansion (migration-safe for all existing profiles). UI: 4 tier chips
  stay as quick presets + "Customize" expands a checklist. Named multi-profiles (Fitbod-style) are
  explicitly SHELVED (Appendix A) — this field is the forward-compatible substrate for them.
- **Touchpoints:** `plan_generator.dart:203` (bypass), profile schema + sync + cloud column
  (migration + `live_schema_columns.json` same-commit), Edit Profile UI, onboarding "Customize"
  expander, SoT registry.
- **Tests:** contract — `equipment_items:['dumbbells','pull-up bar','resistance band']` produces a
  plan whose every exercise's `equipment_needed` ⊆ selection ∪ {none, bodyweight}; fallback parity —
  absent field reproduces today's tier behavior byte-identically.

### W1.6 Detraining-aware resume (R4) — FREE
- **What:** gap since last logged session decays suggested weights: ≤7d none; 8–21d −5–10%;
  22–35d −15–20% + halve sets first week; >35d ~50% + ramp. Applied in `ProgressionResolver`
  (phase regen) AND as a session-time banner adjustment when resuming mid-phase after a gap.
  Copy: fresh-start framing, never shame (market failure mode: calendar guilt loops).
- **Kill-switch:** `configBox['disable_detraining_decay']`.
- **Tests:** contract — synthetic log gaps produce the correct decay bands; no decay ≤7d.

### W1.7 BUG — AI-coach regen phase demotion (G8)
- **What:** thread real `current_phase` (progress box) into `regenerate_plan_planner.dart:170`
  instead of hardcoded 1. Diagnose-doc + regression test (rule 22).

---

## Wave 2 — "The plan responds to you" (feedback loops)

### W2.1 Graded double progression (R1, replaces binary rule) — FREE
- **What:** rep-range-aware table in `ProgressionResolver`: top of range on all sets → +2.5kg
  upper/small, +5kg lower/compound (ACSM 2–10%); within range → hold load, target +1 rep; below
  bottom of range 2 consecutive sessions → −5–10%. Beginner auto-linear window (R2): training age
  < ~4 months progresses every session until 2 consecutive stalls, then flips to double progression.
- **Kill-switch:** `disable_graded_progression` (old binary path preserved verbatim, §4.6).
- **Tests:** table-driven contract test over (reps history → adjustment) grid; regression: current
  behavior reproducible with flag off.

### W2.2 One-tap difficulty rating (feeds R3/R6/R7) — FREE collection
- **What:** post-exercise (not per-set) 1-tap: "Easy / Just right / Too hard" — phrased "could you
  have done 2 more reps?", never "rate RIR" (RP's beginner-abandonment failure mode). Stored on the
  `exlog_*` row (`difficulty: -1|0|1`), synced. Skippable, never blocks logging.
- **Consumers:** W2.1 grading (R3: easy → bigger step; too hard → hold; failed → cut), W2.4 deload
  trigger, W2.6 titration. SoT registry entry `exlog_difficulty` with behavioral test.
- **Tests:** writer/reader contract (log with rating → next-phase weight differs accordingly).

### W2.3 Readiness check-in — FREE (founder decision 2026-07-10)
- **What:** on entering active workout mode: skippable 3×3-chip sheet (Sleep: Solid/Okay/Rough ·
  Soreness: Fresh/A little/Beat up · Energy: Charged/Normal/Running low). Deterministic session
  modes: **Green** unchanged; **Yellow** (1–2 flags) −5–7% suggested loads on compounds;
  **Red** (3 flags) −10% loads + drop 1 isolation set (respect volume floor) + optionally swap the
  highest-`cns_demand` exercise for a lighter same-pattern sibling. NOT a generator change —
  a session-time modulation layer on the materialized day.
- **Data model:** answers → Hive `readiness_<date>` (synced); adjustment stamped on the scheduled
  day row as `readiness_adjustment` (auditable; base plan untouched; tomorrow unaffected).
  Skipped 3 sessions running → offer to disable. Every adjustment carries a one-line "why"
  (dispatch voice; Wardroom CLAUDE.md loaded before copywriting per §DISCIPLINE).
- **Free/PRO seam:** check-in + today's adjustment FREE; readiness *trends/insights* PRO (Wave 3).
- **SoT:** `readiness_daily` writer/reader pair; kill-switch `disable_readiness_adjust`.
- **Tests:** behavioral — red check-in → suggested weights reduced on that day's rows only; base
  plan rows unchanged; contract for the `readiness_<date>` writer/reader.

### W2.4 Triggered deload + 8-week backstop (R7) — PRO
- **What:** deload fires on signal, not calendar: (e1RM on ≥2 main lifts declining across 2
  consecutive sessions AND difficulty ratings high) OR (persistent red readiness + flat e1RM) OR
  backstop 8 weeks since last deload. Deload = 1 week, ~50% sets, −10–20% load, same exercises.
  The fixed week-4 deload in the periodization wave becomes **conditional** — this is the deepest
  engine change in the plan; the 4-week phase container stays (UI/paywall semantics untouched),
  only the deload week's content is autoregulated. **Design-review focus area #1.**
- **Kill-switch:** `disable_triggered_deload` (fixed week-4 behavior preserved as fallback).
- **Tests:** fakeAsync harness — synthetic declining-e1RM logs trigger deload; adherent
  strong-performance logs get a working week 4; backstop fires at 8 weeks regardless.

### W2.5 Performance/adherence-gated phase advance — PRO
- **What:** phase N+1 auto-generation (splash path) additionally consults adherence: <~40%
  completion of phase N → offer "repeat phase at adjusted loads" instead of silent advance
  (respecting W1.6 decay). Never blocks a user who explicitly chooses to advance.
  **Design-review focus area #2** (interacts with PhaseProgressReconciler + paywall moments —
  b0baa5/0e7714/ec4d27 bug-class history).
- **Tests:** contract over the (completion% × user-choice) decision table.

### W2.6 Wire the dead levers (G7) — PRO
- **What:** (a) `demotedExercises()` → selector down-ranks exercises the user repeatedly swapped
  away from (never re-prescribe a 2×-demoted exercise when a same-pattern sibling exists);
  (b) `bodyweightTrendSignal()` → cardio-volume / calorie-copy nudge input.
- **Tests:** contract — an exercise swapped away twice in logs does not appear in the next
  generated phase when an alternative exists.

### W2.7 Volume titration with MEV/MRV clamps (R5+R6) — PRO
- **What:** weekly set-count per muscle titrates on evidence: performance met + soreness resolved
  (from difficulty/readiness data) → +1 set (cap ~MRV≈20); performance dropped or persistent
  soreness → hold, two weeks → −sets. Clamp all plans to [MEV≈8, MRV≈20] direct sets/muscle/week
  (indirect ×0.5). Conservative defaults — audience is desk workers, not athletes (Juggernaut/RP
  core complaint). Landmarks labeled heuristic in code comments.
- **Tests:** clamp invariant test over the full goal×days×experience grid; titration table test.

---

## Wave 3 — "The plan talks to you" (trust + longevity)

- **W3.1 Explainability layer** — every generated adjustment (bring-up +1 set, readiness trim,
  deload trigger, progression step, injury substitution) stamps a machine-readable reason;
  UI renders one-line dispatch-voice explanations. Market finding: visible cause→effect is THE
  differentiator between "real coach" and "template picker"; fits AVYA's briefing voice natively.
- **W3.2 Visible phase arc** — Train screen shows the wave (baseline → overreach → peak → deload)
  and the deload horizon. We already have the arc; we just never show it.
- **W3.3 ID-keyed history (G9)** — progression/analyzer/swap stamps keyed on exercise `id` with
  name fallback; swaps stop erasing weight history. Migration for existing `exlog_*` rows.
- **W3.4 Variety engine + pool-depth hardening** — cross-phase novelty bias (rotate same-pattern
  siblings between phases; Baz-Valle 2019: equal gains, higher motivation — but bounded, no random
  churn) + close the shallow-pool triples that force `universalPool` wrong-picks (bug-class 40a426).
- **W3.5 Plateau detection + escalation (R8)** — PRO: e1RM flat ≥3 exposures & ≥4 weeks & sessions
  completed → escalate one variable: deload (if fatigue) → +sets (if below MAV) → same-pattern
  exercise rotation / rep-range shift.
- **W3.6 Surface per-exercise coaching content** — library already stores coaching_cues, tempo,
  common_mistakes, breathing_cue, warmup_protocol per exercise; render in active workout.
- **W3.7 Readiness trends (PRO)** — "your Friday sessions are always red" insight surface over
  `readiness_<date>` history.

---

## Free / PRO matrix (converged with founder 2026-07-10)

| FREE — safety + credibility | PRO — the adaptive coach |
|---|---|
| Injury-aware generation + substitution (W1.1) | Triggered deloads + backstop (W2.4) |
| Session-duration fitter (W1.2) | Gated phase advance (W2.5) |
| Cardio preference (W1.3) | Demoted-exercise + trend levers (W2.6) |
| Bring-up muscles input (W1.4) | Volume titration (W2.7) |
| Equipment checklist (W1.5) | Plateau detection (W3.5) |
| Detraining-aware resume (W1.6) | Readiness trends/insights (W3.7) |
| Graded progression (W2.1) + difficulty tap (W2.2) | |
| **Readiness check-in + today's adjustment (W2.3)** | |
| Exercise swap (stays free — safety action; Boostcamp's paywalled-swap is a named market failure) | |

Phase 1 free / phases 2–12 PRO paywall unchanged (§4.4 rule 6).

## Process obligations (per CLAUDE.md)

- **§4.12:** this document gets **×2 context-blind reviews** (round 2 on the hardened plan) BEFORE
  any implementation; record → `docs/plan-reviews/` keyed to this branch; if reviews keep surfacing
  new material issues, split and ship the smallest converged piece (Wave 1 already structured for
  that — W1.1/W1.7 bugs can ship as a standalone first unit).
- **§4.4 rule 14:** `plan_generator.dart` edits are authorized by founder approval of this plan.
- **§4.6:** every engine-behavior change ships behind a kill-switch with the old path verbatim
  (flags named per-unit above).
- **§4.5:** every new writer/reader pair → `docs/sot_registry.yaml` entry with
  `behavioral_test_path`; new profile fields walk §4.7 naming check; cloud columns land with
  migration + `live_schema_columns.json` regen same-commit.
- **Blast radius:** plan_engine + onboarding + auth-bootstrapper ⇒ ≥account at minimum ⇒
  self-initiated `/code-review` B-pass before each merge (§4.3); Wave 2 (engine progression
  semantics) treated as platform.
- **Bugs W1.1-graduation-mismatch + W1.7** each land with diagnose-doc + `closes-diagnose:` (rule 22).

## Review focus areas (for the §4.12 reviewers)

1. W2.4's conditional deload vs the periodization wave's week-4 assumptions (weightCue copy,
   `weekCharacter` consumers, tests pinned to 4-week shape).
2. W2.5 interaction with PhaseProgressReconciler + graduation paywall moment (bug-class
   b0baa5/0e7714/a3f8c1/7d2e6b).
3. W1.2 time-fitter vs `SwapService.shortenDay` — one trim algorithm, two entry points; avoid drift
   (candidate shared module).
4. W1.5 checklist vs the beginner Phase-1 shallow pool (`suitable_for` ⊇ Beginner AND
   `is_foundational` — a sparse custom equipment list could force universalPool picks; needs the
   `sample_plans_report` grid extended to checklist combinations).
5. W2.3 readiness adjustment writer vs active-workout persistence + edit-log flows (writer/reader
   drift is the house default suspect class).

## Appendix A — Shelved (explicit, with rationale; NOT deferrals — out of approved scope by founder decision 2026-07-10)

| Item | Why shelved | Re-entry trigger |
|---|---|---|
| Per-set prescription ("next set: 62.5kg × 8") | Autoregulation edge over graded double progression is small (Larsen 2021); requires logging-UX + engine data-model rework | After W2.1/W2.2 ship and difficulty-tap adoption is measurable |
| Named equipment profiles (Fitbod "Home/Gym/Travel") | Needs profiles collection + switching semantics; W1.5 checklist field is the substrate | After W1.5 ships; travel mode already covers the acute case |

## Appendix B — Science rulebook (from research pass 2026-07-10, citations in research archive)

R1 graded double progression (ACSM 2009) · R2 beginner linear window (~3-6mo) · R3 difficulty-graded
load step (APRE, Mann 2010; RIR accuracy Halperin 2022 — 3 buckets max) · R4 detraining decay bands
(Stronger by Science detraining synthesis) · R5 volume clamps MEV≈8/MRV≈20 (Schoenfeld 2017
dose-response; Pelland 2024 diminishing returns; landmarks = heuristic) · R6 evidence-titrated sets
(RP algorithm, publicly described; heuristic) · R7 triggered deload + 8wk backstop (Coleman 2024:
fixed deloads can cost strength; Bell 2023 practice survey) · R8 plateau escalation, one variable at
a time (Baz-Valle 2019 variation; Kassiano 2022 anti-churn) · R9 movement-pattern injury
substitution (practice standard; non-medical framing) · R10 time-budget fitting (Iversen 2021 "No
Time to Lift"; Schoenfeld 2019 frequency-neutral) · R11 periodization by training age (no DUP/block
complexity for novices).
