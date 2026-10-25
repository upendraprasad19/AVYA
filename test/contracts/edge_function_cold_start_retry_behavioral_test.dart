import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Behavioral regression tests for Bug 7c4e1a + Bug c01d57 — cold-start
/// retry control flow.
///
/// Source-grep tests (`retry_loop_guard_test.dart`,
/// `edge_function_503_retry_test.dart`) pin the *code shape* — the const
/// backoff list, the telemetry op_type, the single `invoke` call site, the
/// rethrow gate. They CANNOT catch:
///
///   - A future refactor preserving those static markers but breaking the
///     break/rethrow condition (off-by-one, wrong comparator, etc.).
///   - A future refactor adding a second invoker call site inside the loop
///     that grep's "exactly N invoke calls" assumption misses silently.
///   - Actual retry counting semantics under thrown exceptions.
///
/// These behavioral tests inject a mock invoker into
/// `SupabaseService.retryColdStart` (the `@visibleForTesting` helper that
/// `callFunction` delegates to) and assert runtime behavior end-to-end.
///
/// Schedule history pinned across the tests below:
///   - 2026-05-11 (24d6d54): [1500] — single retry @ 1.5 s.
///   - 2026-05-12 (7c4e1a):  [1500, 4000] — 2 retries, ~5.5 s total.
///   - 2026-05-15 (c01d57):  [2000, 6000, 12000] — 3 retries, ~20 s
///     total. Also added 504 to the retry-trigger set.
void main() {
  group('Bug 7c4e1a + c01d57 — cold-start retry behavioral', () {
    test('2 consecutive 502s then 200 on 3rd attempt returns success', () async {
      var attempts = 0;
      Future<FunctionResponse> mockInvoker() async {
        attempts++;
        if (attempts <= 2) {
          throw const FunctionException(status: 502, details: 'cold start');
        }
        return FunctionResponse(status: 200, data: {'ok': true});
      }

      final resp = await SupabaseService.retryColdStart(
        mockInvoker,
        functionName: 'test-fn',
        backoffsMs: const [10, 10], // fast for tests
      );

      expect(attempts, 3,
          reason: 'Should have invoked exactly 3 times (1 initial + 2 retries)');
      expect(resp.status, 200);
      expect(resp.data, {'ok': true});
    });

    test('2 consecutive 503s then 200 on 3rd attempt returns success', () async {
      // Mirror of the 502 case — both BAD_GATEWAY (502) and BOOT_ERROR (503)
      // are treated as cold-start signatures and trigger retry.
      var attempts = 0;
      Future<FunctionResponse> mockInvoker() async {
        attempts++;
        if (attempts <= 2) {
          throw const FunctionException(status: 503, details: 'boot error');
        }
        return FunctionResponse(status: 200, data: {'ok': true});
      }

      final resp = await SupabaseService.retryColdStart(
        mockInvoker,
        functionName: 'test-fn',
        backoffsMs: const [10, 10],
      );

      expect(attempts, 3);
      expect(resp.status, 200);
    });

    test('502 then 500 stops retry (does NOT recurse on non-cold-start)',
        () async {
      // First attempt 502 (cold-start, retryable) → second attempt 500
      // (server error, NOT cold-start) → must rethrow the 500 without
      // a third invocation.
      var attempts = 0;
      Future<FunctionResponse> mockInvoker() async {
        attempts++;
        if (attempts == 1) {
          throw const FunctionException(status: 502, details: 'cold');
        }
        throw const FunctionException(status: 500, details: 'internal');
      }

      await expectLater(
        () => SupabaseService.retryColdStart(
          mockInvoker,
          functionName: 'test-fn',
          backoffsMs: const [10, 10],
        ),
        throwsA(
            isA<FunctionException>().having((e) => e.status, 'status', 500)),
      );
      expect(attempts, 2,
          reason: 'Should stop after 500 (initial 502 + 1 retry → 500 rethrows)');
    });

    test('non-cold-start 4xx on first attempt rethrows immediately', () async {
      // 400 Bad Request must NOT trigger any retry. This protects the
      // 401-recursion guard intent — only 502/503 are retryable; auth
      // and validation errors surface immediately to the caller.
      var attempts = 0;
      Future<FunctionResponse> mockInvoker() async {
        attempts++;
        throw const FunctionException(status: 400, details: 'bad request');
      }

      await expectLater(
        () => SupabaseService.retryColdStart(
          mockInvoker,
          functionName: 'test-fn',
          backoffsMs: const [10, 10],
        ),
        throwsA(
            isA<FunctionException>().having((e) => e.status, 'status', 400)),
      );
      expect(attempts, 1, reason: 'No retry on 4xx — must invoke exactly once');
    });

    test('401 unauthorized rethrows immediately (no retry recursion)', () async {
      // Belt + suspenders for the 2026-04-07 401-recursion guard. Even
      // though callFunction proactively refreshes the JWT, if a 401
      // somehow surfaces from the invoker, retryColdStart must NOT loop.
      var attempts = 0;
      Future<FunctionResponse> mockInvoker() async {
        attempts++;
        throw const FunctionException(status: 401, details: 'unauthorized');
      }

      await expectLater(
        () => SupabaseService.retryColdStart(
          mockInvoker,
          functionName: 'test-fn',
          backoffsMs: const [10, 10],
        ),
        throwsA(
            isA<FunctionException>().having((e) => e.status, 'status', 401)),
      );
      expect(attempts, 1);
    });

    test('exhausting all retries rethrows the last 502', () async {
      // Every attempt fails with 502. With backoffsMs.length == 2 (test
      // override), that's 1 initial + 2 retries = 3 total invocations,
      // then rethrow. Default schedule asserts the production count
      // separately below.
      var attempts = 0;
      Future<FunctionResponse> mockInvoker() async {
        attempts++;
        throw FunctionException(status: 502, details: 'cold #$attempts');
      }

      await expectLater(
        () => SupabaseService.retryColdStart(
          mockInvoker,
          functionName: 'test-fn',
          backoffsMs: const [10, 10],
        ),
        throwsA(
            isA<FunctionException>().having((e) => e.status, 'status', 502)),
      );
      expect(attempts, 3, reason: '1 initial + 2 retries before rethrow');
    });

    test('success on first attempt does not retry', () async {
      var attempts = 0;
      Future<FunctionResponse> mockInvoker() async {
        attempts++;
        return FunctionResponse(status: 200, data: {'fresh': true});
      }

      final resp = await SupabaseService.retryColdStart(
        mockInvoker,
        functionName: 'test-fn',
        backoffsMs: const [10, 10],
      );

      expect(attempts, 1);
      expect(resp.status, 200);
    });

    test('default backoffsMs length matches retry budget (3 retries)',
        () async {
      // Pins the default schedule's retry count. Test #15.5 / Bug c01d57
      // bumped from [1500, 4000] (2 retries) to [2000, 6000, 12000]
      // (3 retries) — total wait window now ~20 s to cover the 20.2 s
      // worst-case warm-start measured in the 7c4e1a diagnose. If
      // someone shrinks `_coldStartBackoffsMs` without updating this
      // test, the runtime count changes silently — caught here.
      var attempts = 0;
      Future<FunctionResponse> mockInvoker() async {
        attempts++;
        throw const FunctionException(status: 502, details: 'cold');
      }

      await expectLater(
        () => SupabaseService.retryColdStart(
          mockInvoker,
          functionName: 'test-fn',
          // No backoffsMs override — uses the default schedule.
        ),
        throwsA(isA<FunctionException>()),
      );
      expect(attempts, 4,
          reason: 'Default schedule = 3 retries → 4 total invocations '
              '(Test #15.5 / c01d57 — schedule [2000, 6000, 12000])');
    }, timeout: const Timeout(Duration(seconds: 30))); // covers real 2000+6000+12000 ms waits

    // ─── Bug c01d57 — Test #15.5 cases ──────────────────────────────
    // Schedule bump from [1500, 4000] (2 retries) → [2000, 6000, 12000]
    // (3 retries). 504 added to the retry-trigger set. All cases below
    // override `backoffsMs` with fast values so the suite stays quick;
    // production schedule pinned by the `default backoffsMs` test above.

    test('c01d57: 3× 502 then 200 returns success on attempt 4', () async {
      // Worst-case cold start: 3 BAD_GATEWAY responses before warm.
      // Default schedule allows 3 retries — must succeed on attempt 4.
      var attempts = 0;
      Future<FunctionResponse> mockInvoker() async {
        attempts++;
        if (attempts <= 3) {
          throw const FunctionException(status: 502, details: 'cold');
        }
        return FunctionResponse(status: 200, data: {'ok': true});
      }

      final resp = await SupabaseService.retryColdStart(
        mockInvoker,
        functionName: 'test-fn',
        backoffsMs: const [10, 10, 10], // 3 retries, fast for tests
      );

      expect(attempts, 4,
          reason: '1 initial + 3 retries → success on 4th attempt');
      expect(resp.status, 200);
    });

    test('c01d57: 4× 502 exhausts retries', () async {
      // Every attempt fails with 502. With backoffsMs.length == 3 (the
      // new default), that's 1 initial + 3 retries = 4 total
      // invocations, then rethrow the last 502.
      var attempts = 0;
      Future<FunctionResponse> mockInvoker() async {
        attempts++;
        throw FunctionException(status: 502, details: 'cold #$attempts');
      }

      await expectLater(
        () => SupabaseService.retryColdStart(
          mockInvoker,
          functionName: 'test-fn',
          backoffsMs: const [10, 10, 10],
        ),
        throwsA(
            isA<FunctionException>().having((e) => e.status, 'status', 502)),
      );
      expect(attempts, 4, reason: '1 initial + 3 retries before rethrow');
    });

    test('c01d57: 504 Gateway Timeout retries and succeeds on attempt 2',
        () async {
      // 504 added to retry-trigger set in Test #15.5. Cold-start
      // gateway timeouts can surface as either 502 or 504.
      var attempts = 0;
      Future<FunctionResponse> mockInvoker() async {
        attempts++;
        if (attempts == 1) {
          throw const FunctionException(status: 504, details: 'gateway timeout');
        }
        return FunctionResponse(status: 200, data: {'ok': true});
      }

      final resp = await SupabaseService.retryColdStart(
        mockInvoker,
        functionName: 'test-fn',
        backoffsMs: const [10, 10, 10],
      );

      expect(attempts, 2,
          reason: '504 must trigger retry — succeeded on 2nd attempt');
      expect(resp.status, 200);
    });

    test('c01d57: 502 then 500 stops retry (500 is NOT cold-start)',
        () async {
      // First attempt 502 (cold-start, retryable) → second attempt 500
      // (server error, NOT cold-start; pre-c01d57 behavior preserved).
      // Must rethrow the 500 without a third invocation.
      var attempts = 0;
      Future<FunctionResponse> mockInvoker() async {
        attempts++;
        if (attempts == 1) {
          throw const FunctionException(status: 502, details: 'cold');
        }
        throw const FunctionException(status: 500, details: 'internal');
      }

      await expectLater(
        () => SupabaseService.retryColdStart(
          mockInvoker,
          functionName: 'test-fn',
          backoffsMs: const [10, 10, 10],
        ),
        throwsA(
            isA<FunctionException>().having((e) => e.status, 'status', 500)),
      );
      expect(attempts, 2,
          reason: '500 ≠ cold-start trigger → rethrow without further retry');
    });

    test('c01d57: 504 + 500 stops retry (500 still not retryable)', () async {
      // Mirror of the previous case, but the first attempt is 504
      // (newly retryable) rather than 502. Validates the wider trigger
      // set does NOT pull 500 into the retry pool.
      var attempts = 0;
      Future<FunctionResponse> mockInvoker() async {
        attempts++;
        if (attempts == 1) {
          throw const FunctionException(status: 504, details: 'gateway timeout');
        }
        throw const FunctionException(status: 500, details: 'internal');
      }

      await expectLater(
        () => SupabaseService.retryColdStart(
          mockInvoker,
          functionName: 'test-fn',
          backoffsMs: const [10, 10, 10],
        ),
        throwsA(
            isA<FunctionException>().having((e) => e.status, 'status', 500)),
      );
      expect(attempts, 2);
    });
  });
  // OI-414 — a call flagged `spendsQuotaPerCall` is never sent again on a
  // gateway 502/503/504, because the handler may already have run and spent
  // its quota unit. Events are captured through the telemetry seam; the hook is
  // set in setUp and nulled in tearDown so a failing expect cannot leak it.
  //
  // A compile error before the fix is NOT proof that these tests catch it: the
  // proof is the mutant run recorded in
  // docs/diagnoses/2026-10-25-promo-check-gateway-retry-a6d2f9.md. Rows marked
  // (control) pass with and without the fix.
  group('OI-414 spendsQuotaPerCall', () {
    final events = <String>[];

    setUp(() {
      events.clear();
      ErrorTelemetry.debugOnLogEventForTests = (opType, {message}) {
        events.add('$opType:$message');
      };
    });

    tearDown(() {
      ErrorTelemetry.debugOnLogEventForTests = null;
    });

    // A long first wait on purpose: a gate placed AFTER the backoff would not
    // finish inside the timeout, and an EMPTY backoff list would rethrow at the
    // first attempt even without the gate (a pass for the wrong reason).
    Future<void> expectStopsAtFirstAnswer(int status) async {
      var attempts = 0;
      Future<FunctionResponse> invoker() async {
        attempts++;
        throw FunctionException(status: status, details: 'gateway');
      }

      await expectLater(
        () => SupabaseService.retryColdStart(
          invoker,
          functionName: 'test-fn',
          backoffsMs: const [60000, 60000, 60000],
          spendsQuotaPerCall: true,
        ).timeout(const Duration(seconds: 2)),
        throwsA(isA<FunctionException>()
            .having((e) => e.status, 'status', status)),
        reason: 'a TimeoutException here means the gateway status was still '
            'waiting for a re-send',
      );
      expect(attempts, 1, reason: 'one invocation, no re-send');
      expect(events,
          ['edge_function_no_retry_quota_call:fn=test-fn status=$status'],
          reason: 'exactly the stop event, and no cold-start re-send event');
    }

    test('T1: 502 on a flagged call is thrown on the first answer', () async {
      await expectStopsAtFirstAnswer(502);
    });

    test('T2: 504 on a flagged call is thrown on the first answer', () async {
      await expectStopsAtFirstAnswer(504);
    });

    test('T3: 503 on a flagged call is thrown on the first answer', () async {
      await expectStopsAtFirstAnswer(503);
    });

    test('T5a (control): 504 then 200 WITHOUT the flag is still re-sent',
        () async {
      var attempts = 0;
      Future<FunctionResponse> invoker() async {
        attempts++;
        if (attempts == 1) {
          throw const FunctionException(status: 504, details: 'gateway');
        }
        return FunctionResponse(status: 200, data: {'ok': true});
      }

      final resp = await SupabaseService.retryColdStart(
        invoker,
        functionName: 'test-fn',
        backoffsMs: const [10, 10, 10],
      );
      expect(attempts, 2);
      expect(resp.status, 200);
      expect(events, [
        'edge_function_cold_start_retry:fn=test-fn attempt=1 status=504 '
            'backoff_ms=10'
      ], reason: 'the old path, event for event');
    });

    test('T5b (control): 503 with string details WITHOUT the flag is re-sent',
        () async {
      var attempts = 0;
      Future<FunctionResponse> invoker() async {
        attempts++;
        if (attempts == 1) {
          throw const FunctionException(status: 503, details: 'boot error');
        }
        return FunctionResponse(status: 200, data: {'ok': true});
      }

      await SupabaseService.retryColdStart(
        invoker,
        functionName: 'test-fn',
        backoffsMs: const [10, 10, 10],
      );
      expect(attempts, 2);
      expect(events.where((e) => e.startsWith('edge_function_no_retry')),
          isEmpty);
    });

    test('T6: the explicit retryOn500 opt-in is respected on a flagged call',
        () async {
      var attempts = 0;
      Future<FunctionResponse> invoker() async {
        attempts++;
        if (attempts == 1) {
          throw const FunctionException(status: 500, details: 'upstream');
        }
        return FunctionResponse(status: 200, data: {'ok': true});
      }

      final resp = await SupabaseService.retryColdStart(
        invoker,
        functionName: 'test-fn',
        backoffsMs: const [10, 10, 10],
        retryOn500: true,
        spendsQuotaPerCall: true,
      );
      expect(attempts, 2, reason: 'the flag only covers the gateway statuses');
      expect(resp.status, 200);
      expect(events.where((e) => e.startsWith('edge_function_no_retry')),
          isEmpty);
    });

    test('T7 (control): 400, 401 and a plain 500 on a flagged call rethrow at '
        'once with no stop event', () async {
      for (final status in [400, 401, 500]) {
        events.clear();
        var attempts = 0;
        Future<FunctionResponse> invoker() async {
          attempts++;
          throw FunctionException(status: status, details: 'caller error');
        }

        await expectLater(
          () => SupabaseService.retryColdStart(
            invoker,
            functionName: 'test-fn',
            backoffsMs: const [10, 10, 10],
            spendsQuotaPerCall: true,
          ),
          throwsA(isA<FunctionException>()
              .having((e) => e.status, 'status', status)),
        );
        expect(attempts, 1, reason: 'status $status');
        expect(events, isEmpty, reason: 'status $status is not a gateway status');
      }
    });

    test('T7b: the storage-race 400 on a flagged call is still re-sent',
        () async {
      var attempts = 0;
      Future<FunctionResponse> invoker() async {
        attempts++;
        if (attempts == 1) {
          throw const FunctionException(
              status: 400, details: {'error_type': 'storage'});
        }
        return FunctionResponse(status: 200, data: {'ok': true});
      }

      await SupabaseService.retryColdStart(
        invoker,
        functionName: 'test-fn',
        storageRaceBackoffsMs: const [10, 10, 10],
        spendsQuotaPerCall: true,
      );
      expect(attempts, 2);
      expect(events.where((e) => e.startsWith('edge_function_no_retry')),
          isEmpty);
    });

    test('T7c: a transport failure (status 0) on a flagged call rethrows once '
        'with no stop event', () async {
      var attempts = 0;
      Future<FunctionResponse> invoker() async {
        attempts++;
        throw const FunctionsFetchException(details: 'offline');
      }

      await expectLater(
        () => SupabaseService.retryColdStart(
          invoker,
          functionName: 'test-fn',
          backoffsMs: const [10, 10, 10],
          spendsQuotaPerCall: true,
        ),
        throwsA(isA<FunctionException>()
            .having((e) => e.status, 'status', 0)),
      );
      expect(attempts, 1);
      expect(events, isEmpty);
    });

    test('T8: a flagged call stops at the first answer of EVERY status 100-599 '
        'except the storage-race 400: one attempt, a stop event only for '
        '502/503/504', () async {
      // The sweep, not a list, so a status added to the cold-start predicate
      // (520, 522, ...) cannot be re-sent on a flagged call unnoticed.
      for (var status = 100; status <= 599; status++) {
        events.clear();
        var attempts = 0;
        Future<FunctionResponse> invoker() async {
          attempts++;
          throw FunctionException(status: status, details: 'gateway');
        }

        await expectLater(
          () => SupabaseService.retryColdStart(
            invoker,
            functionName: 'test-fn',
            backoffsMs: const [10, 10, 10],
            storageRaceBackoffsMs: const [10, 10, 10],
            spendsQuotaPerCall: true,
          ),
          throwsA(isA<FunctionException>()
              .having((e) => e.status, 'status', status)),
          reason: 'status $status',
        );
        expect(attempts, 1, reason: 'status $status was sent again');
        final isGateway = status == 502 || status == 503 || status == 504;
        expect(
          events,
          isGateway
              ? ['edge_function_no_retry_quota_call:fn=test-fn status=$status']
              : isEmpty,
          reason: 'status $status',
        );
      }
    });

    test('T9: retryOn500 does not switch the stop off for a gateway status',
        () async {
      // The two switches are independent: retryOn500 adds the 500 retry, the
      // flag stops the gateway re-send. A gate written as `&& !retryOn500`
      // would send a metered call again here.
      var attempts = 0;
      Future<FunctionResponse> invoker() async {
        attempts++;
        throw const FunctionException(status: 502, details: 'gateway');
      }

      await expectLater(
        () => SupabaseService.retryColdStart(
          invoker,
          functionName: 'test-fn',
          backoffsMs: const [10, 10, 10],
          retryOn500: true,
          spendsQuotaPerCall: true,
        ),
        throwsA(isA<FunctionException>()
            .having((e) => e.status, 'status', 502)),
      );
      expect(attempts, 1);
      expect(events,
          ['edge_function_no_retry_quota_call:fn=test-fn status=502']);
    });
  });
}
