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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/services/regenerate_plan_planner.dart';
import 'package:icanbefitter/features/ai_coach/services/hotel_workout_planner.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';

/// Exposes a real Riverpod [Ref] so we can drive
/// `ToolDispatcher.execute(ref, intent)` — the REAL dispatch path (mirrors
/// `test/contracts/reschedule_week_terminal_row_test.dart`).
final _refProvider = Provider<Ref>((ref) => ref);

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
    // Keep the dispatch hermetic (C3 hotel test drives ToolDispatcher):
    // execute()'s fire-and-forget syncWorkoutData()/pushSnapshot()
    // short-circuit under this flag.
    SyncService.pausedForSimulation = true;

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
    SyncService.pausedForSimulation = false;
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

  // C3 (ai-coach-ux-tool-integrity spec 2026-09-18) — the hotel commit must
  // not silently un-pause a paused day. The planner filters only 'completed'
  // out of the raw-schedule queue, so a paused day IS queued for write; the
  // dispatcher's concurrent-edit guard is the only protection between
  // sheet-open and confirm.
  test('hotel: a paused day survives the commit overwrite (C3)', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final pausedDate = today.add(const Duration(days: 2));
    final pausedDateStr = istDateStr(pausedDate);
    await HiveService.instance.workoutBox.put('schedule_$pausedDateStr', {
      'date': pausedDateStr,
      'type': 'workout',
      'workout_name': 'Push A',
      'status': 'paused',
      'paused_via': 'ai_coach',
      'paused_at': now.toIso8601String(),
      'exercises': [
        {'exercise_name': 'Bench Press'},
      ],
    });

    final out = await HotelWorkoutPlanner.instance.plan(
      days: 3,
      startDate: pausedDateStr,
    );
    expect(
      out.rawSchedules.any((r) => r['date'] == pausedDateStr),
      isTrue,
      reason: 'precondition: the hotel planner queues the paused day for '
          "write (it filters only 'completed') — the dispatcher's guard is "
          'the only protection',
    );

    HotelWorkoutPlanner.instance.cache('hotel_pause_1', out.days, out.rawSchedules);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final res = await ToolDispatcher.instance.execute(
      container.read(_refProvider),
      ToolIntent(
        id: 'hotel_pause_1',
        type: 'generate_hotel_workout',
        payload: const <String, dynamic>{},
        confirmationClass: ConfirmationClass.reviewable,
        previewSummary: '3-day hotel plan over a paused day',
        createdAt: DateTime.now(),
      ),
    );

    expect(res.success, isTrue, reason: 'dispatch must succeed');
    final schedules = (res.data as Map<String, dynamic>?)?['schedules'] as List? ?? const <dynamic>[];
    expect(
      schedules.whereType<Map>().where((m) => m['date'] == pausedDateStr),
      isEmpty,
      reason: 'the paused date must be skipped, not reported as scheduled',
    );

    final row =
        HiveService.instance.workoutBox.get('schedule_$pausedDateStr') as Map?;
    expect(row, isNotNull,
        reason: 'the paused row must survive untouched');
    expect(row!['status'], 'paused',
        reason: 'pre-fix the hotel commit overwrote the paused row with a '
            "fresh status:'planned' row — silently un-pausing the user's "
            'pause');
    expect(row['workout_name'], 'Push A');
    expect(row['paused_via'], 'ai_coach');
    expect(row['paused_at'], isNotNull);
  });
}
