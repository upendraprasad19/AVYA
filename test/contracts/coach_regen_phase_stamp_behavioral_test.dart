// Behavioral regression — item ② (phase demotion) + COACH-1 (phase row-stamp).
//
// A coach "regenerate my plan" / "switch goal" (shared RegeneratePlanPlanner
// sink) and "generate hotel workout" must:
//   ② NOT demote a phase-6 user to Foundation — thread the real current_phase
//      into PlanGenerator.generate(); and
//   COACH-1 stamp the schedule-row `phase` key so bucketPastRows /
//      PhaseProgressReconciler bucket these rows to the correct phase (they were
//      unstamped → relied on carry-forward; a wrong stamp mints a phantom block).
//
// FAILS pre-fix: generate defaulted phase=1 AND the rows carried no `phase` key
// (→ null ≠ 6). PASSES post-fix. Diagnose: docs/diagnoses/<...>-coach-phase.md.
//
// Pure Hive (path_provider-mocked), real exercise library seeded so the
// generator produces real workouts. No Supabase.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/ai_coach/services/regenerate_plan_planner.dart';
import 'package:icanbefitter/features/ai_coach/services/hotel_workout_planner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_coach_phase_stamp');
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
      HiveService.coachBoxName,
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      HiveService.exerciseBoxName,
      'workoutBox_aaaaaaaa',
      'coachBox_aaaaaaaa',
      'userBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);

    // Seed the REAL exercise library so PlanGenerator produces real workouts
    // (ExerciseRepository reads exerciseBox.values). Non-empty → the planner's
    // `if (exerciseBox.isEmpty) seedIfNeeded()` is skipped.
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final lib = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    for (final e in lib) {
      final m = Map<String, dynamic>.from(e as Map);
      await exBox.put(m['id'], m);
    }

    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');

    // A phase-6 user (the demotion victim in the pre-fix bug).
    await HiveService.instance.userBox.put('profile', {
      'primary_goal': 'build_muscle',
      'equipment_access': 'full_gym',
      'days_per_week': 4,
      'fitness_experience': 'advanced',
    });
    await HiveService.instance.userBox.put('progress', {'current_phase': 6});
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  test('regenerate: every schedule row carries the real phase (6), not 1', () async {
    final out = await RegeneratePlanPlanner.instance.plan(weeks: 4);

    expect(out.rawSchedules, isNotEmpty,
        reason: 'the generator must produce rows for a phase-6 user');
    // Proves BOTH fixes: resolvedPhase==6 flowed to generate() AND was stamped
    // on the rows (same variable feeds both).
    for (final row in out.rawSchedules) {
      expect(row['phase'], 6,
          reason: 'row missing/wrong phase stamp (COACH-1): $row');
    }
    // Sanity: a real workout row exists (generate produced content at phase 6).
    expect(out.rawSchedules.any((r) => r['type'] == 'workout'), isTrue);
    // Both workout AND rest rows must carry the stamp.
    expect(out.rawSchedules.any((r) => r['type'] == 'rest'), isTrue,
        reason: 'expected at least one rest row in a 4-day week');
  });

  test('hotel: every schedule row carries the real phase (6)', () async {
    final out = await HotelWorkoutPlanner.instance.plan(days: 3);

    expect(out.rawSchedules, isNotEmpty);
    for (final row in out.rawSchedules) {
      expect(row['phase'], 6,
          reason: 'hotel row missing/wrong phase stamp (COACH-1): $row');
    }
  });
}
