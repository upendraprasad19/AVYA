/// IST (Asia/Kolkata, UTC+5:30) date/time helpers.
///
/// All "today" / "this week" / "calendar" logic in the app derives
/// from IST per CLAUDE.md §3.1 + apk-test-6 spec §3.1. Use these
/// helpers — never hand-roll `toUtc().add(Duration(hours: 5, ...))`.
library;

const Duration _istOffset = Duration(hours: 5, minutes: 30);

/// Current IST instant (returned as a "naive" DateTime in IST wall
/// clock — `isUtc` is false but the components ARE IST values).
DateTime istNow() {
  return DateTime.now().toUtc().add(_istOffset);
}

/// Returns the IST wall-clock equivalent of [t].
///
/// If [t] is UTC: shifts forward by +5:30.
/// If [t] is local (device): converts to UTC first, then shifts.
DateTime istDateOf(DateTime t) {
  return t.toUtc().add(_istOffset);
}

/// Returns the IST date as a `YYYY-MM-DD` string. Stable for use
/// as a Hive key / Supabase DATE column / calendar bucket.
String istDateStr(DateTime t) {
  final ist = istDateOf(t);
  final y = ist.year.toString().padLeft(4, '0');
  final m = ist.month.toString().padLeft(2, '0');
  final d = ist.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// IST midnight (00:00:00) of the date containing [t].
DateTime istMidnight(DateTime t) {
  final ist = istDateOf(t);
  return DateTime(ist.year, ist.month, ist.day);
}

/// IST midnight UTC equivalent — useful for storing Postgres TIMESTAMPTZ
/// values that should round-trip correctly. Returns the UTC instant
/// corresponding to IST 00:00 of the date containing [t].
DateTime istMidnightUtc(DateTime t) {
  final mid = istMidnight(t);
  // mid is naive-IST; convert back: IST midnight = UTC (midnight - 5:30)
  return DateTime.utc(mid.year, mid.month, mid.day).subtract(_istOffset);
}

/// Monday of the IST calendar week containing [t]. Time component
/// is 00:00:00 (the Monday's IST midnight).
DateTime mondayOfIst(DateTime t) {
  final ist = istMidnight(t);
  // DateTime.weekday: Monday=1, ..., Sunday=7
  final daysFromMonday = ist.weekday - 1;
  return ist.subtract(Duration(days: daysFromMonday));
}

/// Sunday of the IST calendar week containing [t]. Time component
/// is 00:00:00 (the Sunday's IST midnight).
DateTime sundayOfIst(DateTime t) {
  return mondayOfIst(t).add(const Duration(days: 6));
}

/// True if both timestamps fall on the same IST calendar date.
bool isSameIstDate(DateTime a, DateTime b) {
  return istDateStr(a) == istDateStr(b);
}
