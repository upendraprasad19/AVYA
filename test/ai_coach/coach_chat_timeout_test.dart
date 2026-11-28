// BEHAVIORAL TEST — OI-505 fix 2 (plan docs/plans/2026-11-13-coach-late-link-timeout-retry.md
// section 4 fix 2, section 5; diagnose c8f2a4): the coach chat call has a time
// limit, owned by the SendMessageNotifier.
//
// Writer: SendMessageNotifier._chatBounded / _sendKeyed / _sendWithMediaKeyed
//   (lib/features/ai_coach/providers/ai_coach_provider.dart).
// Reader: the chat bubble (ChatHistoryNotifier state) and the Hive coach row.
//
// Plain `test`s with a few-millisecond timeout override: _sendKeyed does real
// Hive disk I/O, which never drains inside fakeAsync (the sibling
// streak_freeze_refill_race_behavioral_test.dart documents it).
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/ai_service.dart';
import 'package:icanbefitter/core/services/coach_call_budget.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

const _user = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

class _Call {
  _Call(this.clientKey, this.clientRetry, this.budget);
  final String? clientKey;
  final bool clientRetry;
  final CoachCallBudget? budget;
  final done = Completer<AiChatResponse>();
}

class _Ai implements AiService {
  final calls = <_Call>[];

  @override
  Future<AiChatResponse> chat(String message, Map<String, dynamic> context,
      {List<Map<String, dynamic>>? history,
      String? clientKey,
      bool clientRetry = false,
      CoachCallBudget? budget}) {
    final c = _Call(clientKey, clientRetry, budget);
    calls.add(c);
    return c.done.future;
  }

  @override
  Future<AiChatResponse> chatWithMedia(String message, String mediaUrl,
      String mediaType, Map<String, dynamic> context,
      {String? clientKey, CoachCallBudget? budget}) {
    final c = _Call(clientKey, false, budget);
    calls.add(c);
    return c.done.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProSub implements SubscriptionService {
  @override
  bool isPro() => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('coach_chat_timeout');
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
    await HiveUserSession.openForUser(_user);
    SyncService.pausedForSimulation = true;
    CoachInteractionRepository.clearInFlight();
    CoachCallBudget.chatTimeoutOverride = const Duration(milliseconds: 60);
    CoachCallBudget.mediaTimeoutOverride = const Duration(milliseconds: 60);
    CoachCallBudget.turnDeadlineOverride = const Duration(milliseconds: 400);
    CoachCallBudget.minimumResendOverride = const Duration(milliseconds: 60);
    SendMessageNotifier.refreshSessionOverride = null;
  });

  tearDown(() async {
    CoachCallBudget.chatTimeoutOverride = null;
    CoachCallBudget.mediaTimeoutOverride = null;
    CoachCallBudget.turnDeadlineOverride = null;
    CoachCallBudget.minimumResendOverride = null;
    CoachCallBudget.latestAuthResendOverride = null;
    SendMessageNotifier.refreshSessionOverride = null;
    SyncService.pausedForSimulation = false;
    await HiveUserSession.closeAll();
  });

  late _Ai ai;

