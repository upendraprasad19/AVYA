// OI-348 P3 (docs/plans/oi348-landing3d.md §3.4): the freeze ledger's
// `refund:<date>` marker and the merge that must count it. The old rule (same
// week: LOWER count, UNION ledger) "never refunds a freeze", so without the
// marker a legitimate refund is undone by every restore / push conflict.
//
// Pure tests of StreakProgressService.mergeFreezeProgress / FreezeLedger /
// prunePastHorizon, a sequence simulator over every interleaving of a fixed
// two-device event set (MS1-MS3), and UserRepository.mergeCloudProgress's
// grant carry (M8, real Hive for its kill-switch reads).
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

const m1 = '2026-09-21'; // a Monday (last_refill)
const m2 = '2026-09-28'; // the next Monday
const wed = '2026-09-23';
const thu = '2026-09-24';
const wed2 = '2026-09-30';
String r(String d) => FreezeLedger.marker(d);

typedef S = ({int a, List<String> u, String? lr});

FreezeMergeResult merge(S local, S cloud) =>
    StreakProgressService.mergeFreezeProgress(
      localAvailable: local.a,
      localUsed: local.u,
      localLastRefill: local.lr,
      cloudAvailable: cloud.a,
      cloudUsed: cloud.u,
      cloudLastRefill: cloud.lr,
    );

/// The rule before OI-348 P3, verbatim, as the oracle for MS1 / MS3 / M6.
int oldAvailable(S local, S cloud) {
  int clamp3(int v) => v.clamp(0, 3);
  if (local.lr != null && cloud.lr != null && local.lr == cloud.lr) {
    return clamp3(local.a < cloud.a ? local.a : cloud.a);
  }
  final cloudWins = local.lr == null ||
      (cloud.lr != null && cloud.lr!.compareTo(local.lr!) > 0);
  return clamp3(cloudWins ? cloud.a : local.a);
}

S asState(FreezeMergeResult m) =>
    (a: m.available, u: List<String>.of(m.usedDates), lr: m.lastRefill);

