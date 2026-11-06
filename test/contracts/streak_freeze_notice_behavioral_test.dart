// Slice U6 (ledger F8; diagnose a5e3c7): the BEHAVIORAL companion to
// `streak_freeze_notice_copy_test.dart` -- real Hive, the real writer
// (`StreakProgressService.commitConsume` / `commitRefill`), the real clearer
// (`UserRepository.clearStreakFreezeNotice`) and the real reader chain
// (`getProgress()` -> `streakFreezeNoticeFromProgress`).
//
// What this proves that the pure tests cannot: the WRITER's keys are the keys
// the READER consumes (writer/reader drift is the default suspect class here),
// a second debit before Home shows the notice is counted, a Monday refill that
// lands between the debit and the notice changes the number shown (the
// founder-visible "0 remaining" bug), and the clearer removes the notice
// without touching any other progress field.
//
// Run: flutter test test/contracts/streak_freeze_notice_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/copy/streak_freeze_copy.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('streak_freeze_notice_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.closeAll();
    await HiveUserSession.openForUser('cafeface-aaaa-bbbb-cccc-eeeeeeeeeeee');
    await HiveService.instance.userBox.clear();
  });

  Map<String, dynamic> progress() => Map<String, dynamic>.from(
      HiveService.instance.userBox.get('progress') as Map);

  String? notice() =>
      streakFreezeNoticeFromProgress(UserRepository.instance.getProgress());

  void seed(Map<String, dynamic> extra) =>
      HiveService.instance.userBox.put('progress', <String, dynamic>{
        'current_phase': 2,
        'total_workouts_done': 31,
        'streak_freezes_available': 2,
        'streak_freeze_used_dates': <String>[],
        ...extra,
      });

  group('writer -> reader: commitConsume then the notice', () {
    test('one debit: "1 used, live count left"', () {
      seed({});
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 1,
        usedDatesAfterConsume: const ['2026-10-05'],
        newlyConsumedDates: const ['2026-10-05'],
      );
      expect(progress()['streak_freeze_just_used'], isTrue);
      expect(progress()['streak_freeze_just_used_count'], 1);
      expect(notice(), 'Streak Freeze used on a missed day. 1 left.');
    });

    test(
        'a second debit BEFORE Home shows the notice is counted: 2 Streak '
        'Freezes, not 1', () {
      seed({});
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 1,
        usedDatesAfterConsume: const ['2026-10-03'],
        newlyConsumedDates: const ['2026-10-03'],
      );
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 0,
        usedDatesAfterConsume: const ['2026-10-03', '2026-10-05'],
        newlyConsumedDates: const ['2026-10-05'],
      );
      expect(progress()['streak_freeze_just_used_count'], 2);
      expect(
        notice(),
        '2 Streak Freezes used on missed days. None left. '
        'A new one arrives next Monday.',
      );
    });

    test('one walk that spends two dates counts both', () {
      seed({});
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 0,
        usedDatesAfterConsume: const ['2026-10-03', '2026-10-05'],
        newlyConsumedDates: const ['2026-10-03', '2026-10-05'],
      );
      expect(progress()['streak_freeze_just_used_count'], 2);
      expect(notice(), startsWith('2 Streak Freezes used on missed days.'));
    });

    test('a caller that passes no dates still counts one freeze', () {
      seed({});
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 1,
        usedDatesAfterConsume: const ['2026-10-05'],
      );
      expect(progress()['streak_freeze_just_used_count'], 1);
    });

    test(
        'an old flag with NO count (written by a pre-count build) reads as one '
        'and a new debit makes it two', () {
      seed({
        'streak_freeze_just_used': true,
        'streak_freeze_remaining_after_use': 1,
      });
      expect(notice(), 'Streak Freeze used on a missed day. 2 left.');
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 1,
        usedDatesAfterConsume: const ['2026-10-05'],
        newlyConsumedDates: const ['2026-10-05'],
      );
      expect(progress()['streak_freeze_just_used_count'], 2);
    });

    test(
        'STALE SNAPSHOT end to end: a freeze is spent with none left, the '
        'Monday refill lands before Home shows the notice -> "1 left", not '
        '"None left"', () {
      seed({'streak_freezes_available': 1});
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 0,
        usedDatesAfterConsume: const ['2026-10-05'],
        newlyConsumedDates: const ['2026-10-05'],
      );
      // The snapshot written at debit time says 0.
      expect(progress()['streak_freeze_remaining_after_use'], 0);
      StreakProgressService.instance.commitRefill(
        maxFreezes: 1,
        thisMondayStr: '2026-10-05',
      );
      // The live count is now 1; the snapshot is stale at 0.
      expect(progress()['streak_freezes_available'], 1);
      expect(progress()['streak_freeze_remaining_after_use'], 0);
      expect(notice(), 'Streak Freeze used on a missed day. 1 left.');
    });
  });

  group('writer tolerance: a bad stored count never drops the debit', () {
    test(
        'a string or NaN count behind a true flag: commitConsume still persists '
        'the freeze debit and the used date, and the count reads as 2', () {
      for (final bad in <Object>['two', double.nan]) {
        seed({
          'streak_freeze_just_used': true,
          'streak_freeze_just_used_count': bad,
          'streak_freezes_available': 2,
        });
        StreakProgressService.instance.commitConsume(
          freezesAvailableAfterConsume: 1,
          usedDatesAfterConsume: const ['2026-10-05'],
          newlyConsumedDates: const ['2026-10-05'],
        );
        final p = progress();
        expect(p['streak_freezes_available'], 1,
            reason: 'the debit itself must land with a $bad stored count');
        expect(p['streak_freeze_used_dates'], contains('2026-10-05'));
        expect(p['streak_freeze_just_used_count'], 2);
      }
    });
  });

  group('StreakProgressService.takeFreezeNotice: handed out ONCE', () {
    test('no debit pending: null, and nothing is written', () {
      seed({});
      final before = progress();
      expect(StreakProgressService.instance.takeFreezeNotice(), isNull);
      expect(progress(), before);
    });

    test(
        'a pending notice is returned by the first take and NOT by the second '
        '(initTab plus the background-restore listener can never both show it)',
        () {
      seed({});
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 1,
        usedDatesAfterConsume: const ['2026-10-05'],
        newlyConsumedDates: const ['2026-10-05'],
      );
      expect(StreakProgressService.instance.takeFreezeNotice(),
          'Streak Freeze used on a missed day. 1 left.');
      expect(StreakProgressService.instance.takeFreezeNotice(), isNull);
      expect(progress()['streak_freeze_just_used'], isFalse);
      expect(progress()['streak_freeze_just_used_count'], 0);
    });

    test('the text is built from the LIVE count at the moment of the take', () {
      seed({'streak_freezes_available': 1});
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 0,
        usedDatesAfterConsume: const ['2026-10-05'],
        newlyConsumedDates: const ['2026-10-05'],
      );
      StreakProgressService.instance
          .commitRefill(maxFreezes: 1, thisMondayStr: '2026-10-05');
      expect(StreakProgressService.instance.takeFreezeNotice(),
          'Streak Freeze used on a missed day. 1 left.');
    });

    test('a debit AFTER a take starts a new notice at one', () {
      seed({});
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 1,
        usedDatesAfterConsume: const ['2026-10-03'],
        newlyConsumedDates: const ['2026-10-03'],
      );
      StreakProgressService.instance.takeFreezeNotice();
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 0,
        usedDatesAfterConsume: const ['2026-10-03', '2026-10-05'],
        newlyConsumedDates: const ['2026-10-05'],
      );
      expect(
        StreakProgressService.instance.takeFreezeNotice(),
        'Streak Freeze used on a missed day. None left. '
        'A new one arrives next Monday.',
      );
    });

    test('with no progress map at all: null (and no map is minted)', () {
      // setUp cleared the box: there is no `progress` key.
      expect(HiveService.instance.userBox.get('progress'), isNull);
      expect(StreakProgressService.instance.takeFreezeNotice(), isNull);
      expect(HiveService.instance.userBox.get('progress'), isNull);
    });
  });

  group('UserRepository.clearStreakFreezeNotice', () {
    test('clears the flag, the count and the snapshot; the notice is gone',
        () async {
      seed({});
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 1,
        usedDatesAfterConsume: const ['2026-10-05'],
        newlyConsumedDates: const ['2026-10-05'],
      );
      expect(notice(), isNotNull);

      await UserRepository.instance.clearStreakFreezeNotice();

      final p = progress();
      expect(p['streak_freeze_just_used'], isFalse);
      expect(p['streak_freeze_just_used_count'], 0);
      expect(p['streak_freeze_remaining_after_use'], isNull);
      expect(notice(), isNull);
    });

    test('it is a DELTA: every other progress field survives', () async {
      seed({
        'streak_freeze_just_used': true,
        'streak_freeze_just_used_count': 2,
        'streak_freeze_remaining_after_use': 1,
        'streak_freezes_last_refill': '2026-10-05',
        'current_streak_weeks': 4,
      });
      await UserRepository.instance.clearStreakFreezeNotice();
      final p = progress();
      expect(p['current_phase'], 2);
      expect(p['total_workouts_done'], 31);
      expect(p['streak_freezes_available'], 2);
      expect(p['streak_freezes_last_refill'], '2026-10-05');
      expect(p['current_streak_weeks'], 4);
      expect(p['streak_freeze_used_dates'], isEmpty);
    });

    test('after a clear the NEXT debit starts again at one, not at the old '
        'count', () async {
      seed({});
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 1,
        usedDatesAfterConsume: const ['2026-10-03', '2026-10-04'],
        newlyConsumedDates: const ['2026-10-03', '2026-10-04'],
      );
      expect(progress()['streak_freeze_just_used_count'], 2);
      await UserRepository.instance.clearStreakFreezeNotice();

      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 0,
        usedDatesAfterConsume: const ['2026-10-03', '2026-10-04', '2026-10-05'],
        newlyConsumedDates: const ['2026-10-05'],
      );
      expect(progress()['streak_freeze_just_used_count'], 1);
      expect(
        notice(),
        'Streak Freeze used on a missed day. None left. '
        'A new one arrives next Monday.',
      );
    });

    test(
        'with no progress map yet, the clear writes NOTHING (it must not mint '
        'a default progress map just to hold three UI keys)', () async {
      await HiveService.instance.userBox.clear();
      await UserRepository.instance.clearStreakFreezeNotice();
      expect(HiveService.instance.userBox.get('progress'), isNull);
      expect(notice(), isNull);
    });

    test('showing then clearing twice never shows the notice twice', () async {
      seed({});
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 1,
        usedDatesAfterConsume: const ['2026-10-05'],
        newlyConsumedDates: const ['2026-10-05'],
      );
      final first = notice();
      await UserRepository.instance.clearStreakFreezeNotice();
      final second = notice();
      expect(first, isNotNull);
      expect(second, isNull);
    });
  });
}
