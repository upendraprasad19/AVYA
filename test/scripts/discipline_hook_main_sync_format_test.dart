// test/scripts/discipline_hook_main_sync_format_test.dart
//
// Pure unit tests for `formatMainSyncWarning` in scripts/discipline_hook.dart.
//
// Regression coverage for the SessionStart main-vs-origin/main sync warning
// added 2026-09-24, closing the gap that let a VPS clone's local `main` drift
// 300 commits behind `origin/main` with no warning until someone happened to
// run `git status`. This tests only the pure message-formatting core (no
// subprocess, no real git) -- see discipline_hook_main_sync_e2e_test.dart for
// the real-process/real-git coverage of the I/O wrapper `_mainSyncWarning()`.
//
// MUTATION: deleting the `ahead == 0 && behind == 0` early return reddens the
// "in sync" test below. Deleting the `wasFetched` short-circuit (so staleness
// text always prints) reddens the "behind, wasFetched: true" test. Flipping
// `fetchAge > const Duration(hours: 6)` to `>=` moves the boundary test's
// pass condition to the other wording -- see the boundary test's own comment.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/discipline_hook.dart';

void main() {
  group('formatMainSyncWarning', () {
    test('ahead:0, behind:0 -> empty regardless of fetch state', () {
      expect(
        formatMainSyncWarning(
            ahead: 0, behind: 0, wasFetched: true, fetchAge: null),
        '',
      );
      expect(
        formatMainSyncWarning(
            ahead: 0,
            behind: 0,
            wasFetched: false,
            fetchAge: const Duration(hours: 10)),
        '',
      );
    });

    test('behind-only, wasFetched:true -> MAIN BEHIND, no staleness caveat',
        () {
      final msg = formatMainSyncWarning(
        ahead: 0,
        behind: 3,
        wasFetched: true,
        fetchAge: null,
      );
      expect(msg, contains('MAIN BEHIND'));
      expect(msg, contains('3 commit(s) behind'));
      expect(msg, contains('git pull origin main'));
      expect(msg, isNot(contains('offline/fetch failed')));
      expect(msg, isNot(contains('stale')));
    });

    test('ahead-only, wasFetched:false, fetchAge:null -> MAIN AHEAD, '
        'no-prior-sync caveat', () {
      final msg = formatMainSyncWarning(
        ahead: 2,
        behind: 0,
        wasFetched: false,
        fetchAge: null,
      );
      expect(msg, contains('MAIN AHEAD'));
      expect(msg, contains('2 commit(s) ahead'));
      expect(msg, contains('git push origin main'));
      expect(msg, contains('no prior sync on record'));
    });

    test('diverged, wasFetched:false, fetchAge:8h -> MAIN DIVERGED, '
        'stale caveat', () {
      final msg = formatMainSyncWarning(
        ahead: 1,
        behind: 4,
        wasFetched: false,
        fetchAge: const Duration(hours: 8),
      );
      expect(msg, contains('MAIN DIVERGED'));
      expect(msg, contains('1 ahead'));
      expect(msg, contains('4 behind'));
      expect(msg, contains('git fetch origin main && git log'));
      expect(msg, contains('this may itself be stale'));
    });

    // Boundary: exactly 6h does NOT trigger the "may itself be stale" wording
    // (the implementation uses a strict `>`), 6h+1m does.
    test('staleness boundary at exactly 6h vs just over 6h', () {
      final atBoundary = formatMainSyncWarning(
        ahead: 0,
        behind: 1,
        wasFetched: false,
        fetchAge: const Duration(hours: 6),
      );
      expect(atBoundary, contains('last known sync was 6h ago'));
      expect(atBoundary, isNot(contains('may itself be stale')));

      final justOver = formatMainSyncWarning(
        ahead: 0,
        behind: 1,
        wasFetched: false,
        fetchAge: const Duration(hours: 6, minutes: 1),
      );
      expect(justOver, contains('may itself be stale'));
    });
  });
}
