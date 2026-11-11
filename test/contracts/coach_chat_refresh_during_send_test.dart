// Diagnose 3e7b41 (found by the S3 B-pass, seat 2 F3): a chat refresh from
// Hive while a send is in flight. The loading bubble lives only in memory and
// the turn's Hive row is still `pending`, which ChatHistoryNotifier.build
// renders as a "didn't finish" error (the crash-leftover case). The tool
// dispatcher refreshes the chat after a log_set APPLY (and after the S3
// tile), so an APPLY tapped while a reply is pending ran this sequence: the
// dots became a false "didn't finish - Tap Retry", and the reply's
// replaceLastMessage then overwrote whatever was last (a tile the APPLY had
// just written). The steps below are SendMessageNotifier.send's, in order;
// the last group pins that every loading bubble carries the turn's coachKey.

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/ai_service.dart';
import 'package:icanbefitter/core/services/completion_prompt_store.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/train/services/coach_day_completion.dart';

const _userA = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

/// The model call is held open by a Completer per call, so a test can act
/// while the reply is pending.
class _FakeAi implements AiService {
  final calls = <Completer<AiChatResponse>>[];

  @override
  Future<AiChatResponse> chat(String message, Map<String, dynamic> context,
      {List<Map<String, dynamic>>? history}) {
    final c = Completer<AiChatResponse>();
    calls.add(c);
    return c.future;
  }

