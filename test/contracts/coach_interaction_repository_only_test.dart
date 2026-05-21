// Tech-debt audit 2026-05-20 finding A10 — behavioral contract for
// CoachInteractionRepository.
//
// Pre-A10 the chat-interaction persistence surface (saveInteraction,
// saveUserMessagePending + dedup window, updateInteractionWithResponse/
// Error, getTodayUserMessageCount, getLatestInsight) lived inside
// AiCoachRepository alongside the snapshot builder + identity-signal +
// coaching-notes extractor — one 2127-line class. This test pins the
// behaviour of the extracted CoachInteractionRepository.
//
// Run: flutter test test/contracts/coach_interaction_repository_only_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp =
        Directory.systemTemp.createTempSync('coach_interaction_repo_').path;
    PathProviderPlatform.instance = _FakePathProvider(tmp);
    Hive.init(tmp);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
  });

  setUp(() async {
    await HiveUserSession.closeAll();
    const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await HiveUserSession.openForUser(fakeUserId);
    await HiveService.instance.coachBox.clear();
    await HiveService.instance.userBox.clear();
    // Plant user_id so identity-signal detection in saveUserMessagePending
    // can resolve the active user without crashing (no-op for tests with
    // a message that doesn't trip identity heuristics).
    await HiveService.instance.userBox.put('user_id', 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
  });

  group('CoachInteractionRepository — behavioral contract', () {
    test('saveInteraction writes a coach_<ms> row with the expected fields',
        () async {
      final key = await CoachInteractionRepository.instance.saveInteraction(
        userMessage: 'hi',
        aiResponse: 'hello, Lt',
        modelUsed: 'gemini-2.5-flash',
        mode: 'chat',
      );

      expect(key, startsWith('coach_'));
      final stored = HiveService.instance.coachBox.get(key) as Map;
      expect(stored['id'], key);
      expect(stored['user_message'], 'hi');
      expect(stored['ai_response'], 'hello, Lt');
      expect(stored['model_used'], 'gemini-2.5-flash');
      expect(stored['mode'], 'chat');
      expect(stored['is_user_message'], isTrue);
      expect(stored['created_at'], isA<String>());
    });

    test('saveUserMessagePending writes a pending row, deduplicates within the window',
        () async {
      final k1 = await CoachInteractionRepository.instance
          .saveUserMessagePending(userMessage: 'log my lunch', mode: 'quick');
      final stored = HiveService.instance.coachBox.get(k1) as Map;
      expect(stored['pending'], isTrue);
      expect(stored['failed'], isFalse);
      expect(stored['ai_response'], '');

      // Second identical pending request inside the 60s dedup window
      // returns the same key (no new row).
      final k2 = await CoachInteractionRepository.instance
          .saveUserMessagePending(userMessage: 'log my lunch', mode: 'quick');
      expect(k2, equals(k1));

      var coachRowCount = 0;
      for (final k in HiveService.instance.coachBox.keys) {
        if (k is String && k.startsWith('coach_')) coachRowCount++;
      }
      expect(coachRowCount, 1,
          reason: 'dedup must prevent a second row for identical input '
              'within the dedup window');
    });

    test('updateInteractionWithResponse + WithError mutate the pending row',
        () async {
      final key = await CoachInteractionRepository.instance
          .saveUserMessagePending(userMessage: 'plan a hotel workout', mode: 'quick');

      await CoachInteractionRepository.instance.updateInteractionWithResponse(
        key,
        aiResponse: 'here is your 20-min HIIT…',
        modelUsed: 'gemini-2.5-flash',
      );

      var stored = HiveService.instance.coachBox.get(key) as Map;
      expect(stored['ai_response'], 'here is your 20-min HIIT…');
      expect(stored['model_used'], 'gemini-2.5-flash');
      expect(stored['pending'], isFalse);
      expect(stored['failed'], isFalse);
      expect(stored.containsKey('error_text'), isFalse);

      await CoachInteractionRepository.instance.updateInteractionWithError(
        key,
        errorText: 'model temporarily unavailable',
      );

      stored = HiveService.instance.coachBox.get(key) as Map;
      expect(stored['failed'], isTrue);
      expect(stored['pending'], isFalse);
      expect(stored['error_text'], 'model temporarily unavailable');
      expect(stored['ai_response'], '');
    });

    test(
        'getTodayUserMessageCount counts only today\'s user messages, '
        'getLatestInsight returns the last AI response when notes empty',
        () async {
      final todayIso = DateTime.now().toIso8601String();

      await HiveService.instance.coachBox.put('coach_a', {
        'id': 'coach_a',
        'user_message': 'q1',
        'ai_response': 'a1',
        'created_at': todayIso,
      });
      await HiveService.instance.coachBox.put('coach_b', {
        'id': 'coach_b',
        'user_message': 'q2',
        'ai_response': 'a2 — most recent',
        'created_at': DateTime.now().add(const Duration(seconds: 1)).toIso8601String(),
      });
      // A row without a user_message must NOT count.
      await HiveService.instance.coachBox.put('coach_c', {
        'id': 'coach_c',
        'user_message': '',
        'ai_response': 'orphan',
        'created_at': todayIso,
      });

      expect(CoachInteractionRepository.instance.getTodayUserMessageCount(), 2);

      final insight = CoachInteractionRepository.instance.getLatestInsight();
      expect(insight, contains('most recent'));
    });
  });
}
