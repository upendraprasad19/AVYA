---
adr_id: 0006
title: Wardroom design system + Campaign Gold palette
status: accepted
date: 2026-04-22
deciders: Upendra
---

# ADR-0006: Wardroom design system + Campaign Gold palette

## Context

Early ICANBEFITTER builds used a generic dark theme with Electric Cyan
accent (`#00e5a0` → a green-cyan). The visual identity was indistinct
from the field of fitness apps (every fitness app is dark + neon).

The product positioning sharpened during the wedge thesis lock
(2026-05-20): Tier-1 IT/desk worker, "Become a Lt" promise, Indian
Navy ladder ranks (Cadet → Lt → Cdr → ...). The product is a
**campaign of self-improvement**, not a "workout app." That promise
demanded a visual language with weight and ceremony.

## Decision

**Wardroom design system, Campaign Gold palette.**

- Primary accent: `#D4B270` (Campaign Gold) — a muted military gold,
  not Electric Cyan, not yellow.
- Background hierarchy: `#02070F` (bg) > `#06101F` (card) > `#0E1E30`
  (input).
- DM Sans typography everywhere via `GoogleFonts.getFont('DM Sans')`.
  No system fonts.
- Component library lives in `lib/shared/widgets/wardroom/` — 34+
  primitives (WardCard, WardCTAButton, WardRankInsignia, WardDashedBorder,
  ...).
- Single design source of truth: the JSX mock files in
  `lib/shared/widgets/wardroom/CLAUDE.md`. Flutter components pin to
  the mock, not to memory.

Encoded in CLAUDE.md rule 11 + rule 12.

## Alternatives considered

1. **Stay with Electric Cyan `#00e5a0`.** Rejected.
   - Looked like every other fitness app's "energy green."
   - Didn't carry the gravitas the "Become a Lt" promise wants.
   - Indistinct in screenshots / store listings.

2. **Light theme.** Rejected.
   - Gym lighting is dim; phone backlight at high brightness on a
     light screen is harsh.
   - Most fitness logging happens at edges of day (morning, late
     evening); dark theme is friendlier.
   - Brand consistency: navy/ceremonial palettes read better dark.

3. **Material 3 dynamic theming.** Rejected.
   - Personalized colors break brand. Wardroom IS the brand.
   - Wallpaper-derived palette would clash with rank insignia colors.

4. **Bright primary accent (red / orange).** Rejected.
   - Red = error/danger semantic; would clash with state cues.
   - Orange = warning semantic + tonally too "energy drink."
   - Gold = achievement/medal, on-message with Lt promise.

5. **Material symbols + system font (Roboto / SF).** Rejected.
   - DM Sans has the geometric clarity + slight humanist warmth that
     matches "professional but personal." System fonts feel generic.

## Consequences

Good:
- **Brand recognition.** Campaign Gold + dark hierarchy is
  immediately distinguishable in screenshots, store listings, social
  shares.
- **Rank ceremony works.** WardRankInsignia (11 ranks Cadet → Adm)
  reads as serious because the surrounding palette is serious.
- **Component reuse.** 34+ primitives mean new screens compose
  quickly; no per-screen visual drift.
- **Single mock = single truth.** JSX mocks in
  `lib/shared/widgets/wardroom/CLAUDE.md` are the design contract.
  When pixel drift happens, the mock is the arbiter.

Bad:
- **Migration cost was real.** PR-AH / Part B did a 14-screen
  Wardroom enforcement sweep (`project_wardroom_handoff_enforcement.md`).
  Old code paths with `#00e5a0` references had to be rooted out by
  grep + visual audit; some lingered into Test #6.
- **Pixel-fidelity vigilance.** Founder repeatedly catches drift
  between JSX mock and Flutter render. There's no automated
  pixel-diff gate yet; we rely on manual side-by-side review.
- **Onboarding for new contributors** (if we hire) will be heavier —
  the design system is opinionated and doesn't match standard
  Material patterns.

## Status

Active. Campaign Gold is locked. Component additions go through the
JSX mock first, then Flutter.

## See also

- CLAUDE.md rule 11 + rule 12
- `lib/shared/widgets/wardroom/CLAUDE.md` — JSX mocks (source of truth)
- `project_wardroom_handoff_enforcement.md` — 17-commit sweep retro
- ADR-0008 (single-tester workflow) — context for why design-system
  cost is acceptable at solo-founder stage
