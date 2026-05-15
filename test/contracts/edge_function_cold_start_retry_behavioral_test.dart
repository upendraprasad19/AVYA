import 'package:flutter_test/flutter_test.dart';
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
}
