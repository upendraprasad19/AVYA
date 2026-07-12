---
branch: onboarding-injuries-chip
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/onboarding-injuries-chip-bpass.md
---

# Plan review — onboarding-injuries-chip Ship 3 (U5: collect injuries at onboarding)

Ship 3 of the workout-generator overhaul's injury-safety batch (Ships 1/2 landed
the vocab + threading + universal-pool filter `5772c27d` and the U3 warmup/cooldown
filter `2ba5962e`). Ship 3 closes the collection gap: onboarding never asked about
injuries — `plan_screen._onReportForDuty` hard-coded `setAnswer('injuries', ['none'])`
(~:531) — so an injured user's generated plan was never injury-filtered because the
data was never captured (the Ships 1/2 filter was inert for every onboarded user).
This is a `feat` (adds a Details chip + collection), NOT one of the batch's two
genuine bugs (injury-vocab drift a1f6c3, phase demotion) — so no diagnose-doc; the
discipline is the ×2 plan review, the SoT extension, and the contract tests.

Blast radius **account** (`lib/features/onboarding/**` + the `lib/core/**` catch-all
for `injury_vocab.dart`; profile/docs/test are feature). Account tier → self-initiated
B-pass before the `--no-ff` merge (§4.3); no kill-switch required (this is a
collection UI + a read-side wiring fix, not a plan-engine behavior toggle — the
downstream filter it feeds already ships behind Ships 1/2 kill-switches).

## Founder decisions (pre-plan, via AskUserQuestion)

- **Option A (library injury-tag aggressiveness):** "Bounded U3 now + separate library
  audit" — the library-wide `injury_contraindications` under-tagging audit stays a
  SEPARATE deliberate batch; Ship 3 does not expand into it.
- **Option B (onboarding injuries UX):** "Pre-selected 'No injuries' default" — the
  chip is pre-selected to "No injuries" (frictionless, matches the Details screen's
  other 4 chip rows), NOT a mandatory tap. Accepted tradeoff: a silent-injured user
  who leaves the default isn't later nagged by the completeness nudge (so the nudge's
  default-vs-explicit-none ambiguity fix is NOT in scope — it was only needed for the
  mandatory-tap design Option B rejected).

## Review rounds (≥2, on the design + the ground truth, BEFORE code)

- **Round 1 — design reviewer** (context-blind): surfaced the ADJUST-PLAN round-trip
  drop (P1-A) and the growable-list requirement (P1-B); confirmed the extras-spread
  pattern is the right integration point and the pre-selected-none default is
  consistent with the screen's existing UX.
- **Round 2 — end-to-end / regression reviewer** (context-blind, on the hardened
  plan): confirmed P1-A/B corrections were sound and did not introduce new defects,
  and raised P1-C (the wiring needs a regression test that catches a future
  re-hardcode of plan_screen or an extras-key rename — Ships 1/2's generator test
  wouldn't). No new material issues beyond P1-C → convergence signal reached.

## Findings, resolved (converged)

1. **P1-A — ADJUST-PLAN round-trip reset.** The plan→details "ADJUST PLAN" link sends
   `widget.data` back to Details; without seeding, a real selection would reset to
   `['none']` before generation. FIX: `details_screen.initState` seeds `_injuries`
   from `widget.data['injuries']` (crash-safe: `is List` else `['none']`; empty →
   `['none']`). Pinned by `onboarding_injuries_chip_wiring_test` (initState seed).
2. **P1-B — growable list + sentinel integrity.** Chips mutate the list, and `'none'`
   must never co-present a real injury nor the list be empty. FIX: `InjuryVocab.toggleChip`
   is a pure function returning a fresh **growable** list with the none-toggle invariant;
   pinned by `injury_chip_vocab_contract_test` (growable + fuzz-sequence invariants).
3. **P1-C — wiring regression test.** FIX: `onboarding_injuries_chip_wiring_test`
   (comment-stripped source-grep — the established onboarding-wiring pattern, cf
   `plan_screen_targets_match_completeOnboarding_test`) fails on a re-hardcode of
   plan_screen's injuries answer, a dropped `'injuries'` extras key, or a missing
   initState seed. The RUNTIME filter it feeds is behaviorally proven downstream
   (`injury_filter_behavioral_test`, Ship 1) and the chip toggle by the vocab
   contract test; `completeOnboarding`'s full runtime (auth/sync/weight-seed) is an
   integration_test concern, not a contract unit test (matching how the existing
   `completeOnboarding` tests work).
4. **P2-A/B/C — shared source, no vocab duplication.** BOTH chip screens consume the
   single `InjuryVocab.chipTokens`/`chipLabel`/`toggleChip`; `chipTokens` minus `'none'`
   is pinned == `canonicalTokens` so the two UIs can never drift from each other or the
   engine. plan_screen preserves the `['none']` sentinel and does NOT normalize
   (generateV4 normalizes centrally, per Ship 1's read-side-alias design).

## Ground-truth verification (true)

Self-verified against live code in the worktree: `plan_screen`'s injuries `setAnswer`
now reads `widget.data['injuries']` (grep — line ~531, no hard-coded `['none']` literal);
`details_screen` seeds `_injuries` in initState (:112–127), writes `'injuries'` into the
enriched extras (:145) and `context.go('/onboarding/plan')` (:147); `completeOnboarding`
reads `a['injuries']` and threads it to `generateAndSchedule(injuries:)` (:453–461);
`edit_profile` now consumes `InjuryVocab.chipTokens`/`toggleChip`. SoT concept
`injury_vocabulary_contract` extended with the two onboarding writers (line-parity gates
green). Every cited line read directly, not taken from subagent prose.

## Verdict: converged

All Ship-3 tests green (`injury_chip_vocab_contract_test` + `onboarding_injuries_chip_wiring_test`
+ the Ship-1 `injury_vocab_library_contract_test` regression = 22/22); touched-file
`flutter analyze` clean; SoT completeness + parity gates green; nested onboarding
CLAUDE.md gate green. B-pass on the implemented diff accepted
(docs/reviews/onboarding-injuries-chip-bpass.md). No open issues.
