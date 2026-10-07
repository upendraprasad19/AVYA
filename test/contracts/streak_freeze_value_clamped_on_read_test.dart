// Bug f8c1a5 regression test (APK Test #16.2) — Layer 1.
//
// Pins the contract that StreakFreezeNotifier.build clamps the
// `streak_freezes_available` value read from userBox['progress']
// against the current-tier cap (1 for free, 3 for PRO).
//
// Pre-fix, the build returned the stored value verbatim, so a
// corrupted Hive map with available=8 rendered "8/3" on the streak
// badge until the next Monday refill ran. The refill itself was
// idempotency-gated by a stale streak_freezes_last_refill, so the
// display stayed broken across launches.
//
// Source-grep contract (strips comments per
// feedback_source_grep_strip_comments_first.md).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'f8c1a5 — StreakFreezeNotifier.build clamps streak_freezes_available against tier cap',
      () {
    final src =
        File('lib/features/home/providers/home_provider.dart')
            .readAsStringSync();

    // Scope to the class body so this assertion is robust against
    // other clamp() usages elsewhere in the file.
    final classIdx = src.indexOf('class StreakFreezeNotifier');
    expect(classIdx, isNonNegative,
        reason:
            'StreakFreezeNotifier class moved or renamed — re-baseline this test.');
    // Bumped 1500 → 2500 because B5 audit / A7 + f8c1a5 closure dropped
    // an extra ~700 chars of explanatory comment block inside the build()
    // body (documenting the provider-vs-singleton migration). The
    // `stored.clamp(0, cap)` line lives at offset ~1700 — beyond the
    // old window. Stripping comments before scoping would be more
    // robust but inverts the assertion semantic (we want to assert the
    // clamp is in the actual class body, not in a comment elsewhere).
    final scoped = src.substring(classIdx, classIdx + 2500);

    // Strip comments inside scoped block.
    final stripped = scoped
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
        .join('\n');

    expect(
      stripped.contains(RegExp(r'\.clamp\s*\(\s*0\s*,')),
      isTrue,
      reason:
          'StreakFreezeNotifier.build must clamp the stored value against [0, cap]. '
          'Without this, a corrupted Hive value (e.g. legacy unclamped 8) renders as '
          '"8/3" on the streak badge.',
    );
    // Tech-debt audit 2026-05-20 / A7 (B5 D9-D10) migrated
    // SubscriptionService from a singleton accessor to a Riverpod
    // provider. StreakFreezeNotifier.build now reads via
    // `ref.read(subscriptionServiceProvider).isPro() ? 3 : 1` instead
    // of `SubscriptionService.instance.isPro() ? 3 : 1`. Accept either
    // form — both express "tier-derived cap, 3 for PRO else 1".
    // Phase 2 (discipline-overhaul, 2026-06-18) — upgraded to
    // ref.watch(subscriptionInfoProvider).isPro so a mid-session PRO
    // grant immediately rebuilds this notifier and flips the cap 1→3
    // without requiring an auth change or app relaunch. Accept all three
    // canonical forms.
    final singletonForm = RegExp(
        r'SubscriptionService\.instance\.isPro\(\)\s*\?\s*3\s*:\s*1');
    final providerReadForm = RegExp(
        r'ref\.read\(\s*subscriptionServiceProvider\s*\)\.isPro\(\)\s*\?\s*3\s*:\s*1');
    final providerWatchForm = RegExp(
        r'ref\.watch\(\s*subscriptionInfoProvider\s*\)\.isPro\s*\?\s*3\s*:\s*1');
    expect(
      singletonForm.hasMatch(stripped) ||
          providerReadForm.hasMatch(stripped) ||
          providerWatchForm.hasMatch(stripped),
      isTrue,
      reason:
          'StreakFreezeNotifier.build must compute the cap from the live tier — '
          '3 for PRO, 1 for free. Accepts: `SubscriptionService.instance` '
          '(legacy singleton), `ref.read(subscriptionServiceProvider)` '
          '(post-A7 canonical provider), or `ref.watch(subscriptionInfoProvider)` '
          '(Phase 2 reactive — cap flips 1→3 on mid-session PRO grant).',
    );
  });
}
