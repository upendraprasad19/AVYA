// BEHAVIORAL + SOURCE TEST — OI-503 client half (plan
// docs/plans/2026-11-13-coach-chat-time-dup.md section 4 C3; diagnose d4a7c9).
//
// Writer: SendMessageNotifier.send / sendWithMedia (ai_coach_provider.dart)
//   pass the turn's Hive key as `clientKey`; AiService.chat / chatWithMedia
//   (lib/core/services/ai_service.dart) put it in the request body as
//   `client_key`, in BOTH transports.
// Reader: ai-proxy / ai-media-proxy (store it); the in-flight counter
//   (CoachInteractionRepository.isInFlight) is read by the restore and the push.
//
// The counter must be up for the whole send, from the moment the key is known
// until after the last Hive write, and released on every exit.

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/ai_service.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/coach_call_budget.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

const _user = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

class _Call {
  _Call(this.clientKey, this.inFlightDuringCall,
      {this.clientRetry = false, this.budget});
  final String? clientKey;
  final bool inFlightDuringCall;

  /// OI-505 fix 4: the Retry marker the notifier passed (chat only).
  final bool clientRetry;

  /// OI-505 fix 2: the per-call budget the notifier passed.
  final CoachCallBudget? budget;
  final done = Completer<AiChatResponse>();
}

class _RecordingAi implements AiService {
  final calls = <_Call>[];

  _Call _record(String? clientKey,
      {bool clientRetry = false, CoachCallBudget? budget}) {
    final c = _Call(
      clientKey,
      clientKey != null && CoachInteractionRepository.isInFlight(clientKey),
      clientRetry: clientRetry,
      budget: budget,
    );
    calls.add(c);
    return c;
  }

  @override
  Future<AiChatResponse> chat(String message, Map<String, dynamic> context,
          {List<Map<String, dynamic>>? history,
          String? clientKey,
          bool clientRetry = false,
          CoachCallBudget? budget}) =>
      _record(clientKey, clientRetry: clientRetry, budget: budget).done.future;

