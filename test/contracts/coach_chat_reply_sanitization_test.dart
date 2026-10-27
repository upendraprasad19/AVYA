// test/contracts/coach_chat_reply_sanitization_test.dart
//
// SoT contract for coach_chat_reply_sanitization (observation-batch-and-
// digest-redesign 2026-09-21 / A2a).
//
// THE BUG (founder Obs 2): AI Coach chat rendered a raw JSON-shaped Gemini
// reply instead of natural language — both live (right after sending) and,
// separately, on the NEXT app launch (the restore path re-rendering the same
// raw value from Hive on every cold boot until fixed).
//
// THE FIX: `detectAndStripJsonShapedReply` (pure, no Hive access) extracted
// from `PredictionNotifier._sanitisePredictionText` — which is NOT reused
// directly for chat because every one of its code paths also writes back to
// the single global `prediction_text` Hive key read by the UNRELATED
// Profile-tab prediction card. Reusing it for chat would have silently
// overwritten that card with unrelated chat content. The pure function is
// wired into FIVE render sites in ai_coach_provider.dart: the live
// `SendMessageNotifier.send` (primary + auth-retry) and `.sendWithMedia`
// paths, AND `ChatHistoryNotifier.build()`'s restore-path render (both its
// success branch and its isFailed→aiResponse fallback branch) — the last of
// these is what the founder's "force-close, reopen" half of the report
// actually needed; a live-send-only fix would have left it reproducing on
// every relaunch.
//
// Run: flutter test test/contracts/coach_chat_reply_sanitization_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
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
  group('detectAndStripJsonShapedReply (pure)', () {
    test('JSON object with a summary key → the summary prose', () {
      final result = detectAndStripJsonShapedReply(
          jsonEncode({'summary': 'You are on track for your goal.'}));
      expect(result, 'You are on track for your goal.');
    });

    test('JSON with a predictions array of maps → first entry\'s prose key',
        () {
      final result = detectAndStripJsonShapedReply(jsonEncode({
        'predictions': [
          {'timeframe': 'In 3 months you should see visible progress.'}
        ]
      }));
      expect(result, 'In 3 months you should see visible progress.');
    });

    test('malformed / unrecognised JSON shape → artefact-stripped fallback',
        () {
      final result = detectAndStripJsonShapedReply('{"error":"Gemini returned no content"}');
      expect(result, isNotNull);
      expect(result!.contains('{'), isFalse,
          reason: 'the fallback must strip JSON syntax characters');
      expect(result.contains('error'), isTrue);
    });

    test('YAML-style flat key:value lines → the longest prose value', () {
      final result = detectAndStripJsonShapedReply(
          'outcome_3_months: You will likely gain 2-3kg of lean mass with '
          'consistent training.\nconfidence: high');
      expect(result,
          'You will likely gain 2-3kg of lean mass with consistent training.');
    });

    test('plain prose → returned unchanged (identity, no cleaning)', () {
      const prose = 'Great question! Based on your recent logs, keep pushing.';
      final result = detectAndStripJsonShapedReply(prose);
      expect(identical(result, prose), isTrue,
          reason: 'plain prose must be the SAME instance — callers use '
              'identity to decide whether cleaning happened.');
    });

    test('null → null', () {
      expect(detectAndStripJsonShapedReply(null), isNull);
    });

    test('empty/whitespace-only → null', () {
      expect(detectAndStripJsonShapedReply('   '), isNull);
    });
  });

  group('allowYamlHeuristic: false (chat mode) — Hermes L1, 2026-09-21: the '
      'YAML heuristic is safe for the prediction card\'s single-tagline '
      'contract but shreds legitimate multi-line chat prose', () {
    test('a real macro-breakdown chat reply is returned UNCHANGED, not '
        'shredded into "150g · 200g · 60g" — THE BUG, fixed', () {
      const reply = "Here's the breakdown for today:\n"
          'protein: 150g\n'
          'carbs: 200g\n'
          'fats: 60g\n'
          'Keep it up, Recruit.';
      final result =
          detectAndStripJsonShapedReply(reply, allowYamlHeuristic: false);
      expect(identical(result, reply), isTrue,
          reason: 'a chat reply with normal label:value coaching lines must '
              'pass through unchanged — the pre-fix regex matched every one '
              'of these lines and rebuilt the message from fragments, '
              'dropping "Here\'s the breakdown for today:" and "Keep it up, '
              'Recruit." entirely.');
    });

    test('a second real shape: "Quick answer: yes." + a rest-interval line '
        'is also left unchanged', () {
      const reply = 'Quick answer: yes.\nrest: 90s between sets';
      final result =
          detectAndStripJsonShapedReply(reply, allowYamlHeuristic: false);
      expect(identical(result, reply), isTrue);
    });

    test('the JSON/code-fence path (step 1) is UNAFFECTED by '
        'allowYamlHeuristic: false — only step 2 is gated', () {
      final result = detectAndStripJsonShapedReply(
        jsonEncode({'summary': 'You are on track for your goal.'}),
        allowYamlHeuristic: false,
      );
      expect(result, 'You are on track for your goal.',
          reason: 'a genuinely JSON-shaped reply must still be cleaned in '
              'chat mode — the flag only turns off the free-text '
              'key:value-line heuristic, not JSON detection.');
    });

    test('with allowYamlHeuristic left at its default (true), the SAME '
        'macro-breakdown reply is still shredded — proves the default '
        'preserves the prediction card\'s original, unchanged behavior', () {
      const reply = "Here's the breakdown for today:\n"
          'protein: 150g\n'
          'carbs: 200g\n'
          'fats: 60g\n'
          'Keep it up, Recruit.';
      final result = detectAndStripJsonShapedReply(reply);
      expect(identical(result, reply), isFalse,
          reason: 'the default must be unchanged from before this fix — '
              'only explicit chat call sites opt out.');
    });
  });

  group('ChatHistoryNotifier.build() — restore-path render is cleaned '
      '(integration)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await setUpHiveForTests();
    });

    tearDown(() async {
      await tearDownHiveForTests(tempDir);
    });

    test('a JSON-shaped stored ai_response renders as cleaned prose, not '
        'raw JSON — THE FOUNDER BUG (restore half), fixed', () async {
      final box = HiveService.instance.coachBox;
      await box.put('coach_1', {
        'id': 'coach_1',
        'user_message': 'how is my progress',
        'ai_response': jsonEncode({'summary': 'You are progressing well.'}),
        'created_at': DateTime(2026, 9, 20).toIso8601String(),
        'model_used': 'gemini-2.5-flash',
        'pending': false,
        'failed': false,
      });

      final container = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(container.dispose);

      final messages = container.read(chatHistoryProvider);
      final aiBubble = messages.firstWhere((m) => !m.isUser);

      expect(aiBubble.text, 'You are progressing well.',
          reason: 'THE FOUNDER BUG — pre-fix this rendered the raw '
              '\'{"summary":"..."}\' string on every relaunch, because '
              'build() reads straight from Hive with no sanitization.');
      expect(aiBubble.text.startsWith('{'), isFalse);
    });

    test('a JSON-shaped isFailed fallback (no error_text) also renders '
        'cleaned', () async {
      final box = HiveService.instance.coachBox;
      await box.put('coach_2', {
        'id': 'coach_2',
        'user_message': 'log curd',
        'ai_response': '{"error":"Gemini returned no content"}',
        'created_at': DateTime(2026, 9, 20).toIso8601String(),
        'model_used': 'gemini-2.5-flash',
        'pending': false,
        'failed': true,
        // error_text deliberately absent — forces the aiResponse fallback.
      });

      final container = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(container.dispose);

      final messages = container.read(chatHistoryProvider);
      final errorBubble = messages.firstWhere((m) => m.isError);

      expect(errorBubble.text.startsWith('{'), isFalse,
          reason: 'the isFailed fallback must also be cleaned, not just the '
              'success-path render.');
    });

    test('plain-prose stored ai_response is untouched', () async {
      final box = HiveService.instance.coachBox;
      await box.put('coach_3', {
        'id': 'coach_3',
        'user_message': 'hi',
        'ai_response': 'Hey! How can I help with your training today?',
        'created_at': DateTime(2026, 9, 20).toIso8601String(),
        'model_used': 'gemini-2.5-flash',
        'pending': false,
        'failed': false,
      });

      final container = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(container.dispose);

      final messages = container.read(chatHistoryProvider);
      final aiBubble = messages.firstWhere((m) => !m.isUser);
      expect(aiBubble.text, 'Hey! How can I help with your training today?');
    });
  });

  group('ai_coach_provider.dart source — the fix is wired at every render '
      'site, and the chat path never touches prediction_text', () {
    late String source;

    setUpAll(() {
      source = _stripComments(File(
        'lib/features/ai_coach/providers/ai_coach_provider.dart',
      ).readAsStringSync());
    });

    // Position-based, per-site checks — NOT a whole-file occurrence count.
    // A raw total count is structurally blind to WHICH site is covered: it
    // was first written as `allMatches(source).length >= 5` and stayed
    // green after a mutation that deleted the build()-success call, because
    // the total still included the function's own definition, the
    // unrelated _sanitisePredictionText wrapper's call, AND the untouched
    // isFailed-fallback call in the SAME method — 4 unrelated matches
    // papering over exactly the 1 that was removed. Each site is now
    // isolated by slicing the source between named anchors before counting.
    int _indexOfOrFail(String marker, [int start = 0]) {
      final i = source.indexOf(marker, start);
      expect(i, greaterThanOrEqualTo(0),
          reason: 'could not locate anchor "$marker" in ai_coach_provider.dart');
      return i;
    }

    test('sendWithMedia\'s success render calls the sanitizer', () {
      final start = _indexOfOrFail('Future<void> sendWithMedia(');
      final end = _indexOfOrFail('Future<void> send(', start);
      final body = source.substring(start, end);
      expect(body.contains('detectAndStripJsonShapedReply('), isTrue,
          reason: 'sendWithMedia must sanitize aiResponse.reply before '
              'rendering it.');
    });

    test('send() sanitizes BOTH the primary AND the auth-retry render — '
        'exactly 2 call sites in this method, not 1', () {
      final start = _indexOfOrFail('Future<void> send(');
      final classEnd = _indexOfOrFail('\nclass ', start);
      final body = source.substring(start, classEnd);
      final count =
          'detectAndStripJsonShapedReply('.allMatches(body).length;
      expect(count, 2,
          reason: 'found $count call site(s) inside send() — expected '
              'exactly 2 (primary success + auth-retry success). A missed '
              'site (esp. the auth-retry path, easy to overlook) '
              'reintroduces this bug on that path alone.');
    });

    test('ChatHistoryNotifier.build() sanitizes BOTH the success render AND '
        'the isFailed aiResponse-fallback render — exactly 2 call sites, '
        'not 1', () {
      final start = _indexOfOrFail('List<ChatMessage> build() {');
      final end = _indexOfOrFail('void refreshFromHive()', start);
      final body = source.substring(start, end);
      final count =
          'detectAndStripJsonShapedReply('.allMatches(body).length;
      expect(count, 2,
          reason: 'found $count call site(s) inside build() — expected '
              'exactly 2. THIS is the restore-path method: a missed site '
              'here means a JSON-shaped reply keeps reappearing raw on '
              'every relaunch even after the live-send paths are fixed.');
    });

    test('sendWithMedia\'s call site passes allowYamlHeuristic: false — '
        'Hermes L1 fix, 2026-09-21', () {
      final start = _indexOfOrFail('Future<void> sendWithMedia(');
      final end = _indexOfOrFail('Future<void> send(', start);
      final body = source.substring(start, end);
      final count = 'allowYamlHeuristic: false'.allMatches(body).length;
      expect(count, 1,
          reason: 'sendWithMedia has exactly 1 detectAndStripJsonShapedReply '
              'call site; it must pass allowYamlHeuristic: false or a real '
              'multi-line chat reply gets shredded (Hermes L1).');
    });

    test('send()\'s TWO call sites (primary + auth-retry) both pass '
        'allowYamlHeuristic: false', () {
      final start = _indexOfOrFail('Future<void> send(');
      final classEnd = _indexOfOrFail('\nclass ', start);
      final body = source.substring(start, classEnd);
      final count = 'allowYamlHeuristic: false'.allMatches(body).length;
      expect(count, 2,
          reason: 'send() has exactly 2 call sites; found $count passing '
              'allowYamlHeuristic: false — a missed site (esp. the '
              'easy-to-overlook auth-retry path) reopens the bug on that '
              'path alone.');
    });

    test('ChatHistoryNotifier.build()\'s TWO call sites (success + isFailed '
        'fallback) both pass allowYamlHeuristic: false', () {
      final start = _indexOfOrFail('List<ChatMessage> build() {');
      final end = _indexOfOrFail('void refreshFromHive()', start);
      final body = source.substring(start, end);
      final count = 'allowYamlHeuristic: false'.allMatches(body).length;
      expect(count, 2,
          reason: 'build() has exactly 2 call sites (this is the '
              'RESTORE-path method, rendered on every cold boot); found '
              '$count passing allowYamlHeuristic: false.');
    });

    test('the prediction card\'s own call site does NOT pass '
        'allowYamlHeuristic: false — it must keep the default (true)', () {
      final start = _indexOfOrFail('_sanitisePredictionText(String? raw)');
      final end = _indexOfOrFail('}', start);
      final body = source.substring(start, end);
      expect(body.contains('detectAndStripJsonShapedReply(raw)'), isTrue,
          reason: 'the prediction card must call with no explicit '
              'allowYamlHeuristic argument, preserving its original '
              'behavior — flipping this would silently stop cleaning '
              'genuinely YAML-shaped predictions.');
      expect(body.contains('allowYamlHeuristic'), isFalse);
    });

    test('SendMessageNotifier never calls _writeBackToHive or writes '
        'prediction_text — the Hive-corruption hazard review round 1 '
        'flagged must not recur', () {
      final classBlock = RegExp(
        r'class SendMessageNotifier extends Notifier<bool> \{[\s\S]*?(?=\nclass )',
      ).firstMatch(source);
      expect(classBlock, isNotNull,
          reason: 'Could not locate SendMessageNotifier in '
              'ai_coach_provider.dart.');
      final body = classBlock!.group(0)!;
      expect(body.contains('_writeBackToHive'), isFalse,
          reason: 'the chat path must never call the prediction-card-only '
              'Hive write-back — doing so would silently overwrite the '
              'Profile-tab prediction card with unrelated chat content.');
      expect(body.contains("MigratedKey.write('prediction_text'"), isFalse);
    });
  });
}
