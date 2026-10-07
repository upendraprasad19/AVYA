import 'package:icanbefitter/core/utils/ist_date.dart';

/// Whether the Weekly Report screen should fire its silent refresh-on-open
/// (issue #78 / diagnose `d7b2e5`).
///
/// Every refresh is one `MODEL_PRO` thinking-on Gemini call, and the server has
/// no per-day cap for PRO, so an uncapped refresh-on-open meant one call per
/// screen open. A refresh is skipped when the cached report was written on the
/// same IST day as [now]; a missing/unparseable cache always refreshes.
bool shouldSilentRefreshWeeklyReport({
  required String? cachedJson,
  required String? cachedDateIso,
  required DateTime now,
}) {
  if (cachedJson == null || cachedDateIso == null) return true;
  final cachedAt = DateTime.tryParse(cachedDateIso);
  if (cachedAt == null) return true;
  return istDateStr(cachedAt) != istDateStr(now);
}
