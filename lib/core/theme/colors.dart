import 'package:flutter/material.dart';

/// Wardroom palette — officer-grade navy surfaces + Campaign Gold accent.
///
/// Values reconciled with the canonical design handoff
/// `Knowledgebase/Avya App redesign/design_handoff_wardroom/src/wardroom-tokens.jsx`
/// (the `const W = {}` map — the literal palette that renders every mock).
///
/// The README.md palette in the same folder is a rounded-for-print
/// summary; the JSX is the source of truth ("if a number appears in the
/// HTML source, it's intentional" — handoff rule). The JSX runs darker
/// than the README and uses slightly different text / semantic hues.
///
/// Legacy field names (`bg`, `header`, `card`, `input`, `border`, `red`,
/// `orange`, `blue`, `green`, `purple`, `emerald`) are preserved so
/// existing widgets inherit the new look without rewrites. Wardroom
/// aliases (`bgDeep`, `bgRaise`, `cardHi`, `cardTop`, `line`, `line2`,
/// `line3`, `ok`, `warn`, `bad`, `info`, `textDim`, `textMute`,
/// `textGhost`, `accentHi`, `accentSoft`, `accentBg`, `accentDeep`) are
/// exposed alongside.
class AppColors {
  AppColors._();

  // ── Backgrounds ────────────────────────────────────────────────────────
  /// Page base — deep navy (primary canvas). JSX `W.bg`.
  static const bg = Color(0xFF02070F);

  /// Tab bar · modals · deepest surface. JSX `W.bgDeep`.
  static const header = Color(0xFF01040A);
  static const bgDeep = Color(0xFF01040A);

  /// Card default background. JSX `W.card`.
  static const card = Color(0xFF06101F);

  /// Inset rails · input fields. JSX `W.bgRaise`.
  static const input = Color(0xFF0A1423);
  static const bgRaise = Color(0xFF0A1423);

  /// Elevated card · hover state. JSX `W.cardHi`.
  static const cardHi = Color(0xFF0B172A);

  /// Hero cards · featured blocks. JSX `W.cardTop`.
  static const cardTop = Color(0xFF0F1E36);

  /// Neutral hairline — parchment at 8% alpha. JSX `W.line2` =
  /// `rgba(255,250,232,0.08)`. Default card / divider border.
  static const line2 = Color(0x14FFFAE8);

  /// Legacy `border` → `line2`. Keep alias so old callsites compile.
  static const border = line2;

  /// Ghost hairline — parchment at 4% alpha. JSX `W.line3`.
  static const line3 = Color(0x0AFFFAE8);

  /// Gold hairline (28% alpha) — hero dividers / section kickers only.
  /// Never use as a regular card border; use [line2] instead.
  /// JSX `W.line` = `rgba(212,178,112,0.28)`.
  static const line = Color(0x47D4B270);

  // ── Accent — Campaign Gold (rank, CTA, progression) ───────────────────
  /// Primary accent — Campaign Gold. JSX `W.accent`.
  static const accent = Color(0xFFD4B270);

  /// Gold hover / active. JSX `W.accentHi`.
  static const accentHi = Color(0xFFE9C788);

  /// Gold tint (16% alpha) — soft backgrounds on chips / hero cards.
  /// JSX `W.accentSoft` = `rgba(212,178,112,0.16)`.
  static const accentTint = Color(0x29D4B270);
  static const accentSoft = Color(0x29D4B270);

  /// Gold bg tint (8% alpha) — subtle panel highlight.
  /// JSX `W.accentBg` = `rgba(212,178,112,0.08)`.
  static const accentBg = Color(0x14D4B270);

  /// Deep gold — pressed state / replaces legacy `accentDark` callers.
  /// JSX `W.accentDeep`.
  static const accentDark = Color(0xFF8A6F35);
  static const accentDeep = Color(0xFF8A6F35);

  // ── Semantic tints (audit 2026-05-20 / C10) ───────────────────────────
  /// Subtle green tint for success snackbars / banners over the dark
  /// background. Centralized so `Color(0xFF1a2a1a)` no longer appears
  /// inline at `profile_screen.dart:457,486`.
  static const successTint = Color(0xFF1A2A1A);

  /// Subtle red tint for error snackbars / banners. Replaces inline
  /// `Color(0xFF2a1a1a)` at `profile_screen.dart:458,487`.
  static const errorTint = Color(0xFF2A1A1A);

  // ── PRO / Monetisation ────────────────────────────────────────────────
  /// PRO emphasis. Gold is the base CTA in Wardroom, so PRO uses the
  /// amber `warn` hue to stay visually distinct.
  static const proGold = Color(0xFFF0B23E);
  static const proGoldTint = Color(0x29F0B23E);

