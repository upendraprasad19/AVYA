import 'package:flutter/material.dart';

/// Wardroom palette — officer-grade navy surfaces + Campaign Gold accent.
///
/// Field names are preserved for backward compatibility with existing
/// widgets; values swapped to the Wardroom spec. New Wardroom-named
/// aliases (`bgDeep`, `bgRaise`, `cardHi`, `cardTop`, `line`, `line2`,
/// `ok`, `warn`, `bad`, `info`, `textDim`, `textMute`, `textGhost`,
/// `accentHi`, `accentSoft`, `accentDeep`) are exposed alongside.
///
/// Source of truth: `Knowledgebase/Avya App redesign/
/// design_handoff_wardroom/readme.md` (§Design Tokens · Palette).
class AppColors {
  AppColors._();

  // ── Backgrounds ────────────────────────────────────────────────────────
  /// Page base — deep navy (primary canvas).
  static const bg = Color(0xFF0A1020);

  /// Tab bar · modals · deepest surface.
  static const header = Color(0xFF02070F);
  static const bgDeep = Color(0xFF02070F);

  /// Card default background.
  static const card = Color(0xFF111826);

  /// Inset rails · input fields.
  static const input = Color(0xFF141B2E);
  static const bgRaise = Color(0xFF141B2E);

  /// Elevated card · hover state.
  static const cardHi = Color(0xFF1A2236);

  /// Hero cards · featured blocks.
  static const cardTop = Color(0xFF1E2942);

  /// Neutral borders · card edges (default).
  static const border = Color(0xFF2A3142);
  static const line2 = Color(0xFF2A3142);

  /// Gold hairline (27% alpha) — hero dividers / section kickers only.
  /// Never use as a regular card border; use [line2] instead.
  static const line = Color(0x44D4B270);

  // ── Accent — Campaign Gold (rank, CTA, progression) ───────────────────
  /// Primary accent — Campaign Gold.
  static const accent = Color(0xFFD4B270);

  /// Gold hover / active.
  static const accentHi = Color(0xFFE6C788);

  /// Gold tint (~13% alpha) — soft backgrounds on chips / hero cards.
  static const accentTint = Color(0x22D4B270);
  static const accentSoft = Color(0x22D4B270);

  /// Deep gold — pressed state / replaces legacy `accentDark` callers.
  static const accentDark = Color(0xFF8A6F35);
  static const accentDeep = Color(0xFF8A6F35);

  // ── PRO / Monetisation ────────────────────────────────────────────────
  /// PRO emphasis. Gold is the base CTA in Wardroom, so PRO uses the
  /// amber `warn` hue to stay visually distinct.
  static const proGold = Color(0xFFD9A04C);
  static const proGoldTint = Color(0x1AD9A04C);

  // ── Text — parchment hierarchy (never pure white) ─────────────────────
  /// Primary text · warm parchment.
  static const textPrimary = Color(0xFFFFF7E0);

  /// Body text · dim parchment.
  static const textSecondary = Color(0xFFC8BFA8);
  static const textDim = Color(0xFFC8BFA8);

  /// Eyebrow labels · JetBrains Mono caps.
  static const textMute = Color(0xFF8A8270);

  /// Disabled / placeholder.
  static const textDisabled = Color(0xFF4A4E5C);
  static const textGhost = Color(0xFF4A4E5C);

  // ── Semantic (old field names retained; values aligned to Wardroom) ──
  /// Destructive · streak-at-risk.
  static const red = Color(0xFFC76C5C);
  static const bad = Color(0xFFC76C5C);

  /// Caution · due. Amber — not gold.
  static const orange = Color(0xFFD9A04C);
  static const warn = Color(0xFFD9A04C);

  /// Water · sleep · sync.
  static const blue = Color(0xFF7B9EB8);
  static const info = Color(0xFF7B9EB8);

  /// Sleep (collapsed to the info hue in Wardroom — no separate purple).
  static const purple = Color(0xFF7B9EB8);

  /// Success · complete · ready.
  static const green = Color(0xFF7FB586);
  static const ok = Color(0xFF7FB586);

  /// Completion accent — kept distinct for receipts / PRs.
  static const emerald = Color(0xFF7FB586);
  static const emeraldTint = Color(0x1F7FB586);
}
