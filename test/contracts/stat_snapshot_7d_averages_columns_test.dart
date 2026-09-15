// Regression guard — diagnose 2026-05-30-stat-snapshot-7d-averages-wrong-
// columns (a7c3e1).
//
// StatSnapshotService._compute7dAverages queried two columns that do not exist
// on the live schema:
//   - daily_steps.total_steps  (real column: `steps`)
//   - sleep_logs.hours         (real column: `duration_hrs`)
// Each threw PostgrestException 42703; because the queries share one try block,
// the daily_steps throw dumped the whole method to its catch → every 7d average
// (calories/protein/steps/sleep) returned 0 on promotion + manual snapshots.
//
// This is a source-grep guard pinning the corrected column literals in the
// service. The authoritative behavioral proof is the live SELECT recorded in
// the diagnose-doc (total_steps -> 42703; steps -> 1526) plus the
// check_schema_column_refs.dart gate, which validates EVERY .from().select
// column against the committed live-schema snapshot.
//
// Run: flutter test test/contracts/stat_snapshot_7d_averages_columns_test.dart

import 'dart:io';
import 'package:test/test.dart';

const _service = 'lib/core/services/stat_snapshot_service.dart';

/// Strip Dart `// ...` line comments so absence assertions don't false-positive
/// on the explanatory comment block (which names the old wrong columns).
String _stripDartComments(String src) =>
    src.replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('StatSnapshotService 7d-average columns (a7c3e1)', () {
    late String code;

    setUpAll(() {
      final f = File(_service);
      expect(f.existsSync(), isTrue, reason: '$_service must exist');
      code = _stripDartComments(f.readAsStringSync());
    });

    test('daily_steps query selects `steps`, never `total_steps`', () {
      expect(code.contains("select('total_steps')"), isFalse,
          reason: 'daily_steps has no total_steps column — use steps.');
      expect(code.contains("select('steps')"), isTrue,
          reason: 'daily_steps daily total lives in column `steps`.');
    });

    test('sleep_logs query selects `duration_hrs`, never `hours`', () {
      expect(code.contains("select('hours')"), isFalse,
          reason: 'sleep_logs has no hours column — use duration_hrs.');
      expect(code.contains("select('duration_hrs')"), isTrue,
          reason: 'sleep_logs duration lives in column `duration_hrs`.');
    });

    test('result rows are read by the corrected keys', () {
      // The avg() helper is called with the same key names that were selected.
      expect(code.contains("avg(stepRows as List, 'steps')"), isTrue,
          reason: 'step average must read the `steps` result key.');
      expect(code.contains("avg(sleepRows as List, 'duration_hrs')"), isTrue,
          reason: 'sleep average must read the `duration_hrs` result key.');
      expect(code.contains("'total_steps')"), isFalse);
      expect(code.contains("'hours')"), isFalse);
    });

    test('nutrition query (already correct) is unchanged', () {
      expect(code.contains("select('total_calories, total_protein')"), isTrue,
          reason: 'nutrition_logs has total_calories + total_protein.');
    });
  });
}
