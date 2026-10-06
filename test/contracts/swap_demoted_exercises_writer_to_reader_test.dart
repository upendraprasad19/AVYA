// Gate-19 writer/reader-drift fix (2026-05-31) — pins the LEVER 6 swap
// writer→reader contract.
//
// Bug class (writer/reader field drift): TrainingHistoryAnalyzer.demotedExercises
// reads `swapped_from` off a swapped exercise inside a `schedule_*` row to
// deprioritize the name the user moved AWAY from in future generated plans.
// But SwapService.swapExercise originally stamped the replacement with
// `swapped_via` only and DISCARDED the original name — so `swapped_from` was
// never written and LEVER 6 was a dead read (always empty). Caught by Gate 19
// (check_hive_map_field_drift.dart) before the personalization batch shipped.
//
// Fix: SwapService.swapExercise now persists `swapped_from` (the original
// exercise_name) on the replacement map. The day-level swap branch in the
// analyzer (which read a never-written `original_exercise_name`) was removed.
//
// This test pins BOTH sides: (a) the analyzer picks up `swapped_from`, and
// (b) it does NOT depend on the removed `original_exercise_name` field.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_swap_demoted');
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
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'workoutBox_aaaaaaaa',
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
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  String todayKey() {
    final d = DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  group('LEVER 6 — swapped-out exercises are demoted (Gate-19 drift fix)', () {
    test('demotedExercises returns the swapped_from name written by SwapService',
        () async {
      final wb = HiveService.instance.workoutBox;
      final dateStr = todayKey();

      // A schedule row whose 2nd exercise was swapped: SwapService.swapExercise
      // replaces the entry in-place and stamps `swapped_via` + `swapped_from`
      // (the ORIGINAL exercise_name we want demoted).
      await wb.put('schedule_$dateStr', {
        'date': dateStr,
        'workout_name': 'Push Day',
        'is_swapped': false,
        'exercises': [
          {'exercise_name': 'Bench Press', 'sets': 4, 'reps': '8-12'},
          {
            'exercise_name': 'Dumbbell Shoulder Press',
            'sets': 3,
            'reps': '10-12',
            'swapped_via': 'ai_coach',
            'swapped_from': 'Barbell Overhead Press',
          },
        ],
      });

      final demoted = TrainingHistoryAnalyzer.demotedExercises();
      expect(demoted, contains('Barbell Overhead Press'),
          reason: 'analyzer must pick up the swapped_from name the writer persists');
      // The replacement that is currently scheduled is NOT demoted.
      expect(demoted, isNot(contains('Dumbbell Shoulder Press')));
      expect(demoted, isNot(contains('Bench Press')));
    });

    test('no swap history → empty set (safe no-op)', () async {
      final wb = HiveService.instance.workoutBox;
      final dateStr = todayKey();
      await wb.put('schedule_$dateStr', {
        'date': dateStr,
        'workout_name': 'Push Day',
        'exercises': [
          {'exercise_name': 'Bench Press', 'sets': 4, 'reps': '8-12'},
        ],
      });
      expect(TrainingHistoryAnalyzer.demotedExercises(), isEmpty);
    });

    test('SwapService persists swapped_from (writer side, source-grep guard)',
        () {
      final src = File('lib/core/services/swap_service.dart').readAsStringSync();
      expect(src.contains("'swapped_from':"), isTrue,
          reason: 'swapExercise must persist the original name for LEVER 6');
    });

    test('analyzer no longer depends on the never-written original_exercise_name',
        () {
      final src = File(
              'lib/shared/repositories/plan_engine/training_history_analyzer.dart')
          .readAsStringSync()
          // strip comments — the removal NOTE legitimately mentions the name.
          .replaceAll(RegExp(r'//[^\n]*'), '');
      expect(src.contains("['original_exercise_name']"), isFalse,
          reason: 'dead read of a field no writer emits must stay removed');
    });
  });
}
