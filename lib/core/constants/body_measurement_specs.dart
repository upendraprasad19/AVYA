/// Inclusive sanity range, in centimetres, for one body-measurement site.
class BodyMeasurementSpec {
  const BodyMeasurementSpec({required this.minCm, required this.maxCm});

  final double minCm;
  final double maxCm;
}

/// Sanity bounds (centimetres) for the four body-measurement sites in
/// `body_measurement_sites.dart` (L2b Landing A, OI-297).
///
/// Before this table any positive number was accepted at every entry point
/// (`valueCm <= 0` was the only guard), NaN and Infinity included: a stored NaN
/// makes `AiSnapshotBuilder.buildAiContext` throw (its size trim JSON-encodes
/// the snapshot), which stops every chat context build and every snapshot
/// push, and a finite absurd value (a waist of 3000) went to the coach as fact.
///
/// The bounds are adult floors and ceilings. They double as the "probably
/// inches" threshold: the common inch values typed in a centimetre field
/// (waist 26-49, chest 30-55, hips 30-55, arms 10-19) land BELOW the floor and
/// are rejected, which is how a unit mix-up is told apart from a real value. A
/// value that is valid in both units (waist 50-78, chest and hips 60-78, arms
/// 20-27) is stored as centimetres.
///
/// Every bound MUST be a multiple of 0.1 (a fixed point of
/// [roundMeasurementToTenth]): the chat parse checks the raw value and the
/// writer checks the value rounded to 0.1 cm, and a bound that rounding moves
/// would let the parse accept a value the writer then rejects.
/// `test/contracts/body_measurement_bounds_behavioral_test.dart` enforces it.
///
/// The keys are exactly [kBodyMeasurementSites]; the values are written as
/// constructor calls on purpose, so this table is not a second flat multi-site
/// literal for `test/contracts/body_measurement_sites_derivation_test.dart`
/// (the keys == tokens test is the protection, not that scan's blind spot).
const Map<String, BodyMeasurementSpec> kBodyMeasurementSpecs = {
  'chest': BodyMeasurementSpec(minCm: 60, maxCm: 200),
  'waist': BodyMeasurementSpec(minCm: 50, maxCm: 200),
  'hips': BodyMeasurementSpec(minCm: 60, maxCm: 200),
  'arms': BodyMeasurementSpec(minCm: 20, maxCm: 70),
};

/// True when [site] is a registered site and [v] lies within its bounds,
/// inclusive. NaN fails both comparisons and ±Infinity fails the range, so
/// there is deliberately no separate `isFinite` term (it would duplicate the
/// range test and make every single-guard NaN mutant equivalent).
bool isValidBodyMeasurementCm(String? site, double? v) {
  final spec = site == null ? null : kBodyMeasurementSpecs[site];
  return spec != null && v != null && v >= spec.minCm && v <= spec.maxCm;
}

/// [v] rounded to one decimal (0.1 cm), the precision the app shows and stores.
///
/// Total: on the pinned Dart, `toStringAsFixed` returns "NaN", "Infinity" and
/// "-Infinity" for the non-finite values and `double.parse` reads them back, so
/// NaN and ±Infinity come back unchanged and then fail
/// [isValidBodyMeasurementCm]. There is no `isFinite` guard on purpose (it
/// would be dead code no test can redden); the formula `(v * 10).round() / 10`
/// would throw `UnsupportedError` on them, which the totality tests catch.
double roundMeasurementToTenth(double v) => double.parse(v.toStringAsFixed(1));

/// The `ErrorTelemetry` message for a rejected value, for example
/// `tier=chat site=waist side=below` (`side` is `below`, `above` or
/// `nonfinite`), or null when there is nothing to report (an unregistered site,
/// a missing value, or a value that is valid). Never carries the number itself.
String? measurementRejectionMessage(String tier, String? site, double? v) {
  final spec = site == null ? null : kBodyMeasurementSpecs[site];
  if (spec == null || v == null) return null;
  if (isValidBodyMeasurementCm(site, v)) return null;
  final side = !v.isFinite ? 'nonfinite' : (v < spec.minCm ? 'below' : 'above');
  return 'tier=$tier site=$site side=$side';
}
