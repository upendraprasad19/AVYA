// test/contracts/coach_chat_history_render_channel_filter_writer_to_reader_test.dart
//
// SoT contract for coach_chat_history_render_channel_filter
// (observation-batch-and-digest-redesign 2026-09-21 / A2c).
//
// ⚠ Concept name deliberately NOT `coach_chat_history_replay` — that name is
// ALREADY a registered SoT concept (docs/sot_registry.yaml, since Unit 2
// 2026-07-07) governing recentHistoryExchanges' exclusion of non-chat rows
// from what's sent TO Gemini — a DIFFERENT writer/reader pair from this
// fix's target (the chat-UI BUBBLE renderer). Reusing the name would collide
// with Gate 9's test-filename derivation from `concept:` (the exact OI-204
// recurrence class CLAUDE.md's own pitfall table documents).
//
// THE BUG (founder Obs 2, second half — 4 repeated `{"error":"Gemini
// returned no content"}` bubbles for "curd" after force-close/reopen):
// `_restoreCoachInteractions` (sync_coach.dart:225) pulls ALL
// ai_coach_interactions rows with NO channel filter, so a FAILED
// food_text_analysis attempt (logging "curd") restored into coachBox got
// rendered as an ordinary chat bubble by `ChatHistoryNotifier.build`, which
// had no channel guard at all — unlike `recentHistoryExchanges`, which
// already filtered to `coachChatChannels = {'app','chat','in_app_orphan'}`
// for the Gemini-history use case.
//
// THE FIX (A2c, first cut): the SAME `coachChatChannels` allowlist
// `recentHistoryExchanges` already used, applied inside
// `ChatHistoryNotifier.build`'s row loop too.
//
// THE REGRESSION THIS INTRODUCED, caught by the self-triggered B-pass review
// on A2c (same day, A2d): `coachChatChannels` is an ALLOWLIST tuned for "what
// feeds Gemini's own conversation history" — narrow by design. Applied to the
// render path, it silently dropped every LEGITIMATE proactive/paywall
// channel outside `{'app','chat','in_app_orphan'}`: a restored rank-promotion
// congrats (`channel:'in_app'`, proactive-coach-promotion), a rank-ceremony
// message (`channel:'promotion_ceremony'`, evaluate-rank-promotions), an "I
// see you" callout (`channel:'proactive_i_see_you'`, i-see-you-callout), and
// both media-paywall exchanges (`channel:'image_paywall'`/`'video_paywall'`,
// ai-media-proxy) all vanished from a user's restored chat history with no
// error — the exact same silent-disappearance shape as the founder's
// original "curd" bug, just for a different, WIDER set of rows.
//
// THE CORRECTED FIX (A2d): a separate, purpose-built DENYLIST
// (`CoachInteractionRepository.nonChatAnalysisChannels`) for the render path,
// holding only the small, closed set of channels that ARE raw analysis
// output (`food_text_analysis`/`scan_meal`/`cart_auditor`/`weekly_report`/
// `app_event`) — the render path excludes ONLY those, so any current or
// future proactive/paywall channel renders correctly by default.
// `coachChatChannels` reverts to being used ONLY by `recentHistoryExchanges`,
// unchanged from before A2c.
//
// Run: flutter test test/contracts/coach_chat_history_render_channel_filter_writer_to_reader_test.dart

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';

import '../helpers/hive_test_setup.dart';

String _stripComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

