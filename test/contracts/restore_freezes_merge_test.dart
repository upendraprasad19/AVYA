// test/contracts/restore_freezes_merge_test.dart
//
// a8f3d1 — _restoreFreezes used to UNCONDITIONALLY overwrite
// streak_freeze_used_dates with the cloud snapshot (only the available/
// last_refill legs had a merge guard, 9c4a17). The slow-boot flip (ADR-0014)
// lands /home BEFORE restore Step C, so a freeze consumed locally during the
// background-restore window (not yet synced) was wiped + the freeze refunded →
// spurious streak break. Fix: refill-aware merge — same week UNION used_dates +
// take the LOWER available; cloud-refill-newer → cloud; local-refill-newer →
// local + sync up. Pure function, behaviorally tested here.
//
// D1 (f9d2e7): used_dates is now a PERMANENT ledger (commitRefill prunes >365d,
// never clears) so used_dates is ALWAYS the union of BOTH sides -- even on the
// newer-refill branches that previously dropped the older side. The weekly
// BUDGET (available / last_refill) still follows the newer refill. The two
// newer-refill cases below assert the union (pre-D1 they expected empty).
//
// closes-diagnose: a8f3d1, f9d2e7
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';

void main() {
  FreezeMergeResult merge({
    required int la,
    required List<String> lu,
    required String? ll,
    required int ca,
    required List<String> cu,
    required String? cl,
  }) =>
      StreakProgressService.mergeFreezeProgress(
        localAvailable: la,
        localUsed: lu,
        localLastRefill: ll,
        cloudAvailable: ca,
        cloudUsed: cu,
        cloudLastRefill: cl,
      );

  group('mergeFreezeProgress — refill-aware restore merge (a8f3d1)', () {
    test('THE BUG: same week, local consumed a freeze cloud has not seen → '
        'the consume survives + the freeze is NOT refunded', () {
      // local: consumed 2026-06-09 this week (avail 3→2). cloud: stale snapshot
      // from before the consume synced (avail 3, used []). same last_refill.
      final r = merge(
        la: 2, lu: ['2026-06-09'], ll: '2026-06-08',
        ca: 3, cu: const [], cl: '2026-06-08',
      );
      expect(r.usedDates, ['2026-06-09'],
          reason: 'the locally-consumed date must NOT be wiped by cloud');
      expect(r.available, 2, reason: 'must not refund the freeze to 3');
      expect(r.scheduleSyncUp, isFalse);
    });

    test('same week, two different-day consumes (cross-device) → union both', () {
      final r = merge(
        la: 2, lu: ['2026-06-09'], ll: '2026-06-08',
        ca: 2, cu: ['2026-06-10'], cl: '2026-06-08',
      );
      expect(r.usedDates, ['2026-06-09', '2026-06-10']);
      expect(r.available, 2, reason: 'lower available (conservative)');
    });

    test('cloud refill strictly newer → cloud BUDGET, but used_dates UNIONS '
        'the local historical freeze (D1 permanent ledger)', () {
      final r = merge(
        la: 1, lu: ['2026-06-02'], ll: '2026-06-01',
        ca: 3, cu: const [], cl: '2026-06-08',
      );
      expect(r.available, 3, reason: 'cloud is the newer-week budget');
      expect(r.usedDates, ['2026-06-02'],
          reason: 'D1: never drop a historically-frozen day, even when cloud '
              'refill is newer (pre-D1 this returned empty)');
      expect(r.lastRefill, '2026-06-08');
      expect(r.scheduleSyncUp, isFalse);
    });

    test('local refill strictly newer → local BUDGET + sync up, used_dates '
        'UNIONS the cloud historical freeze (D1 permanent ledger)', () {
      final r = merge(
        la: 3, lu: const [], ll: '2026-06-08',
        ca: 1, cu: ['2026-06-02'], cl: '2026-06-01',
      );
      expect(r.available, 3, reason: 'local is the newer-week budget');
      expect(r.usedDates, ['2026-06-02'],
          reason: 'D1: keep the cloud-side historical freeze (pre-D1 empty)');
      expect(r.lastRefill, '2026-06-08');
      expect(r.scheduleSyncUp, isTrue, reason: 'push the newer local up to cloud');
    });

    test('D1 permanent ledger: newer-refill branch unions used_dates from BOTH '
        'weeks (never drops the older side)', () {
      // local is the newer week (06-08) AND consumed 06-09; cloud is an older
      // week (06-01) that recorded a freeze on 06-02. The permanent ledger must
      // keep BOTH — pre-D1 the local-newer branch returned only local's list.
      final r = merge(
        la: 2, lu: ['2026-06-09'], ll: '2026-06-08',
        ca: 1, cu: ['2026-06-02'], cl: '2026-06-01',
      );
      expect(r.usedDates, ['2026-06-02', '2026-06-09'],
          reason: 'union of both weeks, sorted');
      expect(r.available, 2, reason: 'local newer-week budget');
      expect(r.scheduleSyncUp, isTrue);
    });

    test('cloud last_refill null → local wins + sync up', () {
      final r = merge(
        la: 2, lu: ['2026-06-09'], ll: '2026-06-08',
        ca: 1, cu: const [], cl: null,
      );
      expect(r.usedDates, ['2026-06-09']);
      expect(r.available, 2);
      expect(r.scheduleSyncUp, isTrue);
    });

    test('available is clamped to 0..3', () {
      final r = merge(
        la: 9, lu: const [], ll: '2026-06-08',
        ca: 9, cu: const [], cl: '2026-06-08',
      );
      expect(r.available, 3);
    });
  });
}
