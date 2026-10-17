import 'ist_date.dart';

/// Format a [DateTime] as the IST 'yyyy-MM-dd' string key for Hive storage.
///
/// Used across workout, nutrition, and health modules for consistent
/// date-keyed Hive entries. Single source of truth — avoids duplicating
/// the same formatting logic in every repository and service.
///
/// **IST-aware (APK Test #12 / Task A-1).** Always converts the input
/// to IST (Asia/Kolkata, UTC+5:30) before extracting the date components.
/// This matches `WorkoutWriteService.istDateStr` (the writer side) so
/// reads via `formatDateKey` and writes via `istDateStr` agree on the
/// same key — even when the device is on a non-IST locale, even when
/// the input is a UTC DateTime, even at the IST midnight boundary.
///
/// Pre-Test-#12 implementation read `date.year/month/day` directly,
/// which gave UTC dates for UTC inputs and local-date for local inputs
/// — those didn't match IST keys around midnight. This caused the
/// "May 4 receipt shows May 5 exercises" bug observed in APK 11.1.
///
/// Examples:
///   formatDateKey(DateTime.utc(2026, 5, 4, 20))   → '2026-05-05'
///     (UTC 20:00 = IST 01:30 next day)
///   formatDateKey(DateTime(2026, 3, 31))           → '2026-03-31'
///     (local-time midnight → same date if device is on IST)
String formatDateKey(DateTime date) {
  return istDateStr(date);
}

/// The app's canonical `day_of_week` for a `yyyy-MM-dd` date string:
/// **0 = Monday … 6 = Sunday**. Returns null when [date] will not parse.
///
/// THE CANON, AND WHY IT NEEDED A SINGLE DEFINITION (OI-170, 2026-09-08).
/// Dart's `DateTime.weekday` is **1..7**, so every site that wants this value
/// has to remember to subtract one. Most did — `tool_dispatcher.dart:695`
/// (`destDate.weekday - 1; // 0=Mon..6=Sun`) and
/// `workout_schedule_read_service.dart:415` — and the readers assume it:
/// `train_provider.dart:619` and `:816` compute
/// `(week - 1) * 7 + day_of_week + 1` and render it as the `D<n>` badge.
///
/// Two sites did not. `sync_workout.dart` pushed raw `parsedDate.weekday`
/// (1..7) to the cloud and restored the wire value verbatim **after** the
/// `...existingMap` spread, so a correct local 0..6 was overwritten by a wrong
/// 1..7 on every round-trip: Monday of week 1 rendered `D2`, Sunday `D8`.
/// `hotel_workout_planner.dart:183` had the same off-by-one locally.
///
/// Deriving from the date rather than trusting a stored value is what makes the
/// restore self-healing — no migration is needed for rows already corrupted in
/// the cloud, because nothing reads the transmitted number any more.
int? dayOfWeekFromDate(String date) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return null;
  return parsed.weekday - 1;
}
