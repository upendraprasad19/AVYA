// test/contracts/chat_limit_part_b_client_test.dart
//
// Part B (gemini3-limits-caching) — the CLIENT half of the chat cap reset
// (free 7 / PRO 20, migration 153) and the failed-turn refund:
//
//   1. 429 copy is tier-aware and parsed from the body `tier` + `limit`
//      (CoachReplies.chatRateLimitedFromError): PRO = no upsell, no rank,
//      resets at midnight IST; free = the cap + a modest PRO line; never
//      "unlimited" in either.
//   2. The local daily tally (getTodayUserMessageCount) mirrors the SERVER
//      ledger: it skips failed rows, media rows (ai-media-proxy spends no chat
//      unit) and hard-failure rows the server REFUNDED (`refunded: true`), but a
//      hard failure the server did NOT refund (content block, budget spent) still
//      counts, because that unit is spent.
//   3. The send paths tick the tally unless the server refunded the turn
//      (`AiChatResponse.refunded`), and the media path never ticks it (source
//      PRESENCE only; the behavioural half is (2) + the SQL refund script
//      test/sql/gemini3_limits_refund_live_verify.sql).
//   4. The paywall no longer promises "Unlimited" (source PRESENCE).
//
// Run: flutter test test/contracts/chat_limit_part_b_client_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/ai_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/copy/coach_replies.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';

import '../helpers/hive_test_setup.dart';

/// The tally reads `istDateStr(DateTime.now())` itself, so a fixture dated "today" would
/// flake if a run straddled IST midnight. Wait the last seconds out instead of mocking the
/// clock (the repository has no clock seam, and adding one here would be test-only surface).
Future<void> _avoidIstMidnightStraddle() async {
  final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  if (ist.hour == 23 && ist.minute == 59 && ist.second >= 50) {
    await Future<void>.delayed(const Duration(seconds: 12));
  }
}

