// Unit C (OI-336) - PURE and repository-seam behaviour.
//
// `ReferrerSummary.tryParse`, `creditNoticeFor` (the whole decision table),
// `creditNoticeText`, the expected-absence classifier and
// `ReferralRepository.referrerSummary` through its seam. The surfaces and the
// notifier live in referral_credit_notice_behavioral_test.dart and
// referral_unit_c_surfaces_test.dart.
//
// Plan: docs/plans/referral-unit-c-client.md (sections 2.1, 2.3, 3)

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/features/profile/models/referrer_summary.dart';
import 'package:icanbefitter/features/profile/repositories/referral_repository.dart';
import 'package:icanbefitter/features/profile/services/referral_credit_notice_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionResponse, PostgrestException;

Map<String, dynamic> _body({
  Object? joined = 5,
  Object? subscribed = 2,
  Object? pending = 1,
  Object? credited = 1,
  Object? daysEarned = 14,
}) =>
    {
      'joined': joined,
      'subscribed': subscribed,
      'pending': pending,
      'credited': credited,
      'days_earned': daysEarned,
    };

void main() {
  group('ReferrerSummary.tryParse', () {
    test('a Map with all five int fields parses to exactly those numbers', () {
      final s = ReferrerSummary.tryParse(_body())!;
      expect(s.joined, 5);
      expect(s.subscribed, 2);
      expect(s.pending, 1);
      expect(s.credited, 1);
      expect(s.daysEarned, 14);
    });

    test('a one-row List of maps parses; two rows or none are unknown', () {
      expect(ReferrerSummary.tryParse([_body()]), isNotNull);
      expect(ReferrerSummary.tryParse([_body(), _body()]), isNull);
      expect(ReferrerSummary.tryParse(<Object>[]), isNull);
    });

    test('a missing key makes the WHOLE object unknown (never zeros)', () {
      for (final k in ['joined', 'subscribed', 'pending', 'credited', 'days_earned']) {
        final m = _body()..remove(k);
        expect(ReferrerSummary.tryParse(m), isNull, reason: k);
      }
    });

    test('a string number, a double, a negative or a null field is unknown', () {
      expect(ReferrerSummary.tryParse(_body(joined: '5')), isNull);
      expect(ReferrerSummary.tryParse(_body(subscribed: 2.5)), isNull);
      expect(ReferrerSummary.tryParse(_body(pending: -1)), isNull);
      expect(ReferrerSummary.tryParse(_body(daysEarned: null)), isNull);
    });

    test('null, a string and an empty map are unknown; extra keys are ignored', () {
      expect(ReferrerSummary.tryParse(null), isNull);
      expect(ReferrerSummary.tryParse('x'), isNull);
      expect(ReferrerSummary.tryParse(<String, dynamic>{}), isNull);
      expect(ReferrerSummary.tryParse({..._body(), 'extra': 9}), isNotNull);
    });

    test('joined and subscribed are not swapped', () {
      final s = ReferrerSummary.tryParse(_body(joined: 9, subscribed: 3))!;
      expect([s.joined, s.subscribed], [9, 3]);
    });
  });

  group('creditNoticeFor (the decision table)', () {
    test('first run (no stored scalar) stores the total silently and shows nothing',
        () {
      expect(creditNoticeFor(daysEarned: 0, seen: null),
          const CreditNoticeDecision(storeSeenSilently: 0));
      expect(creditNoticeFor(daysEarned: 7, seen: null),
          const CreditNoticeDecision(storeSeenSilently: 7));
      expect(creditNoticeFor(daysEarned: 7, seen: null).announceDays, 0);
    });

    test('a larger total announces ONLY the difference and writes nothing yet', () {
      final d = creditNoticeFor(daysEarned: 21, seen: 7);
      expect(d.announceDays, 14);
      expect(d.storeSeenSilently, isNull);
    });

    test('an equal total shows nothing and writes nothing', () {
      expect(creditNoticeFor(daysEarned: 7, seen: 7), CreditNoticeDecision.none);
      expect(creditNoticeFor(daysEarned: 0, seen: 0), CreditNoticeDecision.none);
    });

    test('a lower total (a void or a repair) re-baselines silently', () {
      final d = creditNoticeFor(daysEarned: 7, seen: 30);
      expect(d.announceDays, 0);
      expect(d.storeSeenSilently, 7);
    });

    test('a negative input is treated as unknown; large numbers are exact', () {
      expect(creditNoticeFor(daysEarned: -1, seen: 5), CreditNoticeDecision.none);
      expect(creditNoticeFor(daysEarned: -1, seen: null), CreditNoticeDecision.none);
      expect(creditNoticeFor(daysEarned: 1000000, seen: 1).announceDays, 999999);
    });

    test('a negative stored scalar counts as no scalar', () {
      expect(creditNoticeFor(daysEarned: 7, seen: -3),
          const CreditNoticeDecision(storeSeenSilently: 7));
    });

    test('the notice copy is singular/plural safe', () {
      expect(creditNoticeText(1), 'You earned 1 PRO day from friends who subscribed.');
      expect(creditNoticeText(7), 'You earned 7 PRO days from friends who subscribed.');
    });
  });

  group('isExpectedReferrerSummaryAbsence', () {
    test('function missing, lapsed session and revoked EXECUTE are expected', () {
      expect(isExpectedReferrerSummaryAbsence(
          PostgrestException(message: 'x', code: 'PGRST202')), isTrue);
      expect(isExpectedReferrerSummaryAbsence(
          PostgrestException(message: 'x', code: '28000')), isTrue);
      expect(isExpectedReferrerSummaryAbsence(
          PostgrestException(message: 'x', code: '42501')), isTrue);
      expect(isExpectedReferrerSummaryAbsence(Exception('FunctionException(status: 401)')),
          isTrue);
      expect(isExpectedReferrerSummaryAbsence(Exception('FunctionException(status: 404)')),
          isTrue);
    });

    test('offline shapes, native and web, are expected', () {
      expect(isExpectedReferrerSummaryAbsence(const SocketException('no route')),
          isTrue);
      expect(isExpectedReferrerSummaryAbsence(TimeoutException('t')), isTrue);
      expect(isExpectedReferrerSummaryAbsence(Exception('XMLHttpRequest error.')),
          isTrue);
      expect(
          isExpectedReferrerSummaryAbsence(
              Exception('ClientException: Failed to fetch')),
          isTrue);
    });

    test('a genuine other failure is NOT expected', () {
      expect(isExpectedReferrerSummaryAbsence(
          PostgrestException(message: 'boom', code: 'XX000')), isFalse);
      expect(isExpectedReferrerSummaryAbsence(Exception('boom')), isFalse);
      expect(isExpectedReferrerSummaryAbsence(const FormatException('bad')),
          isFalse);
    });
  });

  group('ReferralRepository.redeem 200 bodies (fail CLOSED without success)', () {
    tearDown(() => ReferralRepository.redeemCallForTest = null);

    Future<RedemptionResult> redeemWith(Map<String, dynamic>? data) {
      ReferralRepository.redeemCallForTest =
          (_) async => FunctionResponse(status: 200, data: data);
      return ReferralRepository.instance.redeem('AVYA-ABC12345');
    }

    test('success:true is a grant; with alreadyRedeemed it says so', () async {
      final ok = await redeemWith({'success': true});
      expect((ok.success, ok.alreadyRedeemed), (true, false));
      final replay = await redeemWith({'success': true, 'alreadyRedeemed': true});
      expect((replay.success, replay.alreadyRedeemed), (true, true));
    });

    test('a 200 with no success flag, an empty body or null is NOT a grant',
        () async {
      for (final body in <Map<String, dynamic>?>[
        <String, dynamic>{},
        {'days_granted': 7},
        {'success': 'yes'},
        null,
      ]) {
        final r = await redeemWith(body);
        expect(r.success, isFalse, reason: '$body');
        expect(r.errorMessage, isNotNull);
      }
    });

    test('a 200 carrying an error shows the server text', () async {
      final r = await redeemWith({'error': 'Code expired.'});
      expect((r.success, r.errorMessage), (false, 'Code expired.'));
    });
  });

  group('ReferralRepository.referrerSummary through its seam', () {
    late List<String> nonFatals;

    setUp(() {
      nonFatals = [];
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, s, {required reason, extra}) => nonFatals.add(reason);
    });

    tearDown(() {
      ReferralRepository.summaryRpcForTest = null;
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    });

    Future<ReferrerSummary?> run(Future<dynamic> Function() rpc) {
      ReferralRepository.summaryRpcForTest = rpc;
      return ReferralRepository.instance.referrerSummary();
    }

    test('a good body returns the numbers, no telemetry', () async {
      final s = await run(() async => _body());
      expect(s?.daysEarned, 14);
      expect(nonFatals, isEmpty);
    });

    test('a NULL body and a malformed body are unknown (null), never zeros',
        () async {
      expect(await run(() async => null), isNull);
      expect(await run(() async => _body(joined: 'x')), isNull);
      expect(await run(() async => 'oops'), isNull);
      expect(nonFatals, isEmpty,
          reason: 'a malformed body is not an exception; it is just unknown');
    });

    test('PGRST202, 404, 28000, 42501, 401 and offline return null SILENTLY',
        () async {
      for (final e in <Object>[
        PostgrestException(message: 'missing', code: 'PGRST202'),
        PostgrestException(message: 'auth', code: '28000'),
        PostgrestException(message: 'revoked', code: '42501'),
        Exception('FunctionException(status: 404)'),
        Exception('FunctionException(status: 401)'),
        PostgrestException(message: 'JWT expired', code: 'PGRST301'),
        const SocketException('offline'),
        TimeoutException('slow'),
        Exception('XMLHttpRequest error.'),
      ]) {
        expect(await run(() async => throw e), isNull, reason: '$e');
      }
      expect(nonFatals, isEmpty, reason: 'expected absences must not write rows');
    });

    test('a genuine other failure returns null AND writes one telemetry row',
        () async {
      expect(
          await run(() async =>
              throw PostgrestException(message: 'boom', code: 'XX000')),
          isNull);
      await Future<void>.delayed(Duration.zero);
      expect(nonFatals, ['referral_repository_summary']);
    });
  });
}
