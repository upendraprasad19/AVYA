import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';

/// Behavioral regression tests for diagnose d7b1f8 — `ensureFreshToken` held
/// no in-flight future, so N concurrent callers each fired their own
/// `refreshSession()`.
///
/// Why behavioral and not source-grep: a grep can only prove the string
/// `_inFlightRefresh` appears in `supabase_service.dart`. It cannot catch a
/// refactor that keeps the field but assigns it AFTER the await (reopening the
/// race window), clears it on the wrong path, or returns a fresh future to each
/// joiner instead of the shared one. Every test below asserts the observable
/// consequence — how many times the refresher actually ran.
///
/// The seam is `SupabaseService.coalescedRefresh`, which is the real code path:
/// `ensureFreshToken`'s expiry branch calls exactly this, so a regression in
/// the join reddens these tests.
void main() {
  setUp(() {
    SupabaseService.resetRefreshJoinForTest();
    SupabaseService.disableRefreshJoin = false;
  });

  tearDown(() {
    SupabaseService.resetRefreshJoinForTest();
    SupabaseService.disableRefreshJoin = false;
  });

  group('d7b1f8 — token refresh join', () {
    test('15 concurrent callers produce exactly ONE refresh', () async {
      // 15 mirrors the observed prod signature: edge_logs recorded ~15
      // GET /auth/v1/user requests all completing inside one 400ms window at
      // 17:49:45, because 15 independent in-flight refreshes had each been
      // blocked on the same starved backend and were released together.
      var refreshCount = 0;
      final gate = Completer<void>();

      Future<String?> refresher() async {
        refreshCount++;
        await gate.future;
        return 'token-abc';
      }

      final callers = List.generate(
          15, (_) => SupabaseService.coalescedRefresh(refresher));

      // All 15 are now parked on the same in-flight future.
      expect(refreshCount, 1,
          reason: 'PRE-FIX THIS WAS 15. Concurrent callers must JOIN the '
              'in-flight refresh, not each start their own — the client must '
              'not amplify a backend brown-out it is already a victim of.');

      gate.complete();
      final results = await Future.wait(callers);

      expect(refreshCount, 1, reason: 'still exactly one after settling');
      expect(results, everyElement('token-abc'),
          reason: 'every joiner receives the shared result');
    });

    test('a caller arriving AFTER completion starts a new refresh', () async {
      var refreshCount = 0;
      Future<String?> refresher() async {
        refreshCount++;
        return 'tok-$refreshCount';
      }

      final first = await SupabaseService.coalescedRefresh(refresher);
      final second = await SupabaseService.coalescedRefresh(refresher);

      expect(refreshCount, 2,
          reason: 'the join must COALESCE concurrent callers, never CACHE. A '
              'stale token served forever would be a worse bug than the race.');
      expect(first, 'tok-1');
      expect(second, 'tok-2');
    });

    test('a throwing refresher does not strand the in-flight field', () async {
      var refreshCount = 0;
      Future<String?> throwingRefresher() async {
        refreshCount++;
        throw StateError('network down');
      }

      await expectLater(
          SupabaseService.coalescedRefresh(throwingRefresher),
          throwsA(isA<StateError>()));

      // If the field were only cleared on the success path, this second call
      // would join a dead future and every later refresh would wedge forever.
      await expectLater(
          SupabaseService.coalescedRefresh(throwingRefresher),
          throwsA(isA<StateError>()));

      expect(refreshCount, 2,
          reason: 'the second call must start a REAL new refresh, proving the '
              'field was cleared on the throw path too');
    });

    test('kill-switch restores the pre-fix racing behaviour', () async {
      SupabaseService.disableRefreshJoin = true;

      var refreshCount = 0;
      final gate = Completer<void>();
      Future<String?> refresher() async {
        refreshCount++;
        await gate.future;
        return 'token';
      }

      final callers =
          List.generate(5, (_) => SupabaseService.coalescedRefresh(refresher));
      expect(refreshCount, 5,
          reason: '§4.6 requires the old path stay reachable when the switch '
              'is thrown; 5 concurrent callers must race again');

      gate.complete();
      await Future.wait(callers);
    });
  });
}
