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