  ProviderContainer container() {
    ai = _Ai();
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => const Stream.empty()),
      authUserIdTokenProvider.overrideWithValue(_user),
      aiServiceProvider.overrideWithValue(ai),
      subscriptionServiceProvider.overrideWithValue(_ProSub()),
    ]);
    addTearDown(c.dispose);
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
    for (var i = 0; i < 300 && ai.calls.length < n; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ai.calls.length, n, reason: 'the model call was reached');
  }

  String onlyChatKey() => HiveService.instance.coachBox.keys
      .whereType<String>()
      .singleWhere((k) => RegExp(r'^coach_[0-9]+$').hasMatch(k));

  // A successful send ends with an unawaited limit increment: wait for it so
  // the container is not disposed under its Hive write.
  Future<void> settleLimit(ProviderContainer c, int before) async {
    for (var i = 0; i < 200 && c.read(messageLimitProvider) == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  String lastBubbleText(ProviderContainer c) => c.read(chatHistoryProvider).last.text;

  test('T1: a chat call that never answers is abandoned: the timeout copy, Retry kept, the counter released, a late answer ignored',
      () async {
    final c = container();
    await c.read(sendMessageProvider.notifier).send('what is my workout');
    // send() returned: the turn ended on the timeout.
    expect(ai.calls, hasLength(1));
    final key = onlyChatKey();
    final last = c.read(chatHistoryProvider).last;
    expect(last.isError, isTrue);
    expect(last.text, 'The coach took too long to answer. Tap Retry to ask again.');
    expect(last.retryUserMessage, 'what is my workout', reason: 'the Retry button stays');
    expect(ai.calls.single.budget!.expired, isTrue,
        reason: 'the abandoned call is told to stop sending');
    expect(CoachInteractionRepository.isInFlight(key), isFalse);
    expect((HiveService.instance.coachBox.get(key) as Map)['failed'], isTrue);
    // The dropped request answers later: nothing changes, nothing throws.
    ai.calls.single.done.complete(
        AiChatResponse(reply: 'late', modelUsed: 'test', tokensUsed: 0));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(lastBubbleText(c), 'The coach took too long to answer. Tap Retry to ask again.');
    expect((HiveService.instance.coachBox.get(key) as Map)['ai_response'], '');
  });

  test('T2: a TimeoutException whose Duration text contains "401" is a timeout, NOT an auth error: no refresh, no re-send',
      () async {
    var refreshes = 0;
    SendMessageNotifier.refreshSessionOverride = () async => refreshes++;
    final c = container();
    final f = c.read(sendMessageProvider.notifier).send('q');
    await untilCalls(1);
    // `0:00:40.140123` contains 401; the old substring test read it as a 401.
    final hostile = TimeoutException(
        'x', const Duration(seconds: 40, microseconds: 140123));
    expect(hostile.toString(), contains('401'));
    ai.calls.single.done.completeError(hostile);
    await f;
    expect(refreshes, 0, reason: 'no refresh');
    expect(ai.calls, hasLength(1), reason: 'no second send');
    expect(lastBubbleText(c), 'The coach took too long to answer. Tap Retry to ask again.');
  });

  test('T3: an auth error is refreshed and re-sent ONCE, with the same key and the Retry marker of its turn', () async {
    var refreshes = 0;
    SendMessageNotifier.refreshSessionOverride = () async => refreshes++;
    final c = container();
    final before = c.read(messageLimitProvider);
    final f = c.read(sendMessageProvider.notifier).send('q');
    await untilCalls(1);
    ai.calls[0].done.completeError(Exception('401 unauthorized'));
    await untilCalls(2);
    expect(refreshes, 1);
    expect(ai.calls[1].clientKey, ai.calls[0].clientKey);
    expect(ai.calls[1].clientRetry, ai.calls[0].clientRetry,
        reason: 'the re-send of a new ask is a new ask; of a Retry it is a Retry');
    expect(ai.calls[1].budget, isNot(same(ai.calls[0].budget)), reason: 'a fresh budget per send');
    ai.calls[1].done.complete(AiChatResponse(reply: 'ok', modelUsed: 'test', tokensUsed: 0));
    await f;
    await settleLimit(c, before);
    expect(lastBubbleText(c), 'ok');
  });

  test('T3b: the re-send of a Retry carries the Retry marker', () async {
    SendMessageNotifier.refreshSessionOverride = () async {};
    final c = container();
    final before = c.read(messageLimitProvider);
    final repo = CoachInteractionRepository.instance;
    final key = await repo.saveUserMessagePending(userMessage: 'q2', mode: 'quick');
    await repo.updateInteractionWithError(key, errorText: 'boom');
    final f = c.read(sendMessageProvider.notifier).send('q2', existingCoachKey: key);
    await untilCalls(1);
    expect(ai.calls[0].clientRetry, isTrue);
    ai.calls[0].done.completeError(Exception('401 unauthorized'));
    await untilCalls(2);
    expect(ai.calls[1].clientRetry, isTrue,
        reason: 'a re-send without the marker would RUN the turn again and spend a second unit');
    ai.calls[1].done.complete(AiChatResponse(reply: 'ok', modelUsed: 'test', tokensUsed: 0));
    await f;
    await settleLimit(c, before);
  });

  test('T4: the re-send hangs: it is bounded, abandoned, and shows the timeout copy (not the original auth text)', () async {
    SendMessageNotifier.refreshSessionOverride = () async {};
    final c = container();
    final f = c.read(sendMessageProvider.notifier).send('q');
    await untilCalls(1);
    ai.calls[0].done.completeError(Exception('401 unauthorized'));
    await untilCalls(2);
    await f; // the second call never answers: the bound ends the turn
    expect(ai.calls[1].budget!.expired, isTrue);
    expect(lastBubbleText(c), 'The coach took too long to answer. Tap Retry to ask again.');
    expect(CoachInteractionRepository.isInFlight(onlyChatKey()), isFalse);
  });

  test('T4b: the session refresh hangs: it is bounded by its own timeout and ends in the timeout copy', () async {
    // The refresh gets 15 s in production; here the hang is the Completer.
    final never = Completer<void>();
    SendMessageNotifier.refreshSessionOverride = () => never.future;
    CoachCallBudget.authRefreshTimeoutOverride = const Duration(milliseconds: 60);
    addTearDown(() => CoachCallBudget.authRefreshTimeoutOverride = null);
    final c = container();
    final f = c.read(sendMessageProvider.notifier).send('q');
    await untilCalls(1);
    ai.calls[0].done.completeError(Exception('401 unauthorized'));
    await f;
    expect(ai.calls, hasLength(1), reason: 'no send after a refresh that never came back');
    expect(lastBubbleText(c), 'The coach took too long to answer. Tap Retry to ask again.');
  });

  test('T5: an auth error that arrives after the latest re-send time is NOT re-sent (the turn stays inside its deadline)', () async {
    var refreshes = 0;
    SendMessageNotifier.refreshSessionOverride = () async => refreshes++;
    CoachCallBudget.latestAuthResendOverride = Duration.zero;
    final c = container();
    final f = c.read(sendMessageProvider.notifier).send('q');
    await untilCalls(1);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    ai.calls[0].done.completeError(Exception('401 unauthorized'));
    await f;
    expect(refreshes, 0);
    expect(ai.calls, hasLength(1));
    expect(lastBubbleText(c), 'Session error. Please try again.');
  });

  test('T6: a photo turn is bounded too; the copy says it may still be analysed; no Retry button', () async {
    final c = container();
    await c.read(sendMessageProvider.notifier).sendWithMedia('my squat',
        mediaUrl: 'https://x.supabase.co/storage/v1/object/chat-media/u/a.jpg');
    expect(ai.calls, hasLength(1));
    final key = onlyChatKey();
    final last = c.read(chatHistoryProvider).last;
    expect(last.isError, isTrue);
    expect(last.text, contains('may still be analysed'));
    expect(last.retryUserMessage, isNull, reason: 'media failures have no Retry button');
    expect(ai.calls.single.budget!.expired, isTrue);
    expect(CoachInteractionRepository.isInFlight(key), isFalse);
  });

  test('T7: the "still working" answer (503 in_progress), in BOTH exception shapes, gets its own copy before the 503 branch', () async {
    for (final err in <Object>[
      const AiServiceException('in_progress', statusCode: 503),
      FunctionException(status: 503, details: {'error': 'in_progress'}),
    ]) {
      final c = container();
      final f = c.read(sendMessageProvider.notifier).send('q');
      await untilCalls(1);
      ai.calls.single.done.completeError(err);
      await f;
      expect(lastBubbleText(c),
          'The coach is still working on your last message. Tap Retry in a moment.',
          reason: '$err');
      c.dispose();
    }
  });

  test('T8: a plain 503 still shows the temporarily-unavailable copy (the new branch did not swallow it)', () async {
    final c = container();
    final f = c.read(sendMessageProvider.notifier).send('q');
    await untilCalls(1);
    ai.calls.single.done.completeError(FunctionException(status: 503, details: 'boom'));
    await f;
    expect(lastBubbleText(c), 'The AI model is temporarily unavailable. Please try again in a minute.');
  });

  test('T9: a normal answer inside the limit is unaffected: no timeout, the budget is not expired', () async {
    CoachCallBudget.chatTimeoutOverride = const Duration(seconds: 5);
    final c = container();
    final before = c.read(messageLimitProvider);
    final f = c.read(sendMessageProvider.notifier).send('q');
    await untilCalls(1);
    ai.calls.single.done.complete(AiChatResponse(reply: 'Push day', modelUsed: 'test', tokensUsed: 0));
    await f;
    await settleLimit(c, before);
    expect(lastBubbleText(c), 'Push day');
    expect(ai.calls.single.budget!.expired, isFalse);
  });
}
