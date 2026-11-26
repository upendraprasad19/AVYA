// OI-348 P3 (docs/plans/oi348-landing3d.md): rescue a missed workout of this
// week into TODAY, when today is a rest day, through the one day-swap engine;
// a streak freeze spent on the missed day is given back.
//
// Behavioral: real Hive, the real engine, StreakProgressService and
// WorkoutRepository. Week of Mon 21 – Sun 27 Sep 2026; "today" is Fri 25.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_allowance.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_rules.dart';
import 'package:icanbefitter/core/services/day_swap/missed_day_rescue_flag.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/train/widgets/day_swap_drag_wrapper.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../../helpers/hive_test_setup.dart';

const mon = '2026-09-21';
const tue = '2026-09-22';
const wed = '2026-09-23';
const thu = '2026-09-24';
const fri = '2026-09-25'; // today
const sat = '2026-09-26';
const sun = '2026-09-27';
const nextMon = '2026-09-28';

// ignore: deprecated_member_use
SwapService get engine => SwapService.instance;

Map<String, dynamic> workout(String date, String name,
        {String status = 'planned'}) =>
    {
      'date': date,
      'week': 2,
      'phase': 3,
      'type': 'workout',
      'workout_name': name,
      'exercises': [
        {'exercise_name': '$name A', 'sets': 3}
      ],
      'status': status,
      'is_swapped': false,
      'original_date': null,
    };

Map<String, dynamic> rest(String date) => {
      'date': date,
      'week': 2,
      'phase': 3,
      'type': 'rest',
      'workout_name': 'Rest Day',
      'exercises': <Map<String, dynamic>>[],
      'status': 'rest',
    };

Future<void> put(String date, Map<String, dynamic> row) =>
    HiveService.instance.workoutBox.put('schedule_$date', row);

Map<String, dynamic>? row(String date) {
  final raw = HiveService.instance.workoutBox.get('schedule_$date');
  return raw is Map ? Map<String, dynamic>.from(raw) : null;
}

Future<void> progress({required int available, List<String> used = const []}) =>
    HiveService.instance.userBox.put('progress', {
      'streak_freezes_available': available,
      'streak_freeze_used_dates': used,
      'streak_freezes_last_refill': mon,
    });

Map<String, dynamic> prog() =>
    Map<String, dynamic>.from(UserRepository.instance.getProgress() ?? {});