  @override
  Future<AiChatResponse> chatWithMedia(String message, String mediaUrl,
          String mediaType, Map<String, dynamic> context,
          {String? clientKey, CoachCallBudget? budget}) =>
      _record(clientKey, budget: budget).done.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProSub implements SubscriptionService {
  @override
  bool isPro() => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _strip(String s) => s
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('coach_client_key_request');
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
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    await HiveUserSession.closeAll();
  });

  group('through the real SendMessageNotifier', () {
    late _RecordingAi ai;

    ProviderContainer container() {
      ai = _RecordingAi();
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
      for (var i = 0; i < 200 && ai.calls.length < n; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(ai.calls.length, n, reason: 'the model call was reached');
    }

    AiChatResponse reply(String t) =>
        AiChatResponse(reply: t, modelUsed: 'test', tokensUsed: 0);

    // send's LAST step is an unawaited limit increment: wait for it, so the
    // container is not disposed under its Hive write (the sibling
    // coach_chat_refresh_during_send_test.dart pattern).
    Future<void> settleLimit(ProviderContainer c, int before) async {
      for (var i = 0; i < 200 && c.read(messageLimitProvider) == before; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    String onlyChatKey() => HiveService.instance.coachBox.keys
        .whereType<String>()
        .singleWhere((k) => RegExp(r'^coach_[0-9]+$').hasMatch(k));

    test('a new send carries its row key and is in flight until after its last Hive write',
        () async {
      final c = container();
      final f = c.read(sendMessageProvider.notifier).send('what is my workout');
      await untilCalls(1);
      final key = onlyChatKey();
      expect(ai.calls.single.clientKey, key);
      expect(ai.calls.single.inFlightDuringCall, isTrue);
      expect(ai.calls.single.clientRetry, isFalse,
          reason: 'OI-505: a NEW ask never carries the Retry marker, so a deliberate repeat is never served a stored answer');
      expect(ai.calls.single.budget, isNotNull, reason: 'OI-505: every chat call carries its budget');
      final before = c.read(messageLimitProvider);
      ai.calls.single.done.complete(reply('Push day'));
      await f;
      await settleLimit(c, before);
      expect(CoachInteractionRepository.isInFlight(key), isFalse);
      expect((HiveService.instance.coachBox.get(key) as Map)['ai_response'], 'Push day',
          reason: 'released only after the reply was written');
    });

    test('a failed send releases the key too', () async {
      final c = container();
      final f = c.read(sendMessageProvider.notifier).send('q');
      await untilCalls(1);
      final key = onlyChatKey();
      ai.calls.single.done.completeError(Exception('Gemini 503'));
      await f;
      expect(CoachInteractionRepository.isInFlight(key), isFalse);
      expect((HiveService.instance.coachBox.get(key) as Map)['failed'], isTrue);
    });

    test('Retry: the SAME key, counted before the reset put, released after', () async {
      final c = container();
      final repo = CoachInteractionRepository.instance;
      final key = await repo.saveUserMessagePending(userMessage: 'q2', mode: 'quick');
      await repo.updateInteractionWithError(key, errorText: 'boom');
      var countedAtReset = false;
      final sub = HiveService.instance.coachBox.watch(key: key).listen((_) {
        countedAtReset = countedAtReset || CoachInteractionRepository.isInFlight(key);
      });
      addTearDown(sub.cancel);
      final f = c.read(sendMessageProvider.notifier).send('q2', existingCoachKey: key);
      await untilCalls(1);
      expect(ai.calls.single.clientKey, key);
      expect(ai.calls.single.inFlightDuringCall, isTrue);
      expect(ai.calls.single.clientRetry, isTrue,
          reason: 'OI-505 fix 4: the Retry button (existingCoachKey) is the ONLY sender of the marker');
      final before = c.read(messageLimitProvider);
      ai.calls.single.done.complete(reply('ok'));
      await f;
      await settleLimit(c, before);
      expect(countedAtReset, isTrue, reason: 'the reset put happens while counted');
      expect(CoachInteractionRepository.isInFlight(key), isFalse);
    });

    test('media: the row key goes to chatWithMedia, in flight during the call, released after',
        () async {
      final c = container();
      final f = c.read(sendMessageProvider.notifier).sendWithMedia('my squat',
          mediaUrl: 'https://x.supabase.co/storage/v1/object/chat-media/u/a.jpg');
      await untilCalls(1);
      final key = onlyChatKey();
      expect(ai.calls.single.clientKey, key);
      expect(ai.calls.single.inFlightDuringCall, isTrue);
      ai.calls.single.done.complete(reply('Good depth'));
      await f;
      expect(CoachInteractionRepository.isInFlight(key), isFalse);
    });
  });

  group('source pins', () {
    final svc = _strip(File('lib/core/services/ai_service.dart').readAsStringSync());
    final provider = _strip(File(
      'lib/features/ai_coach/providers/ai_coach_provider.dart',
    ).readAsStringSync());

    test('all four request bodies carry client_key; both fallbacks receive it', () {
      expect("'client_key': ?clientKey,".allMatches(svc).length, 4);
      // OI-505: the fallbacks also receive the Retry marker (chat only) and the
      // call budget; the exact text is repointed, never loosened.
      expect(
        "_directHttpCall('ai-proxy', message, compact,\n            history: history,\n            clientKey: clientKey,\n            clientRetry: clientRetry,\n            budget: budget);"
            .allMatches(svc)
            .length,
        2,
      );
      expect(
        '_directMediaHttpCall(message, mediaUrl, mediaType, compact,\n            clientKey: clientKey, budget: budget);'
            .allMatches(svc)
            .length,
        2,
      );
    });

    test('the Retry marker is in BOTH chat bodies (transport and fallback) and in no media body', () {
      expect("if (clientRetry) 'client_retry': true,".allMatches(svc).length, 2);
      final media = svc.substring(svc.indexOf('Future<AiChatResponse> chatWithMedia('));
      expect(media, isNot(contains('client_retry')));
    });

    test('predict sends no key', () {
      final start = svc.indexOf('Future<AiChatResponse> predict(');
      final body = svc.substring(start, svc.indexOf('\n  }\n', start));
      expect(body, isNot(contains('client_key')));
    });

    test('both chat calls of a send (primary and auth re-send) go through _chatBounded; it and the media call pass the key',
        () {
      // OI-505: one helper owns the timeout, the budget and the Retry marker.
      final viaHelper = RegExp(
          r'_chatBounded\(\s*message,\s*\w+,\s*history: coachHistory,\s*coachKey: coachKey,\s*isRetry: existingCoachKey != null,');
      expect(viaHelper.allMatches(provider).length, 2,
          reason: 'primary send and auth re-send, both with the history and the marker');
      expect('clientKey: coachKey,\n            clientRetry: isRetry,'.allMatches(provider).length, 1,
          reason: 'the helper forwards the key and the marker');
      expect('clientKey: coachKey,\n            budget: mediaBudget,'.allMatches(provider).length, 1,
          reason: 'the media call passes the key and its budget');
    });

    test('the count opens a try at once, and the finally releases it, in both send bodies', () {
      final open = RegExp(
          r'CoachInteractionRepository\.beginInFlight\(coachKey\);\n\s*try \{');
      expect(open.allMatches(provider).length, 2);
      expect(
        RegExp(r'\} finally \{\n\s*CoachInteractionRepository\.endInFlight\(coachKey\);')
            .allMatches(provider)
            .length,
        2,
      );
      // The Retry's reset put sits inside that try (round 5 P3-a).
      final send = provider.indexOf('Future<void> _sendBody(');
      final begin = provider.indexOf('beginInFlight(coachKey);', send);
      final reset = provider.indexOf("entry['pending'] = true;", send);
      final keyed = provider.indexOf('await _sendKeyed(', send);
      expect(begin, lessThan(reset));
      expect(reset, lessThan(keyed));
      // Every exit of the keyed body (its auth-retry `return` included) is
      // inside _sendKeyed, which only runs inside that try.
      expect('_sendKeyed('.allMatches(provider).length, 2, reason: 'one call, one declaration');
      expect('_sendWithMediaKeyed('.allMatches(provider).length, 2);
    });

    test('the account switch clears the counter', () {
      final sync = File('lib/core/services/sync_service.dart').readAsStringSync();
      final start = sync.indexOf('void _onUserChanged() {');
      expect(sync.substring(start, start + 1200),
          contains('CoachInteractionRepository.clearInFlight();'));
    });
  });
}
