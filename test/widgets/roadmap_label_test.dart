import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

void main() {
  group('Roadmap label format', () {
    test('roadmap labels read "WEEK <n>" not "W<n>"', () {
      // For every non-zero-week rank, the canonical roadmap label
      // must be "WEEK <minWeeks>" — not the legacy "W<minWeeks>" form.
      for (final rank in kRankLadder) {
        if (rank.minWeeks == 0) continue;
        final expected = 'WEEK ${rank.minWeeks}';
        expect(expected, startsWith('WEEK '));
        expect(expected, isNot(matches(RegExp(r'^W\d'))));
      }
    });

    test('all 11 ranks present including Lt', () {
      final codes = kRankLadder.map((r) => r.code).toList();
      expect(codes, containsAll([
        'SD2', 'SD1', 'LS', 'PO', 'CPO', 'MCPO',
        'SubLt', 'Lt', 'LtCdr', 'Cdr', 'Capt',
      ]));
      expect(kRankLadder.length, 11);
    });
  });
}