void main() {
  group('merge rule', () {
    test('M1 cloud never saw the spend: the refund stands, and is pushed', () {
      final m = merge((a: 1, u: [wed, r(wed)], lr: m1), (a: 1, u: [], lr: m1));
      expect(m.available, 1);
      expect(m.usedDates, containsAll([wed, r(wed)]));
      expect(m.scheduleSyncUp, isTrue);
    });

    test('M2 cloud saw the spend, not the refund: the refund stands', () {
      final m =
          merge((a: 1, u: [wed, r(wed)], lr: m1), (a: 0, u: [wed], lr: m1));
      expect(m.available, 1); // the old rule gave 0
      expect(oldAvailable((a: 1, u: [wed, r(wed)], lr: m1),
              (a: 0, u: [wed], lr: m1)),
          0);
      // and the other way round
      expect(
          merge((a: 0, u: [wed], lr: m1), (a: 1, u: [wed, r(wed)], lr: m1))
              .available,
          1);
    });

    test('M3 a side that never debited the spend is never raised', () {
      // device B spent Thu, never saw Wed; cloud spent+refunded Wed.
      final m = merge((a: 0, u: [thu], lr: m1), (a: 1, u: [wed, r(wed)], lr: m1));
      expect(m.available, 0);
    });

    test('M4 cloud refill newer: +1 only when the cloud holds the date', () {
      expect(
          merge((a: 1, u: [wed2, r(wed2)], lr: m1), (a: 0, u: [wed2], lr: m2))
              .available,
          1);
      expect(
          merge((a: 1, u: [wed2, r(wed2)], lr: m1), (a: 1, u: [], lr: m2))
              .available,
          1);
      expect(
          merge((a: 0, u: [wed2, r(wed2)], lr: m1), (a: 0, u: [], lr: m2))
              .available,
          0);
    });

    test('M4b local refill newer + a cloud-only marker on a date local holds', () {
      final m =
          merge((a: 0, u: [wed2], lr: m2), (a: 1, u: [wed2, r(wed2)], lr: m1));
      expect(m.available, 1);
      expect(m.scheduleSyncUp, isTrue);
    });

    test('M5 a marker older than the side\'s last_refill never raises it', () {
      final m = merge((a: 0, u: [wed], lr: m2), (a: 2, u: [wed, r(wed)], lr: m2));
      expect(m.available, 0);
    });

    test('M6 with no markers every branch is the old rule', () {
      final cases = <(S, S)>[
        ((a: 1, u: [wed], lr: m1), (a: 0, u: [thu], lr: m1)),
        ((a: 2, u: [], lr: m1), (a: 3, u: [wed], lr: m2)),
        ((a: 3, u: [wed], lr: m2), (a: 1, u: [], lr: m1)),
        ((a: 1, u: [], lr: null), (a: 1, u: [], lr: null)),
        ((a: 0, u: [wed, thu], lr: null), (a: 2, u: [], lr: m1)),
        ((a: 5, u: [], lr: m1), (a: 4, u: [], lr: m1)),
      ];
      for (final (l, c) in cases) {
        final m = merge(l, c);
        expect(m.available, oldAvailable(l, c), reason: '$l / $c');
        expect(m.usedDates, ({...l.u, ...c.u}.toList()..sort()));
      }
    });

    test('M-cap a free side is never raised past its pre-spend count', () {
      final m = merge((a: 1, u: [wed, r(wed)], lr: m1), (a: 0, u: [wed], lr: m1));
      expect(m.available, lessThanOrEqualTo(1));
    });
  });

  group('ledger', () {
    test('FreezeLedger splits plain dates from markers', () {
      final l = [wed, r(wed), thu];
      expect(FreezeLedger.dates(l), [wed, thu]);
      expect(FreezeLedger.refunds(l), {wed});
      expect(FreezeLedger.dateOf(r(wed)), wed);
    });

    test('M7 prune keeps or drops a marker by ITS date', () {
      setTestClockTo(DateTime.utc(2026, 9, 25, 4, 30));
      addTearDown(resetTestClock);
      final pruned = StreakProgressService.prunePastHorizon(
          ['2024-01-01', r('2024-01-01'), wed, r(wed)]);
      expect(pruned, containsAll([wed, r(wed)]));
      expect(pruned, isNot(contains(r('2024-01-01'))));
      expect(pruned, isNot(contains('2024-01-01')));
    });
  });

  group('sequences (two devices + cloud)', () {
    // A device event: spend a day, refund (rescue) a day, or sync (push with
    // the conflict-retry merge, modelled: cloud and device both take
    // merge(device, cloud) — the retry's first merge and its write-back
    // merge against the just-confirmed state agree, MS2). Events are strings
    // `<device>:<kind>[:<date>]`.

    List<List<String>> interleavings(List<String> x, List<String> y) {
      if (x.isEmpty) return [y];
      if (y.isEmpty) return [x];
      return [
        for (final rest in interleavings(x.sublist(1), y)) [x.first, ...rest],
        for (final rest in interleavings(x, y.sublist(1))) [y.first, ...rest],
      ];
    }

    void run({required bool withRefund}) {
      final xEvents = [
        'X:spend:$wed',
        if (withRefund) 'X:refund:$wed',
        'X:sync',
      ];
      final yEvents = ['Y:spend:$thu', 'Y:sync'];
      final all = interleavings(xEvents, yEvents);
      expect(all, isNotEmpty);
      for (final seq in all) {
        final dev = <String, S>{
          'X': (a: 3, u: <String>[], lr: m1),
          'Y': (a: 3, u: <String>[], lr: m1),
        };
        S cloud = (a: 3, u: <String>[], lr: m1);
        var refundsGiven = 0;
        void sync(String d) {
          final a = dev[d]!;
          final m = merge(a, cloud);
          final old = oldAvailable(a, cloud);
          final markers = FreezeLedger.refunds([...a.u, ...cloud.u]).length;
          // MS1: never more than the old rule plus the distinct markers.
          expect(m.available, lessThanOrEqualTo(old + markers),
              reason: '$seq at sync $d');
          // MS3: no markers -> exactly the old rule.
          if (markers == 0) {
            expect(m.available, old, reason: '$seq at sync $d');
          }
          // MS2 idempotent and symmetric (same week).
          final again = merge(asState(m), cloud);
          expect(again.available, m.available, reason: '$seq idempotent');
          expect(again.usedDates.toSet(), m.usedDates.toSet());
          final swapped = merge(cloud, a);
          expect(swapped.available, m.available, reason: '$seq symmetric');
          expect(swapped.usedDates.toSet(), m.usedDates.toSet());
          cloud = asState(m);
          dev[d] = asState(m);
        }

        for (final e in [...seq, 'X:sync', 'Y:sync', 'X:sync']) {
          final p = e.split(':');
          final d = p[0];
          final s = dev[d]!;
          switch (p[1]) {
            case 'spend':
              dev[d] = (a: s.a - 1, u: [...s.u, p[2]], lr: s.lr);
            case 'refund':
              if (s.u.contains(p[2]) && !s.u.contains(r(p[2]))) {
                refundsGiven++;
                dev[d] = (a: s.a + 1, u: [...s.u, r(p[2])], lr: s.lr);
              }
            case 'sync':
              sync(d);
          }
        }
        // One refund per date, ever.
        expect(refundsGiven, lessThanOrEqualTo(1));
        expect(cloud.u.where((e) => e == r(wed)).length,
            lessThanOrEqualTo(1));
        // Settled: both devices agree with the cloud.
        expect(dev['X']!.a, cloud.a, reason: '$seq settled');
        expect(dev['Y']!.a, cloud.a, reason: '$seq settled');
        if (withRefund) {
          // Wed refunded, Thu spent: 3 - 1 = 2 once both are seen.
          expect(cloud.a, 2, reason: '$seq');
        }
      }
    }

    test('MS1-MS3 every interleaving with a rescue refund', () {
      run(withRefund: true);
    });

    test('MS3 every interleaving without a refund equals the old rule', () {
      run(withRefund: false);
    });
  });

  group('M8 progress-restore grant carry', () {
    late Directory dir;
    setUp(() async => dir = await setUpHiveForTests());
    tearDown(() async => tearDownHiveForTests(dir));

    test('a refunded date is not counted as a spend the cloud has not seen', () {
      final res = UserRepository.mergeCloudProgress(
        local: {
          'streak_freezes_available': 1,
          'streak_freeze_used_dates': [wed, r(wed)],
          'streak_freezes_last_refill': m1,
          'streak_freezes_first_pro_grant_done': false,
        },
        cloud: {
          'streak_freezes_available': 3,
          'streak_freezes_used_dates': <String>[],
          'streak_freezes_last_refill': m1,
          'streak_freezes_first_pro_grant_done': true,
        },
        istToday: '2026-09-25',
      );
      // grant 3, Wed spent and given back: 3 (counting the date or the marker
      // as a spend gave 2 or 1).
      expect(res.merged['streak_freezes_available'], 3);
      expect(res.scheduleFreezeSyncUp, isTrue); // the marker goes up
      // A second round against what was pushed settles (no push loop).
      final again = UserRepository.mergeCloudProgress(
        local: Map<String, dynamic>.from(res.merged),
        cloud: {
          'streak_freezes_available': res.merged['streak_freezes_available'],
          'streak_freezes_used_dates': res.merged['streak_freeze_used_dates'],
          'streak_freezes_last_refill': m1,
          'streak_freezes_first_pro_grant_done': true,
        },
        istToday: '2026-09-25',
      );
      expect(again.scheduleFreezeSyncUp, isFalse);
      expect(again.merged['streak_freezes_available'], 3);
    });
  });
}
