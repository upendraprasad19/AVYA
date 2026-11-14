// BEHAVIORAL TEST — OI-505 fix 2 (plan docs/plans/2026-11-13-coach-late-link-timeout-retry.md
// section 5; diagnose c8f2a4): an ABANDONED coach call sends nothing more.
//
// Writer: CoachCallBudget.expired (set by the notifier's timeout handler).
// Reader: SupabaseService.retryColdStart and AiService.retryHttpColdStart, the
// two loops that would otherwise keep re-sending the turn after the caller gave
// up (a Future.timeout abandons the future, it does not cancel it).
//
// No Hive: plain async tests with a 1 ms back-off.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/ai_service.dart';
import 'package:icanbefitter/core/services/coach_call_budget.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException, FunctionResponse;

Response<dynamic> _http(int status, [Object? data]) => Response<dynamic>(
    requestOptions: RequestOptions(path: '/x'), statusCode: status, data: data);

void main() {
  tearDown(() {
    CoachCallBudget.minimumResendOverride = null;
    CoachCallBudget.turnDeadlineOverride = null;
  });

  group('CoachCallBudget', () {
    test('B1: throwIfExpired is silent until expired, then throws a TimeoutException', () {
      final b = CoachCallBudget();
      b.throwIfExpired();
      b.expired = true;
      expect(b.throwIfExpired, throwsA(isA<TimeoutException>()));
    });

    test('B2: resendTimeout is the rest of the turn deadline, never below the minimum', () {
      expect(CoachCallBudget.resendTimeout(const Duration(seconds: 10)),
          const Duration(seconds: 80));
      expect(CoachCallBudget.resendTimeout(const Duration(seconds: 80)),
          CoachCallBudget.minimumResend);
      expect(CoachCallBudget.resendTimeout(const Duration(seconds: 300)),
          CoachCallBudget.minimumResend);
      CoachCallBudget.turnDeadlineOverride = const Duration(milliseconds: 400);
      CoachCallBudget.minimumResendOverride = const Duration(milliseconds: 60);
      expect(CoachCallBudget.resendTimeout(const Duration(milliseconds: 100)),
          const Duration(milliseconds: 300));
      expect(CoachCallBudget.resendTimeout(const Duration(milliseconds: 399)),
          const Duration(milliseconds: 60));
    });

    test('B3: the constants keep the plan\'s ordering (a resend after auth always fits the deadline)', () {
      expect(CoachCallBudget.chatTimeout, lessThan(CoachCallBudget.turnDeadline));
      expect(CoachCallBudget.latestAuthResend + CoachCallBudget.minimumResend,
          lessThanOrEqualTo(CoachCallBudget.turnDeadline));
      expect(CoachCallBudget.mediaTimeout, greaterThan(CoachCallBudget.chatTimeout));
    });
  });

  group('SupabaseService.retryColdStart', () {
    test('B4: a budget already expired at entry makes NO attempt', () async {
      final b = CoachCallBudget()..expired = true;
      var calls = 0;
      await expectLater(
        SupabaseService.retryColdStart(() async {
          calls++;
          return FunctionResponse(data: {}, status: 200);
        }, functionName: 'ai-proxy', backoffsMs: const [1, 1], budget: b),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 0);
    });

    test('B5: expiry during a cold-start back-off stops the next attempt', () async {
      final b = CoachCallBudget();
      var calls = 0;
      await expectLater(
        SupabaseService.retryColdStart(() async {
          calls++;
          b.expired = true; // the notifier's timeout fires while this attempt runs
          throw FunctionException(status: 503, details: 'cold');
        }, functionName: 'ai-proxy', backoffsMs: const [1, 1], budget: b),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 1, reason: 'no second send after expiry');
    });

    test('B6: expiry during a storage-race back-off stops the next attempt', () async {
      final b = CoachCallBudget();
      var calls = 0;
      await expectLater(
        SupabaseService.retryColdStart(() async {
          calls++;
          b.expired = true;
          throw FunctionException(status: 400, details: {'error_type': 'storage'});
        },
            functionName: 'ai-media-proxy',
            storageRaceBackoffsMs: const [1, 1],
            budget: b),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 1);
    });

    test('B7: without an expired budget the loop still retries a cold start (the guard changed nothing else)', () async {
      final b = CoachCallBudget();
      var calls = 0;
      final r = await SupabaseService.retryColdStart(() async {
        calls++;
        if (calls < 3) throw FunctionException(status: 503, details: 'cold');
        return FunctionResponse(data: {'ok': true}, status: 200);
      }, functionName: 'ai-proxy', backoffsMs: const [1, 1], budget: b);
      expect(calls, 3);
      expect(r.status, 200);
    });
  });

  group('AiService.retryHttpColdStart', () {
    test('B8: a budget already expired at entry makes NO attempt', () async {
      final b = CoachCallBudget()..expired = true;
      var calls = 0;
      await expectLater(
        AiService.retryHttpColdStart(() async {
          calls++;
          return _http(200);
        }, functionName: 'ai-proxy', budget: b, sleep: (_) async {}),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 0);
    });

    test('B9: expiry during a cold-start back-off stops the next attempt', () async {
      final b = CoachCallBudget();
      var calls = 0;
      await expectLater(
        AiService.retryHttpColdStart(() async {
          calls++;
          return _http(503);
        },
            functionName: 'ai-proxy',
            budget: b,
            sleep: (_) async => b.expired = true),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 1);
    });

    test('B10: expiry during a storage-race back-off stops the next attempt', () async {
      final b = CoachCallBudget();
      var calls = 0;
      await expectLater(
        AiService.retryHttpColdStart(() async {
          calls++;
          return _http(400, '{"error_type":"storage"}');
        },
            functionName: 'ai-media-proxy',
            budget: b,
            sleep: (_) async => b.expired = true),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 1);
    });

    test('B11: without an expired budget the loop still retries a cold start', () async {
      var calls = 0;
      final r = await AiService.retryHttpColdStart(() async {
        calls++;
        return _http(calls < 3 ? 503 : 200);
      },
          functionName: 'ai-proxy',
          budget: CoachCallBudget(),
          sleep: (_) async {});
      expect(calls, 3);
      expect(r.statusCode, 200);
    });
  });
}
