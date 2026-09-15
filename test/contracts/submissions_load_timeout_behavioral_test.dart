// Behavioral contract for diagnose 2a9f3c — Profile > My Submissions (and its
// sibling Community Review tab) hung on an infinite spinner forever.
//
// THE BUG (founder, internal-testing batch, 2026-09-15, Obs 2): tapping
// My Submissions showed a spinner that never resolved. Root cause:
// `_MySubmissionsBodyState._load` (and `_CommunityReviewBodyState._load`)
// awaited SubmissionsRepository calls with NO timeout — `grep -c '\.timeout('
// lib/features/profile/screens/submissions_screen.dart` returned 0 pre-fix.
// A stalled network call left `_rows`/`_loading` stuck, and since `_error` is
// only ever set inside the `catch` block, a hang never reaches it — no Retry
// button ever appears, unlike every other loading state in the app (CLAUDE.md
// §4.4 rule 13: loading / error+retry / empty are mandatory for every screen).
//
// THE FIX: `applySubmissionsLoadTimeout` wraps every repo call at both call
// sites with a 15s ceiling, so a stalled request throws `TimeoutException`
// and falls into the existing catch block, surfacing the existing
// ErrorState(onRetry: _load) UI instead of hanging.
//
// MUTATION-PROVEN: change `applySubmissionsLoadTimeout` to `=> future` (drop
// the ceiling) and the first test fails — the future never completes, exactly
// the founder's hang.
//
// Run: flutter test test/contracts/submissions_load_timeout_behavioral_test.dart

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/screens/submissions_screen.dart';

void main() {
  group('applySubmissionsLoadTimeout — the stalled-load ceiling', () {
    test('THE BUG: a never-completing repo call aborts instead of hanging '
        'forever', () {
      fakeAsync((async) {
        final stalled = Completer<List<Map<String, dynamic>>>();
        Object? thrown;

        applySubmissionsLoadTimeout(stalled.future).catchError((Object e) {
          thrown = e;
          return <Map<String, dynamic>>[];
        });

        // Just before the ceiling: still waiting — a genuinely slow (but
        // healthy) request must not be aborted early.
        async.elapse(submissionsLoadTimeout - const Duration(seconds: 1));
        expect(thrown, isNull,
            reason: 'must not fire before '
                '${submissionsLoadTimeout.inSeconds}s.');

        // Past the ceiling: aborted with a TimeoutException, which the
        // caller's existing catch block turns into a retriable error state.
        async.elapse(const Duration(seconds: 2));
        expect(
          thrown,
          isA<TimeoutException>(),
          reason: 'THE FOUNDER BUG — without this the submissions spinner '
              'never resolves on a stalled request.',
        );
      });
    });

    test('a call that finishes inside the ceiling passes through untouched',
        () {
      fakeAsync((async) {
        var result = <Map<String, dynamic>>[];
        var completed = false;

        applySubmissionsLoadTimeout(
          Future.delayed(
            const Duration(seconds: 5),
            () => <Map<String, dynamic>>[
              {'id': '1'}
            ],
          ),
        ).then((r) {
          result = r;
          completed = true;
        });

        async.elapse(const Duration(seconds: 6));
        expect(completed, isTrue);
        expect(result, [
          {'id': '1'}
        ]);
      });
    });

    test('a real failure still propagates — the ceiling swallows nothing',
        () {
      fakeAsync((async) {
        Object? thrown;

        applySubmissionsLoadTimeout(
          Future<List<Map<String, dynamic>>>.error(
              StateError('4xx from PostgREST')),
        ).catchError((Object e) {
          thrown = e;
          return <Map<String, dynamic>>[];
        });

        async.flushMicrotasks();
        expect(thrown, isA<StateError>());
      });
    });

    test('the ceiling is 15s — a value change must be a deliberate edit', () {
      expect(submissionsLoadTimeout, const Duration(seconds: 15));
    });
  });
}
