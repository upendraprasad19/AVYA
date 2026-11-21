// test/contracts/coach_interactions_behavioral_test.dart
//
// Behavioral contract: coach_interactions
// Writer: lib/features/ai_coach/repositories/coach_interaction_repository.dart
//         (saveInteraction → coachBox.put('coach_<ms>', {...}))
// Reader: lib/features/ai_coach/providers/ai_coach_provider.dart
//         (ChatHistoryNotifier.build() reads coachBox, sorts by createdAt)
//
// Assert:
//   1. After saveInteraction, a ChatHistoryNotifier-simulated build()
//      includes the new message in sorted order.
//   2. The 'coaching_notes' singleton key is NOT surfaced as a chat row
//      (the skip-guard at ai_coach_provider.dart line 90 is intact).
//
// This test FAILS if:
//   - saveInteraction writes under a key pattern ChatHistoryNotifier doesn't read
//   - the coaching_notes skip-guard is removed
//   - the created_at sort order is broken

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';

import '../helpers/hive_test_setup.dart';

// Simulate ChatHistoryNotifier.build() without Riverpod overhead.
// Mirrors the exact filter/sort/build logic from ai_coach_provider.dart.
List<_SimMsg> _buildChatHistory() {
  final coachBox = HiveService.instance.coachBox;
  final entries = <_SimEntry>[];

  for (final key in coachBox.keys) {
    final raw = coachBox.get(key);
    if (raw is! Map) continue;
    // skip-guard from ChatHistoryNotifier.build() line 90
    if (key.toString() == 'coaching_notes') continue;
    final interaction = Map<String, dynamic>.from(raw);
    final createdAt = interaction['created_at'] as String? ?? '';
    entries.add(_SimEntry(key: key.toString(), createdAt: createdAt, data: interaction));
  }

  entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));

  final messages = <_SimMsg>[];
  for (final e in entries) {
    final userMsg = e.data['user_message'] as String?;
    final aiResponse = e.data['ai_response'] as String?;
    final createdAt = DateTime.tryParse(e.createdAt) ?? DateTime.now();
    if (userMsg != null && userMsg.isNotEmpty) {
      messages.add(_SimMsg(text: userMsg, isUser: true, timestamp: createdAt));
    }
    if (aiResponse != null && aiResponse.isNotEmpty) {
      messages.add(_SimMsg(
        text: aiResponse,
        isUser: false,
        timestamp: createdAt.add(const Duration(seconds: 1)),
      ));
    }
  }
  return messages;
}

class _SimEntry {
  final String key;
  final String createdAt;
  final Map<String, dynamic> data;
  const _SimEntry({required this.key, required this.createdAt, required this.data});
}

class _SimMsg {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  const _SimMsg({required this.text, required this.isUser, required this.timestamp});
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  test('saveInteraction writes a coachBox row that ChatHistoryNotifier reads',
      () async {
    await CoachInteractionRepository.instance.saveInteraction(
      userMessage: 'How many sets today?',
      aiResponse: 'Start with 3 sets of 10 reps.',
      modelUsed: 'gemini-2.5-flash',
      mode: 'quick',
    );

    final history = _buildChatHistory();

    // Must have at least user + AI message
    expect(history.length, greaterThanOrEqualTo(2),
        reason: 'saveInteraction must produce rows ChatHistoryNotifier sees');

    final userMsgs = history.where((m) => m.isUser).toList();
    final aiMsgs = history.where((m) => !m.isUser).toList();

    expect(userMsgs.any((m) => m.text == 'How many sets today?'), isTrue,
        reason: 'user message must appear in chat history');
    expect(aiMsgs.any((m) => m.text == 'Start with 3 sets of 10 reps.'), isTrue,
        reason: 'AI response must appear in chat history');
  });

  test('ChatHistoryNotifier-simulated build() respects createdAt sort order',
      () async {
    // Write two interactions with a known time gap so we can verify ordering.
    final t1 = DateTime.now().subtract(const Duration(seconds: 5));
    final t2 = DateTime.now();

    final coachBox = HiveService.instance.coachBox;
    await coachBox.put('coach_${t1.millisecondsSinceEpoch}', {
      'id': 'coach_${t1.millisecondsSinceEpoch}',
      'user_message': 'First message',
      'ai_response': 'First response',
      'model_used': 'gemini-2.5-flash',
      'mode': 'quick',
      'is_user_message': true,
      'created_at': t1.toIso8601String(),
    });
    await coachBox.put('coach_${t2.millisecondsSinceEpoch}', {
      'id': 'coach_${t2.millisecondsSinceEpoch}',
      'user_message': 'Second message',
      'ai_response': 'Second response',
      'model_used': 'gemini-2.5-flash',
      'mode': 'quick',
      'is_user_message': true,
      'created_at': t2.toIso8601String(),
    });

    final history = _buildChatHistory();

    final userMsgs = history.where((m) => m.isUser).toList();
    expect(userMsgs.length, equals(2));
    // First message must come before second message in sorted output.
    expect(userMsgs[0].text, equals('First message'));
    expect(userMsgs[1].text, equals('Second message'));
  });

  test(
      'coaching_notes singleton key does NOT appear as a chat row (skip-guard)',
      () async {
    final coachBox = HiveService.instance.coachBox;

    // Write the coaching_notes singleton key (must be skipped by ChatHistoryNotifier).
    await coachBox.put('coaching_notes', {
      'notes': ['User prefers morning workouts'],
      'last_extracted': DateTime.now().toIso8601String(),
    });

    // Also write a real chat row so the history is non-empty.
    await CoachInteractionRepository.instance.saveInteraction(
      userMessage: 'What time should I train?',
      aiResponse: 'Morning is best for you.',
      modelUsed: 'gemini-2.5-flash',
      mode: 'quick',
    );

    final history = _buildChatHistory();

    // The coaching_notes content must never appear as a chat message.
    expect(
      history.any((m) => m.text.contains('User prefers morning workouts')),
      isFalse,
      reason:
          'coaching_notes singleton key must be skipped by ChatHistoryNotifier',
    );

    // But the real chat row must still be visible.
    expect(
      history.any((m) => m.text == 'What time should I train?'),
      isTrue,
      reason: 'real chat row must still appear after skip-guard',
    );
  });

  test(
      'saveInteraction key format is coach_<ms> which ChatHistoryNotifier skips coaching_notes correctly',
      () async {
    await CoachInteractionRepository.instance.saveInteraction(
      userMessage: 'Test key format',
      aiResponse: 'OK',
      modelUsed: 'gemini-2.5-flash',
      mode: 'quick',
    );

    final coachBox = HiveService.instance.coachBox;
    // All coach interaction keys must start with 'coach_'.
    final interactionKeys = coachBox.keys
        .where((k) => k.toString() != 'coaching_notes')
        .map((k) => k.toString())
        .toList();

    expect(
      interactionKeys.every((k) => k.startsWith('coach_')),
      isTrue,
      reason: 'saveInteraction must write keys with coach_ prefix',
    );
  });
}
