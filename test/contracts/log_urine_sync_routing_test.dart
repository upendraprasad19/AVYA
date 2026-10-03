import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression contract for diagnose b6d3f9 — `logUrine` must push the urine row
/// via the dedicated health-domain push, NOT `syncNutritionData()`.
///
/// `logUrine` writes `urine_color_<date>` into healthBox. `syncNutritionData()`'s
/// `_syncWaterLogs` reads ONLY `water_ml_` keys (sync_nutrition.dart), so routing
/// urine through it never pushed the urine row — it reached cloud only on the
/// next FULL sync. The fix fires `pushUrineColorLogsForSyncDomain()` (→
/// `_syncUrineColorLogs`) so urine syncs per-mutation like sleep/weight/measurement.
///
/// Source contract (comment-stripped per feedback_source_grep_strip_comments_first)
/// scoped to the `logUrine` method body so a regression to the nutrition route
/// fails here. Behavioral coverage of the push itself lives in the sync-layer
/// urine tests (`_syncUrineColorLogs`).
String _strip(String s) {
  s = s.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s.replaceAll(RegExp(r'(?<!:)//.*'), '');
  return s;
}

void main() {
  test('logUrine routes to the dedicated urine push, not syncNutritionData (b6d3f9)',
      () {
    final src = _strip(
        File('lib/core/services/health_write_service.dart').readAsStringSync());

    // Isolate the logUrine method body (from its signature to the next method).
    final start = src.indexOf('logUrine({');
    expect(start, greaterThan(-1), reason: 'logUrine method must exist');
    final next = src.indexOf('logHydration({', start);
    expect(next, greaterThan(start), reason: 'logHydration delimits logUrine');
    final body = src.substring(start, next);

    expect(
      body.contains('pushUrineColorLogsForSyncDomain'),
      isTrue,
      reason:
          'logUrine MUST fire pushUrineColorLogsForSyncDomain so the healthBox '
          'urine_color_<date> row reaches cloud per-mutation.',
    );
    expect(
      body.contains('syncNutritionData'),
      isFalse,
      reason:
          'logUrine MUST NOT route urine through syncNutritionData — its '
          '_syncWaterLogs reads only water_ml_ keys, so urine never syncs there.',
    );
  });
}
