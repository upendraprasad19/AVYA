// Spec 2026-09-26-day-swapper-design.md §1.4/§5.7, plan Task 23, diagnose b6e1c8.
//
// One-time PER-USER repair: rows with `status: rest` + a workout `type` + NO
// exercises are corrected to `type: rest` (28 live rows across 3 users' plan_json
// backups as of 2026-09-26, per the spec's live read-only check). A hybrid WITH
// exercises (the one ambiguous live case) is left ALONE, with a telemetry event.
// Also deletes the two dead swap-counter keys (plan D9) and the stale plan_json
// copy already inside userBox['progress'] (spec §1.5 / plan Task 20).
//
// closes-diagnose: b6e1c8

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/schedule_hybrid_repair_migrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('classifyRow / repairRow (pure) — b6e1c8', () {
    test('status:rest + workout type + empty exercises -> needsTypeFix, and '
        'repairRow fixes it', () {
      final row = <String, dynamic>{
        'type': 'workout',
        'status': 'rest',
        'exercises': <dynamic>[],
        'workout_name': 'Legs',
      };
      expect(ScheduleHybridRepairMigrator.classifyRow(row),
          HybridRowVerdict.needsTypeFix);
      final changed = ScheduleHybridRepairMigrator.repairRow(row);
      expect(changed, isTrue);
      expect(row['type'], 'rest');
    });

    test('status:rest + workout type + missing exercises key (never even '
        'seeded) -> needsTypeFix too', () {
      final row = <String, dynamic>{'type': 'custom_template', 'status': 'rest'};
      expect(ScheduleHybridRepairMigrator.classifyRow(row),
          HybridRowVerdict.needsTypeFix);
    });

    test('status:rest + workout type + NON-EMPTY exercises -> '
        'hasExercisesLeaveAlone, and repairRow does NOT touch it', () {
      final row = <String, dynamic>{
        'type': 'workout',
        'status': 'rest',
        'exercises': [
          {'name': 'Bench Press'}
        ],
      };
      expect(ScheduleHybridRepairMigrator.classifyRow(row),
          HybridRowVerdict.hasExercisesLeaveAlone);
      expect(ScheduleHybridRepairMigrator.repairRow(row), isFalse);
      expect(row['type'], 'workout', reason: 'left alone — ambiguous, in the past');
    });

    test('a genuine rest row (type already rest) -> notAHybrid, unchanged', () {
      final row = <String, dynamic>{
        'type': 'rest',
        'status': 'rest',
        'exercises': <dynamic>[],
      };
      expect(ScheduleHybridRepairMigrator.classifyRow(row),
          HybridRowVerdict.notAHybrid);
      expect(ScheduleHybridRepairMigrator.repairRow(row), isFalse);
    });

    test('a planned workout day (status != rest) -> notAHybrid, unchanged', () {
      final row = <String, dynamic>{
        'type': 'workout',
        'status': 'planned',
        'exercises': <dynamic>[],
      };
      expect(ScheduleHybridRepairMigrator.classifyRow(row),
          HybridRowVerdict.notAHybrid);
    });
  });

  group('runIfNeeded (behavioral heal) — b6e1c8', () {
    late Directory tempDir;
    final events = <String>[];

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('test_hybrid_repair');
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
        HiveService.workoutBoxName,
        HiveService.userBoxName,
        HiveService.configBoxName,
        HiveService.migrationBoxName,
        'workoutBox_aaaaaaaa',
        'userBox_aaaaaaaa',
        'workoutBox_bbbbbbbb',
      ]) {
        if (Hive.isBoxOpen(name)) await Hive.box(name).close();
        try {
          await Hive.deleteBoxFromDisk(name);
        } catch (_) {}
      }
      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
      HiveService.instance.markInitializedForTests();
      await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      events.clear();
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {message}) => events.add('$op $message');
    });

    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
      // Precedent pairing (every other openForUser test in this repo, e.g.
      // test/contracts/body_fat_default_heal_test.dart): without this,
      // HiveUserSession._currentOwnerFullId stays 'aaaaaaaa...' across
      // tests, so the NEXT test's setUp-time openForUser call short-
      // circuits as a same-user no-op (hive_session_reopen_noop) instead
      // of reopening the namespaced boxes setUp just deleted from disk —
      // surfaced as "HiveError: Box not found" on the 2nd/3rd test.
      await HiveUserSession.closeAll();
    });

    test('repairs a no-exercise hybrid, leaves a with-exercises hybrid alone '
        '+ logs telemetry, deletes dead keys, strips plan_json — all in ONE '
        'pass, then is idempotent', () async {
      final wb = HiveService.instance.workoutBox;
      final ub = HiveService.instance.userBox;

      await wb.put('schedule_2026-08-01', {
        'type': 'workout',
        'status': 'rest',
        'exercises': <dynamic>[],
        'workout_name': 'Legs',
      });
      await wb.put('schedule_2026-08-02', {
        'type': 'workout',
        'status': 'rest',
        'exercises': [
          {'name': 'Bench Press'}
        ],
        'workout_name': 'Push',
      });
      await wb.put('schedule_2026-08-03', {
        'type': 'workout',
        'status': 'planned',
        'exercises': [
          {'name': 'Squat'}
        ],
      });
      await ub.put('swaps_this_week', 2);
      await ub.put('swap_week_start', '2026-07-27');
      await ub.put('progress', {
        'current_phase': 2,
        'plan_json': {'plan': 'stale-copy-of-the-whole-plan-blob'},
      });

      final repaired = await ScheduleHybridRepairMigrator.runIfNeeded();
      expect(repaired, 1, reason: 'exactly one no-exercise hybrid seeded');

      final fixed = wb.get('schedule_2026-08-01') as Map;
      expect(fixed['type'], 'rest');

      final leftAlone = wb.get('schedule_2026-08-02') as Map;
      expect(leftAlone['type'], 'workout',
          reason: 'the ambiguous hybrid WITH exercises must be left untouched');
      expect(events.where((e) => e.startsWith('schedule_hybrid_left_alone ')),
          hasLength(1));

      final untouched = wb.get('schedule_2026-08-03') as Map;
      expect(untouched['status'], 'planned',
          reason: 'a genuine planned workout day must never be touched');

      expect(MigratedKey.read<int>('swaps_this_week'), isNull);
      expect(MigratedKey.read<String>('swap_week_start'), isNull);
      expect(ub.containsKey('swaps_this_week'), isFalse);
      expect(ub.containsKey('swap_week_start'), isFalse);

      final progress = ub.get('progress') as Map;
      expect(progress.containsKey('plan_json'), isFalse,
          reason: 'the stale on-disk copy must be deleted');
      expect(progress['current_phase'], 2,
          reason: 'sibling progress fields must survive the plan_json strip');

      // Idempotent — second run repairs nothing more.
      final again = await ScheduleHybridRepairMigrator.runIfNeeded();
      expect(again, 0);
      expect(ScheduleHybridRepairMigrator.hasRun(), isTrue);
    });

    test('the flag genuinely gates re-runs (not merely "nothing left to '
        'repair") — manually re-hybridizing a row after the first pass is '
        'NOT touched by a second call', () async {
      final wb = HiveService.instance.workoutBox;
      await wb.put('schedule_2026-08-01', {
        'type': 'workout',
        'status': 'rest',
        'exercises': <dynamic>[],
      });
      final first = await ScheduleHybridRepairMigrator.runIfNeeded();
      expect(first, 1);

      // Simulate a row somehow becoming a hybrid again after the flag is set
      // (not a real production path — this isolates the FLAG's own effect
      // from "there happened to be nothing left to fix").
      await wb.put('schedule_2026-08-01', {
        'type': 'workout',
        'status': 'rest',
        'exercises': <dynamic>[],
      });
      final second = await ScheduleHybridRepairMigrator.runIfNeeded();
      expect(second, 0, reason: 'the per-user flag must block a second pass '
          'outright, not merely find nothing to do');
      expect((wb.get('schedule_2026-08-01') as Map)['type'], 'workout',
          reason: 'unrepaired because the flag short-circuited before the scan');
    });

    test('D10: gated per-USER, not per-device — a second account on the same '
        'device is independently repaired', () async {
      final wbA = HiveService.instance.workoutBox;
      await wbA.put('schedule_2026-08-01', {
        'type': 'workout',
        'status': 'rest',
        'exercises': <dynamic>[],
      });
      await ScheduleHybridRepairMigrator.runIfNeeded();
      expect(ScheduleHybridRepairMigrator.hasRun(), isTrue);

      await HiveUserSession.openForUser('bbbbbbbb-cccc-dddd-eeee-ffffffffffff');
      expect(ScheduleHybridRepairMigrator.hasRun(), isFalse,
          reason: 'a fresh account has its own namespaced workoutBox, so the '
              "first account's flag must not leak across");
      final wbB = HiveService.instance.workoutBox;
      await wbB.put('schedule_2026-09-01', {
        'type': 'custom_template',
        'status': 'rest',
        'exercises': <dynamic>[],
      });
      final repairedB = await ScheduleHybridRepairMigrator.runIfNeeded();
      expect(repairedB, 1);
      expect((wbB.get('schedule_2026-09-01') as Map)['type'], 'rest');

      // Re-open account A — its own earlier repair state must be untouched.
      await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      expect(ScheduleHybridRepairMigrator.hasRun(), isTrue);
    });
  });
}