void main() {
  group('429 copy — tier-aware, parsed from the body', () {
    test('a Dart-map body (FunctionException toString) is parsed', () {
      final pro = CoachReplies.chatRateLimitedFromError(
        'FunctionException(status: 429, details: {error: Daily message limit '
        'reached, code: RATE_LIMITED, tier: pro, limit: 20}, reasonPhrase: x)',
        isPro: false, // the body wins over the caller's guess
      );
      expect(pro, contains('20 messages'));
      expect(pro, contains('midnight IST'));
      expect(pro.contains('Upgrade'), isFalse);
      expect(pro.contains('PRO adds'), isFalse, reason: 'no upsell for PRO');
      expect(pro.contains('Recruit'), isFalse, reason: 'PRO copy is rank-free');
    });

    test('a JSON body is parsed too', () {
      final free = CoachReplies.chatRateLimitedFromError(
        '{"error":"Daily message limit reached","code":"RATE_LIMITED",'
        '"tier":"free","limit":7}',
        isPro: true,
      );
      expect(free, contains('7 messages'));
      expect(free, contains('PRO adds dedicated coaching and higher limits'));
      expect(free, contains('midnight IST'));
    });

    test('an older server body (no tier/limit) falls back to the caller tier + AppConstants', () {
      final free = CoachReplies.chatRateLimitedFromError(
          'RATE_LIMITED status 429',
          isPro: false);
      expect(free, contains('${AppConstants.freeAiMessagesPerDay} messages'));
      final pro = CoachReplies.chatRateLimitedFromError(
          'RATE_LIMITED status 429',
          isPro: true);
      expect(pro, contains('${AppConstants.proAiMessagesPerDay} messages'));
    });

    test('tier is case-insensitive and an absurd limit cannot throw', () {
      final pro = CoachReplies.chatRateLimitedFromError(
          'details: {code: RATE_LIMITED, Tier: PRO, Limit: 20}',
          isPro: false);
      expect(pro, contains('20 messages'));
      expect(pro.contains('PRO adds'), isFalse);
      // 40 digits overflows int.parse (FormatException); the handler must degrade
      // to the caller's tier + AppConstants instead of throwing.
      final huge = CoachReplies.chatRateLimitedFromError(
          'details: {tier: free, limit: ${'9' * 40}}',
          isPro: false);
      expect(huge, contains('${AppConstants.freeAiMessagesPerDay} messages'));
    });

    test('neither copy says "unlimited"', () {
      for (final s in [
        CoachReplies.chatDailyLimitReached(isPro: true, limit: 20),
        CoachReplies.chatDailyLimitReached(isPro: false, limit: 7),
      ]) {
        expect(s.toLowerCase().contains('unlimited'), isFalse);
      }
    });

    test('the number is the argument, never typed into the copy', () {
      expect(CoachReplies.chatDailyLimitReached(isPro: true, limit: 13),
          contains('13 messages'));
      expect(CoachReplies.chatDailyLimitReached(isPro: false, limit: 3),
          contains('3 messages'));
    });

    test('the send path wires the helper (presence)', () {
      final src = File('lib/features/ai_coach/providers/ai_coach_provider.dart')
          .readAsStringSync();
      expect(src, contains('CoachReplies.chatRateLimitedFromError(errStr, isPro: isPro)'));
      expect('on free plan).'.allMatches(src).length, 0,
          reason: 'the old free-plan-only 429 copy must be gone');
    });
  });

  group('local daily tally mirrors the server ledger', () {
    late Directory tmp;
    setUp(() async {
      tmp = await setUpHiveForTests();
    });
    tearDown(() async {
      await tearDownHiveForTests(tmp);
    });

    test('only turns that spent a chat unit count', () async {
      await _avoidIstMidnightStraddle();
      final box = HiveService.instance.coachBox;
      final today = istDateStr(DateTime.now());
      Future<void> put(String key, Map<String, dynamic> extra) => box.put(key, {
            'created_at': '${today}T10:00:00',
            'user_message': 'msg $key',
            ...extra,
          });
      await put('ok1', {});
      await put('ok2', {'failed': false, 'had_hard_failure': false});
      await put('failed', {'failed': true});
      // A transport-failed turn the server gave the unit back for: NOT counted.
      await put('refunded_apology', {'had_hard_failure': true, 'refunded': true});
      // A content-blocked / budget-exhausted apology: the unit is SPENT, counted.
      await put('blocked_apology', {'had_hard_failure': true, 'refunded': false});
      await put('legacy_apology', {'had_hard_failure': true}); // no flag => spent
      // A media turn spends no chat unit (ai-media-proxy), refunded or not.
      await put('photo', {'mode': 'media'});
      expect(CoachInteractionRepository.instance.getTodayUserMessageCount(), 4,
          reason: 'ok1, ok2, blocked_apology, legacy_apology');
    });

    test('updateInteractionWithResponse persists the server refunded flag', () async {
      await _avoidIstMidnightStraddle();
      final box = HiveService.instance.coachBox;
      final today = istDateStr(DateTime.now());
      await box.put('coach_r', {
        'created_at': '${today}T10:00:00',
        'user_message': 'hello',
        'pending': true,
      });
      await CoachInteractionRepository.instance.updateInteractionWithResponse(
        'coach_r',
        aiResponse: 'apology',
        modelUsed: 'x',
        hadHardFailure: true,
        refunded: true,
      );
      expect((box.get('coach_r') as Map)['refunded'], true);
      expect(CoachInteractionRepository.instance.getTodayUserMessageCount(), 0);
    });

    test('AiChatResponse parses `refunded` from the 200 body (default false)', () {
      expect(AiService.buildResponseForTest({'reply': 'r', 'refunded': true}).refunded,
          isTrue);
      expect(AiService.buildResponseForTest({'reply': 'r'}).refunded, isFalse,
          reason: 'an older server omits the field: treat the unit as spent');
    });
  });

  group('send paths and paywall (source presence)', () {
    final provider = File('lib/features/ai_coach/providers/ai_coach_provider.dart')
        .readAsStringSync();

    test('the chat send + retry increment unless the SERVER refunded the turn', () {
      expect('if (!aiResponse.refunded) limitNotifier.increment();'
              .allMatches(provider)
              .length,
          1);
      expect('if (!retryResponse.refunded) limitNotifier.increment();'
              .allMatches(provider)
              .length,
          1);
      expect(provider.contains('hadHardFailure) limitNotifier.increment'), isFalse,
          reason: 'gating on hadHardFailure would under-count a content-blocked '
              'turn the server did NOT refund');
      expect(RegExp(r'\n\s*limitNotifier\.increment\(\);').hasMatch(provider),
          isFalse,
          reason: 'an unconditional increment is back');
      // All three persist the flag the tally reads.
      expect('refunded: aiResponse.refunded,'.allMatches(provider).length, 2);
      expect('refunded: retryResponse.refunded,'.allMatches(provider).length, 1);
    });

    test('sendWithMedia never ticks the chat tally', () {
      final start = provider.indexOf('Future<void> sendWithMedia(');
      final end = provider.indexOf('\n  Future<', start + 10);
      expect(start, greaterThanOrEqualTo(0));
      final body = provider.substring(start, end < 0 ? provider.length : end);
      // ANY `.increment(` / messageLimitProvider reference counts, whatever the spelling.
      expect(body.contains('.increment('), isFalse,
          reason: 'a media turn spends no chat unit (ai-media-proxy)');
      expect(body.contains('messageLimitProvider'), isFalse,
          reason: 'sendWithMedia must not touch the chat message-limit notifier');
    });

    test('every coach paywall entry point passes the label the sheet switches on', () {
      const label = "'Higher daily AI coach limit'";
      expect(File('lib/shared/widgets/paywall_sheet.dart')
              .readAsStringSync()
              .contains('case $label:'),
          isTrue,
          reason: 'the paywall subtitle switch lost the coach-limit label');
      for (final path in [
        'lib/features/ai_coach/screens/ai_coach/input_bar.dart',
        'lib/features/ai_coach/screens/ai_coach/compact_header.dart',
        'lib/features/ai_coach/screens/ai_coach/screen.dart',
        'lib/features/ai_coach/screens/ai_coach/status_pill.dart',
      ]) {
        expect(File(path).readAsStringSync().contains('feature: $label'), isTrue,
            reason: '$path no longer passes the coach-limit label (the sheet would fall '
                'through to its generic subtitle and the funnel series would split again)');
      }
    });

    test('no user-visible "Unlimited" on the paywall surfaces', () {
      for (final path in [
        'lib/shared/widgets/paywall_sheet.dart',
        'lib/shared/widgets/paywall_sheet_phase_variant.dart',
        'lib/features/ai_coach/screens/ai_coach/input_bar.dart',
        'lib/features/ai_coach/screens/ai_coach/compact_header.dart',
        'lib/features/ai_coach/screens/ai_coach/screen.dart',
        'lib/features/ai_coach/screens/ai_coach/status_pill.dart',
      ]) {
        final src = File(path).readAsStringSync();
        // Strip comments: the internal gate id `featureAiCoachUnlimited` is not copy.
        final code = src
            .split('\n')
            .map((l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
            .join('\n');
        expect(RegExp(r"'[^'\n]*[Uu]nlimited[^'\n]*'").hasMatch(code), isFalse,
            reason: '$path still carries a quoted "Unlimited" string');
      }
    });
  });
}
