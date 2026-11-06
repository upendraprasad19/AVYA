// Regression test for audit-2026-05-16 / Obs 6 — storage-race retry.
//
// `SupabaseService.retryColdStart` must retry on FunctionException
// status=400 with `details.error_type == 'storage'` (ai-media-proxy v17
// upload-CDN race). Other 400 classes (validation, oversized, etc.) MUST
// NOT retry — they're caller bugs and retrying spends quota on a
// guaranteed failure.
//
// closes-diagnose: 2026-05-16-photo-storage-retry

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

FunctionResponse _ok(Map<String, dynamic> data) =>
    FunctionResponse(status: 200, data: data);

FunctionException _err(int status, dynamic details) =>
    FunctionException(status: status, details: details);

void main() {
  group('retryColdStart — Storage 400 (CDN race)', () {
    test('400 with error_type=storage retries up to 3 times then returns success',
        () async {
      var calls = 0;
      final resp = await SupabaseService.retryColdStart(
        () async {
          calls++;
          if (calls < 3) {
            throw _err(400, {
              'error': 'Image upload incomplete — please retry',
              'error_type': 'storage',
            });
          }
          return _ok({'ok': true});
        },
        functionName: 'ai-media-proxy',
        // Fast schedule for tests.
        backoffsMs: const [10, 10, 10],
        storageRaceBackoffsMs: const [10, 10, 10],
      );
      expect(resp.status, 200);
      expect(calls, 3,
          reason: '2 storage-race retries + 1 success = 3 attempts');
    });

    test('400 with error_type=storage as JSON-string details also retries',
        () async {
      var calls = 0;
      final resp = await SupabaseService.retryColdStart(
        () async {
          calls++;
          if (calls < 2) {
            throw _err(400,
                '{"error":"upload incomplete","error_type":"storage"}');
          }
          return _ok({'ok': true});
        },
        functionName: 'ai-media-proxy',
        backoffsMs: const [10, 10, 10],
        storageRaceBackoffsMs: const [10, 10, 10],
      );
      expect(resp.status, 200);
      expect(calls, 2);
    });

    test('400 WITHOUT error_type=storage rethrows immediately (no retry)',
        () async {
      var calls = 0;
      await expectLater(
        SupabaseService.retryColdStart(
          () async {
            calls++;
            throw _err(400, {
              'error': 'Image too large',
              'error_type': 'validation',
            });
          },
          functionName: 'ai-media-proxy',
          backoffsMs: const [10, 10, 10],
          storageRaceBackoffsMs: const [10, 10, 10],
        ),
        throwsA(isA<FunctionException>()),
      );
      expect(calls, 1,
          reason:
              'Validation 400 is a caller bug — retrying spends quota '
              'on a guaranteed failure.');
    });

    test('400 with null details rethrows (no retry)', () async {
      var calls = 0;
      await expectLater(
        SupabaseService.retryColdStart(
          () async {
            calls++;
            throw _err(400, null);
          },
          functionName: 'ai-media-proxy',
          backoffsMs: const [10, 10, 10],
          storageRaceBackoffsMs: const [10, 10, 10],
        ),
        throwsA(isA<FunctionException>()),
      );
      expect(calls, 1);
    });

    test('exhausts storage-race budget after 3 retries and rethrows',
        () async {
      var calls = 0;
      await expectLater(
        SupabaseService.retryColdStart(
          () async {
            calls++;
            throw _err(400, {'error_type': 'storage'});
          },
          functionName: 'ai-media-proxy',
          backoffsMs: const [10, 10, 10],
          storageRaceBackoffsMs: const [10, 10, 10],
        ),
        throwsA(isA<FunctionException>()),
      );
      expect(calls, 4,
          reason: '1 initial + 3 retries = 4 attempts before giving up');
    });

    test('502 cold-start and 400/storage both retry independently in order',
        () async {
      // First call: 502 cold-start (retry).
      // Second call: 400/storage (retry).
      // Third call: success.
      var calls = 0;
      final resp = await SupabaseService.retryColdStart(
        () async {
          calls++;
          if (calls == 1) throw _err(502, 'cold start');
          if (calls == 2) throw _err(400, {'error_type': 'storage'});
          return _ok({'ok': true});
        },
        functionName: 'ai-media-proxy',
        backoffsMs: const [10, 10, 10],
        storageRaceBackoffsMs: const [10, 10, 10],
      );
      expect(resp.status, 200);
      expect(calls, 3);
    });
  });
}
