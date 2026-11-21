// Behavioral contract — `RankService.shouldPromote` must never return true
// when the qualified rank is at or below the user's current rank.
//
// Closes diagnose 3a7b9f (2026-05-27). Pre-fix `evaluateAndPromote` checked
// `currentCode != qualified.code` and unconditionally overwrote
// `user_profile.current_rank_code` (cloud + Hive). When a user broke a
// sailor-track streak gate (e.g. SD1 requires streak >= 7), `_qualifiedRankCode`
// returned SD2 and the user was silently demoted. The rank_promotions table
// is the append-only event log; current_rank_code is its denormalization and
// must monotonically increase.
//
// Companion source-grep test:
//   test/contracts/rank_service_local_profile_update_test.dart (OI-37 + this fix)
//
// Lens L1 (writer/reader drift) + new monotonic-field-recompute class
// (debugging skill §2.19).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';
import 'package:icanbefitter/core/services/rank_service.dart';

void main() {
  group('RankService.shouldPromote — rank never demotes', () {
    test('null → SD2 promotes (first-ever ranking)', () {
      expect(RankService.shouldPromote(null, rankByCode('SD2')!), isTrue);
    });

    test('SD2 → SD2 is no-op (already at qualified ceiling)', () {
      expect(RankService.shouldPromote('SD2', rankByCode('SD2')!), isFalse);
    });

    test('SD1 → SD2 does NOT demote (streak lost; pre-fix would have)', () {
      // Real-world incident on cloud 2026-05-21: user d7a67a37-... was at
      // SD1 (ordinal 1) and the recompute returned SD2 (ordinal 0) after
      // their streak dropped below 7. Pre-fix demoted to SD2; post-fix
      // stays at SD1.
      expect(RankService.shouldPromote('SD1', rankByCode('SD2')!), isFalse);
    });

    test('Lt → SubLt does NOT demote (officer-track regression)', () {
      // If a future bug recomputes SubLt as the new ceiling for a user
      // who already achieved Lt (ordinal 7), the guard must hold.
      expect(RankService.shouldPromote('Lt', rankByCode('SubLt')!), isFalse);
    });

    test('Capt → any lower rank does NOT demote', () {
      // Terminal rank — must never be revoked.
      for (final lower in const ['SD2', 'SD1', 'LS', 'PO', 'CPO', 'MCPO',
                                 'SubLt', 'Lt', 'LtCdr', 'Cdr']) {
        expect(
          RankService.shouldPromote('Capt', rankByCode(lower)!),
          isFalse,
          reason: 'Capt (ordinal 10) must not demote to $lower',
        );
      }
    });

    test('SD2 → SD1 promotes (legitimate single-rung advance)', () {
      expect(RankService.shouldPromote('SD2', rankByCode('SD1')!), isTrue);
    });

    test('SD2 → Lt promotes (legitimate multi-rung jump per cron backfill)', () {
      // The server cron evaluates ranksUpTo(winner) and can promote a
      // user from SD2 directly to Lt if they cross multiple gates in a
      // single tick (e.g. account inactive for months, then a burst of
      // qualifying state).
      expect(RankService.shouldPromote('SD2', rankByCode('Lt')!), isTrue);
    });

    test('Unknown code → SD2 promotes (treats unknown as -1 ordinal)', () {
      // Defensive: if a stale Hive value has a rank code that no longer
      // exists in the ladder, treat as below-floor and let any current
      // rank overwrite. Failing-open here is correct — failing closed
      // would leave a user stuck on a non-existent rank forever.
      expect(
        RankService.shouldPromote('LegacyRankCode', rankByCode('SD2')!),
        isTrue,
      );
    });

    test('every rank pair: shouldPromote iff qualified.ordinal > current', () {
      // Exhaustive ladder coverage. For every (currentCode, qualifiedCode)
      // pair, the function must return true iff qualified.ordinal is
      // strictly greater than current's ordinal.
      for (final current in kRankLadder) {
        for (final qualified in kRankLadder) {
          final expected = qualified.ordinal > current.ordinal;
          expect(
            RankService.shouldPromote(current.code, qualified),
            expected,
            reason:
                '${current.code} (ord ${current.ordinal}) → '
                '${qualified.code} (ord ${qualified.ordinal}) should be $expected',
          );
        }
      }
    });
  });
}
