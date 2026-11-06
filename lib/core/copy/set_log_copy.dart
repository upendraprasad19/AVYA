/// Copy for a set's duration / distance limits (OI-389 / OI-382): the active
/// workout's blocked-LOG messages and the edit sheet's failure lines.
/// Constants and pure functions only, so every string is testable.
///
/// Voice: plain Wardroom. Short, no blame, the unit of the box the user typed
/// in (minutes for cardio, the 6-hour line for timed seconds). Never shows a
/// raw error code in a release build.
library;

import 'package:flutter/foundation.dart';

// ── Active workout: blocked LOG ─────────────────────────────────────────
const String kSetMinutesMaxMessage = 'Up to 360 min per set.';
const String kSetSecondsMaxMessage = 'Up to 6 hours per set.';
const String kSetKmMaxMessage = 'Up to 300 km per set.';

/// A typed minutes value that rounds to 0 seconds, e.g. "0.001".
const String kSetMinimumSecondMessage = 'At least 1 second per set.';

// ── Edit sheet: failure lines ───────────────────────────────────────────
const String kNotSavedDurationCardio = 'Not saved: a set can be up to 360 min.';
const String kNotSavedDurationTimed = 'Not saved: a set can be up to 6 hours.';
const String kNotSavedDistance = 'Not saved: a set can be up to 300 km.';
const String kNotSavedMinutesFormat =
    'Not saved: enter the minutes as a number, like 12.5.';
const String kNotSavedGeneric = 'Not saved. Try again.';

/// Edit-sheet code for a minutes field that does not parse, or rounds to 0 s.
const String kMinutesFormatCode = 'minutes_format';

/// The one sentence a refusal [code] shows (OI-389 U7). [loggingType] picks
/// the unit for a duration refusal. Any other code, or none, is the generic
/// line; the raw [raw] error is appended only when [debug] (never in release).
String toFailureCopy(
  String? code, {
  String loggingType = 'cardio',
  String? raw,
  bool debug = kDebugMode,
}) {
  switch (code) {
    case 'duration_out_of_range':
      return loggingType == 'timed'
          ? kNotSavedDurationTimed
          : kNotSavedDurationCardio;
    case 'distance_out_of_range':
      return kNotSavedDistance;
    case kMinutesFormatCode:
      return kNotSavedMinutesFormat;
    default:
      return (debug && raw != null && raw.isNotEmpty)
          ? '$kNotSavedGeneric ($raw)'
          : kNotSavedGeneric;
  }
}

/// The multi-row sheet line when some rows saved and some did not, in the
/// shape of `WardroomCopy.coachWorkoutLogPartialTemplate`. Names only the
/// failed exercises and gives no counts (the sheet re-saves every row of the
/// day, so a count would include rows the user never touched). [firstCode]
/// picks the reason sentence.
String partialSaveCopy(
  List<String> failedNames, {
  String? firstCode,
  String loggingType = 'cardio',
}) {
  final reason = switch (firstCode) {
    'duration_out_of_range' => loggingType == 'timed'
        ? 'A set can be up to 6 hours.'
        : 'A set can be up to 360 min.',
    'distance_out_of_range' => 'A set can be up to 300 km.',
    kMinutesFormatCode => 'Enter the minutes as a number, like 12.5.',
    _ => 'Try again.',
  };
  return 'Partly saved. Not saved: ${failedNames.join(', ')}. $reason';
}
