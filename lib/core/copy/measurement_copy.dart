/// Copy for the body-measurements sheet, the Home banner and the Weight-sheet
/// link (L2b Landing B). Constants and pure functions only (no Flutter, no
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

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
