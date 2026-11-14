import '../constants/body_measurement_specs.dart';

/// Pure unit helpers for the body-measurements sheet (L2b Landing B, B4).
///
/// The sheet stores centimetres only. The unit control changes how the digits a
/// user typed are READ; it never rewrites them, so nothing here converts typed
/// text back and forth (which drifts: 75 cm -> 29.5 in -> 74.9 cm). Every
/// result that reaches storage goes through [roundMeasurementToTenth] and is
/// then judged by [isValidBodyMeasurementCm], the same predicate the writer
/// uses.
const double _kCmPerInch = 2.54;

/// [inches] as centimetres, rounded to 0.1 cm.
double cmFromInches(double inches) =>
    roundMeasurementToTenth(inches * _kCmPerInch);

/// [cm] as inches, rounded to 0.1 in.
double inchesFromCm(double cm) => roundMeasurementToTenth(cm / _kCmPerInch);

/// Reads what a user typed as a centimetre value, or null.
///
/// [metric] says whether [text] is centimetres (true) or inches (false); the
/// result is always centimetres, rounded to 0.1. Null for a blank or
/// non-numeric text and for a non-finite result. The parse is bounds-free
/// ("999.9" is 999.9 cm): range is [isValidBodyMeasurementCm]'s job.
///
/// The sheet's input formatter keeps only a leading digit prefix, so
/// "NaN", "Infinity" and "1e999" cannot be typed or pasted; `double.tryParse`
/// does return NaN / Infinity for them, so this guard is defence in depth and
/// is provable only at this pure level.
double? parseMeasurementInput(String text, {required bool metric}) {
  final v = double.tryParse(text.trim());
  if (v == null || !v.isFinite) return null;
  final cm = metric ? roundMeasurementToTenth(v) : cmFromInches(v);
  return cm.isFinite ? cm : null;
}

/// The smallest and largest 0.1-inch values that convert to a centimetre value
/// [site] accepts, for the "Between 19.7 and 78.7 in" message.
///
/// Never printed as `bound / 2.54`: that prints 23.6 for chest and hips (23.6
/// in = 59.944 cm rounds to 59.9, below the floor) and 27.6 for arms (27.6 in =
/// 70.104 cm rounds to 70.1, above the ceiling), values the sheet would itself
/// refuse. Found by an integer-tenths search (`t / 10.0`, never `x += 0.1`,
/// which yields 23.700000000000003); the accepted set is contiguous because the
/// conversion is monotone. An unknown [site] throws [ArgumentError].
({double min, double max}) inchBoundsFor(String site) {
  final spec = kBodyMeasurementSpecs[site];
  if (spec == null) {
    throw ArgumentError.value(site, 'site', 'not a body-measurement site');
  }
  final first = (spec.minCm / _kCmPerInch * 10).floor() - 2;
  final last = (spec.maxCm / _kCmPerInch * 10).ceil() + 2;
  double? lo;
  double? hi;
  for (var t = first; t <= last; t++) {
    final inch = t / 10.0;
    if (isValidBodyMeasurementCm(site, cmFromInches(inch))) {
      lo ??= inch;
      hi = inch;
    }
  }
  if (lo == null || hi == null) {
    throw StateError('no inch value converts into the range of $site');
  }
  return (min: lo, max: hi);
}

/// True when [text] is not a valid [site] value in the unit it is read in
/// ([metric]) but IS valid in the other one: the "Looks like inches · switch?"
/// case (26 typed in a centimetre field). False for a text that does not parse
/// and for a value that is valid in the current unit or in neither.
bool suggestOtherUnit(String site, String text, {required bool metric}) {
  final here = parseMeasurementInput(text, metric: metric);
  if (here == null) return false;
  if (isValidBodyMeasurementCm(site, here)) return false;
  final other = parseMeasurementInput(text, metric: !metric);
  return isValidBodyMeasurementCm(site, other);
}

const List<String> _kMonthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

final RegExp _kIstShape = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// A stored IST date key (`2026-09-12`) as `12 Sep` in the year of [todayIst]
/// and `12 Sep 2025` otherwise; the empty string for anything malformed.
///
/// Total: accepts only the strict shape with the month in 1-12 and the day in
/// 1-31 (its callers pass dates the reader already validated, and this file in
/// `lib/core/utils` cannot import the features-layer date parser). It SPLITS the
/// stored string; it never goes through `DateTime.parse` and local formatting,
/// which can move the day in a far-east zone for a timestamp.
String formatShortIstDate(String istDate, {required String todayIst}) =>
    _formatIstDate(istDate, todayIst, _kMonthNames);

const List<String> _kLongMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// [formatShortIstDate] with the full month name (`12 September`, and
/// `12 September 2025` when the year is not the current one): the words a
/// screen reader says for a tile of the Progress comparison card (L2b Landing
/// C). Same strict shape and the same empty string for anything malformed.
String formatLongIstDate(String istDate, {required String todayIst}) =>
    _formatIstDate(istDate, todayIst, _kLongMonthNames);

/// The one body of both formatters, so a later fix to the shape check reaches
/// the visible title and the spoken sentence together.
String _formatIstDate(
  String istDate,
  String todayIst,
  List<String> monthNames,
) {
  if (!_kIstShape.hasMatch(istDate)) return '';
  final year = int.parse(istDate.substring(0, 4));
  final month = int.parse(istDate.substring(5, 7));
  final day = int.parse(istDate.substring(8, 10));
  if (month < 1 || month > 12 || day < 1 || day > 31) return '';
  final currentYear = _kIstShape.hasMatch(todayIst)
      ? int.parse(todayIst.substring(0, 4))
      : null;
  final base = '$day ${monthNames[month - 1]}';
  return year == currentYear ? base : '$base $year';
}
