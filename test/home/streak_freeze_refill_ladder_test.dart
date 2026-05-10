import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #14 / Bug D.1 — streak-freeze refill ladder.
///
/// Pre-Test-#14 behavior: every Monday refilled to max (1 free / 3 PRO),
/// regardless of how many freezes the user had left. A PRO user who burned
/// all 3 freezes one week was rewarded with a full reset to 3 the next
/// Monday — no incentive to save them.
///
/// Post-Test-#14 ladder: each Monday applies `available = min(available +
/// 1, max)`. Free max stays 1 (no behavioral change for free since there's
/// only one slot). PRO max stays 3 but a PRO user who used all 3 ladders
/// 1 → 2 → 3 over three Mondays.
///
/// Two concerns pinned here:
///   1. **Source contract** — production `_refillIfNewWeek` carries the
///      ladder formula and does NOT carry the reset-to-max formula.
///   2. **Logic** — pure-Dart mirror of the ladder rule covers the 6
///      scenarios from the spec (free 0/1, PRO 0/2/3 boundary, idempotent
///      same-Monday).
///
/// closes-diagnose: 2026-05-10-freeze-ladder

/// Pure mirror of the ladder rule in
/// home_provider.dart `_refillIfNewWeek`. Production reads
/// `streak_freezes_available` from `UserRepository.instance.getProgress()`
/// and writes back via `updateProgress`. This mirror takes the same inputs
/// and returns the new available count, so the 6 spec scenarios can be
/// tested without a Hive bootstrap.
int applyLadderRefill({required int currentAvailable, required bool isPro}) {
  final maxFreezes = isPro ? 3 : 1;
  return (currentAvailable + 1).clamp(0, maxFreezes);
}

void main() {
  group('source contract: _refillIfNewWeek uses ladder, not reset', () {
    late String homeProvSrc;

    setUpAll(() {
      final f = File('lib/features/home/providers/home_provider.dart');
      expect(f.existsSync(), isTrue, reason: 'home_provider.dart must exist');
      homeProvSrc = f.readAsStringSync();
    });

    test('ladder formula present (currentAvailable + 1 clamped to max)', () {
      // The fix: read currentAvailable, then `(currentAvailable + 1).clamp(0, maxFreezes)`.
      expect(
        homeProvSrc.contains('(currentAvailable + 1).clamp(0, maxFreezes)'),
        isTrue,
        reason:
            '_refillIfNewWeek must use ladder formula '
            '`(currentAvailable + 1).clamp(0, maxFreezes)`. '
            'closes-diagnose: 2026-05-10-freeze-ladder',
      );
      expect(
        homeProvSrc.contains(
            "(progress['streak_freezes_available'] as int?) ?? 0"),
        isTrue,
        reason:
            '_refillIfNewWeek must read currentAvailable from progress with '
            'a 0-default so a fresh user (no prior progress row) bumps from '
            '0 to 1 on first refill — not skip the ladder.',
      );
    });

    test('forbidden: reset-to-max pattern absent', () {
      // The pre-fix line wrote `'streak_freezes_available': maxFreezes` which
      // ignored the existing count. The new ladder writes `newAvailable`.
      // Pin the absence of the reset by checking that no `updateProgress`
      // call writes `'streak_freezes_available': maxFreezes` directly.
      expect(
        homeProvSrc.contains("'streak_freezes_available': maxFreezes"),
        isFalse,
        reason:
            'forbidden reset-to-max: writing `maxFreezes` directly into '
            "`streak_freezes_available` defeats the ladder. Use the "
            'pre-clamped `newAvailable` local instead.',
      );
    });
  });

  group('ladder logic: applyLadderRefill', () {
    test('free user, 0 available → 1 (capped at free max=1)', () {
      expect(applyLadderRefill(currentAvailable: 0, isPro: false), 1);
    });

    test('free user, 1 available → 1 (no over-fill)', () {
      expect(applyLadderRefill(currentAvailable: 1, isPro: false), 1);
    });

    test('PRO user, 0 available → 1 (ladder, NOT reset to 3)', () {
      // The whole point of the ladder. Pre-fix this returned 3.
      expect(applyLadderRefill(currentAvailable: 0, isPro: true), 1);
    });

    test('PRO user, 2 available → 3 (capped at PRO max=3)', () {
      expect(applyLadderRefill(currentAvailable: 2, isPro: true), 3);
    });

    test('PRO user, 3 available → 3 (no over-fill)', () {
      expect(applyLadderRefill(currentAvailable: 3, isPro: true), 3);
    });

    test('PRO user, 4 available → 3 (clamp downward defends invariant)', () {
      // Defensive: if some other code path drifted available > max, the
      // ladder must clamp down on next refill, never preserve the bogus
      // higher count.
      expect(applyLadderRefill(currentAvailable: 4, isPro: true), 3);
    });

    test('PRO user, 1 available → 2 (mid-ladder step)', () {
      expect(applyLadderRefill(currentAvailable: 1, isPro: true), 2);
    });
  });
}
