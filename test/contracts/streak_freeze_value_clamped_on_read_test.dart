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
    final scoped = src.substring(classIdx, classIdx + 1500);

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
    expect(
      stripped.contains(RegExp(
          r'SubscriptionService\.instance\.isPro\(\)\s*\?\s*3\s*:\s*1')),
      isTrue,
      reason:
          'StreakFreezeNotifier.build must compute the cap from the live tier — '
          '3 for PRO, 1 for free.',
    );
  });
}
