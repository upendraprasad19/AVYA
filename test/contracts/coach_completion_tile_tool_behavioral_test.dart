// Coach workout parity S3 (OI-492, founder decision C): "I'm done" in chat
// makes the app's own "X of Y - Complete workout" tile appear, one tap total.
// Plan docs/plans/coach-workout-parity-2-server.md 3.1 (client 1-5), 5.1 S3.
//
// Real Hive (path_provider mocked), the REAL dispatcher and the REAL
// providers. The auto-run intent `request_completion_tile`:
//   - re-runs the app's own decision for IST today and writes the tile row
//     ONLY for a part-logged day (askToComplete + at least one log);
//   - never completes anything (status stays planned, no wlog_, count +0);
//   - re-shows the row with a fresh UTC created_at (reshow) so it sorts under
//     the reply that asked for it;
//   - writes nothing while a log_set card waits for APPLY (pendingWrites);
//   - never enters pendingToolIntentsProvider state (no "Logged" pill).
//
// Run this file under TZ=Asia/Kolkata AND TZ=Etc/GMT+12 (the created_at
// ordering cases redden in a different zone each for a local stamp).

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/completion_prompt_store.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/providers/pending_tool_intents_provider.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';
import 'package:icanbefitter/features/ai_coach/screens/ai_coach/screen.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/train/services/coach_day_completion.dart';

final _refProvider = Provider<Ref>((ref) => ref);

