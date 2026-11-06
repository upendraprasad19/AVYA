// Unit 1 (coach-completion-tap-card) — behavioral proof of the founder's bug
// fix + the new tap-to-complete backstop.
//
// THE BUG (pre-fix): one coach `logSet` on a multi-exercise scheduled day
// silently flipped the WHOLE day to `completed` via
// `_maybeCompleteScheduledDay` (no "all exercises logged" check), inflating
// streak / rank / deployment.
//
// THE FIX: after a coach `logSet`, the day auto-completes ONLY when EVERY
// planned exercise now has a log (the all-logged backstop). A genuine partial
// stays `planned` and writes a `completion_prompt_<date>` action row that the
// chat renders as a two-button [Log more] · [Complete workout] tile. The
// user's explicit tap is the reliable fallback.
//
// Each test below FAILS against the pre-fix behavior:
//   (a) partial log → status STAYS 'planned' + a completion_prompt row exists
//       (pre-fix: status flipped to 'completed', no prompt row).
//   (b) log ALL planned → 'completed' (auto) with completed_via:'auto'.
//   (c) tap [Complete] on a partial → 'completed' with completed_via:'tap'.
//   (d) a swapped exercise counts as logged under EITHER name.
//   (e) the prompt row is deduped — one date-scoped row, superseded on re-log.
//
// Pure Hive (path_provider-mocked) — no Supabase — so it runs in the
// pre-commit gate. Mirrors coach_derived_pr_and_completion_test.dart's setup.

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

