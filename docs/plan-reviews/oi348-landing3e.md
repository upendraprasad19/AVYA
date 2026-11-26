---
branch: oi348-landing3e
date: 2026-11-26
blast_radius: account
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: pending
bpass_review: docs/reviews/oi348-landing3e-bpass.md
---

# Plan-review record — OI-348 Landing 3e (V1: dictated words readable in full)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Account tier
(`docs/blast_radius.yaml`: `lib/features/ai_coach/**`), so it carries a B-pass. Not catastrophic, so no Hermes.

Plan: `docs/plans/oi348-landing3e.md`. Founder: the A19 observation 2026-11-25 (a long dictated sentence cannot be
read before it is sent) and "Start 3e" 2026-11-26 after the V1 proposal (both dictation fields grow to about six
lines, then scroll; the live words wrap; A19 step 8 amended). It reverses `voice-input-unified.md` D4 / R2B-10.

## Rounds
- **Round 1** (context-blind Sonnet, on the prose plan): 12 findings, 3 P1 (the 1 dp border makes a padded bubble
  50; `CrossAxisAlignment.end` lowers one line; a TextPainter on a late-loading font with no text scaler), all
  folded (forced strut, min-height + centring, `_HeightReporter` so the chat follows, setClient keyboard guard,
  10-line after-Stop cases, hintMaxLines, jump guards, registry remap).
- **Round 2** (fresh seat, on the post-round-1 plan): 12 findings, 2 P1 introduced by round-1 folds (the dot and
  clock drop under `end`; the reporter's first layout, stale closure and detached call), all folded (T3c / T8c
  cross-checks of the shared cap, T9c, `onHeightGrew` optional and last at the call site, RTL, the paywall tap area).
- **Round 3** (fresh seat, narrow check of the round-2 folds): every R2 item closed; 4 plan-text fixes (N1-N4, one
  P2: `_lastHeight` updated on every layout, T9 grow-shrink-regrow) folded. Converged.

## Ground truth
Every file:line in the plan was read on main `02f70bf8` (both hosts, the screen call site, `keepBottomAfterChip`,
the identity and paywall pins). The build then measured three things the reviews could not see (plan "Build notes"):
B1 an M3 IconButton pads to 48 under loose constraints (built: 46 dp button slots, one line still 48); B2 the engine
rounds a line's height, so the formula cap was 2.4 dp short of the field (built: the cap measured with
`TextPainter.preferredLineHeight` and the forced strut; caught by the planned T3c cross-check); B3 caret coordinates
in two tests. No new mechanism; each is covered by a test and a mutant.

## B-pass
Pending: `docs/reviews/oi348-landing3e-bpass.md`.
