// test/ai_coach/coach_writer_dedup_test.dart
//
// APK Test #16.1 / Agent B (closes-diagnose: a17bc3) — pin the 60s
// client-side dedup window in AiCoachRepository.saveUserMessagePending.
//
// Same (user_message, mode, media_url) within 60s → one Hive row.
// Outside 60s → two rows (legitimate new turn).
// Failed entries are exempt from dedup → explicit retry mints fresh row.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  int countCoachRows() {
    final box = HiveService.instance.coachBox;
    var n = 0;
    for (final k in box.keys) {
      if (k is String && k.startsWith('coach_')) n++;
    }
    return n;
  }

  test('same message within 60s → 1 Hive row (dedup hit)', () async {
    final repo = AiCoachRepository.instance;

    final key1 = await repo.saveUserMessagePending(
      userMessage: 'curd 200gms whey 1.5 scoops cashew 6',
      mode: 'quick',
    );
    final key2 = await repo.saveUserMessagePending(
      userMessage: 'curd 200gms whey 1.5 scoops cashew 6',
      mode: 'quick',
    );

    expect(key1, equals(key2),
        reason: 'second call should return the existing key');
    expect(countCoachRows(), equals(1),
        reason: 'only one coach_* row should exist');
  });

  test('different mode → not deduped (separate identity)', () async {
    final repo = AiCoachRepository.instance;

    final key1 = await repo.saveUserMessagePending(
      userMessage: 'curd 200gms whey 1.5 scoops cashew 6',
      mode: 'quick',
    );
    final key2 = await repo.saveUserMessagePending(
      userMessage: 'curd 200gms whey 1.5 scoops cashew 6',
      mode: 'reasoning',
    );

    expect(key1, isNot(equals(key2)));
    expect(countCoachRows(), equals(2));
  });

  test('different media_url → not deduped (separate photo)', () async {
    final repo = AiCoachRepository.instance;

    final key1 = await repo.saveUserMessagePending(
      userMessage: 'analyse this',
      mode: 'quick',
      mediaUrl: 'https://example.com/a.jpg',
    );
    final key2 = await repo.saveUserMessagePending(
      userMessage: 'analyse this',
      mode: 'quick',
      mediaUrl: 'https://example.com/b.jpg',
    );

    expect(key1, isNot(equals(key2)));
    expect(countCoachRows(), equals(2));
  });

  test('failed entry does NOT dedup → retry mints a new row', () async {
    final repo = AiCoachRepository.instance;

    final key1 = await repo.saveUserMessagePending(
      userMessage: 'curd whey cashew',
      mode: 'quick',
    );
    // Mark the first row as failed (simulates ai-proxy returning an
    // error and the provider calling updateInteractionWithError).
    await repo.updateInteractionWithError(key1, errorText: 'AI unavailable');

    final key2 = await repo.saveUserMessagePending(
      userMessage: 'curd whey cashew',
      mode: 'quick',
    );

    expect(key1, isNot(equals(key2)),
        reason: 'failed entries are exempt from dedup');
    expect(countCoachRows(), equals(2));
  });

  test('outside 60s window → mints fresh row', () async {
    final repo = AiCoachRepository.instance;

    // Hand-write a stale entry 65 seconds ago.
    final staleTime =
        DateTime.now().subtract(const Duration(seconds: 65)).toIso8601String();
    await HiveService.instance.coachBox.put('coach_stale', {
      'id': 'coach_stale',
      'user_message': 'curd whey cashew',
      'ai_response': '',
      'mode': 'quick',
      'is_user_message': true,
      'pending': true,
      'failed': false,
      'created_at': staleTime,
    });

    final keyNew = await repo.saveUserMessagePending(
      userMessage: 'curd whey cashew',
      mode: 'quick',
    );

    expect(keyNew, isNot(equals('coach_stale')),
        reason: 'stale row outside dedup window must not be reused');
    expect(countCoachRows(), equals(2),
        reason: 'fresh row + stale row both present');
  });

  test('findRecentDuplicateMessageKey is a pure read (no side effects)',
      () async {
    final box = HiveService.instance.coachBox;
    await box.put('coach_existing', {
      'id': 'coach_existing',
      'user_message': 'hello',
      'mode': 'quick',
      'pending': true,
      'failed': false,
      'created_at': DateTime.now().toIso8601String(),
    });

    final repo = AiCoachRepository.instance;
    final hit = repo.findRecentDuplicateMessageKey(
      userMessage: 'hello',
      mode: 'quick',
    );
    expect(hit, equals('coach_existing'));

    // Box still has only the one row.
    var n = 0;
    for (final k in box.keys) {
      if (k is String && k.startsWith('coach_')) n++;
    }
    expect(n, equals(1));
  });

  test('coach key minter is unique under same-ms minting (c3f9a1)', () {
    // Without the monotonic minter, rapid mints collide on coach_<ms> (same
    // millisecond) and the second Hive.put overwrites the first. 2000
    // synchronous mints reliably hit the same ms; all must be unique.
    final keys = <String>{};
    for (var i = 0; i < 2000; i++) {
      keys.add(CoachInteractionRepository.mintCoachKey());
    }
    expect(keys.length, 2000,
        reason: 'every minted coach_ key must be unique even when minted within '
            'the same millisecond (monotonic minter, c3f9a1)');
  });
}
