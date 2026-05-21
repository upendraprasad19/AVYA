import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/read_screen_source.dart';

void main() {
  late String src;

  setUpAll(() {
    src = readScreenSource('profile');
  });

  test('Predictions, Progress Comparison, Progress Photos share one _buildCard', () {
    final predictionsIdx = src.indexOf("title: 'Predictions'");
    final comparisonIdx = src.indexOf("title: 'Progress Comparison'");
    final photosIdx = src.indexOf("title: 'Progress Photos'");

    // All three rows must exist
    expect(predictionsIdx, isNot(-1), reason: 'Predictions row missing');
    expect(comparisonIdx, isNot(-1), reason: 'Progress Comparison row missing');
    expect(photosIdx, isNot(-1), reason: 'Progress Photos row missing');

    // They must appear in order
    expect(predictionsIdx < comparisonIdx, isTrue,
        reason: 'Predictions must come before Progress Comparison');
    expect(comparisonIdx < photosIdx, isTrue,
        reason: 'Progress Comparison must come before Progress Photos');

    // There must be only one _buildCard call between Predictions and Photos
    final segment = src.substring(predictionsIdx, photosIdx);
    final buildCardCount = '_buildCard'.allMatches(segment).length;
    expect(buildCardCount, lessThanOrEqualTo(1),
        reason: 'All 3 rows must share a single _buildCard (got $buildCardCount in segment)');
  });

  test('WeeklyReportCard appears before the 3-row card in REPORTS', () {
    final weeklyIdx = src.indexOf('WeeklyReportCard(');
    final predictionsIdx = src.indexOf("title: 'Predictions'");
    expect(weeklyIdx, isNot(-1), reason: 'WeeklyReportCard must exist');
    expect(weeklyIdx < predictionsIdx, isTrue,
        reason: 'WeeklyReportCard must appear before the Predictions row');
  });
}
