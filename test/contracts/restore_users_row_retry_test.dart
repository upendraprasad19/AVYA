// Regression guard for diagnose d4e9a2.
//
// `_restoreUserProfile` (lib/core/services/sync/sync_profile.dart) merges
// `public.users.full_name` into the local Hive profile map on restore. The
// `users` SELECT that feeds that merge sat in its own try/catch with no
// retry: a token that expires mid-restore comes back as either a 401
// (thrown, already caught) or an RLS-filtered EMPTY result — HTTP 200,
// `null` — indistinguishable from "no such row", no exception at all. That
// second shape silently dropped `full_name` from the merge while the rest
// of the profile restore succeeded (`hasProfile=true`, `rawName=<null>` at
// every reader — confirmed live via the `profile_full_name_empty_at_read`
// telemetry probe on 2+ real accounts, 2026-08-01 through 2026-08-29).
//
// Fix mirrors `AuthSessionBootstrapper.resolveDestination`'s existing
// c2e9f4 pattern for the identical ambiguity: proactive `ensureFreshToken`
// + one retry behind a hard `refreshSession` before accepting an empty
// result.
//
// This is a source-grep structural test, not a Postgres-touching
// behavioral one — `test/contracts/auth_session_bootstrapper_test.dart`
// already establishes why for the exact same retry shape ("the heavier
// behavioral tests (Postgres-touching) would require a mocked Supabase
// client we don't have infra for"). `presence_only: true` in the SoT entry
// cites this file for the same reason.

import 'package:flutter_test/flutter_test.dart';

import '../contracts/_sync_service_source.dart';

/// Strip block + line comments so source-grep contracts don't false-
/// positive on explanatory comments that quote the pattern under test.
/// Canonical helper per `feedback_source_grep_strip_comments_first.md`.
String _stripComments(String src) {
  final noBlocks =
      src.replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '');
  return noBlocks.replaceAll(RegExp(r'//[^\n]*'), '');
}

/// Body of `_fetchUsersRowForRestore`, from its signature to the start of
/// the next top-level method in the extension (`static String
/// _shortUserId`) — a fixed neighbor-anchored window rather than a brace
/// balancer, matching this test file's siblings (see
/// `restore_completeness_test.dart`'s own note on why a raised-twice
/// fixed-size window earns a brace-balance extractor on a THIRD
/// recurrence — this is the first instance for this method, so the
/// simpler anchored window is proportionate).
String _fetchUsersRowForRestoreBody(String src) {
  const sig = 'Future<Map<String, dynamic>?> _fetchUsersRowForRestore(';
  final start = src.indexOf(sig);
  if (start == -1) return '';
  final end = src.indexOf('static String _shortUserId', start);
  return end == -1 ? src.substring(start) : src.substring(start, end);
}