List<String> ledger() =>
    (prog()['streak_freeze_used_dates'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();

void main() {
  late Directory dir;
  final nonFatals = <String>[];

  setUp(() async {
    dir = await setUpHiveForTests();
    setTestClockTo(DateTime.utc(2026, 9, 25, 4, 30)); // Fri 25, 10:00 IST
    nonFatals.clear();
    ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {};
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required reason, extra}) => nonFatals.add(reason);
    DaySwapAllowance.debugConsumeForTests = (_) async => null;
    SwapService.debugOnPlanPushForTests = () {};
    SwapService.debugSwapWriteForTests = null;
    SwapService.debugRecordSwapForTests = null;
    SwapService.debugSettleRefundsForTests = null;
    SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
    HiveUserSession.debugCurrentUidResolverForTests = null;
    await HiveService.instance.userBox.put('profile', {
      'id': 'A',
      'onboarding_completed_at': '2026-09-01T10:00:00Z',
    });
    await put(mon, workout(mon, 'Push', status: 'completed'));
    await put(tue, rest(tue));
    await put(wed, workout(wed, 'Legs')); // missed
    await put(thu, workout(thu, 'Calisthenics', status: 'completed'));
    await put(fri, rest(fri)); // today, a rest day
    await put(sat, workout(sat, 'Legs + Core'));
    await put(sun, rest(sun));
    await progress(available: 0);
  });

  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    DaySwapAllowance.debugConsumeForTests = null;
    SwapService.debugOnPlanPushForTests = null;
    SwapService.debugSwapWriteForTests = null;
    SwapService.debugRecordSwapForTests = null;
    SwapService.debugSettleRefundsForTests = null;
    SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
    HiveUserSession.debugCurrentUidResolverForTests = null;
    resetTestClock();
    await tearDownHiveForTests(dir);
  });

  Future<DaySwapResult> swap(String a, String b,
          {bool isPro = true,
          String? inProgress,
          DaySwapOrigin origin = DaySwapOrigin.trainPicker}) =>
      engine.swapDays(
          dateA: a,
          dateB: b,
          origin: origin,
          isPro: isPro,
          inProgressDate: inProgress);

  void expectRefused(DaySwapResult r, DaySwapRefusal reason, String date) {
    expect(r, isA<DaySwapRefused>());
    expect((r as DaySwapRefused).reason, reason);
    expect(r.date, date);
  }

  Map<String, DaySwapRefusal?> locks() => {
        for (final s in engine.weekStates(fri)) s.date: s.lock,
      };

  group('rescue rule', () {
    test('T1 missed Wed + rest today: swapped both ways, MOVED, marked, counted',
        () async {
      final r = await swap(wed, fri);
      expect(r, isA<DaySwapDone>());
      expect((r as DaySwapDone).allowanceAfter.used, 1);
      final w = row(wed)!;
      expect(w['type'], 'rest');
      expect(w['status'], 'rest');
      expect(DaySwapRules.isMoved(w), isTrue);
      expect(w[DaySwapRules.rescuedIntoKey], fri);
      final f = row(fri)!;
      expect(f['workout_name'], 'Legs');
      expect(f['status'], 'planned');
      expect(DaySwapRules.isMoved(f), isTrue);
      expect(f[DaySwapRules.rescuedIntoKey], isNull);
    });

    test('T1b the same pair in the other order', () async {
      final r = await swap(fri, wed);
      expect(r, isA<DaySwapDone>());
      expect(row(wed)![DaySwapRules.rescuedIntoKey], fri);
      expect(row(fri)!['workout_name'], 'Legs');
    });

    test('T1c B-pass F2: a day before the user had the app is never missed',
        () async {
      // Onboarded on Thu: the Wed plan row is a plan-generator artefact.
      await HiveService.instance.userBox.put('profile', {
        'id': 'A',
        'onboarding_completed_at': '2026-09-24T05:00:00Z',
      });
      expect(locks()[wed], DaySwapRefusal.past);
      final before = row(wed);
      expectRefused(await swap(wed, fri), DaySwapRefusal.past, wed);
      expect(row(wed), before);
      // The onboarding day itself is the anchor, not before it.
      await HiveService.instance.userBox.put('profile', {
        'id': 'A',
        'onboarding_completed_at': '2026-09-23T05:00:00Z',
      });
      expect(locks()[wed], isNull);
    });

    test('T2 today is a workout day: refused past, nothing written', () async {
      await put(fri, workout(fri, 'Pull'));
      final before = row(wed);
      expectRefused(await swap(wed, fri), DaySwapRefusal.past, wed);
      expect(row(wed), before);
      expect(DaySwapAllowance.instance.current(mon, isPro: true).used, 0);
    });

    test('T2b today is a rest HYBRID (status rest, workout type): refused',
        () async {
      await put(fri, {
        'date': fri,
        'type': 'workout',
        'workout_name': 'Pull',
        'exercises': <Map<String, dynamic>>[],
        'status': 'rest',
      });
      expectRefused(await swap(wed, fri), DaySwapRefusal.past, wed);
    });

    test('T3 partner is not today (rest Sun): refused past', () async {
      expectRefused(await swap(wed, sun), DaySwapRefusal.past, wed);
      expectRefused(await swap(sun, wed), DaySwapRefusal.past, wed);
    });

    test('T3b the coach gets no rescue', () async {
      expectRefused(await swap(wed, fri, origin: DaySwapOrigin.coach),
          DaySwapRefusal.past, wed);
    });

    test('T-P preview follows the origin', () {
      expect(
          engine
              .preview(
                  dateA: wed,
                  dateB: fri,
                  isPro: true,
                  origin: DaySwapOrigin.coach)
              .refusal,
          DaySwapRefusal.past);
      expect(
          engine
              .preview(
                  dateA: wed,
                  dateB: fri,
                  isPro: true,
                  origin: DaySwapOrigin.trainPicker)
              .refusal,
          isNull);
    });

    test('T4 an exercise log on Wed: refused', () async {
      await HiveService.instance.workoutBox.put(
          WorkoutWriteService.exlogKey(DaySwapRules.utcDate(wed), 'Squat'),
          {'exercise_name': 'Squat', 'date': wed});
      expectRefused(await swap(wed, fri), DaySwapRefusal.past, wed);
    });

    test('T4w only a wlog_ on Wed: refused', () async {
      await HiveService.instance.workoutBox.put(
          WorkoutWriteService.wlogKey(DaySwapRules.utcDate(wed)),
          {'date': wed, 'workout_name': 'Legs'});
      expectRefused(await swap(wed, fri), DaySwapRefusal.past, wed);
    });

    test('T4b a session in progress on Wed: refused', () async {
      expectRefused(
          await swap(wed, fri, inProgress: wed), DaySwapRefusal.past, wed);
    });

    test('T5 a past rest day / a past done day stay put', () async {
      expectRefused(await swap(tue, fri), DaySwapRefusal.past, tue);
      expectRefused(await swap(mon, fri), DaySwapRefusal.completed, mon);
    });

    test('T6 a free week whose swap is spent: allowanceSpent', () async {
      expect(await swap(sat, sun, isPro: false), isA<DaySwapDone>());
      expectRefused(await swap(wed, fri, isPro: false),
          DaySwapRefusal.allowanceSpent, wed);
    });

    test('T-K kill switch: every state and answer is the old one', () async {
      await HiveService.instance.configBox
          .put(kDisableMissedDayRescueKey, true);
      expect(locks()[wed], DaySwapRefusal.past);
      expect(locks()[mon], DaySwapRefusal.completed);
      expect(
          engine.preview(dateA: wed, dateB: fri, isPro: true).refusal,
          DaySwapRefusal.past);
      await progress(available: 0, used: [wed]);
      expectRefused(await swap(wed, fri), DaySwapRefusal.past, wed);
      expect(row(wed)![DaySwapRules.rescuedIntoKey], isNull);
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          0);
      expect(ledger(), [wed]);
    });
  });

  group('week states (picker / Train)', () {
    test('T-W a missed day is movable only while today hosts a rescue', () async {
      final l = locks();
      expect(l[wed], isNull);
      expect(l[tue], DaySwapRefusal.past);
      expect(l[mon], DaySwapRefusal.completed);
      expect(l[thu], DaySwapRefusal.completed);
      await put(fri, workout(fri, 'Pull'));
      expect(locks()[wed], DaySwapRefusal.past);
    });

    test('T-W preview names the same refusal the swap gives', () async {
      // not a host
      await put(fri, workout(fri, 'Pull'));
      expect(engine.preview(dateA: wed, dateB: fri, isPro: true).refusal,
          (await swap(wed, fri) as DaySwapRefused).reason);
      await put(fri, rest(fri));
      // a pair without today
      expect(engine.preview(dateA: sat, dateB: wed, isPro: true).refusal,
          (await swap(sat, wed) as DaySwapRefused).reason);
      // logs on Wed
      await HiveService.instance.workoutBox.put(
          WorkoutWriteService.wlogKey(DaySwapRules.utcDate(wed)), {'date': wed});
      expect(engine.preview(dateA: wed, dateB: fri, isPro: true).refusal,
          (await swap(wed, fri) as DaySwapRefused).reason);
      await HiveService.instance.workoutBox
          .delete(WorkoutWriteService.wlogKey(DaySwapRules.utcDate(wed)));
      // allowance spent
      expect(await swap(sat, sun, isPro: false), isA<DaySwapDone>());
      expect(engine.preview(dateA: wed, dateB: fri, isPro: false).refusal,
          (await swap(wed, fri, isPro: false) as DaySwapRefused).reason);
    });
  });

  group('freeze refund', () {
    test('T7 a freeze spent on Wed comes back with the rescue', () async {
      await progress(available: 0, used: [wed]);
      final r = await swap(wed, fri, isPro: false);
      expect((r as DaySwapDone).freezeRefunded, isTrue);
      expect(prog()['streak_freezes_available'], 1);
      expect(ledger(), containsAll([wed, FreezeLedger.marker(wed)]));
    });

    test('T7b nothing spent on Wed: nothing given', () async {
      final r = await swap(wed, fri, isPro: false);
      expect((r as DaySwapDone).freezeRefunded, isFalse);
      expect(prog()['streak_freezes_available'], 0);
      expect(ledger(), isEmpty);
    });

    test('T7c the derived refund is idempotent', () async {
      await progress(available: 0, used: [wed]);
      await swap(wed, fri, isPro: false);
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          0);
      expect(prog()['streak_freezes_available'], 1);
      expect(ledger().where((e) => e == FreezeLedger.marker(wed)).length, 1);
    });

    test('T7d a refund that throws never fails the swap; the rollover heals it',
        () async {
      await progress(available: 0, used: [wed]);
      SwapService.debugSettleRefundsForTests =
          ({required bool isPro}) => throw StateError('boom');
      final r = await swap(wed, fri, isPro: false);
      expect(r, isA<DaySwapDone>());
      expect((r as DaySwapDone).freezeRefunded, isFalse);
      expect(nonFatals, contains('day_swap_freeze_refund_threw'));
      expect(prog()['streak_freezes_available'], 0);
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          1);
      expect(prog()['streak_freezes_available'], 1);
    });

    test('T7e capped by tier, never raised above it', () async {
      await progress(available: 2, used: [wed]);
      expect(((await swap(wed, fri)) as DaySwapDone).freezeRefunded, isTrue);
      expect(prog()['streak_freezes_available'], 3);
    });

    test('T7e2 already at the cap: nothing given, NOT marked, no refund toast',
        () async {
      await progress(available: 1, used: [wed]);
      final r = await swap(wed, fri, isPro: false);
      expect((r as DaySwapDone).freezeRefunded, isFalse);
      expect(prog()['streak_freezes_available'], 1);
      // B-pass F6a: a date the cap held back stays owed (no marker).
      expect(ledger(), isNot(contains(FreezeLedger.marker(wed))));
    });

    test('T7e3 a refund the cap (or a tier misread) held back is paid later',
        () async {
      await progress(available: 2, used: [wed]);
      // The rollover heal reads a PRO user as free: cap 1, nothing given.
      await swap(wed, fri, isPro: true);
      // swapDays settled with the right tier already; reset to the misread.
      await progress(available: 2, used: [wed]);
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          0);
      expect(ledger(), isNot(contains(FreezeLedger.marker(wed))));
      // The next settle with the tier read right still pays it, once.
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: true),
          1);
      expect(prog()['streak_freezes_available'], 3);
      expect(ledger(), contains(FreezeLedger.marker(wed)));
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: true),
          0);
    });

    test('T7e4 two owed dates, room for one: only the paid date is marked',
        () async {
      await put(tue, {...rest(tue), DaySwapRules.rescuedIntoKey: thu});
      await put(wed, {...rest(wed), DaySwapRules.rescuedIntoKey: fri});
      await progress(available: 0, used: [tue, wed]);
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          1);
      final marks = ledger().where(FreezeLedger.isMarker).toList();
      expect(marks, [FreezeLedger.marker(tue)]);
    });

    test('T7f a rescued day of LAST week is never refunded on the new week',
        () async {
      await swap(wed, fri, isPro: false); // nothing spent yet
      await progress(available: 0, used: [wed]);
      setTestClockTo(DateTime.utc(2026, 9, 28, 4, 30)); // Mon 28
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          0);
      setTestClockTo(DateTime.utc(2026, 9, 26, 4, 30)); // Sat 26, same week
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          1);
      expect(nextMon, isNotEmpty);
    });

    test('T7g the row SHAPE alone (no rescued_into) earns nothing', () async {
      await put(wed, {
        ...rest(wed),
        'is_swapped': true,
        'original_date': fri,
      });
      await progress(available: 0, used: [wed]);
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          0);
    });

    test('T7h a copy of a rescued row in ANOTHER week earns nothing', () async {
      // rescued_into is never re-dated, so a copy lands in a week its own
      // rescued_into is not in (and earlier than the copy's date).
      setTestClockTo(DateTime.utc(2026, 10, 2, 4, 30)); // Fri 2 Oct
      const wedNext = '2026-09-30';
      await put(wedNext, {
        ...rest(wedNext),
        'is_swapped': true,
        'original_date': '2026-10-02',
        DaySwapRules.rescuedIntoKey: fri,
      });
      await progress(available: 0, used: [wedNext]);
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          0);
    });

    test('T7i B-pass F1: a rescue that sends swapped content HOME is refunded',
        () async {
      // Tue: the user swapped a rest Wed with a workout Fri (PRO, 3 a week).
      setTestClockTo(DateTime.utc(2026, 9, 22, 4, 30)); // Tue 22
      await put(wed, rest(wed));
      await put(fri, workout(fri, 'Pull'));
      expect(await swap(wed, fri), isA<DaySwapDone>());
      expect(row(wed)!['workout_name'], 'Pull');
      // Fri: the Pull on Wed was missed and a freeze covered Wed.
      setTestClockTo(DateTime.utc(2026, 9, 25, 4, 30)); // Fri 25
      await progress(available: 0, used: [wed]);
      final r = await swap(wed, fri);
      expect(r, isA<DaySwapDone>());
      // Both contents are home again, so neither carries the swap markers...
      final w = row(wed)!;
      expect(w['type'], 'rest');
      expect(w['is_swapped'], isNot(true));
      expect(w[DaySwapRules.rescuedIntoKey], fri);
      expect(row(fri)!['workout_name'], 'Pull');
      // ...and the freeze still comes back.
      expect((r as DaySwapDone).freezeRefunded, isTrue);
      expect(prog()['streak_freezes_available'], 1);
      expect(ledger(), contains(FreezeLedger.marker(wed)));
    });
  });

  // B-pass seat B (mutation lens): one test per surviving mutant.
  group('B-pass seat B survivors', () {
    Future<void> rescued(String d, {String into = fri, String type = 'rest'}) =>
        put(d, {
          ...(type == 'rest' ? rest(d) : workout(d, 'X')),
          DaySwapRules.rescuedIntoKey: into,
        });

    test('M03/M31 drag target: a missed day pairs only with today', () async {
      bool ok(String lifted, String date) => DaySwapDragWrapper.dropTargetValid(
          movable: true, lifted: lifted, date: date, today: fri);
      expect(ok(wed, fri), isTrue);
      expect(ok(fri, wed), isTrue);
      expect(ok(sat, wed), isFalse);
      expect(ok(wed, sat), isFalse);
      expect(ok(sat, sun), isTrue);
      expect(DaySwapDragWrapper.dropTargetValid(
              movable: false, lifted: wed, date: fri, today: fri),
          isFalse);
      // Kill switch: no pair rule (the old drag: any movable day).
      await HiveService.instance.configBox
          .put(kDisableMissedDayRescueKey, true);
      expect(ok(sat, wed), isTrue);
      expect(ok(wed, sat), isTrue);
    });

    test('M30 kill switch: a rescued row earns nothing, ledger untouched',
        () async {
      await rescued(wed);
      await progress(available: 0, used: [wed]);
      await HiveService.instance.configBox
          .put(kDisableMissedDayRescueKey, true);
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          0);
      expect(ledger(), [wed]);
      expect(prog()['streak_freezes_available'], 0);
      // Mirror: the same state with the switch off pays.
      await HiveService.instance.configBox.delete(kDisableMissedDayRescueKey);
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          1);
    });

    test('M14 a count above the cap (tier misread) is never lowered', () async {
      await rescued(wed);
      await progress(available: 3, used: [wed]);
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          0);
      expect(prog()['streak_freezes_available'], 3);
    });

    test('M07 a freeze spent on MONDAY and rescued is refunded', () async {
      await rescued(mon, into: wed);
      await progress(available: 0, used: [mon]);
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          1);
      expect(ledger(), contains(FreezeLedger.marker(mon)));
    });

    test('M11 a row carrying rescued_into that is not rest earns nothing',
        () async {
      await rescued(wed, type: 'workout');
      await progress(available: 0, used: [wed]);
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          0);
    });

    test('M13 rescued_into in another week earns nothing', () async {
      await rescued(wed, into: nextMon);
      await progress(available: 0, used: [wed]);
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          0);
    });

    test('M46 the unshown freeze notice drops by the freezes given back',
        () async {
      await rescued(wed);
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 0,
        'streak_freeze_used_dates': [tue, wed],
        'streak_freezes_last_refill': mon,
        'streak_freeze_just_used': true,
        'streak_freeze_just_used_count': 2,
      });
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          1);
      expect(prog()['streak_freeze_just_used_count'], 1);
      expect(prog()['streak_freeze_just_used'], isTrue);
    });

    // M42 (drop the same-week test in _weekHostsRescue) is equivalent: weekStates
    // reads today's row from that week's own map (null outside it) and an engine
    // pair is same-week; this pins the behaviour anyway.
    test('M42 last week keeps the old past lock while today hosts', () async {
      const lastWed = '2026-09-16';
      await put(lastWed, workout(lastWed, 'Legs'));
      final last = {
        for (final st in engine.weekStates(lastWed)) st.date: st.lock,
      };
      expect(last[lastWed], DaySwapRefusal.past);
      expect(locks()[wed], isNull); // this week's missed day is movable
    });

    test('M44 today type rest but status planned is not a host', () async {
      await put(fri, {...rest(fri), 'status': 'planned'});
      expect(locks()[wed], DaySwapRefusal.past);
      expectRefused(await swap(wed, fri), DaySwapRefusal.past, wed);
    });
  });

  group('streak after a rescue', () {
    void openRestoreGate() {
      HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
      SyncService.instance.debugSetRestoreSettledUserIdForTest(kTestUserId);
    }

    test('T8 the rescued day counts as rest: a chain it broke is whole again',
        () async {
      expect(WorkoutRepository.instance.currentStreak(), 1); // Thu, then Wed breaks
      openRestoreGate();
      final r = await swap(wed, fri, isPro: false);
      expect(r, isA<DaySwapDone>());
      expect(WorkoutRepository.instance.currentStreak(), 2); // Thu + Mon
      expect(prog()['current_streak_days'], 2); // persisted by the reckon
      expect(prog()['streak_freezes_available'], 0); // nothing spent
    });

    test('T8b a restore that re-plants Wed spends nothing and refunds nothing more',
        () async {
      await progress(available: 0, used: [wed]);
      await swap(wed, fri, isPro: false);
      expect(prog()['streak_freezes_available'], 1);
      await put(wed, workout(wed, 'Legs')); // stale restore
      openRestoreGate();
      WorkoutRepository.instance.reckonStreakDecayAndPersist();
      expect(prog()['streak_freezes_available'], 1);
      expect(StreakProgressService.instance.settleRescueRefunds(isPro: false),
          0);
    });
  });
}
