import 'package:flutter_test/flutter_test.dart';
import '../helpers/read_screen_source.dart';

void main() {
  late String src;

  setUpAll(() {
    // Comment-stripped: a row commented out instead of deleted must not count.
    src = readScreenSourceStripped('profile');
  });

  test('Predictions, Progress Comparison, Photos share one _buildCard', () {
    final predictionsIdx = src.indexOf("title: 'Predictions'");
    final comparisonIdx = src.indexOf("title: 'Progress Comparison'");
    final photosIdx = src.indexOf("title: 'Photos'");

    // All three rows must exist
    expect(predictionsIdx, isNot(-1), reason: 'Predictions row missing');
    expect(comparisonIdx, isNot(-1), reason: 'Progress Comparison row missing');
    expect(photosIdx, isNot(-1), reason: 'Photos hub row missing');

    // They must appear in order
    expect(predictionsIdx < comparisonIdx, isTrue,
        reason: 'Predictions must come before Progress Comparison');
    expect(comparisonIdx < photosIdx, isTrue,
        reason: 'Progress Comparison must come before the Photos row');

    // The segment starts at the Predictions TITLE, which is already inside the
    // card's own `_buildCard([`, so a segment that shares the card has NO
    // `_buildCard` in it; one is a second card (Photos split into its own).
    final segment = src.substring(predictionsIdx, photosIdx);
    final buildCardCount = '_buildCard'.allMatches(segment).length;
    expect(buildCardCount, 0,
        reason: 'All 3 rows must share a single _buildCard (got $buildCardCount '
            'in the Predictions..Photos segment)');
  });

  test('WeeklyReportCard appears before the 3-row card in REPORTS', () {
    final weeklyIdx = src.indexOf('WeeklyReportCard(');
    final predictionsIdx = src.indexOf("title: 'Predictions'");
    expect(weeklyIdx, isNot(-1), reason: 'WeeklyReportCard must exist');
    expect(weeklyIdx < predictionsIdx, isTrue,
        reason: 'WeeklyReportCard must appear before the Predictions row');
  });
}
