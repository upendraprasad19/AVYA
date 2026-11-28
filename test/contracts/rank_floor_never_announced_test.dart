// Diagnose 8b1f3d (OI-348 walk, 2026-11-23): the floor rung (SD2, held by
// every account from sign-up) is written to rank_promotions as history but is
// never announced: no celebration stamp, no Home celebration, no coach
// message, no push.
//
// Behavioural on the two pure seams (`shouldStampPromotionCelebration`,
// `pendingPromotionAction`); source pins on their two call sites, because
// `RankService.evaluateAndPromote` and `_maybeShowPendingPromotion` run on
// singletons / private State and have no test seam.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

String _stripComments(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

String _methodBody(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, greaterThan(-1), reason: 'missing `$signature`');
  var depth = 0;
  var i = src.indexOf('{', start);
  final open = i;
  for (; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) break;
    }
  }
  return src.substring(open, i + 1);
}

void main() {
  group('pure seams', () {
    test('the floor is the first ladder rung', () {
      expect(kRankLadder.first.code, 'SD2');
      expect(isFloorRank('SD2'), isTrue);
      expect(isFloorRank(null), isFalse);
      expect(isFloorRank(''), isFalse);
    });

    test('shouldStampPromotionCelebration: floor false, EVERY higher rung true',
        () {
      expect(shouldStampPromotionCelebration('SD2'), isFalse);
      // Mirror: an "always skip" mutant passes the floor case only.
      for (final r in kRankLadder.skip(1)) {
        expect(shouldStampPromotionCelebration(r.code), isTrue,
            reason: '${r.code} must still be celebrated');
      }
    });

    test('pendingPromotionAction: none / clearOnly / clearAndCelebrate', () {
      expect(pendingPromotionAction(null), PendingPromotionAction.none);
      expect(pendingPromotionAction('SD2'), PendingPromotionAction.clearOnly);
      expect(pendingPromotionAction('SD1'),
          PendingPromotionAction.clearAndCelebrate);
      expect(pendingPromotionAction('Capt'),
          PendingPromotionAction.clearAndCelebrate);
    });
  });

  group('call-site pins', () {
    test(
        'RankService: the stamp is behind shouldStampPromotionCelebration, '
        'the rank writes are not', () {
      final src = _stripComments(
          File('lib/core/services/rank_service.dart').readAsStringSync());
      final promoteAt = src.indexOf('if (shouldPromote(currentCode, qualified))');
      expect(promoteAt, greaterThan(-1));
      final block = _methodBody(src.substring(promoteAt),
          'if (shouldPromote(currentCode, qualified))');
      final gate =
          block.indexOf('if (shouldStampPromotionCelebration(qualified.code))');
      expect(gate, greaterThan(-1), reason: 'stamp gate missing');
      final stamp = block.indexOf('setPendingPromotionRankCode(qualified.code)');
      expect(stamp, greaterThan(gate), reason: 'stamp must sit behind the gate');
      final gateBody = _methodBody(block.substring(gate),
          'if (shouldStampPromotionCelebration(qualified.code))');
      expect(gateBody.contains('setPendingPromotionRankCode'), isTrue);
      // The rank fields must NOT be behind the gate: null -> SD2 still moves.
      for (final w in [
        "'current_rank_code': qualified.code",
        'onStateChanged?.call()',
        'updateProfileFields(',
      ]) {
        expect(block.indexOf(w), allOf(greaterThan(-1), lessThan(gate)),
            reason: '`$w` must run before (outside) the stamp gate');
        expect(gateBody.contains(w), isFalse);
      }
    });

    test(
        'Home: read -> clear -> clearOnly return -> "shown" event -> push, in '
        'that order', () {
      final src = _stripComments(File('lib/features/home/screens/home_screen.dart')
          .readAsStringSync());
      final body = _methodBody(src, 'void _maybeShowPendingPromotion()');
      final read = body.indexOf('getPendingPromotionRankCode()');
      final action = body.indexOf('pendingPromotionAction(rankCode)');
      final clear = body.indexOf('clearPendingPromotionRankCode()');
      final floorReturn =
          body.indexOf('if (action == PendingPromotionAction.clearOnly) return;');
      final shown = body.indexOf("'rank_promotion_celebration_shown'");
      final push = body.indexOf('Navigator.of(context).push');
      for (final (name, at) in [
        ('read', read),
        ('action', action),
        ('clear', clear),
        ('floorReturn', floorReturn),
        ('shown', shown),
        ('push', push),
      ]) {
        expect(at, greaterThan(-1), reason: 'missing $name');
      }
      expect(read < action && action < clear, isTrue);
      expect(clear < floorReturn, isTrue,
          reason: 'a floor stamp must be CLEARED before the floor return');
      expect(floorReturn < shown, isTrue,
          reason: 'no "shown" event for a celebration that never happens');
      expect(shown < push, isTrue);
    });
  });
}
