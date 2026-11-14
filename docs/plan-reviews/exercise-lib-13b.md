---
branch: exercise-lib-13b
batch: 13-B comprehensive injury tagging
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/d30d5a81d6c4-review.md
plan: docs/plan-reviews/exercise-lib-13b.md
diagnose: docs/diagnoses/2026-07-19-injury-undertagging-f4c1e8.md
---

# Plan-review record — Batch 13-B (comprehensive injury tagging)

Full §4.12 ×2 context-blind review. This ships LIVE (changes real behavior for injured
users; no kill-switch) → the FULL ×2 review is required (NOT ship-dark tiering). Non-injured
users are byte-identical (the filter is skipped when no injury is set), verified below.

## Ground-truth (author's own read of the merged library, not point-in-time memory)
`assets/data/exercise_library.json` post-13-A: **259 rows, 124 tagged, 135 untagged
(injury_contraindications == []), 0 field-missing** (13-A closed the field-missing rows,
e1a7c4). The 135 split: ~47 pure mobility (flexibility/cooldown/warmup) that STAY []; a core
subset; ~60 strength rows that are the real tagging surface. Filter reader confirmed at
`exercise_repository.dart:335-345` (exact-lowercase match at :340); empty/missing list never
excluded — the safety hole.

## Round-1 — ×2 context-blind reviewers (on the initial 44-tag proposal)
- **Clinical reviewer (ISSUES):** P1 — dropping `lower_back` from the hanging ab moves
  (Hanging Leg Raise / Toes-to-Bar / Windshield Wiper) was inconsistent with the already-tagged
  E248 Captain's Chair `[lower_back,hip]` / E249 V-Ups / E250 Flutter Kicks → restore. P2 — GHD
  Sit Up under-tagged `[hip]` only (a notorious lumbar move) → add lower_back. P2 — Good Morning
  (barbell) missing hamstring while its bodyweight sibling has both. The 4 heuristic corrections
  (Reverse Nordic→knee, Copenhagen→hip, Nordic→knee+hamstring, Hollow Body kept safe) verified
  CORRECT.
- **Engineering reviewer (ISSUES):** P1 — tagging BOTH Front Raise + Goblet Press shoulder empties
  the whole `vertical_push × shoulder` category (every other overhead press already tagged);
  founder must ratify. P2 — the scorecard baseline WILL move (injury sub-sweep personas) → regen is
  REQUIRED, not optional. All else CLEAN (vocab closed, schema, cloud-not-touched, curated-sub
  coherence = exactly Front Raise + Wall Sit, warmup mirror no-overlap-change).

## Founder decisions (during Round-1 hardening)
1. Tagging philosophy = **clinically-nuanced, variety-first** ("I don't want to reduce exercise
   variety") — tag the provocative pattern, keep the controlled/machine/rehab variant safe.
2. Keep carries + the crunch/sit-up family + all hip machines SAFE (untagged).
3. Overhead-press-for-shoulder = **"keep 1 light option"** → tag Front Raise, keep Kettlebell
   Goblet Press shoulder-safe (the sole shoulder-safe overhead press). Resolves the P1.

## Hardening applied → final set = 26 new tags + 2 deepened (GHD, Good Morning)
Restored the hanging-trio lower_back; added GHD +lower_back, Good Morning +hamstring; Goblet Press
kept safe (Front Raise still tagged); curated-sub edits reduced to Front Raise + stale Wall Sit.

## Round-2 — context-blind (on the hardened + decided set): CONVERGED
Verified: the universal-pool floor holds for every movement pattern (no `(none)`/crash); 9 shoulder
subs survive incl. Goblet Press (substitute-pref test passes); bodyweight+shoulder vertical_push
resolves gracefully via att4 Goblet Press / att5 fallback; vocab/schema/cloud/warmup all clean;
Front Raise + Wall Sit are the ONLY curated-sub edits. Only 3 non-blocking P3 doc-comment refreshes
(folded in-batch). Verdict: CONVERGED.

## Scorecard face-validity (founder checkpoint)
Baseline regenerated. Per-persona deep-diff HEAD vs new: **9 of 606 personas changed — ALL injured**
(lower_back / shoulder / shoulder+knee × 3 experience levels), **0 non-injured moved**. Aggregate
`total_fallback_picks` 1181→1184 (+3, benign "fewer-but-safe"), `unsafe` = 0, mean `overall` = 87.0
(unchanged). `scorecard_gate_test` green.

## B-pass — ACCEPTED (0 findings)
`docs/reviews/d30d5a81d6c4-review.md`. Fresh Sonnet reviewer independently re-ran the tests,
analyze, the diagnose validator, the SoT-behavioral gate, and the real blast-radius classifier;
verified all 28 tags, canonical-tokens-only, no substitute contradictions, migration-074 exclusion,
warmup value-agreement, unchanged canonicalTokens. Zero defects.
