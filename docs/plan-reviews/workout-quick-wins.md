---
branch: workout-quick-wins
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-quick-wins-bpass.md
---

# Plan review — workout-quick-wins (Batch 2: W3.6 coaching panel + W2.6 bodyweight-trend nudge)

Batch 2 of the workout-generator overhaul — two independent, additive, low-risk quick wins.
Blast radius **account** (W2.6 edits `PatternDetector` under `lib/features/ai_coach/`; W3.6 alone is
feature). Own worktree `workout-quick-wins` off `64b9e04b`. Both `feat` (no bug → no diagnose-doc).

## Review rounds (≥2, on the design + ground truth, BEFORE code)

- **Round 1 (per-item, context-blind, on the original plan):** Reviewer A (W3.6) → `harden` (3
  findings); a focused Reviewer (W2.6) → `harden` (5 findings). All verified against code.
- **Round 2 (context-blind, on the HARDENED plan):** one reviewer re-verified every round-1
  correction against code + hunted for defects the corrections introduced → **`converged`**, no new
  material issue (2 optional P3 nits, one folded).

## Findings, resolved (converged)

**W3.6 (Reviewer A):**
1. **P2 — per-type field reads (crash-avoider).** The 4 fields are two shapes: `coaching_cues`/
   `common_mistakes` are JSON **arrays**, `breathing_cue`/`warmup_protocol` are **strings**. Read
   arrays via `(x as List?)?.map((e)=>e.toString())` (NEVER `as List<String>` — Hive gives
   `List<dynamic>`, the cast red-screens the card mid-workout); strings via `String?` + `.trim().isEmpty`
   hide-check (the 45 empty `warmup_protocol` are empty STRINGS, not null — a null-only check renders a
   bare heading).
2. **P3 — memoize off the 1×/sec rebuild.** The card list rebuilds every second (workout timer writes
   `elapsedSeconds`); resolve the library map in `initState`/`didUpdateWidget(name change)`, never
   `build()`.
3. **P3 — part-file wiring.** Author the panel as `part of 'screen.dart'` (its siblings are parts;
   screen.dart already imports everything needed).

**W2.6 (focused reviewer):**
1. **P2 — dedup on OUTCOME, not a re-derived predicate.** `_weightTrendAlert` uses a 14-day 2-point
   delta; the nudge a 28d-vs-28d mean — re-deriving the alert's threshold on the nudge's metric
   diverges both ways (double card / coverage gap). Fix: the nudge CALLS `_weightTrendAlert()` and
   returns null if it fired (drift-proof; round-2 confirmed `_weightTrendAlert` is pure-read, so the
   double-call is side-effect-free + order-independent).
2. **P2 — goal copy across the real set.** Verified `FitnessGoals.tokens` = exactly 5
   (build_muscle/lose_fat/strength/general_fitness/recompose) — **no `maintain`**; `_weightTrendAlert`
   fires only for 2, so the nudge is the sole weight signal for the other 3. Enumerate all 5 × {up,down}
   + a goal-neutral empty-goal fallback; read goal via the existing `profile['primary_goal']`
   (`_weightTrendAlert:255`); test every token.
3. **P3 — spam rationale corrected.** Not a spam vector (pull-only passive cards; `pushWorthy` has zero
   readers; nudge is `pushWorthy:false`); the plan's "cached per-day" claim was false — corrected.
4. **P3 — `severity: low` is the AI-snapshot guard.** `_getCoachNotices` (`ai_snapshot_builder.dart:911`)
   filters `severity != low` before the AI prompt, so a low nudge never pollutes the snapshot — kill-switch
   reason corrected (it's a standard behavior off-switch, not AI-adjacency); code comment pins that `low`
   is load-bearing.
5. **P3 — severity-order/sort** (pre-existing low-tie nondeterminism) — accepted, not introduced here.

**Round 2 P3 (folded):** read the goal via the same `_user.getProfile()` read `_weightTrendAlert` uses,
seed `primary_goal` in the coverage test — drift-avoidance.

## Ground-truth verification (true — self-verified against code, rule 11)

Field counts 258/258 (warmup_protocol 213/258) via JSON grep; `ExerciseData` has `name` but no id
(`train_provider.dart`); `ExerciseRepository.search` is substring, no `getByExactName` exists;
`bodyweightTrendSignal()` zero external callers (dead); `_weightTrendAlert` fires only
lose_fat/build_muscle (`pattern_detector.dart:268,279`); `_getCoachNotices` filters `severity != low`
(`ai_snapshot_builder.dart:911`); `FitnessGoals.tokens` = 5, no `maintain`
(`fitness_goals.dart:65-112`); cards keyed by name-`GlobalKey` (`screen.dart:264/307` → fresh State on
swap). Every cited line read directly, not from subagent prose.

## Verdict: converged

Both items reach terminal state in this batch (§4.2). Self-initiated B-pass on the implemented diff
before the `--no-ff` merge (§4.3) → `docs/reviews/workout-quick-wins-bpass.md`.
