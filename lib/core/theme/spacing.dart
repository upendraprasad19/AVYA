/// Wardroom rhythm — tight, precise, document-like.
///
/// Legacy field names are preserved and remapped onto the Wardroom scale
/// so existing widgets pick up the new rhythm without rewrites. Wardroom
/// aliases (`stackXS`–`stackXL`, `gutter`) are exposed for new widgets.
///
/// Source of truth: `Knowledgebase/Avya App redesign/
/// design_handoff_wardroom/readme.md` (§Design Tokens · Spacing scale).
class AppSpacing {
  AppSpacing._();

  // ── Wardroom stack rhythm ────────────────────────────────────────────
  /// Inline meta — 4 px.
  static const double stackXS = 4;

  /// List rows — 8 px.
  static const double stackS = 8;

  /// Between siblings — 12 px.
  static const double stackM = 12;

  /// Between blocks — 18 px.
  static const double stackL = 18;

  /// Between sections — 28 px.
  static const double stackXL = 28;

  /// Page horizontal padding — 22 px.
  static const double gutter = 22;

  // ── Legacy aliases (remapped to the closest Wardroom rhythm) ─────────
  /// Legacy screen padding (18) → Wardroom gutter (22). All screen-edge
  /// horizontal padding now sits on the 22-px gutter.
  static const double screenPadding = gutter;

  /// Legacy card padding (16) — retained. Card interior padding stays at
  /// 16 in Wardroom (per `wardroom-tokens.jsx` default `pad`).
  static const double cardPadding = 16;

  /// Legacy section gap (14) → Wardroom stackL (18). Closest fit.
  static const double sectionGap = stackL;

  /// Legacy grid gap (9) — retained at 9 for compact stat grids.
  static const double gridGap = 9;

  /// Legacy inline gap (8) → Wardroom stackS (8).
  static const double inlineGap = stackS;
}

/// Wardroom radii — sharp corners signal precision.
///
/// Default card radius drops from 16 → 6. Buttons drop from pill (100)
/// → sharp (2). Do not soften — the system loses discipline.
///
/// Source of truth: `Knowledgebase/Avya App redesign/
/// design_handoff_wardroom/readme.md` (§Design Tokens · Radii).
class AppRadius {
  AppRadius._();

  // ── Wardroom radii ───────────────────────────────────────────────────
  /// Primary surfaces, buttons — 2 px.
  static const double sharp = 2;

  /// Chips · status ticks — 4 px.
  static const double soft = 4;

  /// Cards (default) — 6 px.
  static const double card = 6;

  // ── Legacy aliases (remapped to Wardroom radii) ──────────────────────
  /// Legacy pill (100) → Wardroom pill (999). Status pills only.
  static const double pill = 999;

  /// Legacy large card (22) → Wardroom card (6).
  static const double cardL = card;

  /// Legacy medium card (16) → Wardroom card (6).
  static const double cardM = card;

  /// Legacy small card (14) → Wardroom card (6).
  static const double cardS = card;

  /// Legacy row (12) → Wardroom card (6).
  static const double row = card;

  /// Legacy badge (100) → Wardroom pill (999). Reserved for status pills.
  static const double badge = pill;
}
