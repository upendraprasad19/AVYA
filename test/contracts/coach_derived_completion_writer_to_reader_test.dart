// SoT concept: coach_derived_completion (docs/sot_registry.yaml).
//
// Gate 9 (scripts/check_writeservice_contracts.dart) requires every
// hive-key-prefixed SoT concept to ship a same-named writer→reader contract
// test. This is that test for `coach_derived_completion` — a REAL behavioral
// proof (not a stub), pinning the WRITER→READER contract end-to-end.
//
// THE CONTRACT
// ------------
// Completion of a scheduled workout day is DERIVED, never AI-asserted
// (ADR-0012). Post-Unit-1 (coach-completion-tap-card, 280c4d) it derives via
// TWO paths, BOTH routing through the ONE canonical completion writer,
// `WorkoutWriteService.markCompleted`:
//   (1) the ALL-LOGGED AUTO BACKSTOP — the dispatcher's
//       `_maybeCompleteScheduledDay` auto-`markCompleted(completedVia:'auto')`
//       once EVERY planned exercise has a log today, and
//   (2) the USER-TAPPED CARD — `ChatHistoryNotifier.completeWorkoutFromPrompt`
//       → `markCompleted(completedVia:'tap')`.
//
// This test asserts the writer→reader round-trip through markCompleted:
//   WRITER  = WorkoutWriteService.markCompleted (flips schedule_<date> status
//             to 'completed' + stamps completed_via on the row).
//   READERS = (a) the schedule row itself round-trips — status:'completed' +
//                 completed_via — read both raw AND via the canonical
//                 WorkoutScheduleReadService.getScheduleForDate reader, and
//             (b) AiSnapshotBuilder's today_workout.today_workout_completion
//                 (all_logged) + today_workout.status reflect the derived
//                 completion.
// Each assertion FAILS if the writer stops writing the field the reader reads
// (the recurring writer/reader-drift class this gate defends against).
//
// Pure Hive (path_provider-mocked) — no Supabase — so it runs in the
// pre-commit gate. Mirrors coach_completion_prompt_test.dart's setup exactly.

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('test_coach_derived_completion');
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
      'workoutBox_aaaaaaaa',
      'coachBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    // Shared (non-user-scoped) exerciseBox — the REAL log_set dispatch resolves
    // exerciseId → name via _resolveExerciseName(exerciseBox), which throws
    // "Box not found" if it isn't open. Seeded so 'ex_bench' → 'Bench Press'.
    if (Hive.isBoxOpen(HiveService.exerciseBoxName)) {
      await Hive.box(HiveService.exerciseBoxName).close();
    }
    try {
      await Hive.deleteBoxFromDisk(HiveService.exerciseBoxName);
    } catch (_) {}
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    await exBox.put('ex_bench', {'name': 'Bench Press'});
    await exBox.put('ex_ohp', {'name': 'Overhead Press'});
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    // Keep the tests hermetic: execute()'s fire-and-forget syncWorkoutData() /
    // pushSnapshot() short-circuit under this flag (guarded FIRST in both), so
    // no Supabase touch + no dangling coalescer timers.
    SyncService.pausedForSimulation = true;
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    await HiveUserSession.closeAll();
  });

  // Writes a planned scheduled day with the given exercise maps.
  Future<void> seedScheduledDay(
    DateTime date,
    List<Map<String, dynamic>> exercises, {
    String type = 'custom_template',
    String workoutName = 'Push Day',
  }) async {
    final wb = HiveService.instance.workoutBox;
    await wb.put(WorkoutWriteService.scheduleKey(date), {
      'date': istDateStr(date),
      'workout_name': workoutName,
      'status': 'planned',
      'type': type,
      'exercises': exercises,
    });
  }

  // Coach-logs one exercise (the exact path a coach logSet takes).
  Future<void> coachLog(DateTime date, String exerciseName) async {
    final result = await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: exerciseName,
      sets: [
        ExerciseSet(
          weightKg: 60,
          reps: 8,
          loggedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ],
      source: WriteSource.aiCoach,
    );
    expect(result.success, isTrue);
  }

  Map scheduleRow(DateTime date) => HiveService.instance.workoutBox
      .get(WorkoutWriteService.scheduleKey(date)) as Map;

  // A ProviderContainer with the auth stream stubbed so ChatHistoryNotifier's
  // build() doesn't touch an uninitialized Supabase singleton in a pure-VM test.
  ChatHistoryNotifier makeChatNotifier() {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(c.dispose);
    c.read(chatHistoryProvider);
    return c.read(chatHistoryProvider.notifier);
  }

  group('coach_derived_completion — writer→reader contract', () {
    // ── WRITER → schedule READER (direct markCompleted) ──────────────────────
    test(
        'markCompleted flips schedule_<date> status→completed + stamps '
        'completed_via; a reader round-trips both fields', () async {
      final date = DateTime.now();
      await seedScheduledDay(date, [
        {'exercise_name': 'Bench Press'},
      ]);

      // Sanity: the reader sees 'planned' BEFORE the writer runs (so the
      // post-write assertion proves the writer, not a pre-seeded value).
      expect(scheduleRow(date)['status'], 'planned');

      // WRITER — the canonical completion writer both derived paths route through.
      final WriteResult res = await WorkoutWriteService.instance.markCompleted(
        date: date,
        workoutName: 'Push Day',
        durationSec: 0,
        completedVia: 'auto',
      );
      expect(res.success, isTrue);

      // READER (raw round-trip) — the exact fields the schedule readers read.
      final sched = scheduleRow(date);
      expect(sched['status'], 'completed',
          reason: 'markCompleted must write status:completed on the '
              'schedule_<date> row (the field home/train/snapshot readers read).');
      expect(sched['completed_via'], 'auto',
          reason: 'markCompleted must stamp completed_via — pins the field '
              'name the completion-telemetry reader reads.');
    });

    // ── WRITER → AiSnapshotBuilder READER (all-logged AUTO backstop path) ─────
    test(
        'all-logged AUTO backstop routes through markCompleted; snapshot '
        'today_workout_completion + status reflect the derived completion',
        () async {
      final date = DateTime.now();
      final dateStr = istDateStr(date);
      await seedScheduledDay(date, [
        {'exercise_name': 'Bench Press'},
        {'exercise_name': 'Overhead Press'},
      ]);

      // Log the FIRST of two — a genuine partial. The all-logged backstop must
      // NOT fire; the snapshot reader must report all_logged:false + planned.
      await coachLog(date, 'Bench Press');
      await ToolDispatcher.instance
          .maybeCompleteScheduledDayForTest(date, dateStr);

      expect(scheduleRow(date)['status'], 'planned',
          reason: 'A 1-of-2 partial must NOT auto-complete (the founder bug).');

      final partialSnap = AiSnapshotBuilder.instance.buildAiContext();
      final partialWorkout = partialSnap['today_workout'] as Map?;
      expect(partialWorkout, isNotNull);
      final partialCompletion =
          partialWorkout!['today_workout_completion'] as Map?;
      expect(partialCompletion, isNotNull,
          reason: 'today_workout must carry today_workout_completion counts '
              '(the snapshot reader of the derived-completion concept).');
      expect(partialCompletion!['total_planned'], 2);
      expect(partialCompletion['total_logged'], 1);
      expect(partialCompletion['all_logged'], false);

      // Log the SECOND — now EVERY planned exercise has a log. The backstop
      // auto-`markCompleted`s (the WRITER); the schedule + snapshot READERS
      // must both reflect it.
      await coachLog(date, 'Overhead Press');
      await ToolDispatcher.instance
          .maybeCompleteScheduledDayForTest(date, dateStr);

      final sched = scheduleRow(date);
      expect(sched['status'], 'completed',
          reason: 'Logging EVERY planned exercise must derive completion via '
              'markCompleted (the all-logged backstop).');
      expect(sched['completed_via'], 'auto',
          reason: 'The auto-backstop path must stamp completed_via:auto.');

      final doneSnap = AiSnapshotBuilder.instance.buildAiContext();
      final doneWorkout = doneSnap['today_workout'] as Map;
      expect(doneWorkout['status'], 'completed',
          reason: 'The snapshot status reader must reflect the derived '
              'completion written by markCompleted.');
      final doneCompletion =
          doneWorkout['today_workout_completion'] as Map;
      expect(doneCompletion['total_logged'], 2);
      expect(doneCompletion['all_logged'], true,
          reason: 'all_logged must flip true once every planned exercise is '
              'logged — the reader-side derivation the coach narrates from.');
    });

    // ── WRITER → schedule READER (USER-TAPPED card path) ─────────────────────
    test(
        'completeWorkoutFromPrompt (tap) routes through markCompleted; the '
        'schedule reader sees completed + completed_via:tap', () async {
      final date = DateTime.now();
      final dateStr = istDateStr(date);
      await seedScheduledDay(date, [
        {'exercise_name': 'Bench Press'},
        {'exercise_name': 'Overhead Press'},
        {'exercise_name': 'Triceps Pushdown'},
      ]);
      // A genuine partial → stays planned; the tap is the explicit finisher.
      await coachLog(date, 'Bench Press');
      expect(scheduleRow(date)['status'], 'planned');

      // WRITER — the [Complete workout] card handler → markCompleted(tap).
      final notifier = makeChatNotifier();
      final WriteResult res =
          await notifier.completeWorkoutFromPrompt(dateStr);
      expect(res.success, isTrue);

      // READER — the schedule row round-trips the tap-derived completion.
      final sched = scheduleRow(date);
      expect(sched['status'], 'completed',
          reason: 'The explicit [Complete workout] tap must derive completion '
              'via markCompleted.');
      expect(sched['completed_via'], 'tap',
          reason: 'The user-tap path must stamp completed_via:tap.');
    });

    // ── Swap-tolerance of the derivation (writer input → reader output) ───────
    test(
        'a log under the swapped_from name completes a single-exercise day '
        '(swap-tolerant all-logged derivation)', () async {
      final date = DateTime.now();
      final dateStr = istDateStr(date);
      // Plan was Incline Bench; swapped to Dumbbell Bench. The schedule row
      // carries the new name + swapped_from = the old one.
      await seedScheduledDay(date, [
        {
          'exercise_name': 'Dumbbell Bench Press',
          'swapped_from': 'Incline Bench Press',
        },
      ]);

      // Log under the OLD (swapped_from) name — the swap-tolerant reader-side
      // check must still count it, so the single-exercise day auto-completes.
      await coachLog(date, 'Incline Bench Press');
      await ToolDispatcher.instance
          .maybeCompleteScheduledDayForTest(date, dateStr);

      expect(scheduleRow(date)['status'], 'completed',
          reason: 'A log under the swapped_from name must count as logged '
              '(swap-tolerant), deriving completion for the single-exercise day.');

      // The snapshot reader agrees (all_logged true via the swap-tolerant path).
      final snap = AiSnapshotBuilder.instance.buildAiContext();
      final completion = (snap['today_workout'] as Map)['today_workout_completion']
          as Map;
      expect(completion['all_logged'], true);
    });

    // ── finding-1 — REAL log_set dispatch derives completion end-to-end ───────
    test(
        'a REAL log_set dispatch on a single-exercise day auto-completes '
        'through markCompleted (execute → _maybeCompleteScheduledDay)', () async {
      final date = DateTime.now();
      final dateStr = istDateStr(date);
      await seedScheduledDay(date, [
        {'exercise_name': 'Bench Press'},
      ]);

      final c = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => const Stream.empty()),
      ]);
      addTearDown(c.dispose);
      final ref = c.read(Provider<Ref>((ref) => ref));

      // The REAL dispatch: execute() runs _executeLogSet + the derived-
      // completion decision. exerciseId → exerciseBox['ex_bench'] → 'Bench
      // Press', matching the sole planned exercise → all-logged → auto-complete.
      final intent = ToolIntent(
        id: 'intent_derived_completion',
        type: 'log_set',
        payload: {
          'exerciseId': 'ex_bench',
          'weightKg': 60,
          'reps': 8,
          'sets': 3,
          'date': dateStr,
        },
        confirmationClass: ConfirmationClass.reviewable,
        previewSummary: '',
        createdAt: DateTime.now(),
      );
      final res = await ToolDispatcher.instance.execute(ref, intent);
      expect(res.success, isTrue);

      final sched = scheduleRow(date);
      expect(sched['status'], 'completed',
          reason: 'A single planned exercise, logged via the REAL dispatch, '
              'must derive completion via markCompleted.');
      expect(sched['completed_via'], 'auto');
    });
  });
}