/// Exposes a real Riverpod [Ref] to the test so we can drive
/// `ToolDispatcher.execute(ref, intent)` — the REAL dispatch path (not the
/// `maybeCompleteScheduledDayForTest` seam) — and read `chatHistoryProvider`
/// from the SAME container the dispatch invalidates.
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_coach_completion');
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
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    // Keep the REAL-dispatch tests hermetic: execute()'s fire-and-forget
    // syncWorkoutData()/pushSnapshot() short-circuit under this flag (guarded
    // FIRST in both), so no Supabase touch + no dangling coalescer timers.
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

  // Coach-logs one exercise (the exact path a coach logSet takes) and runs the
  // derived-completion decision, exactly as ToolDispatcher._executeLogSet does.
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
    await ToolDispatcher.instance
        .maybeCompleteScheduledDayForTest(date, istDateStr(date));
  }

  Map? completionPrompt(String dateStr) =>
      HiveService.instance.coachBox.get('completion_prompt_$dateStr') as Map?;

  // A ProviderContainer with the auth stream stubbed so ChatHistoryNotifier's
  // build() (which watches authStateProvider) doesn't touch an uninitialized
  // Supabase singleton in a pure-VM test.
  ChatHistoryNotifier makeChatNotifier() {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(c.dispose);
    // Instantiate the notifier through the container so its `ref` is wired.
    c.read(chatHistoryProvider);
    return c.read(chatHistoryProvider.notifier);
  }

  group('Unit 1 — derived completion backstop + tap-card', () {
    test('(a) partial coach log STAYS planned + writes a completion_prompt row',
        () async {
      final date = DateTime.now();
      await seedScheduledDay(date, [
        {'exercise_name': 'Bench Press'},
        {'exercise_name': 'Overhead Press'},
        {'exercise_name': 'Triceps Pushdown'},
      ]);

      // Log only ONE of the three planned exercises.
      await coachLog(date, 'Bench Press');

      final sched =
          HiveService.instance.workoutBox.get(WorkoutWriteService.scheduleKey(date))
              as Map;
      expect(sched['status'], 'planned',
          reason: 'One logged exercise must NOT flip a 3-exercise day to '
              'completed (the founder bug). Status stays planned.');

      final prompt = completionPrompt(istDateStr(date));
      expect(prompt, isNotNull,
          reason: 'A partial day must write a completion_prompt row.');
      expect(prompt!['kind'], 'completion_prompt');
      expect(prompt['planned_count'], 3);
      expect(prompt['logged_count'], 1);
      expect(prompt['resolved_at'], isNull);
    });

    test('(b) logging ALL planned exercises auto-completes (completed_via:auto)',
        () async {
      final date = DateTime.now();
      await seedScheduledDay(date, [
        {'exercise_name': 'Bench Press'},
        {'exercise_name': 'Overhead Press'},
      ]);

      await coachLog(date, 'Bench Press');
      // Still partial after the first log.
      expect(
        (HiveService.instance.workoutBox
            .get(WorkoutWriteService.scheduleKey(date)) as Map)['status'],
        'planned',
      );

      await coachLog(date, 'Overhead Press');

      final sched =
          HiveService.instance.workoutBox.get(WorkoutWriteService.scheduleKey(date))
              as Map;
      expect(sched['status'], 'completed',
          reason: 'Logging EVERY planned exercise must auto-complete (backstop).');
      expect(sched['completed_via'], 'auto',
          reason: 'The auto-backstop must stamp completed_via:auto.');

      // The partial-state prompt written by the FIRST log is now resolved
      // (auto-complete supersedes the "log more?" ask) — so no card renders.
      final prompt = completionPrompt(istDateStr(date));
      if (prompt != null) {
        expect(prompt['resolved_at'], isNotNull,
            reason: 'On auto-complete, any earlier completion_prompt row must '
                'be resolved so its card stops rendering.');
      }
    });

    test('(c) [Complete workout] tap on a partial completes (completed_via:tap)',
        () async {
      final date = DateTime.now();
      await seedScheduledDay(date, [
        {'exercise_name': 'Bench Press'},
        {'exercise_name': 'Overhead Press'},
        {'exercise_name': 'Triceps Pushdown'},
      ]);
      await coachLog(date, 'Bench Press');
      expect(completionPrompt(istDateStr(date)), isNotNull);

      // The chat card's [Complete workout] handler.
      final notifier = makeChatNotifier();
      final WriteResult res =
          await notifier.completeWorkoutFromPrompt(istDateStr(date));
      expect(res.success, isTrue);

      final sched =
          HiveService.instance.workoutBox.get(WorkoutWriteService.scheduleKey(date))
              as Map;
      expect(sched['status'], 'completed',
          reason: 'The explicit [Complete workout] tap must complete the day.');
      expect(sched['completed_via'], 'tap',
          reason: 'A user tap must stamp completed_via:tap.');

      // The prompt row is resolved (filtered out on the next read).
      final prompt = completionPrompt(istDateStr(date));
      expect(prompt, isNotNull);
      expect(prompt!['resolved_at'], isNotNull,
          reason: 'A successful tap must stamp resolved_at on the prompt row.');
    });

    test('(d) a swapped exercise counts as logged under EITHER name', () async {
      final date = DateTime.now();
      // The plan was Incline Bench; the user swapped to Dumbbell Bench. The
      // schedule row carries the new name + swapped_from = the old one.
      await seedScheduledDay(date, [
        {
          'exercise_name': 'Dumbbell Bench Press',
          'swapped_from': 'Incline Bench Press',
        },
      ]);

      // Log under the OLD (swapped-from) name — the swap-tolerant check must
      // still count it as logged, so the single-exercise day auto-completes.
      await coachLog(date, 'Incline Bench Press');

      final sched =
          HiveService.instance.workoutBox.get(WorkoutWriteService.scheduleKey(date))
              as Map;
      expect(sched['status'], 'completed',
          reason: 'A log under the swapped_from name must count as logged '
              '(swap-tolerant), completing the single-exercise day.');
    });

    test('(e) the completion_prompt row is deduped — one per date, superseded',
        () async {
      final date = DateTime.now();
      await seedScheduledDay(date, [
        {'exercise_name': 'Bench Press'},
        {'exercise_name': 'Overhead Press'},
        {'exercise_name': 'Triceps Pushdown'},
      ]);

      await coachLog(date, 'Bench Press');
      final first = completionPrompt(istDateStr(date));
      expect(first, isNotNull);
      expect(first!['logged_count'], 1);
      final firstCreatedAt = first['created_at'];

      await coachLog(date, 'Overhead Press');

      // Exactly ONE completion_prompt key for this date — updated in place.
      final promptKeys = HiveService.instance.coachBox.keys
          .where((k) => k.toString().startsWith('completion_prompt_'))
          .toList();
      expect(promptKeys.length, 1,
          reason: 'Only one completion_prompt row per date (date-scoped key, '
              'UPDATE-not-INSERT).');

      final second = completionPrompt(istDateStr(date));
      expect(second!['logged_count'], 2,
          reason: 'The superseding write must refresh the logged_count.');
      expect(second['created_at'], firstCreatedAt,
          reason: 'created_at is preserved across supersede so the card keeps '
              'its scroll position.');
    });

    test('snapshot carries today_workout_completion counts', () async {
      final date = DateTime.now();
      await seedScheduledDay(date, [
        {'exercise_name': 'Bench Press'},
        {'exercise_name': 'Overhead Press'},
      ]);
      await coachLog(date, 'Bench Press');

      final snap = AiSnapshotBuilder.instance.buildAiContext();
      final todayWorkout = snap['today_workout'] as Map?;
      expect(todayWorkout, isNotNull);
      final completion =
          todayWorkout!['today_workout_completion'] as Map?;
      expect(completion, isNotNull,
          reason: 'today_workout must carry today_workout_completion counts.');
      expect(completion!['total_planned'], 2);
      expect(completion['total_logged'], 1);
      expect(completion['all_logged'], false);
    });

    test('ChatHistoryNotifier renders an unresolved prompt + skips a resolved one',
        () async {
      final date = DateTime.now();
      await seedScheduledDay(date, [
        {'exercise_name': 'Bench Press'},
        {'exercise_name': 'Overhead Press'},
      ]);
      await coachLog(date, 'Bench Press');

      final notifier = makeChatNotifier();

      // The prompt row surfaces as a kind:'completion_prompt' ChatMessage.
      final rendered = notifier.build();
      final prompts =
          rendered.where((m) => m.kind == 'completion_prompt').toList();
      expect(prompts.length, 1,
          reason: 'An unresolved completion_prompt must render as one tile.');
      expect(prompts.first.promptData, isNotNull);
      expect(prompts.first.promptData!.planned, 2);
      expect(prompts.first.promptData!.logged, 1);

      // After [Log more] resolves it, the tile disappears.
      await notifier.resolveCompletionPrompt(istDateStr(date));
      final afterResolve = notifier
          .build()
          .where((m) => m.kind == 'completion_prompt')
          .toList();
      expect(afterResolve, isEmpty,
          reason: 'A resolved completion_prompt must not render.');
    });

    // ── finding-1 — chat refreshes after a REAL partial coach logSet dispatch ──
    test(
        'finding-1: a REAL log_set dispatch surfaces the completion_prompt card '
        'in chatHistoryProvider state immediately (no next-message wait)',
        () async {
      final date = DateTime.now();
      final dateStr = istDateStr(date);
      await seedScheduledDay(date, [
        {'exercise_name': 'Bench Press'},
        {'exercise_name': 'Overhead Press'},
        {'exercise_name': 'Triceps Pushdown'},
      ]);

      // Build a container + a real Ref, then WATCH chatHistoryProvider so its
      // state is materialized (starts as the welcome message, no prompt).
      final c = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => const Stream.empty()),
      ]);
      addTearDown(c.dispose);
      final ref = c.read(_refProvider);

      final before = c.read(chatHistoryProvider);
      expect(before.where((m) => m.kind == 'completion_prompt'), isEmpty,
          reason: 'No prompt card before the log_set dispatch.');

      // Drive the REAL dispatch path — execute() runs _executeLogSet (which
      // writes the completion_prompt row via _maybeCompleteScheduledDay) AND
      // the post-tool invalidation block (which must now refreshFromHive() the
      // chat). exerciseId doubles as the name (no library entry → fallback).
      final intent = ToolIntent(
        id: 'intent_finding1',
        type: 'log_set',
        payload: {
          // Resolves via exerciseBox['ex_bench'] → 'Bench Press', matching the
          // schedule's exercise_name so the day is a genuine partial (1 of 3).
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
      expect(res.success, isTrue, reason: 'The log_set dispatch must succeed.');

      // The day is a genuine partial → a completion_prompt row was written.
      expect(completionPrompt(dateStr), isNotNull);

      // The card is now visible in chatHistoryProvider STATE without any
      // further action (this is the finding-1 regression: pre-fix the state
      // was stale until the next message rebuilt it).
      final after = c.read(chatHistoryProvider);
      final prompts = after.where((m) => m.kind == 'completion_prompt').toList();
      expect(prompts.length, 1,
          reason: 'The dispatch must refreshFromHive() so the completion_prompt '
              'card surfaces in chatHistoryProvider state immediately.');
      expect(prompts.first.promptData!.planned, 3);
      expect(prompts.first.promptData!.logged, 1);
    });

    // ── finding-2 — timezone double-shift in completeWorkoutFromPrompt ──
    test(
        'finding-2: completeWorkoutFromPrompt flips the IST-keyed schedule row '
        '(no east-of-IST double-shift)', () async {
      final date = DateTime.now();
      final dateStr = istDateStr(date);
      await seedScheduledDay(date, [
        {'exercise_name': 'Bench Press'},
        {'exercise_name': 'Overhead Press'},
        {'exercise_name': 'Triceps Pushdown'},
      ]);
      await coachLog(date, 'Bench Press');
      expect(completionPrompt(dateStr), isNotNull);

      final notifier = makeChatNotifier();
      final res = await notifier.completeWorkoutFromPrompt(dateStr);
      expect(res.success, isTrue);

      // The EXACT `schedule_<dateStr>` row (IST-keyed) must be the one that
      // flipped — not a neighbouring day. Pre-fix, markCompleted received
      // DateTime.parse(dateStr) (device-LOCAL midnight); east of UTC+5:30 its
      // internal istDateStr keyed a DIFFERENT day, leaving THIS row 'planned'.
      final sched = HiveService.instance.workoutBox
          .get(WorkoutWriteService.scheduleKey(date)) as Map;
      expect(sched['status'], 'completed',
          reason: 'The IST-keyed schedule_<dateStr> row must complete.');
      expect(sched['completed_via'], 'tap');
    });

    test(
        'finding-2: the date-key conversion round-trips through istDateStr on '
        'ANY host TZ (the invariant DateTime.parse breaks east of UTC+5:30)',
        () {
      // The fix hands markCompleted DateTime.utc(y,m,d); markCompleted's
      // internal istDateStr(date) must map it BACK to the same yyyy-MM-dd.
      for (final ds in ['2026-07-06', '2026-01-01', '2026-12-31']) {
        final converted =
            ChatHistoryNotifier.utcDateFromIstDateStrForTest(ds);
        expect(converted, isNotNull);
        expect(WorkoutWriteService.istDateStr(converted!), ds,
            reason: 'DateTime.utc(y,m,d) round-trips through istDateStr on any '
                'host TZ.');
      }

      // Demonstrate the pre-fix defect concretely: on a UTC+13 host, LOCAL
      // midnight of 2026-07-06 is 2026-07-05 11:00 UTC. istDateStr (+5:30) of
      // THAT lands on 2026-07-05 — the WRONG day. The fix's UTC-midnight value
      // does not. (No host-TZ dependency: we build the local-midnight instant
      // explicitly.)
      final utc13LocalMidnight = DateTime.utc(2026, 7, 5, 11, 0); // 06 @ +13
      expect(WorkoutWriteService.istDateStr(utc13LocalMidnight), '2026-07-05',
          reason: 'Pre-fix (local parse) east of UTC+5:30 shifts to the '
              'previous day — the bug this fix removes.');
      expect(
          WorkoutWriteService.istDateStr(
              ChatHistoryNotifier.utcDateFromIstDateStrForTest('2026-07-06')!),
          '2026-07-06',
          reason: 'Fix (UTC midnight) keys the correct day regardless of host.');
    });

    // ── finding-4 — empty exercises[] must NOT vacuously auto-complete ──
    test(
        'finding-4: a non-rest schedule with exercises:[] + one coach logSet '
        'does NOT flip to completed (writes the tap-card instead)', () async {
      final date = DateTime.now();
      final dateStr = istDateStr(date);
      // A legacy / restored / ad-hoc non-rest day carrying NO planned exercises.
      await seedScheduledDay(date, const [], type: 'custom_template');

      // One ad-hoc coach log on this plan-less day.
      await coachLog(date, 'Bench Press');

      final sched = HiveService.instance.workoutBox
          .get(WorkoutWriteService.scheduleKey(date)) as Map;
      expect(sched['status'], 'planned',
          reason: 'An empty exercises[] must NOT vacuously auto-complete off '
              'ONE ad-hoc log (the resurrected founder bug). It stays planned.');
      expect(sched['completed_via'], isNull,
          reason: 'No auto-completion means no completed_via stamp.');

      // Instead a completion_prompt tap-card is written (planned_count == 0 →
      // the card suppresses its progress line but still requires an explicit
      // [Complete workout] tap to finish the plan-less day).
      final prompt = completionPrompt(dateStr);
      expect(prompt, isNotNull,
          reason: 'A plan-less day writes the tap-card instead of completing.');
      expect(prompt!['planned_count'], 0);
      expect(prompt['resolved_at'], isNull);
    });
  });
}