  @override
  Future<AiChatResponse> chatWithMedia(String message, String mediaUrl,
      String mediaType, Map<String, dynamic> context) {
    final c = Completer<AiChatResponse>();
    calls.add(c);
    return c.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProSub implements SubscriptionService {
  _ProSub({this.pro = true});
  final bool pro;

  @override
  bool isPro() => pro;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final events = <String>[];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_chat_refresh_inflight');
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


  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(chatHistoryProvider, (_, __) {});
    addTearDown(sub.close);
    return c;
  }

  const didNotFinish = "This message didn't finish";

  Future<ChatHistoryNotifier> startSend(ProviderContainer c, String q,
      {bool keyed = true}) async {
    final n = c.read(chatHistoryProvider.notifier);
    final key = await CoachInteractionRepository.instance
        .saveUserMessagePending(userMessage: q, mode: 'quick');
    n.addMessage(ChatMessage(text: q, isUser: true, timestamp: DateTime.now()));
    n.addMessage(ChatMessage(
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
        isLoading: true,
        coachKey: keyed ? key : null));
    return n;
  }

  test('a refresh during an in-flight send keeps the loading bubble last and '
      'shows no "didn\'t finish" error', () async {
    final c = container();
    final n = await startSend(c, 'q2');
    n.refreshFromHive(); // what the dispatcher runs after a log_set APPLY
    final s = c.read(chatHistoryProvider);
    expect(s.last.isLoading, isTrue);
    expect(s.where((m) => m.text.startsWith(didNotFinish)), isEmpty);
    n.replaceLastMessage(
        ChatMessage(text: 'a2', isUser: false, timestamp: DateTime.now()));
    final after = c.read(chatHistoryProvider);
    expect(after.last.text, 'a2');
    expect(after.where((m) => m.isUser && m.text == 'q2'), hasLength(1));
    expect(after.where((m) => m.text.startsWith(didNotFinish)), isEmpty);
  });

  test('a tile written during an in-flight send survives the reply', () async {
    final c = container();
    final n = await startSend(c, 'q3');
    await CompletionPromptStore.instance.write(
        dateStr: istTodayStr(), plannedCount: 3, loggedCount: 1, reshow: true);
    n.refreshFromHive();
    n.replaceLastMessage(
        ChatMessage(text: 'a3', isUser: false, timestamp: DateTime.now()));
    final after = c.read(chatHistoryProvider);
    expect(after.where((m) => m.kind == 'completion_prompt'), hasLength(1));
    expect(after.last.text, 'a3');
  });

  test('a loading bubble with no coachKey is still kept LAST, so the reply '
      'never overwrites a tile (degrade)', () async {
    final c = container();
    final n = await startSend(c, 'q4', keyed: false);
    await CompletionPromptStore.instance.write(
        dateStr: istTodayStr(), plannedCount: 3, loggedCount: 1, reshow: true);
    n.refreshFromHive();
    expect(c.read(chatHistoryProvider).last.isLoading, isTrue);
    n.replaceLastMessage(
        ChatMessage(text: 'a4', isUser: false, timestamp: DateTime.now()));
    expect(
        c.read(chatHistoryProvider)
            .where((m) => m.kind == 'completion_prompt'),
        hasLength(1));
  });

  test('an OLDER crash-leftover pending row keeps its "didn\'t finish" '
      'bubble while a newer send is in flight (mirror)', () async {
    final c = container();
    await CoachInteractionRepository.instance
        .saveUserMessagePending(userMessage: 'old', mode: 'quick');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final n = await startSend(c, 'q5');
    n.refreshFromHive();
    final s = c.read(chatHistoryProvider);
    expect(s.where((m) => m.text.startsWith(didNotFinish)), hasLength(1));
    expect(s.last.isLoading, isTrue);
  });

  test('retry: the loading bubble goes in BEFORE the refresh, so the old '
      'error bubble is gone once the reply lands', () async {
    final c = container();
    final n = c.read(chatHistoryProvider.notifier);
    final key = await CoachInteractionRepository.instance
        .saveUserMessagePending(userMessage: 'q6', mode: 'quick');
    // The turn failed earlier; the user taps Retry: send() resets the row to
    // pending, adds the keyed loading bubble, then refreshes.
    n.refreshFromHive();
    expect(c.read(chatHistoryProvider).where((m) => m.isError), hasLength(1));
    n.addMessage(ChatMessage(
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
        isLoading: true,
        coachKey: key));
    n.refreshFromHive();
    n.replaceLastMessage(
        ChatMessage(text: 'a6', isUser: false, timestamp: DateTime.now()));
    final after = c.read(chatHistoryProvider);
    expect(after.where((m) => m.isError), isEmpty);
    expect(after.last.text, 'a6');
    expect(after.where((m) => m.isUser && m.text == 'q6'), hasLength(1));
  });

  test('every loading bubble in the send paths carries the turn\'s coachKey, '
      'and the retry adds it before the refresh', () {
    final src = File('lib/features/ai_coach/providers/ai_coach_provider.dart')
        .readAsStringSync();
    final sites = RegExp(r'isLoading: true,\s*\n\s*coachKey: coachKey,')
        .allMatches(src)
        .length;
    expect(RegExp(r'isLoading: true').allMatches(src).length, sites);
    expect(sites, 2);
    final retry = src.indexOf('if (existingCoachKey != null) {\n      chatNotifier.refreshFromHive();');
    expect(retry, isNonNegative);
    expect(src.lastIndexOf('isLoading: true', retry), isNonNegative);
    expect(src.lastIndexOf('isLoading: true', retry),
        greaterThan(src.lastIndexOf('Future<void> send(', retry)));
  });

  group('through the real SendMessageNotifier.send', () {
    late _FakeAi ai;

    ProviderContainer sendContainer({bool pro = true}) {
      ai = _FakeAi();
      final c = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => const Stream.empty()),
        // One stable owner token: the chat and the limit notifier rebuild on
        // it, and a rebuild mid-send is not what these tests measure.
        authUserIdTokenProvider.overrideWithValue(_userA),
        aiServiceProvider.overrideWithValue(ai),
        subscriptionServiceProvider.overrideWithValue(_ProSub(pro: pro)),
      ]);
      addTearDown(c.dispose);
      // The screen keeps these alive while a send runs; an unlistened
      // provider is disposed between awaits in a bare container.
      for (final sub in [
        c.listen(chatHistoryProvider, (_, __) {}),
        c.listen(messageLimitProvider, (_, __) {}),
        c.listen(sendMessageProvider, (_, __) {}),
      ]) {
        addTearDown(sub.close);
      }
      return c;
    }

