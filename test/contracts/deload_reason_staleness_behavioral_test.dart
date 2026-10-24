// Behavioral — Unit B (diagnose `c5a8f3`): the week-4 deload reason line must
// never contradict the wave node it renders under.
//
// `deload_reason_phase_<P>` is written by `deload_evaluator.dart:159` and is
// deleted NOWHERE in `lib/`. TWO BLOB-rewriting paths re-stamp week 4 back to
// `deload` after a lift — `generateAndScheduleFromDate`
// (`workout_schedule_read_service.dart:388`, live caller
// `edit_profile_screen.dart:2029`) and `generateAndSchedule` (`:227`) — while the
// idempotency flag at
// `deload_evaluator.dart:79` blocks any re-evaluation from correcting the string.
// The strip would then render a DELOAD node above "Working week — you've
// recovered", for the rest of the phase.
//
// The fix is at the READER: the eval stamps the outcome `week_character` beside
// the prose, and `currentDeloadReason()` returns the text ONLY while that
// character still equals week 4's in the SAME blob the strip renders
// (`currentWaveCharacters`). Validating against the blob rather than the
// scheduled rows is deliberate — the strip renders the blob.
//
// SCOPE, stated precisely because an earlier draft of this header overclaimed it:
// the AI-coach regen (`regenerate_plan_planner.dart` — applied row-by-row through
// `WorkoutWriteService.upsertScheduled`) writes NO blob at all. It therefore
// cannot make the line contradict the node, because it moves neither; what it
// does is leave BOTH stale together, which is a separate pre-existing defect of
// the phase-arc strip itself (OI-166), not something this reader can see.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  const liftText = "Working week — you've recovered. Full volume restored.";
  const keepText = 'Scheduled recovery week — trust the taper.';
  final planStart = DateTime(2026, 6, 1).subtract(const Duration(days: 21));
  late Directory tempDir;

  String dk(DateTime d) => istDateStr(d);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_deload_reason');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    for (final name in [
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'userBox_aaaaaaaa',
      'workoutBox_aaaaaaaa',
      'nutritionBox_aaaaaaaa',
      'healthBox_aaaaaaaa',
      'coachBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  // Week-4 scheduled rows stamped `phase` — all `currentDeloadReason` needs from
  // the rows is the phase (via `deloadPhaseFromWeek4`).
  Future<void> seedWeek4Rows({required int phase}) async {
    final cb = HiveService.instance.configBox;
    final wb = HiveService.instance.workoutBox;
    await cb.put('plan_start_date', planStart.toIso8601String());
    await cb.put('plan_end_date',
        planStart.add(const Duration(days: 27)).toIso8601String());
    final wk4Start = planStart.add(const Duration(days: 21));
    for (int i = 0; i < 7; i++) {
      final date = wk4Start.add(Duration(days: i));
      final isWorkout = i == 0 || i == 2;
      await wb.put('schedule_${dk(date)}', {
        'date': dk(date),
        'phase': phase,
        'week': 4,
        'day_of_week': i,
        'type': isWorkout ? 'workout' : 'rest',
        'workout_name': isWorkout ? 'Push' : 'Rest Day',
        'workout_focus': 'Chest',
        'exercises': <Map<String, dynamic>>[],
        'week_character': 'deload',
        'status': isWorkout ? 'planned' : 'rest',
        'completed_at': null,
        'is_swapped': false,
        'original_date': null,
      });
    }
  }

  // The blob the STRIP renders. [week4] is the character the node will show.
  Future<void> seedBlob(String week4, {int weeks = 4}) async {
    final chars = ['baseline', 'overreach', 'peak', week4].take(weeks).toList();
    await HiveService.instance.workoutBox.put('current_plan', {
      'week_plans': [
        for (final c in chars) {'week_character': c},
      ],
    });
  }

  Future<void> stampReason(int phase, Object? value) async {
    await HiveService.instance.workoutBox.put(
      '${WorkoutScheduleReadService.deloadReasonKeyPrefix}$phase',
      value,
    );
  }

  String? read() => WorkoutScheduleService.instance.currentDeloadReason();

  group('stale reason after a regen (the Unit B defect)', () {
    test(
        'THE REGRESSION: lift reason stamped, then a regen re-stamps week 4 as '
        'deload -> no line (never DELOAD above a recovered message)', () async {
      await seedWeek4Rows(phase: 2);
      await stampReason(2, {'week_character': 'working', 'text': liftText});
      // The regen: blob week 4 back to `deload`, reason untouched, idempotency
      // flag still set so no re-eval can correct it.
      await seedBlob('deload');
      expect(read(), isNull,
          reason: 'the stamped outcome (working) no longer matches the blob '
              'node (deload), so the prose describes a week that is gone');
    });

    test('POSITIVE CONTROL: the same lift reason shows while the blob agrees',
        () async {
      await seedWeek4Rows(phase: 2);
      await stampReason(2, {'week_character': 'working', 'text': liftText});
      await seedBlob('working');
      expect(read(), liftText);
    });

    test('a KEEP reason shows while the blob still says deload', () async {
      await seedWeek4Rows(phase: 2);
      await stampReason(2, {'week_character': 'deload', 'text': keepText});
      await seedBlob('deload');
      expect(read(), keepText);
    });

    test(
        'MIRROR: stored `deload` while the blob says `working` (a sync landing '
        'a lifted blob over a local keep) is equally stale -> no line',
        () async {
      await seedWeek4Rows(phase: 2);
      await stampReason(2, {'week_character': 'deload', 'text': keepText});
      await seedBlob('working');
      expect(read(), isNull,
          reason: 'the check is EQUALITY, not "is it working" — a guard that '
              'only caught one direction would leave this one live');
    });
  });

  group('values that cannot be validated resolve to no line', () {
    test('LEGACY bare String (written 2026-09-01 until Unit B) -> null',
        () async {
      await seedWeek4Rows(phase: 2);
      await stampReason(2, liftText);
      await seedBlob('working'); // even when it would have matched
      expect(read(), isNull);
    });

    test('map missing `text` -> null', () async {
      await seedWeek4Rows(phase: 2);
      await stampReason(2, {'week_character': 'working'});
      await seedBlob('working');
      expect(read(), isNull);
    });

    test('map missing `week_character` -> null', () async {
      await seedWeek4Rows(phase: 2);
      await stampReason(2, {'text': liftText});
      await seedBlob('working');
      expect(read(), isNull);
    });

    test('empty text -> null', () async {
      await seedWeek4Rows(phase: 2);
      await stampReason(2, {'week_character': 'working', 'text': ''});
      await seedBlob('working');
      expect(read(), isNull);
    });

    test('blob shorter than 4 weeks -> null (the strip renders nothing there)',
        () async {
      await seedWeek4Rows(phase: 2);
      await stampReason(2, {'week_character': 'working', 'text': liftText});
      await seedBlob('working', weeks: 3);
      expect(read(), isNull);
    });

    test('no blob at all -> null', () async {
      await seedWeek4Rows(phase: 2);
      await stampReason(2, {'week_character': 'working', 'text': liftText});
      expect(read(), isNull);
    });

    test('reason stamped for a DIFFERENT phase -> null', () async {
      await seedWeek4Rows(phase: 3);
      await stampReason(2, {'week_character': 'working', 'text': liftText});
      await seedBlob('working');
      expect(read(), isNull);
    });
  });

  // PURE-layer tests. The group above drives the real reader, whose crash-safety
  // `catch` converts ANY throw into the same null those tests assert — so plan-review
  // round 1 measured that deleting the `waves.length`, `is! Map` or `stamped`-shape
  // guard reddened ZERO of them. They were asserting the exception handler.
  // These call the guard directly, with no `catch` above it: delete a guard and
  // the next line throws (RangeError / NoSuchMethodError) and the test goes red.
  group('validatedDeloadReason — every null comes from an explicit guard', () {
    const good = {'week_character': 'working', 'text': liftText};
    const waves4 = ['baseline', 'overreach', 'peak', 'working'];

    test('match → the text (positive control for this whole group)', () {
      expect(WorkoutScheduleReadService.validatedDeloadReason(good, waves4),
          liftText);
    });

    test('LEGACY bare String → null (guards the `is! Map` line)', () {
      expect(
          WorkoutScheduleReadService.validatedDeloadReason(liftText, waves4),
          isNull);
    });

    test('null stored value → null', () {
      expect(WorkoutScheduleReadService.validatedDeloadReason(null, waves4),
          isNull);
    });

    test('missing / non-String / empty text → null', () {
      const w = ['baseline', 'overreach', 'peak', 'working'];
      expect(
          WorkoutScheduleReadService.validatedDeloadReason(
              {'week_character': 'working'}, w),
          isNull);
      expect(
          WorkoutScheduleReadService.validatedDeloadReason(
              {'week_character': 'working', 'text': 7}, w),
          isNull);
      expect(
          WorkoutScheduleReadService.validatedDeloadReason(
              {'week_character': 'working', 'text': ''}, w),
          isNull);
    });

    test('missing / non-String / whitespace week_character → null', () {
      const w = ['baseline', 'overreach', 'peak', 'working'];
      expect(
          WorkoutScheduleReadService.validatedDeloadReason(
              {'text': liftText}, w),
          isNull);
      expect(
          WorkoutScheduleReadService.validatedDeloadReason(
              {'week_character': 3, 'text': liftText}, w),
          isNull);
      expect(
          WorkoutScheduleReadService.validatedDeloadReason(
              {'week_character': '   ', 'text': liftText}, w),
          isNull,
          reason: 'whitespace-only must not sneak past via trim() to an empty '
              'match against an equally blank wave slot');
    });

    test('waves shorter than 4 → null (guards the index, not the catch)', () {
      expect(
          WorkoutScheduleReadService.validatedDeloadReason(
              good, ['baseline', 'overreach', 'peak']),
          isNull);
      expect(
          WorkoutScheduleReadService.validatedDeloadReason(good, const []),
          isNull);
    });

    test('mismatch → null, in BOTH directions', () {
      expect(
          WorkoutScheduleReadService.validatedDeloadReason(
              good, ['baseline', 'overreach', 'peak', 'deload']),
          isNull);
      expect(
          WorkoutScheduleReadService.validatedDeloadReason(
              {'week_character': 'deload', 'text': keepText},
              ['baseline', 'overreach', 'peak', 'working']),
          isNull);
    });

    test(
        'comparison is NORMALISED on both sides, matching PhaseArcStrip.labelFor',
        () {
      expect(
          WorkoutScheduleReadService.validatedDeloadReason(
              {'week_character': '  WORKING ', 'text': liftText},
              ['baseline', 'overreach', 'peak', ' Working  ']),
          liftText,
          reason: 'the widget lowercases and trims before rendering; a raw '
              'compare would disagree with the display about sameness');
    });
  });

  group('kill-switch behaviour is unchanged by Unit B', () {
    test('triggered-deload killed -> null even on a perfectly valid value',
        () async {
      await seedWeek4Rows(phase: 2);
      await stampReason(2, {'week_character': 'working', 'text': liftText});
      await seedBlob('working');
      expect(read(), liftText, reason: 'precondition');
      await HiveService.instance.configBox
          .put('disable_triggered_deload', true);
      expect(read(), isNull);
      await HiveService.instance.configBox.delete('disable_triggered_deload');
      expect(read(), liftText);
    });
  });
}
