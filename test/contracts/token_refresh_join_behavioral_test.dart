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
/// race window), clears it on the wrong path, or hands the shared future to a
/// caller it does not belong to. Every test below asserts an observable
/// consequence — how many times the refresher ran, and WHOSE token came back.
///
/// ⚠ The cross-account group exists because the B-pass (2026-08-17) proved by
/// EXECUTION that the first version of this join had no identity affinity:
/// `refresherARan=true refresherBRan=false resultB=token-for-USER-A`. Caller B
/// joined A's refresh and received A's token. That group was structurally
/// absent from this file's first version — every case used ONE shared
/// refresher, so the mirror case could not be seen. Do not remove it.
void main() {
  setUp(() {
    SupabaseService.resetRefreshJoinForTest();
    SupabaseService.disableRefreshJoinForTest = null;
  });

  tearDown(() {
    SupabaseService.resetRefreshJoinForTest();
    SupabaseService.disableRefreshJoinForTest = null;
  });

  group('d7b1f8 — same-identity join', () {
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
          15,
          (_) => SupabaseService.coalescedRefresh(refresher,
              ownerId: 'user-a', liveOwnerId: () => 'user-a'));

      expect(refreshCount, 1,
          reason: 'PRE-FIX THIS WAS 15. Concurrent callers of the SAME '
              'identity must JOIN the in-flight refresh — the client must not '
              'amplify a backend brown-out it is already a victim of.');

      gate.complete();
      final results = await Future.wait(callers);

      expect(refreshCount, 1, reason: 'still exactly one after settling');
      expect(results, everyElement('token-abc'));
    });

    test('a caller arriving AFTER completion starts a new refresh', () async {
      var refreshCount = 0;
      Future<String?> refresher() async {
        refreshCount++;
        return 'tok-$refreshCount';
      }

      final first = await SupabaseService.coalescedRefresh(refresher,
          ownerId: 'user-a', liveOwnerId: () => 'user-a');
      final second = await SupabaseService.coalescedRefresh(refresher,
          ownerId: 'user-a', liveOwnerId: () => 'user-a');

      expect(refreshCount, 2,
          reason: 'the join must COALESCE concurrent callers, never CACHE. A '
              'stale token served forever would be a worse bug than the race.');
      expect(first, 'tok-1');
      expect(second, 'tok-2');
    });

    test('a throwing refresher does not strand the in-flight field', () async {
      var refreshCount = 0;
      Future<String?> throwing() async {
        refreshCount++;
        throw StateError('network down');
      }

      await expectLater(
          SupabaseService.coalescedRefresh(throwing,
              ownerId: 'user-a', liveOwnerId: () => 'user-a'),
          throwsA(isA<StateError>()));
      await expectLater(
          SupabaseService.coalescedRefresh(throwing,
              ownerId: 'user-a', liveOwnerId: () => 'user-a'),
          throwsA(isA<StateError>()));

      expect(refreshCount, 2,
          reason: 'the second call must start a REAL new refresh, proving the '
              'field was cleared on the throw path too');
    });
  });

  group('d7b1f8 — cross-account (B-pass finding 1)', () {
    test('a DIFFERENT identity never joins, and runs its own refresh',
        () async {
      var aRan = false, bRan = false;
      final gate = Completer<void>();

      Future<String?> refresherA() async {
        aRan = true;
        await gate.future;
        return 'token-for-USER-A';
      }

      Future<String?> refresherB() async {
        bRan = true;
        return 'token-for-USER-B';
      }

      // A arms the join and parks.
      final fa = SupabaseService.coalescedRefresh(refresherA,
          ownerId: 'user-a', liveOwnerId: () => 'user-a');
      // B arrives while A is still in flight — different identity.
      final fb = await SupabaseService.coalescedRefresh(refresherB,
          ownerId: 'user-b', liveOwnerId: () => 'user-b');

      expect(aRan, isTrue);
      expect(bRan, isTrue,
          reason: 'PRE-FIX bRan WAS FALSE — B silently joined A and never ran '
              'its own refresh at all');
      expect(fb, 'token-for-USER-B',
          reason: 'PRE-FIX THIS WAS token-for-USER-A. A shared token is a '
              'shared identity; handing A\'s token to B is the same defect '
              'class e5c2d1 fixes one layer down.');

      gate.complete();
      expect(await fa, 'token-for-USER-A');
    });

    test('a session that swaps mid-refresh yields null, not a stale token',
        () async {
      // Sink-side re-check on RESOLVE: the refresh takes real network time and
      // the session can change while it is in flight.
      var live = 'user-a';
      final gate = Completer<void>();

      Future<String?> refresher() async {
        await gate.future;
        return 'token-for-USER-A';
      }

      final f = SupabaseService.coalescedRefresh(refresher,
          ownerId: 'user-a', liveOwnerId: () => live);

      live = 'user-b'; // account swap lands mid-flight
      gate.complete();

      expect(await f, isNull,
          reason: 'the armed identity is no longer live, so the token must NOT '
              'be handed back — null means "no fresh token", which every '
              'caller already handles');
    });

    test('an unreadable live identity (null) also yields null', () async {
      final f = await SupabaseService.coalescedRefresh(
          () async => 'tok',
          ownerId: 'user-a',
          liveOwnerId: () => null);
      expect(f, isNull, reason: 'fails safe when the live owner is unknown');
    });
  });

  group('d7b1f8 — kill-switch', () {
    test('restores the pre-fix racing behaviour', () async {
      SupabaseService.disableRefreshJoinForTest = true;

      var refreshCount = 0;
      final gate = Completer<void>();
      Future<String?> refresher() async {
        refreshCount++;
        await gate.future;
        return 'token';
      }

      final callers = List.generate(
          5,
          (_) => SupabaseService.coalescedRefresh(refresher,
              ownerId: 'user-a', liveOwnerId: () => 'user-a'));
      expect(refreshCount, 5,
          reason: '§4.6 requires the old path stay reachable when the switch '
              'is thrown; 5 concurrent callers must race again');

      gate.complete();
      await Future.wait(callers);
    });

    test('the shipped refresh ceiling is finite and sane', () {
      // B-pass finding 5: an unbounded refresh under a join is STRICTLY worse
      // than one without, because every later caller joins the stuck future.
      expect(SupabaseService.refreshTimeout.inSeconds, greaterThan(0));
      expect(SupabaseService.refreshTimeout.inSeconds, lessThanOrEqualTo(60),
          reason: 'a ceiling long enough to outlive the user\'s patience is '
              'indistinguishable from none');
    });
  });
}