    Future<void> untilCalls(int n) async {
      for (var i = 0; i < 200 && ai.calls.length < n; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(ai.calls.length, n, reason: 'the model call was reached');
    }

    AiChatResponse reply(String t) =>
        AiChatResponse(reply: t, modelUsed: 'test', tokensUsed: 0);

    test('retry: a refresh while the reply is pending shows the dots, not '
        '"didn\'t finish", and no error is left once it lands', () async {
      final c = sendContainer();
      final repo = CoachInteractionRepository.instance;
      final key =
          await repo.saveUserMessagePending(userMessage: 'q7', mode: 'quick');
      await repo.updateInteractionWithError(key, errorText: 'boom');
      c.read(chatHistoryProvider.notifier).refreshFromHive();
      expect(c.read(chatHistoryProvider).where((m) => m.isError),
          hasLength(1));

      final f = c
          .read(sendMessageProvider.notifier)
          .send('q7', existingCoachKey: key);
      await untilCalls(1);
      var s = c.read(chatHistoryProvider);
      expect(s.last.isLoading, isTrue);
      expect(s.where((m) => m.isError), isEmpty,
          reason: 'the retried turn shows the dots, not its old error');
      // A log_set APPLY (or the tile) refreshes the chat mid-flight.
      c.read(chatHistoryProvider.notifier).refreshFromHive();
      s = c.read(chatHistoryProvider);
      expect(s.last.isLoading, isTrue);
      expect(s.where((m) => m.isError), isEmpty);

      final before = c.read(messageLimitProvider);
      ai.calls.single.complete(reply('a7'));
      await f;
      // send's LAST step is an unawaited limit increment: wait for it, so
      // the container is not disposed under its Hive write.
      for (var i = 0;
          i < 200 && c.read(messageLimitProvider) == before;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      s = c.read(chatHistoryProvider);
      expect(s.where((m) => m.isError), isEmpty);
      expect(s.where((m) => m.isLoading), isEmpty);
      expect(s.last.text, 'a7');
      expect(s.where((m) => m.isUser && m.text == 'q7'), hasLength(1));
    });

    test('two sends in one frame: only the first runs, no orphan loading '
        'bubble (the flag is claimed before the first await)', () async {
      final c = sendContainer();
      final n = c.read(sendMessageProvider.notifier);
      final f1 = n.send('q8');
      final f2 = n.send('q9'); // same frame: a double tap
      await f2;
      await untilCalls(1);
      expect(c.read(sendMessageProvider), isTrue);
      final before = c.read(messageLimitProvider);
      ai.calls.single.complete(reply('a8'));
      await f1;
      for (var i = 0;
          i < 200 && c.read(messageLimitProvider) == before;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(ai.calls, hasLength(1), reason: 'the second send never ran');
      final s = c.read(chatHistoryProvider);
      expect(s.where((m) => m.isLoading), isEmpty);
      expect(s.where((m) => m.isUser && m.text == 'q9'), isEmpty);
      expect(s.last.text, 'a8');
      expect(c.read(sendMessageProvider), isFalse);
    });

    test('two media sends in one frame: only the first runs (sendWithMedia '
        'claims the flag before its first await too)', () async {
      final c = sendContainer();
      final n = c.read(sendMessageProvider.notifier);
      final f1 = n.sendWithMedia('m1', mediaUrl: 'https://x/a.jpg');
      final f2 = n.sendWithMedia('m2', mediaUrl: 'https://x/b.jpg');
      await f2;
      await untilCalls(1);
      ai.calls.single.complete(reply('ma'));
      await f1;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(ai.calls, hasLength(1), reason: 'the second media send never ran');
      final s = c.read(chatHistoryProvider);
      expect(s.where((m) => m.isLoading), isEmpty);
      expect(s.where((m) => m.isUser && m.text == 'm2'), isEmpty);
      expect(c.read(sendMessageProvider), isFalse);
    });

    test('an early return INSIDE the body (free daily limit reached) still '
        'releases the flag', () async {
      await HiveService.instance.userBox.put(
          'msg_count_${istDateStr(DateTime.now())}',
          AppConstants.freeAiMessagesPerDay);
      final c = sendContainer(pro: false);
      await c.read(sendMessageProvider.notifier).send('over the limit');
      expect(ai.calls, isEmpty, reason: 'the limit stopped the send');
      expect(c.read(sendMessageProvider), isFalse,
          reason: 'a stuck flag would block every later send');
    });

    test('an early return (empty message) never claims the flag', () async {
      final c = sendContainer();
      await c.read(sendMessageProvider.notifier).send('   ');
      expect(c.read(sendMessageProvider), isFalse);
    });
  });

  test('without a send in flight a refresh still shows a crash-leftover '
      'pending row as "didn\'t finish" (mirror)', () async {
    final c = container();
    await CoachInteractionRepository.instance
        .saveUserMessagePending(userMessage: 'old', mode: 'quick');
    c.read(chatHistoryProvider.notifier).refreshFromHive();
    expect(
        c.read(chatHistoryProvider)
            .where((m) => m.text.startsWith(didNotFinish)),
        hasLength(1));
  });
}