  // ── Text — parchment hierarchy (never pure white) ─────────────────────
  /// Primary text · warm parchment. JSX `W.text`.
  static const textPrimary = Color(0xFFFFF7E0);

  /// Body text · dim parchment. JSX `W.textDim`.
  static const textSecondary = Color(0xFFB5BDCB);
  static const textDim = Color(0xFFB5BDCB);

  /// Eyebrow labels · JetBrains Mono caps. JSX `W.textMute`.
  static const textMute = Color(0xFF5E6B80);

  /// Disabled / placeholder. JSX `W.textGhost`.
  static const textDisabled = Color(0xFF3F495A);
  static const textGhost = Color(0xFF3F495A);

  // ── Semantic (old field names retained; values aligned to JSX) ────────
  /// Destructive · streak-at-risk. JSX `W.bad`.
  static const red = Color(0xFFD7604E);
  static const bad = Color(0xFFD7604E);

  /// Caution · due. Amber — not gold. JSX `W.warn`.
  static const orange = Color(0xFFF0B23E);
  static const warn = Color(0xFFF0B23E);

  /// Water · sleep · sync. JSX `W.info`.
  static const blue = Color(0xFF6FA2C9);
  static const info = Color(0xFF6FA2C9);

  /// Sleep (collapsed to the info hue in Wardroom — no separate purple).
  static const purple = Color(0xFF6FA2C9);

  /// Success · complete · ready. JSX `W.ok`.
  static const green = Color(0xFF7FB4A2);
  static const ok = Color(0xFF7FB4A2);

  /// Completion accent — kept distinct for receipts / PRs.
  static const emerald = Color(0xFF7FB4A2);
  static const emeraldTint = Color(0x247FB4A2);

  // ── Chart hues (superset group slots) ─────────────────────────────────
  // in-sync sweep 2026-06-07 (audit raw-hex). Vivid data-viz hues used to
  // distinguish superset groups in the active-workout chart. Deliberately
  // brighter than the muted Wardroom semantic hues (info/ok/warn) so adjacent
  // groups stay legible at a glance; not a palette/brand colour.
  static const chartPurple = Color(0xFFA855F7);
  static const chartOrange = Color(0xFFF97316);
  static const chartGreen = Color(0xFF4ADE80);
  static const chartBlue = Color(0xFF38BDF8);

  // ── Hydration / urine-status ladder ───────────────────────────────────
  // in-sync sweep 2026-06-07 (audit raw-hex). 7-step Material colour ladder
  // for the urine-colour hydration picker (excellent → see-doctor). Concrete
  // physiological reference hues — kept verbatim so saved urine indices stay
  // semantically identical; not Wardroom palette colours.
  static const hydrationExcellent = Color(0xFFFFF9C4);
  static const hydrationWellHydrated = Color(0xFFFFF176);
  static const hydrationAdequate = Color(0xFFFFD600);
  static const hydrationLow = Color(0xFFFFB300);
  static const hydrationVeryLow = Color(0xFFE65100);
  static const hydrationCritical = Color(0xFFBF360C);
  static const hydrationSeeDoctor = Color(0xFF4E342E);

  // ── Gradient stops (hero banner / card backgrounds) ───────────────────
  // in-sync sweep 2026-06-07 (audit raw-hex). Bespoke navy gradient stops for
  // profile banners, the subscription card, and badge shareables. Darker /
  // distinct from the flat surface tokens above; centralized so a banner
  // re-tint is a one-file edit.
  static const gradientNavyDeep = Color(0xFF0A1628);
  static const gradientNavyMid = Color(0xFF0D2040);
  static const gradientNavyShadow = Color(0xFF061220);
  static const gradientGreenShadow = Color(0xFF001A0A);
  static const gradientGoldShadow = Color(0xFF1A1408);
  static const gradientSlate = Color(0xFF0E1219);

  /// Elevated slate — rest-timer ring track + badge-card gradient top stop.
  /// in-sync sweep 2026-06-07 (audit raw-hex).
  static const slateRaise = Color(0xFF161D28);

  // ── Coach-bubble body text (neutral light grey, not parchment) ────────
  // in-sync sweep 2026-06-07 (audit raw-hex). Induction / muster coach bubbles
  // render body copy in a neutral near-white grey (NOT the warm parchment
  // [textPrimary]) for a "system transcript" feel. Two steps kept distinct to
  // preserve the existing visual result exactly.
  static const coachBubbleText = Color(0xFFD8D8D8);
  static const coachBubbleTextBright = Color(0xFFE8E8E8);
}
