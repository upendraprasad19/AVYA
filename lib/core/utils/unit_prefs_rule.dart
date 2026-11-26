// Unit preferences as profile fields (OI-348 B9, diagnose e9a6c1).
//
// Two per-user settings live in the profile map (`userBox['profile']`), are
// pushed to `user_profile` (migration 185) and come back with the normal
// profile restore (cloud non-null wins per key), so every device of one
// account shows the same units:
//   units_system      'metric' | 'imperial'   (the Profile Units switch)
//   measurement_unit  'cm' | 'in'             (the body-measurement sheet)
//
// Pure: no Hive, no Supabase. The readers and writers in UserRepository,
// MeasurementWriteNotifier and the profile push call these.
library;

const String kUnitsSystemKey = 'units_system';
const String kMeasurementUnitKey = 'measurement_unit';

/// The stored value for the Profile Units switch.
String unitsSystemValue({required bool metric}) =>
    metric ? 'metric' : 'imperial';

/// The stored value for the measurement sheet's unit.
String measurementUnitValue({required bool inches}) => inches ? 'in' : 'cm';

/// `units_system` read: 'imperial' -> false, 'metric' -> true, ABSENT (null)
/// -> null (the caller falls back to the legacy device key), any other value
/// (a bad cloud value; restore merges verbatim) -> true, the default.
bool? metricFromProfileValue(Object? raw) {
  if (raw == null) return null;
  return raw != 'imperial';
}

/// `measurement_unit` read: 'in' -> true, 'cm' -> false, ABSENT -> null (the
/// caller falls back), any other value -> false, the default.
bool? inchesFromProfileValue(Object? raw) {
  if (raw == null) return null;
  return raw == 'in';
}

/// The unit entries of the profile push (`_syncUserProfile`): each key that
/// holds a VALID stored value is pushed; absent or invalid stays absent (a
/// CHECK violation would reject the whole profile row, and an absent key never
/// overwrites another device's cloud value). [enabled] false (the kill switch
/// `disable_unit_pref_sync`) -> no entries: the payload is byte-identical to the
/// one before this change.
Map<String, String> unitPrefsPushEntries(
  Map<dynamic, dynamic> profile, {
  required bool enabled,
}) {
  if (!enabled) return const {};
  final out = <String, String>{};
  final s = profile[kUnitsSystemKey];
  if (s == 'metric' || s == 'imperial') out[kUnitsSystemKey] = s as String;
  final m = profile[kMeasurementUnitKey];
  if (m == 'cm' || m == 'in') out[kMeasurementUnitKey] = m as String;
  return out;
}
