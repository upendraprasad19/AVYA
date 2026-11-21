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
      'f8c1a5 — restore clamps streak_freezes_available at 3 (via mergeFreezeProgress)',
      () {
    // Refactor 2026-06-11 / diagnose a8f3d1 — the clamp moved out of
    // _restoreFreezes's inline body into the pure
    // StreakProgressService.mergeFreezeProgress, which _restoreFreezes now
    // delegates to. Contract preserved: a legacy unclamped cloud value cannot
    // round-trip into Hive on restore.
    final svc = File('lib/core/services/streak_progress_service.dart')
        .readAsStringSync();
    final mIdx = svc.indexOf('mergeFreezeProgress(');
    expect(mIdx, isNonNegative,
        reason: 'mergeFreezeProgress moved or renamed — re-baseline.');
    final scoped = svc.substring(mIdx, (mIdx + 2000).clamp(0, svc.length));

    // Strip comments.
    final stripped = scoped
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
        .join('\n');

    expect(
      stripped.contains(RegExp(r'clamp\(0,\s*3\)')),
      isTrue,
      reason:
          'mergeFreezeProgress must clamp available via clamp(0, 3) so a legacy '
          'unclamped cloud value cannot round-trip into Hive on restore.',
    );

    // And _restoreFreezes must actually delegate to the clamping helper.
    final restore =
        File('lib/core/services/sync/sync_restore_completeness.dart')
            .readAsStringSync();
    expect(
      restore.contains('StreakProgressService.mergeFreezeProgress('),
      isTrue,
      reason: '_restoreFreezes must delegate to the clamping helper.',
    );
  });
}
