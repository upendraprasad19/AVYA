---
scope: wardroom
parent: ../../../../CLAUDE.md
created: 2026-05-18
updated: 2026-05-21
status: active
---

# Wardroom Design System — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/shared/widgets/wardroom/`.
> Root CLAUDE.md (../../../../CLAUDE.md) contains process invariants and a pointer index.

## Colors — Wardroom palette (post-PR R reconciliation)

```dart
class AppColors {
  // Backgrounds (5-step depth hierarchy)
  static const bg        = Color(0xFF02070F);  // primary canvas
  static const bgDeep    = Color(0xFF01040A);  // deepest — rotated sidebars, modal scrim
  static const bgRaise   = Color(0xFF04111E);  // raised (active workout rest timer etc.)
  static const header    = Color(0xFF0A1020);  // app bar / letterhead band
  static const card      = Color(0xFF06101F);  // standard card
  static const cardHi    = Color(0xFF0A1828);  // elevated card (selected, insight)
  static const input     = Color(0xFF0E1E30);  // text fields, chips
  static const border    = Color(0xFF1A2C40);  // hairline borders
  static const line2     = Color(0x14FFFAE8);  // parchment 8% alpha — divider/grain accent

  // Accent — Campaign Gold (NOT cyan; the Wardroom handoff moved everything off Electric Cyan)
  static const accent     = Color(0xFFD4B270);  // Campaign Gold
  static const accentSoft = Color(0x1AD4B270);  // 10% alpha tint

  // Text (4-step ghost ladder)
  static const textPrimary = Color(0xFFF2EDE4);  // parchment
  static const textDim     = Color(0xFF8A9BAA);
  static const textMute    = Color(0xFF4D6070);
  static const textGhost   = Color(0xFF2A3848);  // placeholder, disabled

  // Semantic
  static const ok   = Color(0xFF7FB4A2);  // success, confirmed
  static const warn = Color(0xFFF0B23E);  // warnings, over-cap
  static const bad  = Color(0xFFD7604E);  // errors, destructive
  static const info = Color(0xFF6FA2C9);  // neutral info, water
}
```

> The handoff's `README.md` rounds the palette for print; the JSX `const W = {}` in
> `Knowledgebase/Avya App redesign/design_handoff_wardroom/src/wardroom-tokens.jsx` is the
> **source of truth** and is what `colors.dart` tracks. PRs K–Q used README hex values and
> were reconciled to the JSX map in PR R (commit `174ff21`).

## Typography (DM Sans via GoogleFonts)
```
Display XL    40px / w900 / tracking +1
Display L     32px / w900 / tracking +0.5
Display M     28px / w900
Title L       22px / w800
Title M       18px / w800
Title S       15px / w700
Body L        15px / w400
Body M        13px / w400
Body S        12px / w400
Label         10px / w700 / tracking +1.2
Micro          9px / w700 / tracking +0.5
```

## Spacing & Radius (constants live in `lib/core/theme/spacing.dart`)
```
Spacing:   screen 18 / card 16 / section 14 / grid 9 / inline 8
Radius:    pill 100 / card-L 22 / card-M 16 / card-S 14 / row 12
```

## Component Patterns
- **Primary button:** `accent` bg, black w900 text, pill radius, shadow
- **Secondary button:** `accentSoft` bg, 1.5 `accent`-30% border, `accent` w800 text
- **Card:** `card` bg, 1 `border` border, radius-M, padding 16. Active variant uses `accent`-20% border.
- **PRO locked card:** blur(4) + `bg`-85% overlay, gold lock, gold CTA
- **Streak badge:** `accentSoft` bg, `accent` w900 text, `accent`-20% border
- **Progress bar:** `input` track, `accent` fill, height 6, radius 3

## Wardroom primitives (36 exports)

Barrel: `lib/shared/widgets/wardroom/wardroom.dart` — 36 export lines. Counts ≥ primitives when a file ships a primitive + a variant or helper (e.g. `ward_ring.dart` exports both `WardRing` and `WardMultiRing`). Grouped by role:

