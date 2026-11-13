// BEHAVIORAL CONTRACT TEST — OI-479 "Clear conversation" (diagnose 5970aa;
// plan docs/plans/2026-11-12-oi479-clear-conversation.md, tests T1-T5).
//
// Writer: CoachChatClear.raiseTo / clear (lib/core/services/coach_chat_clear.dart)
//   -> userBox['coach_chat_cleared_at'].
// Readers that must HIDE rows at or before the marker:
//   T1 ChatHistoryNotifier.build (ai_coach_provider.dart) — today's unresolved
//      completion tile exempt (D3);
//   T2 CoachInteractionRepository.recentHistoryExchanges (D2);
//   T3 CoachInteractionRepository._findRecentDuplicateMessageKey (via
//      saveUserMessagePending): a repeat of a hidden message mints a NEW row.
// Readers that must NOT change (T4): getTodayUserMessageCount, the snapshot's
//   first-message flag, the coaching-notes extraction. (The Home coach tip,
//   once listed here, was removed by OI-502.)
// T5: a cloud restore that re-puts old rows keeps them hidden.
//
// Real Hive throughout; no Supabase (the push is not exercised here: see
// test/sync/coach_chat_cleared_at_sync_test.dart).
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/coach_chat_clear.dart';
import 'package:icanbefitter/core/services/completion_prompt_store.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await setUpHiveForTests();
    // ignore: invalid_use_of_visible_for_testing_member
    HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
  });

  tearDownAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    HiveUserSession.debugCurrentUidResolverForTests = null;
    await tearDownHiveForTests(dir);
  });

  setUp(() async {
    await HiveService.instance.coachBox.clear();
    await HiveService.instance.userBox.delete(CoachChatClear.markerKey);
  });

  Future<void> putChat(
    String key,
    Object? createdAt, {
    String user = 'q',
    String ai = 'a',
  }) {
    final row = <String, dynamic>{
      'id': key,
      'user_message': user,
      'ai_response': ai,
      'mode': 'quick',
      'model_used': 'test',
    };
    if (createdAt != null) row['created_at'] = createdAt;
    return HiveService.instance.coachBox.put(key, row);
  }

  Future<void> setMarker(DateTime at) => HiveService.instance.userBox.put(
    CoachChatClear.markerKey,
    at.toUtc().toIso8601String(),
  );

  List<ChatMessage> thread() {
    final c = ProviderContainer(
      overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
    );
    addTearDown(c.dispose);
    return c.read(chatHistoryProvider);
  }

  List<String> userTexts() =>
      thread().where((m) => m.isUser).map((m) => m.text).toList();

  final t0 = DateTime.utc(2026, 7, 20, 4, 30); // IST 10:00

  group('T1 — the chat thread hides rows at or before the marker', () {
    test('before hidden, after shown; no marker hides nothing', () async {
      await putChat(
        'coach_1',
        t0.subtract(const Duration(minutes: 5)).toIso8601String(),
        user: 'old',
      );
      await putChat(
        'coach_2',
        t0.add(const Duration(minutes: 5)).toIso8601String(),
        user: 'new',
      );
      expect(userTexts(), [
        'old',
        'new',
      ], reason: 'no marker: everything shows');
      await setMarker(t0);
      expect(userTexts(), ['new']);
    });

    test('a row exactly AT the marker is hidden (<=, not <)', () async {
      await putChat('coach_1', t0.toIso8601String(), user: 'at');
      await putChat(
        'coach_2',
        t0.add(const Duration(milliseconds: 1)).toIso8601String(),
        user: 'after',
      );
      await setMarker(t0);
      expect(userTexts(), ['after']);
    });

    test(
      'created_at with no offset is compared as an INSTANT, not as a string',
      () async {
        // A local wall-clock string (no offset), as some writers and restores
        // produce. The marker sits one second AFTER that instant, so the row is
        // hidden on every host zone; a string compare would show it whenever
        // the host is east of UTC (CI pins IST).
        final local = DateTime(2026, 7, 20, 10, 0);
        await putChat('coach_1', local.toIso8601String(), user: 'local-old');
        await putChat(
          'coach_2',
          local.toUtc().add(const Duration(seconds: 2)).toIso8601String(),
          user: 'z-new',
        );
        await setMarker(local.toUtc().add(const Duration(seconds: 1)));
        expect(userTexts(), ['z-new']);
      },
    );

    test(
      'missing or unparseable created_at is hidden once a marker exists',
      () async {
        await putChat('coach_1', null, user: 'no-stamp');
        await putChat('coach_2', 'not-a-date', user: 'bad-stamp');
        await putChat(
          'coach_3',
          t0.add(const Duration(minutes: 1)).toIso8601String(),
          user: 'good',
        );
        await setMarker(t0);
        expect(userTexts(), ['good']);
      },
    );

    test('a fully cleared chat shows only the welcome message', () async {
      await putChat(
        'coach_1',
        t0.subtract(const Duration(minutes: 1)).toIso8601String(),
      );
      await setMarker(t0);
      final msgs = thread();
      expect(msgs, hasLength(1));
      expect(
        msgs.single.isUser,
        isFalse,
        reason: 'the synthetic welcome bubble',
      );
      expect(msgs.single.kind, isNot('completion_prompt'));
    });

    test(
      "D3: today's unresolved completion tile survives a clear; resolved and "
      'past-day tiles do not; a kept tile replaces the welcome',
      () async {
        final today = istTodayStr();
        final store = CompletionPromptStore.instance;
        // Today's tile, written BEFORE the clear.
        await store.write(dateStr: today, plannedCount: 5, loggedCount: 2);
        await putChat(
          'coach_1',
          DateTime.now().toUtc().toIso8601String(),
          user: 'chat',
        );
        await setMarker(DateTime.now().toUtc().add(const Duration(seconds: 1)));

        var msgs = thread();
        expect(
          msgs.where((m) => m.isUser),
          isEmpty,
          reason: 'the chat row is hidden',
        );
        expect(
          msgs.where((m) => m.kind == 'completion_prompt'),
          hasLength(1),
          reason: "today's unresolved tile is kept (D3)",
        );
        expect(
          msgs,
          hasLength(1),
          reason: 'with the tile kept the list is not empty, so no welcome',
        );

        // Completing the day resolves the tile, and then it goes.
        await store.resolve(today);
        msgs = thread();
        expect(msgs.where((m) => m.kind == 'completion_prompt'), isEmpty);
      },
    );
  });

  group('T2 — the coach history replay starts after the marker (D2)', () {
    test(
      'pre-marker exchanges are not replayed; post-marker ones are, in order',
      () async {
        await putChat(
          'coach_1',
          t0.subtract(const Duration(minutes: 2)).toIso8601String(),
          user: 'old',
          ai: 'old-r',
        );
        await putChat(
          'coach_2',
          t0.add(const Duration(minutes: 1)).toIso8601String(),
          user: 'n1',
          ai: 'n1-r',
        );
        await putChat(
          'coach_3',
          t0.add(const Duration(minutes: 2)).toIso8601String(),
          user: 'n2',
          ai: 'n2-r',
        );
        final repo = CoachInteractionRepository.instance;
        expect(repo.recentHistoryExchanges().map((e) => e['text']), [
          'old',
          'old-r',
          'n1',
          'n1-r',
          'n2',
          'n2-r',
        ]);
        await setMarker(t0);
        expect(repo.recentHistoryExchanges().map((e) => e['text']), [
          'n1',
          'n1-r',
          'n2',
          'n2-r',
        ]);
      },
    );
  });

  group('T3 — a repeat of a hidden message mints a NEW visible row', () {
    test('"hi", clear, "hi" within the dedup window', () async {
      final repo = CoachInteractionRepository.instance;
      final first = await repo.saveUserMessagePending(
        userMessage: 'hi',
        mode: 'quick',
      );
      await repo.updateInteractionWithResponse(
        first,
        aiResponse: 'hello',
        modelUsed: 'test',
      );
      // Same message inside the window, no clear: the 60 s dedup reuses it.
      expect(
        await repo.saveUserMessagePending(userMessage: 'hi', mode: 'quick'),
        first,
        reason: 'precondition: the dedup is live',
      );

      await CoachChatClear.raiseTo(DateTime.now().toUtc());
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final second = await repo.saveUserMessagePending(
        userMessage: 'hi',
        mode: 'quick',
      );
      expect(second, isNot(first), reason: 'the hidden row must not be reused');
      expect(userTexts(), ['hi'], reason: 'the new question is visible');
    });
  });

  group('T4 — readers that must NOT change', () {
    test('the daily message count sees hidden rows too', () async {
      final repo = CoachInteractionRepository.instance;
      final today = istTodayStr();
      await putChat('coach_1', '${today}T00:00:01.000Z', user: 'a');
      await putChat('coach_2', '${today}T00:00:02.000Z', user: 'b');
      final before = repo.getTodayUserMessageCount();
      expect(before, 2, reason: 'precondition');
      await setMarker(DateTime.utc(2100));
      expect(
        repo.getTodayUserMessageCount(),
        before,
        reason: 'a clear must never give extra messages',
      );
    });

    test(
      'the first-message flag and coaching notes never read the marker',
      () {
        // Presence-only pins (each reader is deliberately unchanged, plan §3.2):
        // the mutation for this test is ADDING the marker filter to one of them.
        for (final path in const [
          'lib/features/ai_coach/services/ai_snapshot_builder.dart',
          'lib/features/ai_coach/services/coach_memory_service.dart',
          'lib/core/services/badge_service.dart',
        ]) {
          expect(
            File(path).readAsStringSync().contains('CoachChatClear'),
            isFalse,
            reason: '$path must keep reading every chat row',
          );
        }
        final repo = File(
          'lib/features/ai_coach/repositories/coach_interaction_repository.dart',
        ).readAsStringSync();
        final start = repo.indexOf('int getTodayUserMessageCount()');
        final end = repo.indexOf('\n  }\n', start);
        expect(start, greaterThan(0));
        expect(
          repo.substring(start, end).contains('CoachChatClear'),
          isFalse,
          reason: 'the daily count must keep every row',
        );
      },
    );
  });

  group('T5 — a cloud restore does not bring the old thread back', () {
    test('rows re-put by _restoreCoachInteractions stay hidden', () async {
      await setMarker(t0);
      await SyncService.instance.restoreCoachInteractionsForTest(
        kTestUserId,
        preFetched: [
          {
            'id': 'r1',
            'user_message': 'restored-old',
            'ai_response': 'x',
            'model_used': 'gemini',
            'created_at': '2026-07-20T04:00:00.123456+00:00',
          },
          {
            'id': 'r2',
            'user_message': 'restored-new',
            'ai_response': 'y',
            'model_used': 'gemini',
            'created_at': '2026-07-20T05:00:00.123456+00:00',
          },
        ],
      );
      expect(
        HiveService.instance.coachBox.length,
        2,
        reason: 'precondition: both rows were written back',
      );
      expect(userTexts(), ['restored-new']);
    });
  });
}