void main() {
  group('coachChatChannels — unchanged, Gemini-history reader only', () {
    test('the constant is a real, non-empty allowlist', () {
      expect(CoachInteractionRepository.coachChatChannels,
          {'app', 'chat', 'in_app_orphan'});
    });
  });

  group('nonChatAnalysisChannels — the render path\'s own denylist', () {
    test('holds exactly the known raw-analysis / analytics channels', () {
      expect(CoachInteractionRepository.nonChatAnalysisChannels, {
        'food_text_analysis',
        'scan_meal',
        'cart_auditor',
        'weekly_report',
        'app_event',
      });
    });

    test('shares NO members with coachChatChannels (disjoint by construction)',
        () {
      expect(
        CoachInteractionRepository.nonChatAnalysisChannels
            .intersection(CoachInteractionRepository.coachChatChannels),
        isEmpty,
      );
    });
  });

  group('ChatHistoryNotifier.build() — non-chat-channel rows never render '
      '(integration)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await setUpHiveForTests();
    });

    tearDown(() async {
      await tearDownHiveForTests(tempDir);
    });

    Future<void> seed(String key, {String? channel, String userMsg = 'x'}) {
      return HiveService.instance.coachBox.put(key, {
        'id': key,
        'user_message': userMsg,
        'ai_response': '{"error":"Gemini returned no content"}',
        'created_at': DateTime(2026, 9, 20, 9, 30).toIso8601String(),
        'model_used': 'gemini-2.5-flash',
        'pending': false,
        'failed': true,
        if (channel != null) 'channel': channel,
      });
    }

    test('a restored food_text_analysis-channel row never renders as a chat '
        'bubble — THE FOUNDER BUG (curd), fixed', () async {
      await seed('coach_1', channel: 'food_text_analysis', userMsg: 'curd');
      await seed('coach_2', channel: 'chat', userMsg: 'how is my progress');

      final container = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(container.dispose);

      final messages = container.read(chatHistoryProvider);

      expect(
        messages.any((m) => m.retryUserMessage == 'curd' || m.text.contains('curd')),
        isFalse,
        reason: 'THE FOUNDER BUG — a restored food_text_analysis failure '
            'must never appear as a chat bubble.',
      );
      expect(
        messages.any((m) => m.retryUserMessage == 'how is my progress'),
        isTrue,
        reason: 'a genuine chat-channel row must still render.',
      );
    });

    test('scan_meal and cart_auditor channels are also excluded', () async {
      await seed('coach_3', channel: 'scan_meal', userMsg: 'photo of meal');
      await seed('coach_4', channel: 'cart_auditor', userMsg: 'cart items');
      await seed('coach_5', channel: 'weekly_report', userMsg: 'report');

      final container = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(container.dispose);

      final messages = container.read(chatHistoryProvider);
      for (final excluded in ['photo of meal', 'cart items', 'report']) {
        expect(messages.any((m) => m.retryUserMessage == excluded), isFalse,
            reason: '$excluded (a non-chat channel row) must not render.');
      }
    });

    test('a NULL channel (local coach write) still renders — the allowlist '
        'must not accidentally exclude ordinary local writes', () async {
      await seed('coach_6', channel: null, userMsg: 'local write');

      final container = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(container.dispose);

      final messages = container.read(chatHistoryProvider);
      expect(messages.any((m) => m.retryUserMessage == 'local write'), isTrue,
          reason: 'a null channel means a local coach write and must '
              'always render — this is the majority-case row shape.');
    });

    test('in_app_orphan channel renders (part of the allowlist)', () async {
      await seed('coach_7', channel: 'in_app_orphan', userMsg: 'orphan turn');

      final container = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(container.dispose);

      final messages = container.read(chatHistoryProvider);
      expect(messages.any((m) => m.retryUserMessage == 'orphan turn'), isTrue);
    });

    test('app_event channel is excluded — analytics, never a chat exchange',
        () async {
      await seed('coach_8', channel: 'app_event', userMsg: 'phase_1_upgrade');

      final container = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(container.dispose);

      final messages = container.read(chatHistoryProvider);
      expect(messages.any((m) => m.retryUserMessage == 'phase_1_upgrade'),
          isFalse);
    });

    // A2d regression coverage — the channels the A2c allowlist-shaped fix
    // silently dropped (self-triggered B-pass review, 2026-09-21). Each of
    // these is a REAL, currently-shipping server-side writer into
    // ai_coach_interactions (proactive-coach-promotion, evaluate-rank-
    // promotions, i-see-you-callout, ai-media-proxy) and rendered correctly
    // before A2c; this group proves the corrected denylist restores that.
    for (final proactiveChannel in [
      'in_app',
      'promotion_ceremony',
      'proactive_i_see_you',
      'image_paywall',
      'video_paywall',
      'app',
    ]) {
      test('$proactiveChannel channel renders — A2d regression coverage '
          '(dropped by the A2c allowlist, restored by the denylist)',
          () async {
        await seed('coach_$proactiveChannel',
            channel: proactiveChannel, userMsg: 'msg-$proactiveChannel');

        final container = ProviderContainer(overrides: [
          authUserIdTokenProvider.overrideWithValue(kTestUserId),
        ]);
        addTearDown(container.dispose);

        final messages = container.read(chatHistoryProvider);
        expect(
          messages.any((m) => m.retryUserMessage == 'msg-$proactiveChannel'),
          isTrue,
          reason: '$proactiveChannel is a legitimate proactive/paywall '
              'channel and must render like any other chat turn.',
        );
      });
    }
  });

  group('ai_coach_provider.dart / coach_interaction_repository.dart source '
      '— the filter is wired, and the literal set is NOT duplicated', () {
    late String providerSource;
    late String repoSource;

    setUpAll(() {
      providerSource = _stripComments(File(
        'lib/features/ai_coach/providers/ai_coach_provider.dart',
      ).readAsStringSync());
      repoSource = _stripComments(File(
        'lib/features/ai_coach/repositories/coach_interaction_repository.dart',
      ).readAsStringSync());
    });

    test('ChatHistoryNotifier.build references its OWN denylist constant, '
        'not the Gemini-history allowlist and not a duplicated literal set',
        () {
      final start = providerSource.indexOf('List<ChatMessage> build() {');
      final end = providerSource.indexOf('void refreshFromHive()', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final body = providerSource.substring(start, end);

      expect(
        body.contains('CoachInteractionRepository.nonChatAnalysisChannels'),
        isTrue,
        reason: 'build() must use the render-path-specific denylist, not '
            'the Gemini-history allowlist (that was the A2c regression).',
      );
      expect(
        body.contains('CoachInteractionRepository.coachChatChannels'),
        isFalse,
        reason: 'build() must NOT use coachChatChannels — that allowlist is '
            'scoped to recentHistoryExchanges only (A2d correction).',
      );
      expect(
        body.contains(
          "{'food_text_analysis', 'scan_meal', 'cart_auditor', "
          "'weekly_report', 'app_event'}",
        ),
        isFalse,
        reason: 'the denylist literal must not be duplicated here — it must '
            'be a single source of truth in CoachInteractionRepository.',
      );
    });

    test('coach_interaction_repository.dart defines BOTH sets exactly once, '
        'each with its own name, and they are disjoint', () {
      final chatOccurrences =
          "{'app', 'chat', 'in_app_orphan'}".allMatches(repoSource).length;
      expect(chatOccurrences, 1,
          reason: 'coachChatChannels\' literal must be defined exactly once.');
      expect(repoSource.contains('static const Set<String> coachChatChannels'),
          isTrue);
      expect(
        repoSource
            .contains('static const Set<String> nonChatAnalysisChannels'),
        isTrue,
        reason: 'the render path needs its own, separately-named denylist — '
            'A2d correction.',
      );
      expect(repoSource.contains('_coachChatChannels'), isFalse,
          reason: 'the old private name must be fully renamed, not left as '
              'a second, unused declaration.');
    });
  });
}
