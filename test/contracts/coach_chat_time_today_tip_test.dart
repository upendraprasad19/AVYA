// BEHAVIORAL TEST — OI-502 (plan docs/plans/2026-11-13-coach-chat-time-dup.md,
// sections 2, 3 and 5; tests T1, T2, T4).
//
// Writer: every coachBox chat row's `created_at` is UTC since 2026-09-27
// (`coach_interaction_repository.dart` saveInteraction / saveUserMessagePending,
// `DateTime.now().toUtc().toIso8601String()`); a restored row carries the
// cloud's `+00:00` form.
// Readers fixed here:
//   R1 the chat bubble's time (`chat_area.dart`, via `chatClockLabel`), which
//      printed the UTC hour (07:00 IST showed as 01:30);
//   R2 `getTodayUserMessageCount` and R3 `extractAndAppendCoachingNotes`, which
//      tested `created_at.startsWith(<IST date>)` and so missed every turn sent
//      between 00:00 and 05:30 IST (its UTC date is the day before).
// R4, the Home "💡" coach tip, is REMOVED (founder decision 2026-11-13), so the
// Home insight is the schedule sentence alone.
//
// Host-zone dependent cases carry an expectation per host offset (the
// coach_vs_screen_meal_log_parity_test.dart pattern). Run this file under
// TZ=Asia/Kolkata, TZ=UTC and TZ=Asia/Tokyo.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';

import '../helpers/hive_test_setup.dart';

/// 07:00 IST on 2026-11-13 (the founder's screenshot).
final _sent = DateTime.utc(2026, 11, 13, 1, 30);

/// Expected bubble time of [_sent] by host UTC offset in minutes.
const _labelByOffset = {330: '07:00', 0: '01:30', 540: '10:30', -720: '13:30'};

void main() {
  group('T1 the bubble shows the device clock', () {
    test('a UTC instant is converted before formatting', () {
      final offset = _sent.toLocal().timeZoneOffset.inMinutes;
      final label = chatClockLabel(_sent);
      final expected = _labelByOffset[offset];
      if (expected != null) {
        expect(label, expected, reason: 'host offset $offset min');
      }
      // Zone-independent half: the label is the LOCAL hour and minute.
      final local = _sent.toLocal();
      expect(label, '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}');
      if (offset != 0) {
        expect(label, isNot('01:30'), reason: 'never the UTC hour off UTC');
      }
    });

    test('a parsed `Z` and a parsed `+00:00` row give the same label', () {
      expect(
        chatClockLabel(DateTime.parse('2026-11-13T01:30:50.530863+00:00')),
        chatClockLabel(DateTime.parse('2026-11-13T01:30:50.530Z')),
      );
    });

    test('a zone-less legacy row keeps its own clock', () {
      expect(chatClockLabel(DateTime.parse('2026-09-01T18:05:00.000')), '18:05');
    });

    test('the chat bubble takes its time from chatClockLabel', () {
      final src = File(
        'lib/features/ai_coach/screens/ai_coach/chat_area.dart',
      ).readAsStringSync();
      expect(src, contains('final time = chatClockLabel(message.timestamp);'));
      expect(src, isNot(contains('message.timestamp.hour')));
    });
  });

  group('T2 isIsoOnIstDay', () {
    test('00:30 IST is that IST day although its UTC date is the day before',
        () {
      expect(isIsoOnIstDay('2026-11-12T19:00:00.000Z', '2026-11-13'), isTrue);
      expect(isIsoOnIstDay('2026-11-12T19:00:00.000Z', '2026-11-12'), isFalse);
    });

    test('23:30 IST belongs to that day, not the next', () {
      expect(isIsoOnIstDay('2026-11-12T18:00:00+00:00', '2026-11-12'), isTrue);
      expect(isIsoOnIstDay('2026-11-12T18:00:00+00:00', '2026-11-13'), isFalse);
    });

    test('the IST midnight boundary itself', () {
      expect(isIsoOnIstDay('2026-11-12T18:29:59.999Z', '2026-11-12'), isTrue);
      expect(isIsoOnIstDay('2026-11-12T18:30:00.000Z', '2026-11-13'), isTrue);
    });

    test('empty, null and unparseable strings are on no day', () {
      expect(isIsoOnIstDay('', '2026-11-13'), isFalse);
      expect(isIsoOnIstDay(null, '2026-11-13'), isFalse);
      expect(isIsoOnIstDay('not a date', '2026-11-13'), isFalse);
    });

    test('a zone-less legacy string is read as the device clock', () {
      final legacy = '2026-09-01T12:00:00.000';
      expect(
        isIsoOnIstDay(legacy, istDateStr(DateTime.parse(legacy))),
        isTrue,
      );
    });

    test('the coaching-notes extraction uses it (wiring pin)', () {
      final src = File(
        'lib/features/ai_coach/services/coach_memory_service.dart',
      ).readAsStringSync();
      final start = src.indexOf('Future<void> extractAndAppendCoachingNotes()');
      expect(start, greaterThan(0));
      final body = src.substring(start, src.indexOf('\n  }\n', start));
      expect(body, contains('isIsoOnIstDay(createdAt, todayStr)'));
      expect(body, isNot(contains('startsWith(todayStr)')));
    });
  });

  group('T2 and T4 against Hive', () {
    late Directory dir;
    setUpAll(() async => dir = await setUpHiveForTests());
    tearDownAll(() async => tearDownHiveForTests(dir));
    setUp(() async => HiveService.instance.coachBox.clear());

    Future<void> putTurn(String key, DateTime at, {String reply = ''}) =>
        HiveService.instance.coachBox.put(key, {
          'id': key,
          'user_message': 'q $key',
          'ai_response': reply,
          'mode': 'quick',
          'is_user_message': true,
          'created_at': at.toUtc().toIso8601String(),
        });

    test('the daily count includes a turn sent between 00:00 and 05:30 IST',
        () async {
      final midnight = istMidnightUtc(DateTime.now());
      await putTurn('coach_1', midnight.add(const Duration(minutes: 30)));
      await putTurn('coach_2', midnight.add(const Duration(hours: 6)));
      await putTurn('coach_3', midnight.subtract(const Duration(minutes: 30)));
      expect(
        CoachInteractionRepository.instance.getTodayUserMessageCount(),
        2,
        reason: '00:30 and 06:00 IST today count; 23:30 IST yesterday does not',
      );
    });

    test('the Home insight carries no coach tip (the tip is removed)',
        () async {
      // A reply whose last sentence (24 characters) fit the old 10-80 rule.
      await putTurn(
        'coach_9',
        DateTime.now().toUtc(),
        reply: 'Good session. Keep your elbows tucked in.',
      );
      final c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(c.dispose);
      final insight = c.read(aiInsightProvider);
      expect(insight, isNotNull, reason: 'precondition: an insight renders');
      expect(insight, isNot(contains('💡')));
      expect(insight, isNot(contains('elbows')));
    });
  });
}
