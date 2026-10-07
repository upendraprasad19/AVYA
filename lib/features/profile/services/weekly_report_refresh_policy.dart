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

/// True when a `weekly-report` call failed because the server's lifetime free
/// report is spent (HTTP 403 with body `code: NOT_PRO`). Keyed on the body code
/// as well as the status so a 403 that is NOT the free-quota answer (a server
/// error that read the subscription as absent, a future 403) does not set the
/// per-device `first_report_generated` flag or open the paywall by mistake.
/// [details] is `FunctionException.details`: a decoded map, or a JSON string.
bool isLifetimeFreeReportSpent({required int? status, required Object? details}) {
  if (status != 403) return false;
  if (details is Map) return details['code'] == 'NOT_PRO';
  if (details is String) return details.contains('"NOT_PRO"');
  return false;
}
