---
date: 2026-09-16
status: draft
blast_radius: platform (floor — re-classify the real diff at plan-review time via scripts/blast_radius_from_diff.dart)
related: docs/architecture/ai.md, supabase/functions/CLAUDE.md
---

# Proactive cron: remove AI-generated copy, go template-only

## Problem

A production incident (2026-09-15, ~18:27-18:29 UTC) traced to Gemini 429
"quota exceeded" responses, confirmed from the raw Edge Function logs — not
from the app's own 10/day free caps (verified: 7/10 food-text calls, 3/10
chat calls that IST day, both under cap). A single user logging four meals
back-to-back generated ~10 real Gemini HTTP calls in ~90 seconds (each
Flash→Lite fallback silently doubles a call), landing in the same window as
`pr-detection`, which fires every 15 minutes for every user regardless of
whether anyone is using the app.

A follow-up audit of all 15 Gemini-calling Edge Functions (verified directly
against source, not just the audit's summary) found that 8 of those 15 spend
a Gemini call on wording a message whose SEND/DON'T-SEND decision is already
100% deterministic SQL — the AI contributes phrasing only, and 7 of those 8
already have a hardcoded fallback that ships today whenever Gemini fails.
`future-prediction` is a related but distinct case: it asks Gemini to
literally forecast numbers, which is a quality problem (LLMs aren't
calibrated forecasters), not just a volume one.

## Decision

Remove the Gemini call entirely — for every tier, no PRO exception — from
the 8 cron-dispatched notification functions and separately fix
`future-prediction`. A PRO-gated middle option was considered and rejected
by the founder: "I don't want to use AI even for PRO."

## In scope (9 functions)

`pr-detection`, `streak-guardian`, `plateau-alert`, `protein-gap-alert`,
`re-engagement`, `workout-window-closing`, `morning-alert`,
`proactive-coach-promotion`, `future-prediction`.

## Explicitly out of scope — unchanged

`ai-proxy` (chat, food_text_analysis, scan_meal, cart_auditor),
`ai-media-proxy`, `assess-body-composition`, `daily-snapshot`,
`rolling-context`, `weekly-report`. All of these are genuine
extraction-from-unstructured-input or open-ended generation — verified by
reading each one's prompt construction, not assumed from the function name.

## Copy source of truth

Every string below was read verbatim from the current production code, then
reviewed end-to-end by the founder in an interactive approval tool
([Dispatch Ledger](https://claude.ai/artifact/AVGZY5uBV2yTjwvXwsf6S9), all 30
cards marked Approved, 2 edits applied — see per-function sections). That
review is the authoritative content; this spec inlines it so implementation
doesn't depend on the artifact staying reachable.

---

## Per-function changes

### `pr-detection`

- File: `supabase/functions/pr-detection/index.ts`.
- Decision (unchanged): `.eq("is_pr", true)` on `workout_log_exercises`
  (`:89`) — plain SQL, not touched.
- Remove: the `try { geminiChat(...) } catch` block wrapping the Gemini call
  (`:159-189` in the version read for this audit); `message` becomes
  unconditionally `composeMessage(firstName, prs)` (`:244-265`), which
  already exists and is unchanged except the one approved edit below.
- **Approved copy** (edit applied to the single-PR case):
  - 1 PR — title `New PR! 🏆` — message: `{name} — new {exercise} {weight}kg
    PR. Keep going 💪.`
  - 2 PRs — title `2 new PRs! 🏆` — message: `{name} — new PRs: {ex1},
    {ex2}. Strong session.`
  - 3+ PRs — title `{count} new PRs! 🏆` — message: `{name} — new PRs:
    {ex1}, {ex2} +{n} more. Strong session.`

### `streak-guardian`

- File: `supabase/functions/streak-guardian/index.ts`.
- Decision (unchanged): streak ≥ 2 weeks AND no workout logged today — SQL,
  not touched.
- Remove: the Gemini try/catch block (`:316-349` in the version read);
  `message`/`title` become unconditionally whatever the existing
  if/else-if milestone chain (`:270-314`) already computed.
- **Approved copy** (no edits):
  - 7-day — title `1 week strong!` — `You've hit 7 days straight — that's
    the hardest week done. Don't stop now!`
  - 14-day — title `2 weeks! You're building a habit.` — `14 days of
    consistency. Most people quit by now — you didn't. Keep going!`
  - 30-day — title `30-day warrior!` — `A full month of training. You're in
    the top 5% of users. Log today to keep it alive!`
  - 50-day — title `50 days. Legendary.` — `Half a century of consistency.
    This streak is worth protecting — don't miss today!`
  - 100-day — title `100-DAY STREAK!` — `Triple digits. You're officially
    unstoppable. One workout away from 101!`
  - Every 10 days (>10) — title `{days}-day milestone!` — `{days} days of
    showing up. That's elite. Don't let today be the one you miss.`
  - Near goal weight (±2kg) — title `Almost at your goal weight!` — `You're
    within 2kg of your target. Don't miss today — every session counts
    now.`
  - Standard nudge (title always `Don't break your streak!`, rotates by
    `streakDays % 4`):
    1. `It's getting late. Your {weeks}-week streak is waiting for today's
       workout.`
    2. `{days} days of consistency so far. One workout keeps it alive.`
    3. `You didn't come this far to only come this far. {weeks} weeks and
       counting!`
    4. `Your future self will thank you. Log a workout before midnight to
       keep your streak.`

### `plateau-alert` (PRO only)

- File: `supabase/functions/plateau-alert/index.ts`.
- Decision (unchanged): nightly `plateau_risk_score ≥ 0.7`, PRO-only trigger
  — not touched.
- Remove: Gemini try/catch (`:210-235` in the version read); `message`
  becomes unconditionally `fallbackMessage` (`:207-208`).
- **Approved copy** (no edits): `{greeting}weight hasn't moved in a while.
  Before we change anything — are you consistently hitting your daily
  protein target?`

### `protein-gap-alert` (PRO only)

- File: `supabase/functions/protein-gap-alert/index.ts`.
- Decision (unchanged): today's protein <60% of target, PRO-only trigger —
  not touched.
- Remove: Gemini try/catch (`:292-320` in the version read); `message`
  becomes unconditionally `fallbackMessage` (`:289-290`), which already
  calls `pickQuickFix()` (`:393-408`) — untouched.
- **Approved copy** (no edits):
  - Main: `{greeting}{gap}g short on protein today. {quickFix} Want a
    dinner suggestion?`
  - Quick-fix (`pickQuickFix`, 6 variants — 3 gap bands × diet):
    - ≥40g, veg/vegan: `Quick fix: 200g paneer + a glass of milk.`
    - ≥40g, non-veg: `Quick fix: 150g chicken breast or 4 boiled eggs.`
    - ≥20g, veg/vegan: `Quick fix: 100g paneer or a scoop of whey.`
    - ≥20g, non-veg: `Quick fix: 100g chicken or 3 boiled eggs.`
    - <20g, veg/vegan: `Quick fix: a glass of milk + 30g almonds.`
    - <20g, non-veg: `Quick fix: 2 boiled eggs.`

### `re-engagement`

- File: `supabase/functions/re-engagement/index.ts`.
- Decision (unchanged): several days of no logs at all — not touched.
- Remove: Gemini try/catch; `message` becomes unconditionally
  `fallbackMessage` (`:322-323`).
- **Approved copy** (no edits): `{greeting}haven't heard from you in a few
  days. Everything okay? No judgment — just tell me what happened and we
  reset.`

### `workout-window-closing`

- File: `supabase/functions/workout-window-closing/index.ts`.
- Decision (unchanged): scheduled workout not logged as the day winds down
  — not touched.
- Remove: Gemini try/catch; `message` becomes unconditionally
  `fallbackMessage` (`:295-296`).
- **Approved copy** (no edits): `{greeting}haven't seen {workoutName}
  logged yet. Still happening? Even 20 mins counts.`

### `morning-alert`

- File: `supabase/functions/morning-alert/index.ts`.
- Remove: `generateProAlert()` (`:298-339`, the Gemini call) and its call
  site — the `if (isPro && snapshotJson)` branch (`:442-456` in the version
  read). PRO users with a snapshot now fall through to the SAME
  `generateFreeAlert()` path everyone else already uses — no new function
  needed; that path is already the richer, tested one (10 milestone
  branches vs. the AI path's tone-only differentiation).
- `generateProLightAlert()` (PRO, no snapshot — `:267-296`) and
  `generateFreeAlert()` (`:165-259`) are UNCHANGED, already the majority
  production path per the function's own code comment.
- **Approved copy** (no edits) — `generateFreeAlert` milestones (checked in
  this priority order):
  - 7-day streak: `{name}, you just hit 7 DAYS straight! First week
    complete — that's the hardest one. {workoutLine} Let's make it 14!`
  - 30-day streak: `30 DAYS, {name}! A full month of consistency. You're in
    the top 5% of AVYA users. {workoutLine}`
  - 50-day streak: `FIFTY DAYS, {name}! Half a century of showing up for
    yourself. {workoutLine} You're built different.`
  - 100-day streak: `{name}, 100 DAYS! Triple digits. You've done what 99%
    of people only dream about. {workoutLine}`
  - 10 workouts: `Good morning {name}! You've completed 10 workouts total —
    double digits! {workoutLine} Every session counts.`
  - 50 workouts: `{name}, 50 workouts logged! That's serious dedication.
    {workoutLine} Here's to the next 50!`
  - 100 workouts: `100 WORKOUTS, {name}! You've put in the work and it
    shows. {workoutLine} Incredible.`
  - Recent PR: `Good morning {name}! You hit a new PR on
    {exercise}{prDetail} recently! Momentum is real. {workoutLine}`
  - Near goal weight (±2kg): `{name}, you're within 2kg of your goal
    weight! So close. {workoutLine} Keep going!`
  - Yesterday's nutrition win: `Good morning {name}! Yesterday you nailed
    your calorie target ({cals} kcal). {workoutLine} Consistency wins.`
  - Default (assembled from greeting + workout line + streak line + one of
    7 day-of-week closers — structure unchanged):
    `Good morning {name}! {workoutLine} {streakLine} {closer}`
    Closers: Sun `Make today count!` · Mon `Consistency beats perfection.` ·
    Tue `One workout at a time.` · Wed `Your future self will thank you.` ·
    Thu `Small steps, big results.` · Fri `Show up for yourself today.` ·
    Sat `Every rep matters.`
  - `generateProLightAlert` (PRO, no snapshot — goal-keyed):
    - build_muscle: `Good morning {name}! Muscle is built one rep at a time
      — and today's another rep on the journey. Train hard, eat enough, and
      recover well. Let's get after it.`
    - lose_fat: `Good morning {name}! Fat loss is won at the dinner table
      and the gym both. Stay disciplined with your calories today and move
      your body — small daily wins compound fast.`
    - strength: `Good morning {name}! Strength is a long game. Focus on
      quality reps, log every set, and chase progressive overload. Today is
      another deposit in the bank.`
    - endurance: `Good morning {name}! Endurance is built mile by mile.
      Keep showing up, keep moving, and your aerobic base will thank you.
      Make today count.`
    - general_fitness: `Good morning {name}! Fitness isn't a destination —
      it's a daily habit. Move your body today, eat well, hydrate, and
      rest. You've got this.`
    - generic fallback: `Good morning {name}! Today is another opportunity
      to show up for the goals you set. Train smart, eat well, and trust
      the process. Let's go.`

### `proactive-coach-promotion`

- File: `supabase/functions/proactive-coach-promotion/index.ts`.
- **This function currently has NO fallback.** `composeCongrats()`
  (`:224-291`) calls the raw Gemini REST endpoint directly via `fetch`
  (bypassing `_shared/gemini.ts` — no Flash→Lite retry either), `throw`s on
  any non-2xx or empty content, with no try/catch; the throw propagates to
  the outer handler and returns a bare 500 — no chat message written, no
  push sent, the user's rank-up silently vanishes. Removing the Gemini call
  entirely resolves this AS A SIDE EFFECT, not as a separate patch: once
  `composeCongrats()` is pure string composition, there is nothing left to
  fail.
- Remove: the `fetch()` call to Gemini and its error handling (`:262-291`).
  `composeCongrats()` becomes a pure function: pick one of 3 approved
  variants (rotate — e.g. hash of `user_id` + `rank_code`, or simple
  round-robin via a counter; implementation detail for the plan) and
  interpolate `firstName`, `rankLabel` (from the existing `RANK_LABELS`
  map, `:61-73`), `ctx.total_workouts_done`, `ctx.current_streak_weeks`,
  `goalCopy` (existing `goalToCopy()` helper, `:294-301`).
- **Approved copy** (NEW — drafted for this batch, edit applied to variant
  3):
  1. `{name} — you've been promoted to {rank}. {workouts} sessions and a
     {weeks}-week streak got you here. Every rung on this ladder is earned,
     not given. Keep training toward {goal} — the next rank is already
     waiting.`
  2. `Well earned, {name}. {rank} now — {workouts} workouts and {weeks}
     weeks of showing up don't lie. Stay locked on {goal} and the next
     promotion takes care of itself.`
  3. `{name}, your new rank: {rank}. {workouts} sessions logged, {weeks}-
     week streak — that's the record that earned it. Keep pushing toward
     {goal}. There's more ground to cover.`

### `future-prediction`

- File: `supabase/functions/future-prediction/index.ts`.
- Remove: `generatePrediction()` (`:27-125`, the Gemini call) and the
  `isPro || trigger === "onboarding"` branch (`:340-360`) that decides
  whether to call it. `generateLocalPrediction()` (`:128-194`) becomes the
  ONLY path, for every user, every trigger — no more AI/local split.
- **Rewrite `generateLocalPrediction()`'s numeric fields** — the CURRENT
  version is not real trend math either (static profile-based formula, no
  history read at all); this is a genuine improvement, not just an AI
  removal:
  - `predicted_weight_kg`: linear regression over `weight_logs` (last 90
    days). Needs ≥5 entries spanning ≥2 weeks, else fall back to the
    existing target-weight heuristic (`currentWeight + (targetWeight -
    currentWeight) * 0.3`).
  - `predicted_lifts.{squat,bench,deadlift}_kg`: regress each lift's own PR
    history from `workout_log_exercises`/`personal_records` independently
    — rate of kg gained per week, projected 90 days forward. Any lift with
    no logged history falls back to the existing
    `bodyweight × experience-multiplier` formula for THAT lift only
    (partial fallback per lift, not all-or-nothing).
  - `predicted_streak_weeks`: NOT regression (a streak resets on any single
    miss, so trending the streak NUMBER itself is meaningless). Instead:
    compute adherence rate over the trailing 4 weeks (scheduled workouts
    actually completed ÷ scheduled workouts total) and map it linearly onto
    the existing formula's own ceiling: `round(adherenceRate * 13)`, capped
    at 13 (same cap the code already uses today — this replaces the flat
    `daysPerWeek >= 4 ? 10 : 8` with a continuous, data-driven number on the
    same scale, not a newly-invented range). Fewer than 4 weeks of
    schedule history: fall back to the existing flat heuristic.
  - `predicted_bf_pct`: stays `null` — no existing local formula ever
    attempted this, out of scope to add one here.
- **Approved copy** — tagline pool (`:163-183`), no edits, unchanged
  mechanism (goal-keyed, random pick from 2):
  - build_muscle: `Stronger than yesterday, every single day.` /
    `Your muscles are waiting to grow — let's make it happen.`
  - lose_fat: `Every kg lost is a victory earned.` /
    `Your transformation starts with today's workout.`
  - general_fitness: `Fitter, faster, stronger — that's your 90-day story.`
    / `The best version of you is 90 days away.`
  - strength: `Prepare to surprise yourself with what you can lift.` /
    `Heavy iron, strong mind — your future is powerful.`

---

## Testing

Every function gets a test asserting `geminiChat`/`geminiChatWithTools` is
never invoked post-change (spy/mock the import), plus a behavioral test
that the deterministic path still produces the expected message for each
branch — source-grep presence is not sufficient per CLAUDE.md §4.4 rule 21.

`future-prediction`'s trend math gets its own regression tests: synthetic
`weight_logs`/`workout_log_exercises` fixtures with known slopes, asserting
the computed prediction matches expected arithmetic; a sparse-history
fixture asserting correct fallback to the static formula; an empty-history
fixture per lift asserting per-lift (not all-or-nothing) fallback.

Per CLAUDE.md §4.4 rule 21's mutate-it-and-run-it clause: each new test
should be mutated once (e.g., revert a fallback threshold, or re-introduce
a deleted Gemini call) to confirm it actually reddens.

## Rollout

No feature flag — every conversion (except the two NEW pieces below)
deletes a call and always takes the path that is already the proven
production failure-fallback today, which is lower-risk than a typical
AI-prompt change. The two genuinely new pieces —
`proactive-coach-promotion`'s templates and `future-prediction`'s rewritten
trend math — get a manual verification pass (real or test-account data)
before considered done.

Blast radius is at least `platform` (streak-guardian, morning-alert,
proactive-coach-promotion, and `_shared/**` are explicitly platform-tier in
`docs/blast_radius.yaml`); re-classify the actual staged diff via
`scripts/blast_radius_from_diff.dart` at plan-review time rather than
assuming a tier here. Requires the ×2 context-blind plan review + a
self-triggered `/code-review` B-pass before the `--no-ff` merge to `main`,
per CLAUDE.md §4.12/§4.3.

## Deferred / explicitly not in this batch

- Automating the round-robin/selection mechanism for
  `proactive-coach-promotion`'s 3 variants is an implementation detail for
  the plan, not a design decision — any reasonable rotation is fine, the
  content is what was reviewed.
- No new copy variants beyond what was reviewed — if streak-guardian or
  morning-alert later want MORE milestone variety, that is a separate,
  future batch with its own review pass.
