---
branch: oi507-formcues
date: 2026-11-23
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi507-formcues-bpass.md
---

# Plan-review record: OI-507 getFormCues lookup follow-ups (unit A)

Plan: `docs/plans/2026-11-23-oi507-formcues-followups.md` (rev 5). Tier L, blast radius `platform` (`_shared/**`).

Four context-blind Sonnet rounds, each verifying claims against the code and live data:
- Round 1 (rev 1): 4 P1 (alias stage would activate the Forward Lunge to "Reverse Lunge" wrong-movement alias; T5 never reached the regex; existing "both queries" test counts exactly 2 reads; PostgREST `*` is a `%` alias). All verified; applied.
- Round 2 (rev 2): 1 P1 (whole-word regex broke singular queries: 30 of 870 names are plurals) plus test and process gaps. Verified; applied.
- Round 3 (rev 3): 4 P1, all in the machinery added to stage 2 (shortest-name ranking picks a wrong row for common queries, T7 fixture backwards, close-vs-open contradiction, T3 stage-2 unreachable); its `is_foundational` fix needs a column that does not exist live (checked). Per the remove-the-mechanism lesson the machinery was DELETED, not patched (rev 4).
- Round 4 (rev 4): no P0/P1; 3 P2 (T3 `a*b` length, an uncovered `.trim()` mutant, closure wording) plus fail-open on the alias stage. Applied in rev 5.

Ground truth checked live (read-only, `dedsavbjuwgarrhphgnl`, 2026-11-23): `name_aliases` is `text[]` with 14 active aliased rows; no `is_foundational` column; 10 retired-only history sets (Donkey Calf Raise x4 aliased, Negative Pull Up x6 not); `Forward Lunge -> {Reverse Lunge}` while `Reverse Lunge` is a retired row.

Founder decisions 2026-11-23: scope (include aliases, a short `found: false` hint with general cues, strict partial); data fix for the lunge alias in its own unit B that merges and applies live BEFORE this unit merges or `ai-proxy` is deployed. `bpass` is set to `accepted` only after `/code-review` runs on the diff.
