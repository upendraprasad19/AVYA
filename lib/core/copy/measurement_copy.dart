/// Copy for the body-measurements sheet, the Home banner, the Weight-sheet
/// link (L2b Landing B), the Progress comparison card and the chat chip
/// (Landing C). Constants and pure functions only (no Flutter, no
/// Hive), so every string is testable.
///
/// Voice: plain Wardroom. Neutral numbers, no good or bad wording on a change,
/// no guilt or streak-loss framing; the entry is optional and never PRO-gated.
/// No em dashes (the app uses a middle dot where it needs a separator). The
/// per-site label and guide lines live on `BodyMeasurementSpec`
/// (`lib/core/constants/body_measurement_specs.dart`), not here.
library;

class MeasurementCopy {
  MeasurementCopy._();

  // ── Sheet ─────────────────────────────────────────────────────────────
  static const sheetEyebrow = 'BODY MEASUREMENTS';
  static const introFirst =
      'Four numbers give your coach a baseline. Fill in any you have, skip the rest.';
  static const introLater = 'Fill in only what you measured today.';
  static const unitCm = 'CM';
  static const unitIn = 'IN';
  // Screen-reader names of the two unit options (the visible text is CM / IN).
  static const unitCmSemantics = 'Centimetres';
  static const unitInSemantics = 'Inches';
  static const switchToInches = 'Looks like inches · switch?';
  static const switchToCentimetres = 'Looks like centimetres · switch?';
  static const loadError = "Couldn't load your last entries";
  static const retry = 'Retry';
  static const save = 'SAVE';
  static const saveFailed = "Couldn't save. Try again.";

  // ── Saved line ────────────────────────────────────────────────────────
  static const savedPlain = 'Measurements saved ✓';
  static const savedBaseline = 'Baseline set ✓';

  // ── Home banner ───────────────────────────────────────────────────────
  static const bannerDue =
      "It's been about a month. Log a fresh set of measurements?";
  static const bannerBaseline =
      'Set your baseline: four tape measures, about a minute.';
  static const bannerDismissLabel = 'Dismiss measurements reminder';

  // ── Weight sheet ──────────────────────────────────────────────────────
  static const weightSheetLink = 'Add body measurements';

  // ── Progress comparison card and chat chip (L2b Landing C) ────────────
  // One verb ("Add") across the doors: this button, the Weight-sheet link and
  // the chip. The card never uses the word "snapshot" (Take Snapshot sits
  // right below it and does not capture these numbers, plan D1).
  static const cardAddButton = 'Add measurements';
  static const chipLabel = 'Add body measurements';

  // ── Pure builders ─────────────────────────────────────────────────────

  /// "Between 50 and 200 cm" for a centimetre range.
  static String rangeCm(double min, double max) =>
      'Between ${_plain(min)} and ${_plain(max)} cm';

  /// "Between 19.7 and 78.7 in" for an inch range (always one decimal).
  static String rangeIn(double min, double max) =>
      'Between ${min.toStringAsFixed(1)} and ${max.toStringAsFixed(1)} in';

  /// "= 190.5 cm", the value an inch entry will be stored as.
  static String storedAsCm(double cm) => '= ${cm.toStringAsFixed(1)} cm';

  /// "Last: 81.0 cm · 12 Sep" (centimetre mode) or
  /// "Last: 70.0 cm · 27.6 in · 12 Sep" (inch mode: [inches] is set).
  static String lastHint({
    required double cm,
    double? inches,
    required String shortDate,
  }) {
    final mid = inches == null ? '' : ' · ${inches.toStringAsFixed(1)} in';
    return 'Last: ${cm.toStringAsFixed(1)} cm$mid · $shortDate';
  }

  /// "Waist 81.0 → 79.5 cm": one held site changed. Always centimetres (two
  /// stored values 0.1 cm apart can print the same inch figure).
  static String deltaLine(String label, double before, double after) =>
      '$label ${before.toStringAsFixed(1)} → ${after.toStringAsFixed(1)} cm';

  /// "WAIST · 3 Oct": the tile's first line, the site and the day of its
  /// latest value ([shortDate] comes from `formatShortIstDate`).
  static String cardTileTitle(String label, String shortDate) =>
      '${label.toUpperCase()} · $shortDate';

  /// "79.5 cm" / "31.3 in": [value] is already in the unit [inches] names.
  static String cardValue(double value, {required bool inches}) =>
      '${value.toStringAsFixed(1)} ${inches ? 'in' : 'cm'}';

  /// "+1.5 cm since 12 Sep" / "-1.5 cm since 12 Sep" / "no change since 12
  /// Sep". [delta] is the difference of the two DISPLAYED values, already
  /// rounded to 0.1; a zero (or negative zero) reads "no change". Neutral on
  /// purpose: no good or bad wording and no colour for any sign.
  static String cardDeltaLine(
    double delta, {
    required bool inches,
    required String shortFirstDate,
  }) {
    if (delta == 0) return 'no change since $shortFirstDate';
    final sign = delta > 0 ? '+' : '';
    return '$sign${cardValue(delta, inches: inches)} since $shortFirstDate';
  }

  /// The one screen-reader sentence of a tile, built from RAW fields (full
  /// month names, unit words): "Waist, 79.5 centimetres, measured 3 October.
  /// Up 1.5 centimetres since 12 September." [delta] and [longFirstDate] are
  /// both null for a site held by one day only.
  static String cardTileSemantics({
    required String label,
    required double value,
    required bool inches,
    required String longLatestDate,
    double? delta,
    String? longFirstDate,
  }) {
    final unit = inches ? 'inches' : 'centimetres';
    final head =
        '$label, ${value.toStringAsFixed(1)} $unit, measured $longLatestDate.';
    if (delta == null || longFirstDate == null) return head;
    if (delta == 0) return '$head No change since $longFirstDate.';
    final word = delta > 0 ? 'Up' : 'Down';
    return '$head $word ${delta.abs().toStringAsFixed(1)} $unit since '
        '$longFirstDate.';
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