void main() {
  late String syncSrc;

  setUpAll(() async {
    syncSrc = _stripComments(await loadSyncServiceSource().readAsString());
  });

  group('restore_users_row_retry (diagnose d4e9a2)', () {
    test('_restoreUserProfile delegates the users select to the retrying helper', () {
      final start = syncSrc.indexOf('Future<void> _restoreUserProfile(');
      expect(start, isNot(-1), reason: '_restoreUserProfile must still exist');
      final nextSig =
          syncSrc.indexOf('Future<Map<String, dynamic>?> _fetchUsersRowForRestore(', start);
      final body = nextSig == -1
          ? syncSrc.substring(start)
          : syncSrc.substring(start, nextSig);
      expect(
        body.contains('_fetchUsersRowForRestore(userId)'),
        isTrue,
        reason: '_restoreUserProfile must call _fetchUsersRowForRestore for '
            'the non-injected path — a bare inline `.from(\'users\')` select '
            'here has no retry and silently drops full_name on an '
            'RLS-filtered empty result.',
      );
    });

    test('_fetchUsersRowForRestore exists and selects full_name + email', () {
      final body = _fetchUsersRowForRestoreBody(syncSrc);
      expect(body, isNotEmpty, reason: '_fetchUsersRowForRestore must exist');
      expect(body.contains("from('users')"), isTrue);
      expect(body.contains('full_name'), isTrue);
    });

    test('proactively refreshes the token before the first select', () {
      final body = _fetchUsersRowForRestoreBody(syncSrc);
      expect(
        body.contains('ensureFreshToken()'),
        isTrue,
        reason: 'A token expiring mid-restore must be refreshed proactively '
            '— same precaution resolveDestination takes for the identical '
            'ambiguity.',
      );
    });

    test('retries via a HARD refreshSession when the first result is null', () {
      final body = _fetchUsersRowForRestoreBody(syncSrc);
      // Two select() invocations — the first attempt and the retry —
      // straddling a refreshSession() call is the shape that actually
      // recovers an RLS-filtered empty result. A single select() with no
      // retry (the pre-fix shape) would fail this on the call count alone.
      final selectCalls = 'await select()'.allMatches(body).length;
      expect(selectCalls >= 2, isTrue,
          reason: 'must call select() at least twice (first attempt + '
              'post-refresh retry) — found $selectCalls');
      expect(
        body.contains('refreshSession()'),
        isTrue,
        reason: 'the retry must be a HARD refresh (auth.refreshSession), '
            'not another ensureFreshToken() — mirrors '
            'resolveDestination\'s escalation for a token rejected for any '
            'other reason (rotated, revoked, clock skew).',
      );
      // The refresh call must sit BETWEEN the two selects, not before both.
      final firstSelect = body.indexOf('await select()');
      final refresh = body.indexOf('refreshSession()');
      final secondSelect = body.indexOf('await select()', firstSelect + 1);
      expect(firstSelect, isNot(-1));
      expect(secondSelect, isNot(-1));
      expect(
        refresh > firstSelect && refresh < secondSelect,
        isTrue,
        reason: 'refreshSession() must run strictly between the first and '
            'second select() calls, not before both (which would just be a '
            'second proactive refresh, not a retry-on-empty).',
      );
    });

    test('retry outcomes are distinguishably logged', () {
      final body = _fetchUsersRowForRestoreBody(syncSrc);
      expect(body.contains('restore_users_row_empty_retrying'), isTrue);
      expect(body.contains('restore_users_row_retry_succeeded'), isTrue);
      expect(body.contains('restore_users_row_retry_still_empty'), isTrue);
      // Reason: the next live occurrence of this class must be diagnosable
      // from client_errors alone (succeeded vs still-empty vs never-fired),
      // rather than re-deriving the same "leading hypothesis, not yet
      // confirmed" state this diagnose-doc started from.
    });

    // Plan-review round 1 finding 1 — the four tests above pin call COUNT
    // and ORDERING (select() twice, refreshSession() between them) and that
    // telemetry substrings exist, but none of them inspect what the
    // function actually RETURNS after the retry. Demonstrated, not
    // hypothesized: mutating `return retried;` to `return first;` (i.e.
    // reintroducing the exact pre-fix defect — the retry recovers a real
    // row over the network, but the function hands back the stale null
    // anyway) left all 7 pre-existing tests green. This test closes that
    // gap directly.
    test('the retry block returns the RETRIED result, not the stale first '
        'result', () {
      final body = _fetchUsersRowForRestoreBody(syncSrc);
      final firstSelect = body.indexOf('await select()');
      final secondSelect = body.indexOf('await select()', firstSelect + 1);
      expect(firstSelect, isNot(-1));
      expect(secondSelect, isNot(-1));
      final afterSecondSelect = body.substring(secondSelect);
      expect(
        afterSecondSelect.contains('return retried;'),
        isTrue,
        reason: 'after the retry, the function must return the RETRIED '
            'result — returning the stale first (null) result here would '
            'silently resurrect the exact bug this fix closes.',
      );
      expect(
        afterSecondSelect.contains('return first;'),
        isFalse,
        reason: 'a mutation that returns the pre-retry `first` value after '
            'the retry has already run passes every other assertion in '
            'this file (call count, ordering, telemetry substrings) while '
            'silently reintroducing the bug — this is the assertion that '
            'actually pins the return value.',
      );
    });

    // Plan-review round 2 finding 2 — the test above pins what happens
    // AFTER the retry, and nothing pinned the guard that decides whether
    // the retry runs at all. Demonstrated: neutering the early return to
    // `if (false) return first;` left all 8 tests green. The consequence
    // is not merely a wasted round-trip: every restore would then force a
    // hard refreshSession() + second select even when the FIRST select
    // already returned the row, and if that now-mandatory second call
    // fails transiently (exactly the flakiness this fix exists to
    // tolerate) the function returns null — discarding a full_name it had
    // already successfully fetched. Same bug class, re-entered through the
    // guard instead of the return.
    test('the happy path returns early — the retry is gated on a null first '
        'result, not run unconditionally', () {
      final body = _fetchUsersRowForRestoreBody(syncSrc);
      final firstSelect = body.indexOf('await select()');
      expect(firstSelect, isNot(-1));
      final retryLog = body.indexOf('restore_users_row_empty_retrying');
      expect(retryLog, isNot(-1),
          reason: 'the retry-branch telemetry must exist to anchor this test');
      final betweenFirstSelectAndRetry =
          body.substring(firstSelect, retryLog);
      expect(
        betweenFirstSelectAndRetry.contains('if (first != null) return first;'),
        isTrue,
        reason: 'the non-null first result must short-circuit BEFORE the '
            'retry branch. Without this guard the retry runs on every '
            'restore, and a transient failure of the forced second call '
            'discards a full_name the first call already retrieved.',
      );
    });
  });

  // B-pass finding 1 (this diagnose's own review) — the retry helper above
  // is only reachable when _restoreUserProfile is called with NO
  // preFetchedUsers argument. The C3 single-call restore (tried first for
  // EVERY restore, sync_service.dart:1417) injects `preFetchedUsers:
  // row('users')` directly, bypassing _fetchUsersRowForRestore entirely —
  // a real (non-sentinel) null there took the retry-path's telemetry with
  // it. Fixed by distinguishing "no key" (_kNoInject) from "key present,
  // value null" and logging the latter independently.
  group('C3 single-call null-injection coverage (B-pass finding 1)', () {
    test(
        'a non-sentinel null preFetchedUsers does NOT call the retrying '
        'helper, and is logged distinctly', () {
      final start = syncSrc.indexOf('Future<void> _restoreUserProfile(');
      final nextSig = syncSrc.indexOf(
          'Future<Map<String, dynamic>?> _fetchUsersRowForRestore(', start);
      expect(start, isNot(-1));
      expect(nextSig, isNot(-1));
      final body = syncSrc.substring(start, nextSig);
      expect(
        body.contains('!identical(preFetchedUsers, _kNoInject)'),
        isTrue,
        reason: 'the C3 single-call path (a real, non-sentinel '
            'preFetchedUsers value) already queried `users` through a '
            'service-role Edge Function client — RLS-immune, so the '
            'stale-token ambiguity _fetchUsersRowForRestore retries for '
            'cannot occur there. The branch must distinguish this case '
            'rather than silently doing nothing on a null result.',
      );
      expect(
        body.contains('restore_users_row_null_via_singlecall'),
        isTrue,
        reason: 'a null `users` row via the C3 path must be independently '
            'observable — the retry-path telemetry never fires on the '
            'primary (C3) restore path, so without this event a future '
            'occurrence there is invisible.',
      );
    });
  });

  // B-pass finding 3 (this diagnose's own review) — the hard-refresh retry
  // had no catch of its own, so a refresh that itself throws (e.g. a
  // revoked/expired refresh token) fell into _restoreUserProfile's generic
  // outer catch (shared "sync_service_if_14" label with any other
  // failure), silently narrower than the resolveDestination precedent this
  // fix claims to mirror (which DOES wrap its equivalent block).
  group('hard-refresh failure isolation (B-pass finding 3)', () {
    test(
        'the hard-refresh retry is wrapped in its own catch with a '
        'distinct telemetry reason', () {
      final body = _fetchUsersRowForRestoreBody(syncSrc);
      final refresh = body.indexOf('refreshSession()');
      expect(refresh, isNot(-1));
      final catchAfterRefresh = body.indexOf('catch (e, st)', refresh);
      expect(
        catchAfterRefresh,
        isNot(-1),
        reason: '_fetchUsersRowForRestore must catch a throw from the '
            'hard refresh itself, not rely solely on '
            '_restoreUserProfile\'s outer catch.',
      );
      expect(
        body.contains('restore_users_row_retry_threw'),
        isTrue,
        reason: 'a refresh failure must be diagnosable separately from '
            '"retried and still empty" — otherwise it is indistinguishable '
            'from any other exception at the outer catch site.',
      );
    });
  });
}
