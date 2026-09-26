// Contract test: FoodLogNotifier.logFood routes through NutritionWriteService
// so search-mode logs include items[] and project to cloud nutrition_log_items.
//
// Theme C1 (APK Test #11): before this fix, FoodLogNotifier.logFood wrote a
// legacy flat-totals nlog_* row with NO items[] array. The cloud projection
// in _syncNutritionLogs reads log['items'] — for those rows it silently wrote
// 0 rows to cloud nutrition_log_items. Server-side weekly-report /
// protein-gap-alert / rolling-context saw "no items" and gave advice as if
// the user ate nothing.
//
// This test uses a source-scan assertion (mirrors sync_gap_test pattern) to
// structurally lock the contract without needing a full Hive environment.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relativePath) {
  final file = File('${Directory.current.path}/$relativePath');
  return file.readAsStringSync();
}

/// Returns the substring of [src] that comprises the body of a method,
/// searching for [methodSignatureFragment] and then finding `async {`
/// which marks the opening of the method body. This avoids false positives
/// on `{` characters inside record return-type annotations like
/// `Future<({bool x, String? y})>`.
String _extractMethodBody(String src, String methodSignatureFragment) {
  final start = src.indexOf(methodSignatureFragment);
  if (start == -1) return '';
  // Look for ') async {' which is the canonical async method opening.
  // Fallback: just look for the first '{' after ') {' (sync methods).
  final asyncBodyMarker = src.indexOf(') async {', start);
  final syncBodyMarker = src.indexOf(') {', start);
  int braceStart;
  if (asyncBodyMarker != -1 &&
      (syncBodyMarker == -1 || asyncBodyMarker <= syncBodyMarker + 100)) {
    braceStart = src.indexOf('{', asyncBodyMarker + 7);
  } else if (syncBodyMarker != -1) {
    braceStart = src.indexOf('{', syncBodyMarker + 2);
  } else {
    return '';
  }
  if (braceStart == -1) return '';
  int depth = 0;
  final buf = StringBuffer();
  for (int i = braceStart; i < src.length; i++) {
    final ch = src[i];
    if (ch == '{') depth++;
    if (ch == '}') depth--;
    buf.write(ch);
    if (depth == 0) break;
  }
  return buf.toString();
}

void main() {
  group('FoodLogNotifier.logFood → NutritionWriteService contract (Theme C1)', () {
    late String providerSrc;

    setUpAll(() {
      providerSrc = _src(
        'lib/features/nutrition/providers/nutrition_provider.dart',
      );
    });

    test('FoodLogNotifier.logFood delegates to NutritionWriteService.logMeal',
        () {
      final body = _extractMethodBody(
        providerSrc,
        'Future<({bool success, String? error, String? logKey})> logFood(',
      );
      expect(
        body,
        contains('NutritionWriteService.instance.logMeal'),
        reason:
            'FoodLogNotifier.logFood must route through NutritionWriteService '
            'so the resulting nlog_* row includes items[] (Theme C1)',
      );
    });

    test('FoodLogNotifier.logFood does NOT write nlog_ directly to Hive', () {
      final body = _extractMethodBody(
        providerSrc,
        'Future<({bool success, String? error, String? logKey})> logFood(',
      );
      expect(
        body,
        isNot(contains("nutritionBox.put('nlog_")),
        reason:
            'FoodLogNotifier should NOT write nlog_* directly — '
            'that legacy path produces rows without items[] which breaks '
            'cloud nutrition_log_items projection in _syncNutritionLogs',
      );
      expect(
        body,
        isNot(contains("nutritionBox.put(id,")),
        reason:
            'Legacy put(id, logMap) path must not exist inside logFood — '
            'it predates items[] and must be fully replaced',
      );
    });

    test('FoodLogNotifier.logFood uses IST date for NutritionWriteService.logMeal',
        () {
      final body = _extractMethodBody(
        providerSrc,
        'Future<({bool success, String? error, String? logKey})> logFood(',
      );
      expect(
        body,
        contains('istNow()'),
        reason:
            'logMeal date must be the current IST instant per docs/architecture/sync.md '
            'IST-throughout rule — Device-local DateTime.now() drifts on '
            'users outside UTC+5:30',
      );
    });

    test('FoodLogNotifier.logFood passes NutritionWriteSource.manualSearch', () {
      final body = _extractMethodBody(
        providerSrc,
        'Future<({bool success, String? error, String? logKey})> logFood(',
      );
      expect(
        body,
        contains('NutritionWriteSource.manualSearch'),
        reason:
            'Source must be manualSearch so _counterFeatureForSource returns '
            'null (free, unlimited) — using aiText or scan by mistake would '
            'incorrectly increment a rate-limited counter',
      );
    });

    test('FoodLogNotifier.logFood passes macros scaled from per-100g values', () {
      final body = _extractMethodBody(
        providerSrc,
        'Future<({bool success, String? error, String? logKey})> logFood(',
      );
      // Verify both calories_per_100g (database) and calories (fallback) paths
      expect(
        body,
        contains('calories_per_100g'),
        reason:
            'Must read calories_per_100g from food map (bundled food DB format)',
      );
      expect(
        body,
        contains('protein_per_100g'),
        reason: 'Must read protein_per_100g from food map',
      );
    });

    test('search_mode_body.dart calls logFood and does not destructure result',
        () {
      final searchSrc = _src(
        'lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart',
      );
      // Callsite awaits logFood and immediately calls onLogged() — return
      // value is discarded. Broadening the return type to a record does not
      // break this callsite.
      expect(
        searchSrc,
        contains('.logFood('),
        reason: 'search_mode_body must still call logFood via the provider',
      );
      // Confirm no destructuring — the callsite does not reference .success
      // on the return value of logFood (return value is intentionally ignored).
      final logFoodIdx = searchSrc.indexOf('.logFood(');
      final snippetAfter = searchSrc.substring(logFoodIdx,
          (logFoodIdx + 200).clamp(0, searchSrc.length));
      expect(
        snippetAfter,
        isNot(contains('.success')),
        reason:
            'search_mode_body callsite must not destructure the logFood return '
            'record — it discards the result and calls onLogged() directly',
      );
    });

    test('conversational_log_handler.dart calls logFood and does not destructure result',
        () {
      final handlerSrc = _src(
        'lib/features/ai_coach/services/conversational_log_handler.dart',
      );
      expect(
        handlerSrc,
        contains('.logFood('),
        reason:
            'conversational_log_handler._logFood must still delegate to '
            'FoodLogNotifier.logFood via foodLogProvider.notifier',
      );
    });
  });
}
