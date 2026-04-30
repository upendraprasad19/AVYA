import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

void main() {
  group('Lt insertion at ordinal 7', () {
    test('ladder length is 11', () {
      expect(kRankLadder.length, 11);
    });

    test('Lt entry exists at ordinal 7', () {
      final lt = rankByCode('Lt');
      expect(lt, isNotNull);
      expect(lt!.ordinal, 7);
      expect(lt.minWeeks, 130);
      expect(lt.category, 'officer');
      expect(lt.shortName, 'LIEUTENANT');
      expect(lt.isTerminal, isFalse);
    });

    test('downstream ordinals shifted', () {
      expect(rankByCode('LtCdr')!.ordinal, 8);
      expect(rankByCode('Cdr')!.ordinal, 9);
      expect(rankByCode('Capt')!.ordinal, 10);
    });

    test('Capt remains terminal at ordinal 10', () {
      final capt = rankByCode('Capt');
      expect(capt!.isTerminal, isTrue);
      expect(capt.ordinal, 10);
    });

    test('ordinals are dense 0..10 with no gaps', () {
      final ordinals = kRankLadder.map((r) => r.ordinal).toList()..sort();
      expect(ordinals, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    });

    test('short caps names match spec verbatim', () {
      expect(rankByCode('SD2')!.shortName, 'SEAMAN 2');
      expect(rankByCode('LS')!.shortName, 'LEADING SEAMAN');
      expect(rankByCode('MCPO')!.shortName, 'MASTER CHIEF');
      expect(rankByCode('SubLt')!.shortName, 'SUB LT');
    });
  });
}