| Primitive | File | Purpose |
|-----------|------|---------|
| **Shell** | | |
| WardFrame | ward_frame.dart | Root scaffold — grain overlay, padded content area |
| **Header** | | |
| WardLetterhead | ward_letterhead.dart | Section eyebrow + title + optional gold rule (`WardDivider` enum: `none`/`single`/`double`; legacy `divider: bool` still accepted) |
| WardDispatchHeader | ward_dispatch_header.dart | Double gold rule + eyebrow + italic-gold emphasis + context line (reports / coach dispatch) |
| WardEyebrow | ward_eyebrow.dart | Standalone mono eyebrow label |
| WardRule | ward_rule.dart | Gold rule with configurable weight / dash pattern |
| WardTabHeader | ward_tab_header.dart | Unified 56dp top-row header for all 5 tab screens — `[avatar][TAB EYEBROW][spacer][streak chip][freeze chip]`. `docs/superpowers/specs/2026-04-28-apk-test-4-hotfix-batch-design.md` U7 (§3, "Unified tab headers"). |
| **Surface** | | |
| WardCard | ward_card.dart | `WardCardVariant.standard` / `hero` (gold border) / `inset` (no border, for nested rails) |
| WardAvatar | ward_avatar.dart | Circular monogram or photo w/ gold ring at 40% alpha |
| WardInsightQuote | ward_insight_quote.dart | Gradient card with gold quote watermark + `InsightSegment` list |
| WardDashedBorder | ward_dashed_border.dart | `CustomPaint.foregroundPainter` for "empty / add new" affordances — empty meal slots, "+ Create custom exercise" rows, "Request deep analysis" CTAs. Mirrors handoff `borderStyle: 'dashed'` (1px `accent`-44 / radCard). |
| **Action** | | |
| WardButton | ward_button.dart | 4 variants — `primary` (solid gold), `outline` (1px gold), `ghost` (1px `line2`), `danger` (red-tinted). Fraunces w600 uppercase, +2.5 letter-spacing, sharp 2px corners. |
| WardChip | ward_chip.dart | 6 `WardChipTone` — neutral / gold / ok / warn / bad / filled (gold-on-navy for the single most-important chip on a screen) |
| WardRadioRow | ward_radio_row.dart | 44px tap row, 56dp label column, gold left-border when selected |
| WardToggle | ward_toggle.dart | 36×20 pill toggle, 150ms crossfade |
| WardUnitToggle | ward_unit_toggle.dart | KG/LBS 2-position inline pill |
| **Numeric** | | |
| WardBigNumber | ward_big_number.dart | Fraunces tabular figures + JB Mono uppercase unit. Canonical stat display across Daily/Train/Nutrition/Coach/Weekly Report. |
| WardKvRow | ward_kv_row.dart | Label + value row with dotted leader |
| WardStatTile | ward_stat_tile.dart | Mono label + Fraunces numeric + unit |
| **Meter** | | |
| WardBar | ward_bar.dart | Progress bar — optional `trailingLabel` for gold "25%" mono numeral, 400ms ease-out animate-fill |
| WardSpark | ward_spark.dart | Sparkline with gold stroke |
| WardRing / WardMultiRing | ward_ring.dart | Single + concentric ring progress |
| **Structure** | | |
| WardGlassGrid | ward_glass_grid.dart | 8-cell hydration tracker grid |
| WardAchievementStrip | ward_achievement_strip.dart | Horizontal scrollable earned/locked circles, default 36dp diameter |
| WardPhaseDots | ward_phase_dots.dart | 12-phase progress row |
| WardPhaseBlock | ward_phase_block.dart | Roman numeral circle + title/weeks/description + START chip |
| WardSessionRow / WardSessionTable | ward_session_row.dart | Set-log row (set# / weight / reps / status) + table shell |
| WardCategorySidebar | ward_category_sidebar.dart | Vertical 46px `bgDeep` with rotated -90° mono category label (Coach Suggested-Actions, Notifications) |
| WardSetChips | ward_set_chips.dart | Per-set bracketed chip `Wrap` — SoT for "what was logged" rendering. Used by `WorkoutReceiptCard` + Train expanded view. APK Test #12 / Theme E primitive (docs/diagnoses/INDEX.md entry "Train expanded view + Receipt rendered exercises in different formats"). |
| WardStatusStrip | ward_status_strip.dart | Composes streak / freeze / optional rank chips into one horizontal `Wrap`. Used as `WardLetterhead.trailing` slot on Daily / Train / Profile. |
| **Badge** | | |
| WardSealBadge | ward_seal_badge.dart | Seal glyph in 4 `WardSealVariant` (report / subscription / phase / founder) |
| WardRankInsignia | ward_rank_insignia.dart | Indian Navy rank insignia via `CustomPaint`. 11 painters dispatched by `rankCode`. Sizes 16dp (compact chips) / 24dp (`WardRankPill`) / 48dp (record sheets + ladder detail). |
| WardFreezeBadge | ward_freeze_badge.dart | ❄ glyph + count pill on `bgRaise` with hairline parchment border. Sits beside `StreakBadge` inside `WardStatusStrip`. |
| **Composite** | | |
| WardRankPill | ward_rank_pill.dart | Top-of-Profile pill — `[insignia 24dp][shortCapsName][chevron]`. Tap toggles 200ms ease-out inline accordion with caller-supplied `expandedContentBuilder`. |
| **Glyph** | | |
| Glyph set (5) | ward_glyphs.dart | `AnchorGlyph`, `CompassRoseGlyph`, `TierChevronsGlyph`, `SealGlyph`, `RankBarGlyph` |
| **Legacy (slated for removal — do not introduce new usages)** | | |
| ~~`RankChip` + `RankInsignia` — DELETED audit-2026-05-16 / E.11~~ | files removed: `rank_chip.dart` + `rank_insignia.dart`. All 5 callsites migrated to `WardRankInsignia` (+ optional `color: AppColors.textMute` for the "dimmed" variant). Founder approved Phase D NEEDS_DECISION 1 Option A. Re-introducing either file fails `test/contracts/rank_widget_migration_test.dart`. |

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Font fallback / raw GoogleFonts | Use the canonical **`AppTypography`** styles (they wrap DM Sans via `_dmSans`/`_mono`), never the default font AND never raw `GoogleFonts.getFont('DM Sans', …)` in a widget — **Gate 37** (`no_raw_google_fonts_test`) FAILS the commit on raw `GoogleFonts.getFont('DM Sans')` outside `typography.dart`. Adjust size/weight/color via `AppTypography.label/.micro/.bodyS.copyWith(...)`. (7-A phase-arc widget tripped this — the old "always use GoogleFonts.getFont" wording was misleading.) | Gate 37 / `typography.dart` |
| Hidden tap-to-edit targets | Any row that responds to tap-to-edit MUST show a visual affordance (e.g., pencil icon at 14px, `textSecondary.withValues(alpha: 0.7)`). Invisible tap targets will not be discovered. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Fraunces title emphasis not italic-gold | Don't style an entire `Text` widget italic — the non-emphasized leading/trailing words become italic too. Use `RichText` with inline `TextSpan`s carrying `fontStyle: FontStyle.italic`, `color: AppColors.accent`, `fontWeight: FontWeight.w500` on the emphasised span only. Pattern baked into `WardDispatchHeader`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Wardroom palette drift | PRs K–Q used README hex values (rounded for print); PR R (commit `174ff21`) reconciled `colors.dart` to the JSX `const W = {}` in `Knowledgebase/Avya App redesign/design_handoff_wardroom/src/wardroom-tokens.jsx`. The JSX is the truth. Never back-port README hex values into `colors.dart`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Tests pinning the rules here

- `test/contracts/typography_canonical_source_test.dart` — pins DM Sans canonical source.
- `test/contracts/rank_widget_migration_test.dart` — fails if deleted `RankChip` / `RankInsignia` are re-introduced (audit 2026-05-16 / E.11).
- `test/widgets/wardroom/*` — primitive-level golden + interaction tests.
- `test/contracts/wardroom_palette_jsx_source_test.dart` — pins `colors.dart` to the JSX `const W = {}` source.

## See also

- `lib/CLAUDE.md` — root invariant 11+12 (Wardroom palette + dark theme only).
- `Knowledgebase/Avya App redesign/design_handoff_wardroom/src/wardroom-tokens.jsx` — JSX source-of-truth for the palette.
- `lib/core/theme/spacing.dart` + `lib/core/theme/colors.dart` — Dart-side constants.
