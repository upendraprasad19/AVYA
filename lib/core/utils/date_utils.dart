/// Format a [DateTime] as 'yyyy-MM-dd' string key for Hive storage.
///
/// Used across workout, nutrition, and health modules for consistent
/// date-keyed Hive entries. Single source of truth — avoids duplicating
/// the same formatting logic in every repository and service.
///
/// Example:
///   formatDateKey(DateTime(2026, 3, 31)) → '2026-03-31'
String formatDateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
