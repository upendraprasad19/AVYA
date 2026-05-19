// Bug f8c1a5 regression test (APK Test #16.2) — Layer 3.
//
// Pins the contract that the cloud-restore path
// SyncRestoreCompleteness._restoreFreezes clamps the incoming
// streak_freezes_available value at the absolute tier max (3) before
// writing into Hive. Pre-fix the cloud value was written verbatim, so
// any legacy unclamped row in user_progress would round-trip into
// Hive on every reinstall.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'f8c1a5 — _restoreFreezes clamps cloud streak_freezes_available at 3',
      () {
    final src = File(
            'lib/core/services/sync/sync_restore_completeness.dart')
        .readAsStringSync();

    final methodIdx = src.indexOf('_restoreFreezes(');
    expect(methodIdx, isNonNegative,
        reason: '_restoreFreezes method moved or renamed — re-baseline.');
    // Window widened from 2200 → 4000 chars in batch 2026-05-19 / diagnose
    // 9c4a17 — the max-merge fix's explanatory comment block grew the
    // method body past the old window. Contract preserved: clamp(0, 3)
    // still writes streak_freezes_available; just lives in the cloudWins
    // branch instead of unconditionally.
    final scoped = src.substring(
        methodIdx, (methodIdx + 4000).clamp(0, src.length));

    // Strip comments.
    final stripped = scoped
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
        .join('\n');

    expect(
      stripped.contains(
          RegExp(r"streak_freezes_available'\]\s*=\s*\w+\.clamp\(0,\s*3\)")),
      isTrue,
      reason:
          '_restoreFreezes must write streak_freezes_available via .clamp(0, 3) '
          'so a legacy unclamped cloud value cannot round-trip into Hive on restore.',
    );
  });
}
