// test/contracts/last_workout_date_latest_wins_behavioral_test.dart
//
// Slice C1 (streak-freeze-restore-ownership addendum A, ledger LAST-WORKOUT-DATE).
//
// WHAT WAS WRONG. `user_progress.last_workout_date` is written by exactly one
// runtime writer (`train_provider.completeWorkout`) and restored by the generic
// cloud-non-null-wins branch of `UserRepository.mergeCloudProgress`. A device
// that had finished a workout and not yet pushed was handed an OLDER cloud date
// by its own restore, and the next push wrote that regression back to the
// cloud. The rank engine (`evaluate-rank-promotions`) reads this date, so a
// regressed value can block a rung.
//
// THE FIX HERE is the CLIENT half: `laterIsoDate` (pure, latest-wins, a date
// later than IST-today + 1 is malformed) and its use in `mergeCloudProgress`,
// with an independent kill switch `disable_progress_date_merge`. The server half
// (the RPC's GREATEST / clamp) is a migration, pinned by its own test.
//
// Run: flutter test test/contracts/last_workout_date_latest_wins_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

const String _today = '2026-10-07';

IsoDateMerge _m(Object? local, Object? cloud, {String today = _today}) =>
    laterIsoDate(local, cloud, istToday: today);

ProgressMergeResult _merge(
  Map<String, dynamic> local,
  Map<String, dynamic> cloud, {
  String today = _today,
}) =>
    UserRepository.mergeCloudProgress(
        local: local, cloud: cloud, istToday: today);

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('last_workout_date_');
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
    await HiveUserSession.openForUser('d47e0000-1111-4444-8888-0f18d5c0ffee');
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    ErrorTelemetry.debugOnLogEventForTests = null;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    await HiveService.instance.configBox.clear();
  });

  group('laterIsoDate: the pure table', () {
    test('equal dates: nothing to write, nothing declined', () {
      final o = _m('2026-10-05', '2026-10-05');
      expect(o.write, isFalse);
      expect(o.declined, isFalse);
      expect(o.malformed, isFalse);
    });

    test('LATER LOCAL beats an earlier cloud date and is a DECLINE', () {
      final o = _m('2026-10-06', '2026-10-05');
      expect(o.write, isFalse, reason: 'local stands');
      expect(o.declined, isTrue);
      expect(o.malformed, isFalse);
    });

    test('MIRROR: a later CLOUD date wins and is not a decline', () {
      final o = _m('2026-10-05', '2026-10-06');
      expect(o.write, isTrue);
      expect(o.value, '2026-10-06');
      expect(o.declined, isFalse);
    });

    test('local ABSENT x cloud date: the reinstall row, cloud wins and it is '
        'NOT malformed', () {
      final o = _m(null, '2026-10-05');
      expect(o.write, isTrue);
      expect(o.value, '2026-10-05');
      expect(o.malformed, isFalse,
          reason: 'a HIGH-priority event would fire on every reinstall');
      expect(o.declined, isFalse);
    });

    test('cloud ABSENT (null) never changes anything, whatever local holds', () {
      for (final local in <Object?>[null, '2026-10-05', 'garbage', 7]) {
        final o = _m(local, null);
        expect(o.write, isFalse, reason: 'local=$local');
        expect(o.declined, isFalse);
        expect(o.malformed, isFalse, reason: 'cloud null is not corrupt data');
      }
    });

    test('MALFORMED shapes and impossible dates are never well-formed', () {
      for (final bad in <Object?>[
        '2026-9-5',
        '20261005',
        '2026-10-05T00:00:00Z',
        ' 2026-10-05',
        'garbage',
        '',
        '2026-09-99',
        '2026-02-30',
        '2026-13-01',
        '0000-00-00',
        20261005,
        true,
        <String>['2026-10-05'],
      ]) {
        final o = _m('2026-10-01', bad);
        expect(o.write, isFalse, reason: 'cloud=$bad must not be written');
        expect(o.malformed, isTrue, reason: 'cloud=$bad is corrupt data');
        expect(o.declined, isFalse);
      }
    });

    test('local MALFORMED x cloud ok: cloud REPAIRS it and the corruption is '
        'reported', () {
      final o = _m('garbage', '2026-10-05');
      expect(o.write, isTrue);
      expect(o.value, '2026-10-05');
      expect(o.malformed, isTrue);
    });

    test('BOTH malformed: local kept, reported', () {
      final o = _m('garbage', 'also garbage');
      expect(o.write, isFalse);
      expect(o.malformed, isTrue);
    });

    test('local ABSENT x cloud malformed: nothing to write, reported', () {
      final o = _m(null, 'garbage');
      expect(o.write, isFalse);
      expect(o.malformed, isTrue);
    });

    test('the ceiling: exactly IST-today + 1 is accepted, +2 is malformed', () {
      final ok = _m('2026-10-01', '2026-10-08');
      expect(ok.write, isTrue, reason: 'istToday + 1 is the allowed ceiling');
      expect(ok.malformed, isFalse);
      final tooFar = _m('2026-10-01', '2026-10-09');
      expect(tooFar.write, isFalse);
      expect(tooFar.malformed, isTrue);
    });

    test('the ceiling crosses month and year ends', () {
      expect(_m('2026-10-01', '2026-11-01', today: '2026-10-31').write, isTrue);
      expect(_m('2026-10-01', '2026-11-02', today: '2026-10-31').malformed,
          isTrue);
      expect(_m('2026-10-01', '2027-01-01', today: '2026-12-31').write, isTrue);
      expect(_m('2026-10-01', '2027-01-02', today: '2026-12-31').malformed,
          isTrue);
      // A leap day is a real date; a non-leap 02-29 is not.
      expect(_m('2028-02-01', '2028-02-29', today: '2028-02-28').write, isTrue);
      expect(_m('2026-02-01', '2026-02-29', today: '2026-02-28').malformed,
          isTrue);
    });

    test('a FUTURE local date (a skewed clock) is malformed and repaired by a '
        'sane cloud date', () {
      final o = _m('2026-10-20', '2026-10-05');
      expect(o.write, isTrue);
      expect(o.value, '2026-10-05');
      expect(o.malformed, isTrue);
      expect(o.declined, isFalse,
          reason: 'a future local date must not be KEPT as "later"');
    });

    test('an unusable istToday disables the ceiling rather than throwing', () {
      final o = _m('2026-10-01', '2099-01-01', today: 'not a date');
      expect(o.write, isTrue);
    });
  });

  group('mergeCloudProgress: last_workout_date', () {
    test('a STALE restore does not move a newer unpushed date backwards, and '
        'the decline is reported', () {
      final r = _merge({'last_workout_date': '2026-10-07'},
          {'last_workout_date': '2026-10-03'});
      expect(r.merged['last_workout_date'], '2026-10-07');
      expect(r.declinedDateFields, hasLength(1));
      expect(r.declinedDateFields.single.field, 'last_workout_date');
      expect(r.declinedDateFields.single.localValue, '2026-10-07');
      expect(r.declinedDateFields.single.cloudValue, '2026-10-03');
      expect(r.hasDeclined, isTrue);
      expect(r.malformedFields, isEmpty);
    });

    test('a NEWER cloud date is taken', () {
      final r = _merge({'last_workout_date': '2026-10-03'},
          {'last_workout_date': '2026-10-06'});
      expect(r.merged['last_workout_date'], '2026-10-06');
      expect(r.declinedDateFields, isEmpty);
      expect(r.hasDeclined, isFalse);
    });

    test('REINSTALL: local empty x cloud date restores it with NOTHING reported',
        () {
      final r = _merge(const {}, {'last_workout_date': '2026-10-05'});
      expect(r.merged['last_workout_date'], '2026-10-05');
      expect(r.malformedFields, isEmpty);
      expect(r.declinedDateFields, isEmpty);
      expect(r.hasDeclined, isFalse);
    });

    test('a null cloud date leaves local alone', () {
      final r = _merge({'last_workout_date': '2026-10-05'},
          {'last_workout_date': null});
      expect(r.merged['last_workout_date'], '2026-10-05');
      expect(r.hasDeclined, isFalse);
    });

    test('a malformed cloud date keeps local and reports the field', () {
      final r = _merge({'last_workout_date': '2026-10-05'},
          {'last_workout_date': '2026-09-99'});
      expect(r.merged['last_workout_date'], '2026-10-05');
      expect(r.malformedFields, contains('last_workout_date'));
    });

    test('the decision does not depend on the cloud row\'s key order', () {
      final local = {'last_workout_date': '2026-10-07', 'current_phase': 2};
      final a = _merge(local, {
        'last_workout_date': '2026-10-03',
        'current_phase': 3,
        'total_workouts_done': 9,
      });
      final b = _merge(local, {
        'total_workouts_done': 9,
        'current_phase': 3,
        'last_workout_date': '2026-10-03',
      });
      expect(a.merged, b.merged);
      expect(a.merged['last_workout_date'], '2026-10-07');
      expect(a.merged['current_phase'], 3, reason: 'other fields are untouched');
      expect(a.merged['total_workouts_done'], 9);
    });

    test('the existing monotonic guard still works beside the date merge', () {
      final r = _merge(
        {'last_workout_date': '2026-10-07', 'current_streak_weeks': 5},
        {'last_workout_date': '2026-10-03', 'current_streak_weeks': 2},
      );
      expect(r.merged['current_streak_weeks'], 5);
      expect(r.declinedFields.single.field, 'current_streak_weeks');
      expect(r.declinedDateFields.single.field, 'last_workout_date');
    });

    test('disable_progress_date_merge: the PRE-ADDENDUM cloud-wins branch',
        () async {
      await HiveService.instance.configBox
          .put(UserRepository.kDisableProgressDateMergeKey, true);
      final r = _merge({'last_workout_date': '2026-10-07'},
          {'last_workout_date': '2026-10-03'});
      expect(r.merged['last_workout_date'], '2026-10-03');
      expect(r.declinedDateFields, isEmpty);
    });

    test('the WIDER monotonic switch still copies verbatim', () async {
      await HiveService.instance.configBox
          .put(UserRepository.kDisableProgressRestoreMonotonicMergeKey, true);
      final r = _merge({'last_workout_date': '2026-10-07'},
          {'last_workout_date': '2026-10-03'});
      expect(r.merged['last_workout_date'], '2026-10-03');
      expect(r.declinedDateFields, isEmpty);
    });

    test('ONLY the freeze switch set: the date merge still runs', () async {
      await HiveService.instance.configBox
          .put(UserRepository.kDisableProgressFreezeMergeKey, true);
      final r = _merge({'last_workout_date': '2026-10-07'},
          {'last_workout_date': '2026-10-03'});
      expect(r.merged['last_workout_date'], '2026-10-07');
      expect(r.declinedDateFields, hasLength(1));
    });

    test('the caller-supplied istToday reaches the ceiling through the merge',
        () {
      final cloud = {'last_workout_date': '2026-10-20'};
      // Same rows, only istToday differs: 10-20 is beyond 10-08 (malformed,
      // local kept) but within 10-21 (accepted).
      final early = _merge({'last_workout_date': '2026-10-05'}, cloud,
          today: '2026-10-07');
      expect(early.merged['last_workout_date'], '2026-10-05');
      expect(early.malformedFields, contains('last_workout_date'));
      final late = _merge({'last_workout_date': '2026-10-05'}, cloud,
          today: '2026-10-19');
      expect(late.merged['last_workout_date'], '2026-10-20');
      expect(late.malformedFields, isEmpty);
    });
  });

  group('the report', () {
    test('a declined DATE is emitted under the same high-priority event, '
        'within the 500-character cap', () {
      final seen = <String>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {String? message}) => seen.add('$op|$message');
      addTearDown(() => ErrorTelemetry.debugOnLogEventForTests = null);

      final r = _merge({'last_workout_date': '2026-10-07'},
          {'last_workout_date': '2026-10-03'});
      reportProgressDemotionsDeclined(r, source: 'test');

      expect(seen, hasLength(1));
      expect(
          seen.single,
          'progress_restore_demotion_declined|source=test '
          'field=last_workout_date local=2026-10-07 cloud=2026-10-03');
      expect(seen.single.length, lessThan(500));
    });

    test('nothing declined -> nothing emitted for the date', () {
      final seen = <String>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {String? message}) => seen.add('$op|$message');
      addTearDown(() => ErrorTelemetry.debugOnLogEventForTests = null);

      reportProgressDemotionsDeclined(
          _merge(const {}, {'last_workout_date': '2026-10-05'}),
          source: 'test');
      expect(seen, isEmpty);
    });

    test('a MALFORMED cloud date is emitted as field-malformed, names only',
        () {
      final seen = <String>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {String? message}) => seen.add('$op|$message');
      addTearDown(() => ErrorTelemetry.debugOnLogEventForTests = null);

      final r = _merge({'last_workout_date': '2026-10-05'},
          {'last_workout_date': '2026-13-45'});
      reportProgressDemotionsDeclined(r, source: 'test');

      expect(seen, [
        'progress_restore_field_malformed|source=test field=last_workout_date'
      ]);
    });
  });
}