const _userA = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const _userB = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final events = <String>[];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_completion_tile');
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
    await HiveUserSession.closeAll();
    for (final name in [
      HiveService.workoutBoxName,
      HiveService.coachBoxName,
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'workoutBox_aaaaaaaa',
      'coachBox_aaaaaaaa',
      'workoutBox_bbbbbbbb',
      'coachBox_bbbbbbbb',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    if (!Hive.isBoxOpen(HiveService.exerciseBoxName)) {
      await Hive.openBox(HiveService.exerciseBoxName);
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(_userA);
    SyncService.pausedForSimulation = true;
    events.clear();
    ErrorTelemetry.debugOnLogEventForTests =
        (op, {String? message}) => events.add('$op:${message ?? ''}');
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required String reason, Map<String, String>? extra}) =>
            events.add('nonfatal:$reason');
  });

  tearDown(() async {
    CoachDayCompletion.debugBeforeTileWrite = null;
    ErrorTelemetry.debugOnLogEventForTests = null;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    SyncService.pausedForSimulation = false;
    await HiveUserSession.closeAll();
  });

  DateTime today() => DateTime.now();
  String todayStr() => istTodayStr();

  Future<void> seedDay(
    List<Map<String, dynamic>> exercises, {
    String status = 'planned',
    String type = 'custom_template',
  }) async {
    await HiveService.instance.workoutBox
        .put(WorkoutWriteService.scheduleKey(today()), {
      'date': todayStr(),
      'workout_name': 'Push Day',
      'status': status,
      'type': type,
      'exercises': exercises,
    });
  }

  Future<void> log(String name) async {
    final r = await WorkoutWriteService.instance.logExercise(
      date: today(),
      exerciseName: name,
      sets: [
        ExerciseSet(
          weightKg: 60,
          reps: 8,
          loggedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ],
      source: WriteSource.aiCoach,
    );
    expect(r.success, isTrue);
  }

  const threePlanned = [
    {'exercise_name': 'Bench Press'},
    {'exercise_name': 'Overhead Press'},
    {'exercise_name': 'Triceps Pushdown'},
  ];

  Map? tileRow() => HiveService.instance.coachBox
      .get(CompletionPromptStore.keyFor(todayStr())) as Map?;

  Map schedRow() => HiveService.instance.workoutBox
      .get(WorkoutWriteService.scheduleKey(today())) as Map;

  bool hasWlog() => HiveService.instance.workoutBox
      .get(WorkoutWriteService.wlogKey(today())) is Map;

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  ToolIntent tileIntent({String id = 'tile_1'}) => ToolIntent(
        id: id,
        type: 'request_completion_tile',
        payload: const {},
        confirmationClass: ConfirmationClass.trivial,
        previewSummary: 'Show the Complete workout tile',
        createdAt: DateTime.now(),
      );

  ToolIntent otherIntent(
    String type,
    ToolIntentStatus status, {
    String id = 'other_1',
    Duration age = Duration.zero,
  }) =>
      ToolIntent(
        id: id,
        type: type,
        payload: const {
          'exerciseId': 'ex',
          'weightKg': 60,
          'reps': 8,
          'sets': 3,
        },
        confirmationClass: ConfirmationClass.trivial,
        previewSummary: '',
        createdAt: DateTime.now().subtract(age),
        status: status,
      );

  Future<ToolExecutionResult> dispatch(ProviderContainer c, ToolIntent i) =>
      ToolDispatcher.instance.execute(c.read(_refProvider), i);

  group('S3 tile — a part-logged day shows the tile and completes nothing', () {
    test('1 of 3 logged: row written 3/1 unresolved; planned; no wlog; count +0; '
        'the chat state shows the tile at once', () async {
      await seedDay(threePlanned);
      await log('Bench Press');
      final progressBefore = HiveService.instance.userBox.get('progress');
      final c = container();
      expect(c.read(chatHistoryProvider)
          .where((m) => m.kind == 'completion_prompt'), isEmpty);

      final res = await dispatch(c, tileIntent());
      expect(res.success, isTrue);
      expect(res.data, CompletionTileOutcome.shown);

      final row = tileRow()!;
      expect(row['planned_count'], 3);
      expect(row['logged_count'], 1);
      expect(row['resolved_at'], isNull);
      expect(schedRow()['status'], 'planned');
      expect(hasWlog(), isFalse);
      expect(HiveService.instance.userBox.get('progress'), progressBefore);

      // refreshFromHive ran: the provider state already holds the tile.
      final tiles = c.read(chatHistoryProvider)
          .where((m) => m.kind == 'completion_prompt')
          .toList();
      expect(tiles, hasLength(1));
      expect(tiles.single.promptData!.planned, 3);
      expect(tiles.single.promptData!.logged, 1);
    });

    test('an off-plan-only log on an askToComplete day SHOWS the tile '
        '(documented asymmetry with the server push)', () async {
      await seedDay(threePlanned);
      await log('Bicep Curl');
      final outcome = await CoachDayCompletion.instance
          .offerTileIfPartial(hasPendingLogSet: false);
      expect(outcome, CompletionTileOutcome.shown);
      expect(tileRow()!['logged_count'], 0);
    });
  });

  group('S3 tile — every non-partial shape writes nothing', () {
    Future<void> expectNothing(CompletionTileOutcome expected) async {
      final outcome = await CoachDayCompletion.instance
          .offerTileIfPartial(hasPendingLogSet: false);
      expect(outcome, expected);
      expect(tileRow(), isNull);
      expect(events, contains('completion_tile_not_shown:${expected.name}'));
    }

    test('already completed (wlog present) -> alreadyDone', () async {
      await seedDay(threePlanned);
      await log('Bench Press');
      await HiveService.instance.workoutBox
          .put(WorkoutWriteService.scheduleKey(today()), {
        ...schedRow(),
        'status': 'completed',
      });
      await HiveService.instance.workoutBox
          .put(WorkoutWriteService.wlogKey(today()), {'date': todayStr()});
      await expectNothing(CompletionTileOutcome.alreadyDone);
    });

    test('completed with no wlog (repairDone) -> alreadyDone', () async {
      await seedDay(threePlanned, status: 'completed');
      await log('Bench Press');
      await expectNothing(CompletionTileOutcome.alreadyDone);
    });

    test('rest day -> notCountable', () async {
      await seedDay(threePlanned, type: 'rest');
      await log('Bench Press');
      await expectNothing(CompletionTileOutcome.notCountable);
    });

    for (final terminal in ['moved', 'dropped']) {
      test('$terminal -> notCountable', () async {
        await seedDay(threePlanned, status: terminal);
        await log('Bench Press');
        await expectNothing(CompletionTileOutcome.notCountable);
      });
    }

    test('no plan row -> notCountable', () async {
      await log('Bench Press');
      await expectNothing(CompletionTileOutcome.notCountable);
    });

    test('every planned exercise logged -> allLogged (nothing written)',
        () async {
      await seedDay(threePlanned.sublist(0, 1));
      await log('Bench Press');
      await expectNothing(CompletionTileOutcome.allLogged);
      expect(schedRow()['status'], 'planned',
          reason: 'the tile never completes; the backstop does');
    });

    test('nothing logged today -> noLogs', () async {
      await seedDay(threePlanned);
      await expectNothing(CompletionTileOutcome.noLogs);
    });
  });

  group('S3 tile — a log_set card waiting for APPLY (hasPendingLogSet)', () {
    Future<CompletionTileOutcome> runWith(List<ToolIntent> state) async {
      await seedDay(threePlanned);
      await log('Bench Press');
      final c = container();
      c.read(pendingToolIntentsProvider.notifier).addIntents(state);
      final res = await dispatch(c, tileIntent());
      expect(res.success, isTrue,
          reason: 'every outcome is a success, never a failed intent');
      return res.data! as CompletionTileOutcome;
    }

    test('a log_set card still waiting for APPLY does NOT block: the tile '
        'shows the counts as they are (B-pass seat 2 F2)', () async {
      expect(
          await runWith([otherIntent('log_set', ToolIntentStatus.pending)]),
          CompletionTileOutcome.shown);
      expect(tileRow()!['logged_count'], 1);
    });

    test('an executing log_set -> pendingWrites', () async {
      expect(
          await runWith([otherIntent('log_set', ToolIntentStatus.executing)]),
          CompletionTileOutcome.pendingWrites);
      expect(tileRow(), isNull);
    });

    for (final st in [
      ToolIntentStatus.failed,
      ToolIntentStatus.executed,
      ToolIntentStatus.rejected,
    ]) {
      test('a ${st.name} log_set does not block (mirror)', () async {
        expect(await runWith([otherIntent('log_set', st)]),
            CompletionTileOutcome.shown);
        expect(tileRow(), isNotNull);
      });
    }

    test('an EXPIRED executing log_set does not block (mirror)', () async {
      expect(
          await runWith([
            otherIntent('log_set', ToolIntentStatus.executing,
                age: const Duration(hours: 2)),
          ]),
          CompletionTileOutcome.shown);
    });

    test('an executing swap_exercise does not block (mirror)', () async {
      expect(
          await runWith(
              [otherIntent('swap_exercise', ToolIntentStatus.executing)]),
          CompletionTileOutcome.shown);
    });

    test('no owner: success with ownerChanged, nothing written '
        '(B-pass seat 2 F1)', () async {
      await seedDay(threePlanned);
      await log('Bench Press');
      final c = container();
      await HiveUserSession.closeAll();
      final res = await dispatch(c, tileIntent(id: 'no_owner'));
      expect(res.success, isTrue,
          reason: 'a signed-out tile is a quiet no-op, not a failed intent');
      expect(res.data, CompletionTileOutcome.ownerChanged);
      await HiveUserSession.openForUser(_userA);
      expect(tileRow(), isNull);
    });

    test('no intents at all -> shown', () async {
      expect(await runWith(const []), CompletionTileOutcome.shown);
    });
  });

  group('S3 tile — reshow and created_at (UTC with Z)', () {
    test('a RESOLVED row for today is re-written unresolved with a fresh UTC '
        'created_at, and sorts after a newer coach reply', () async {
      await seedDay(threePlanned);
      await log('Bench Press');
      await HiveService.instance.coachBox
          .put(CompletionPromptStore.keyFor(todayStr()), {
        'kind': 'completion_prompt',
        'date': todayStr(),
        'planned_count': 3,
        'logged_count': 0,
        'created_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 30))
            .toIso8601String(),
        'resolved_at': DateTime.now().toIso8601String(),
      });
      await CoachInteractionRepository.instance.saveInteraction(
        userMessage: 'how was that',
        aiResponse: 'reply before done',
        modelUsed: 'test',
        mode: 'chat',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final outcome = await CoachDayCompletion.instance
          .offerTileIfPartial(hasPendingLogSet: false);
      expect(outcome, CompletionTileOutcome.shown);
      final row = tileRow()!;
      expect(row['resolved_at'], isNull);
      expect((row['created_at'] as String).endsWith('Z'), isTrue);
      expect(row['logged_count'], 1);

      final c = container();
      final msgs = c.read(chatHistoryProvider);
      final tileAt = msgs.indexWhere((m) => m.kind == 'completion_prompt');
      final replyAt = msgs.indexWhere((m) => m.text == 'reply before done');
      expect(tileAt, isNonNegative);
      expect(replyAt, isNonNegative);
      expect(tileAt, greaterThan(replyAt),
          reason: 'reshow: the tile sorts under the newer reply '
              '(TZ=${DateTime.now().timeZoneName})');
    });

    test('an UNRESOLVED older row also moves to the bottom', () async {
      await seedDay(threePlanned);
      await log('Bench Press');
      await CompletionPromptStore.instance
          .write(dateStr: todayStr(), plannedCount: 3, loggedCount: 1);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await CoachInteractionRepository.instance.saveInteraction(
        userMessage: 'q',
        aiResponse: 'later reply',
        modelUsed: 'test',
        mode: 'chat',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await CoachDayCompletion.instance
          .offerTileIfPartial(hasPendingLogSet: false);
      final msgs = container().read(chatHistoryProvider);
      expect(msgs.indexWhere((m) => m.kind == 'completion_prompt'),
          greaterThan(msgs.indexWhere((m) => m.text == 'later reply')));
    });

    test('a NEW tile row sorts between a coach reply written before it and '
        'one written after it (any host zone)', () async {
      await seedDay(threePlanned);
      await log('Bench Press');
      await CoachInteractionRepository.instance.saveInteraction(
        userMessage: 'q1',
        aiResponse: 'reply one',
        modelUsed: 'test',
        mode: 'chat',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await CoachDayCompletion.instance
          .offerTileIfPartial(hasPendingLogSet: false);
      expect((tileRow()!['created_at'] as String).endsWith('Z'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await CoachInteractionRepository.instance.saveInteraction(
        userMessage: 'q2',
        aiResponse: 'reply two',
        modelUsed: 'test',
        mode: 'chat',
      );
      final msgs = container().read(chatHistoryProvider);
      final tileAt = msgs.indexWhere((m) => m.kind == 'completion_prompt');
      expect(msgs.indexWhere((m) => m.text == 'reply one'), lessThan(tileAt),
          reason: 'TZ=${DateTime.now().timeZoneName}');
      expect(msgs.indexWhere((m) => m.text == 'q2'), greaterThan(tileAt),
          reason: 'TZ=${DateTime.now().timeZoneName}');
    });
  });

  group('S3 tile — owner change and replay', () {
    test('owner change after the first await: nothing written', () async {
      await seedDay(threePlanned);
      await log('Bench Press');
      CoachDayCompletion.debugBeforeTileWrite = () async {
        await HiveUserSession.openForUser(_userB);
      };
      final outcome = await CoachDayCompletion.instance
          .offerTileIfPartial(hasPendingLogSet: false);
      expect(outcome, CompletionTileOutcome.ownerChanged);
      expect(tileRow(), isNull, reason: 'B never gets A\'s tile');
      CoachDayCompletion.debugBeforeTileWrite = null;
      await HiveUserSession.openForUser(_userA);
      expect(tileRow(), isNull, reason: 'A\'s box was not written either');
    });

    test('a replay of the same intent id after the marker writes nothing',
        () async {
      await seedDay(threePlanned);
      await log('Bench Press');
      final c = container();
      await dispatch(c, tileIntent(id: 'replayed'));
      await CompletionPromptStore.instance.resolve(todayStr());
      final res = await dispatch(c, tileIntent(id: 'replayed'));
      expect(res.success, isTrue);
      expect(tileRow()!['resolved_at'], isNotNull,
          reason: 'a second run would have reshown (resolved_at null)');
    });
  });

  group('S3 tile — the auto-run chain', () {
    test('addIntents([tile]) leaves state EMPTY and the dispatcher runs once',
        () async {
      await seedDay(threePlanned);
      await log('Bench Press');
      final c = container();
      // Materialise the chat state first, so a tile in it afterwards proves
      // the dispatch refreshed it through the notifier's own ref.
      final chatSub = c.listen(chatHistoryProvider, (_, __) {});
      addTearDown(chatSub.close);
      expect(c.read(chatHistoryProvider)
          .where((m) => m.kind == 'completion_prompt'), isEmpty);
      c.read(pendingToolIntentsProvider.notifier).addIntents([tileIntent()]);
      expect(c.read(pendingToolIntentsProvider), isEmpty);
      // The dispatch is fire-and-forget: wait for its LAST step (the marker).
      const marker = 'intent_tile_1_dispatched_at';
      for (var i = 0;
          i < 50 && HiveService.instance.coachBox.get(marker) == null;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(HiveService.instance.coachBox.get(marker), isNotNull,
          reason: 'the tile intent ran at once');
      expect(tileRow(), isNotNull);
      expect(tileRow()!['logged_count'], 1);
      expect(
          c.read(chatHistoryProvider)
              .where((m) => m.kind == 'completion_prompt'),
          hasLength(1));
    });

    test('addIntents([log_set]) still enters state', () {
      final c = container();
      c.read(pendingToolIntentsProvider.notifier).addIntents(
          [otherIntent('log_set', ToolIntentStatus.pending, id: 'ls')]);
      expect(c.read(pendingToolIntentsProvider).map((i) => i.id), ['ls']);
    });

    test('a mixed batch: the log_set enters state, the tile does not, and '
        'a card waiting for APPLY does not block the tile', () async {
      await seedDay(threePlanned);
      await log('Bench Press');
      final c = container();
      c.read(pendingToolIntentsProvider.notifier).addIntents([
        otherIntent('log_set', ToolIntentStatus.pending, id: 'ls'),
        tileIntent(id: 'tile_mixed'),
      ]);
      expect(c.read(pendingToolIntentsProvider).map((i) => i.id), ['ls']);
      final marker = 'intent_tile_mixed_dispatched_at';
      for (var i = 0;
          i < 50 && HiveService.instance.coachBox.get(marker) == null;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(HiveService.instance.coachBox.get(marker), isNotNull,
          reason: 'the tile intent ran');
      expect(tileRow(), isNotNull, reason: 'a pending card does not block');
      expect(events, isNot(contains('completion_tile_not_shown:pendingWrites')));
    });

    test('an EARLIER batch\'s executing log_set reaches the tile through '
        'addIntents (its own state is passed; B-pass seat 2 F4)', () async {
      await seedDay(threePlanned);
      await log('Bench Press');
      final c = container();
      final n = c.read(pendingToolIntentsProvider.notifier);
      n.addIntents(
          [otherIntent('log_set', ToolIntentStatus.executing, id: 'ls_x')]);
      n.addIntents([tileIntent(id: 'tile_later')]);
      const marker = 'intent_tile_later_dispatched_at';
      for (var i = 0;
          i < 50 && HiveService.instance.coachBox.get(marker) == null;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(HiveService.instance.coachBox.get(marker), isNotNull,
          reason: 'the tile intent ran');
      expect(tileRow(), isNull, reason: 'pendingWrites: nothing written');
      expect(events, contains('completion_tile_not_shown:pendingWrites'));
      expect(events.where((e) => e.startsWith('nonfatal:')), isEmpty,
          reason: 'no Riverpod self-read failure inside the dispatch');
    });

    test('filterVisibleIntents drops a tile intent even if one is in state',
        () {
      final visible = AiCoachScreen.filterVisibleIntents([
        tileIntent(id: 'in_state'),
        otherIntent('log_set', ToolIntentStatus.pending, id: 'ls'),
      ]);
      expect(visible.map((i) => i.id), ['ls']);
    });
  });

  group('S3 tile — structure pins', () {
    String src(String p) => File(p).readAsStringSync();

    test('the Train service imports nothing from the coach feature', () {
      final train = src('lib/features/train/services/coach_day_completion.dart');
      expect(train.contains('features/ai_coach'), isFalse);
      expect(train.contains("import '../../ai_coach"), isFalse);
    });

    test('the dispatcher\'s tile branch skips sync and pushSnapshot, runs '
        'refreshFromHive and the marker', () {
      final d = src('lib/features/ai_coach/services/tool_dispatcher.dart');
      const open = "if (intent.type == 'request_completion_tile') {";
      final at = d.indexOf(open);
      expect(at, isNonNegative);
      final body = d.substring(at, d.indexOf('return result;', at));
      expect(body, contains('refreshFromHive()'));
      expect(body, contains('_stampDispatched(intent)'));
      for (final f in [
        'syncWorkoutData',
        'pushSnapshot',
        '_invalidateWorkoutProviders',
      ]) {
        expect(body.contains(f), isFalse, reason: f);
      }
      expect(at, lessThan(d.indexOf('if (_isNutritionIntent(intent.type))')));
    });
  });
}
