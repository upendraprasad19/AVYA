// test/contracts/background_restore_test.dart
//
// Obs 4 (2026-06-05) — cold-start latency. Two fixes:
//   * backend-warm: warm the PostgREST/edge connection during splash so the
//     restore's first query doesn't eat the ~24s cold-start penalty (un-flagged,
//     low-risk).
//   * background-restore: a returning user reaches /home immediately while the
//     cloud restore finishes in the background; the ownership gate stays BLOCKING
//     (cross-account safety, APK #15.4); the in-flight restore is NOT cancelled
//     (single restore, no double-write race); post-restore heals run ref-free,
//     then bump a tick the home screen bridges to invalidateOnRetry.
//
// Slow-boot guard (4e8b1d): the flag flipped from opt-IN (`bg_restore_enabled`,
// default OFF — returning users blocked >1 min on the full restore every cold
// start) to opt-OUT (`disable_bg_restore` kill-switch). Returning users now
// DEFAULT to the bg path; fresh installs still block; the kill-switch preserves
// the old blocking path (§4.6). Because the restore now runs concurrently with
// logging, the loss-sensitive restore writers are additive / local-wins
// (skip-if-local-exists) so a background restore never overwrites a just-logged
// local row (c5a1f2); reconcileExlogIndexes heals any index drift post-restore.
//
// Source-grep with comment-stripping (the established pattern for the
// restoring-screen surface — see auth_invalidation_*). Behavioral coverage is
// the device walk on the flag rollout + the local-wins/additive restore test
// (restore_local_wins_additive_test.dart).

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  late String restoring, splash, sync, home, supa;
  setUpAll(() {
    restoring = _strip(
        File('lib/features/auth/screens/restoring_screen.dart')
            .readAsStringSync());
    splash = _strip(File('lib/features/auth/screens/splash_screen.dart')
        .readAsStringSync());
    sync = _strip(
        File('lib/core/services/sync_service.dart').readAsStringSync());
    home = _strip(File('lib/features/home/screens/home_screen.dart')
        .readAsStringSync());
    supa = _strip(File('lib/core/services/supabase_service.dart')
        .readAsStringSync());
  });

  // The _goHome method body (between its signature and _ensureOwnershipBeforeHome).
  String goHomeBody() {
    final a = restoring.indexOf('Future<void> _goHome(');
    final b = restoring.indexOf('Future<void> _ensureOwnershipBeforeHome');
    expect(a, greaterThan(-1));
    expect(b, greaterThan(a));
    return restoring.substring(a, b);
  }

  group('Obs 4 — backend warm-up (un-flagged, low-risk)', () {
    test('SupabaseService exposes warmConnection', () {
      expect(supa.contains('Future<void> warmConnection()'), isTrue);
    });
    test('splash fires warmConnection fire-and-forget after init', () {
      expect(
        splash.contains(
            'unawaited(SupabaseService.instance.warmConnection())'),
        isTrue,
        reason: 'warm-up must be fire-and-forget — never blocks navigation',
      );
    });
  });

  group('Obs 4 — restore completion tick (home refresh bridge)', () {
    test('SyncService exposes restoreCompletedTick + bumpRestoreCompleted', () {
      expect(sync.contains('restoreCompletedTick'), isTrue);
      expect(sync.contains('void bumpRestoreCompleted()'), isTrue);
    });
    test('home listens to the tick (added + removed) + invalidateOnRetry', () {
      expect(home.contains('restoreCompletedTick.addListener'), isTrue);
      expect(home.contains('restoreCompletedTick.removeListener'), isTrue,
          reason: 'listener must be removed in dispose (no leak)');
      expect(home.contains('invalidateOnRetry(ref)'), isTrue);
    });
  });

  group('Obs 4 — bg-restore flag-gated + ownership stays blocking', () {
    test('bg path is opt-OUT via disable_bg_restore (default ON for returning '
        'users) — slow-boot guard 4e8b1d', () {
      expect(restoring.contains("configBox.get('disable_bg_restore')"), isTrue,
          reason: 'returning users default to the bg path; the kill-switch '
              'opts out (the old opt-in bg_restore_enabled is gone)');
      expect(restoring.contains("configBox.get('bg_restore_enabled')"), isFalse,
          reason: 'opt-in flag must be fully replaced by the opt-out kill-switch');
      expect(
          RegExp(r'if\s*\(\s*!killSwitch\s*&&\s*isReturning\s*\)')
              .hasMatch(goHomeBody()),
          isTrue,
          reason: 'returning users take the bg path unless kill-switch set');
    });

    test('fresh install (not returning) still blocks on the full restore', () {
      final body = goHomeBody();
      expect(body.contains("localProfile['primary_goal']"), isTrue,
          reason: 'isReturning = local profile present; a fresh install '
              '(primary_goal null) is NOT returning → falls through to the '
              'blocking default path');
    });

    test('ownership (openForUser) completes BEFORE navigation in the bg path',
        () {
      final body = goHomeBody();
      final ownIdx = body.indexOf('await HiveUserSession.openForUser(userId)');
      final goIdx = body.indexOf("context.go('/home')");
      expect(ownIdx, greaterThan(-1), reason: 'bg path must await openForUser');
      expect(goIdx, greaterThan(ownIdx),
          reason: 'ownership gate MUST complete before navigation '
              '(cross-account safety, APK #15.4)');
    });

    test('the in-flight restore is NOT cancelled in the bg path', () {
      expect(goHomeBody().contains('cancelInflightRestore'), isFalse,
          reason: 'cancel + re-run would race the unwinding restore against '
              'the heals — keep the single in-flight restore');
    });

    test('default path preserves order: await restore → ownership → go', () {
      final body = goHomeBody();
      final r = body.lastIndexOf('await restoreFuture');
      final e = body.lastIndexOf('_ensureOwnershipBeforeHome(userId)');
      final g = body.lastIndexOf("context.go('/home')");
      expect(r > -1 && r < e && e < g, isTrue,
          reason: 'default/fresh-install path keeps the proven order');
    });

    test('bg heals run post-restore, ref-free, then bump the tick', () {
      final idx =
          restoring.indexOf('Future<void> _healAfterRestoreInBackground()');
      expect(idx, greaterThan(-1));
      final body = restoring.substring(idx);
      expect(body.contains('ExlogKeyMigrator.runIfNeeded()'), isTrue);
      expect(body.contains('PhaseProgressReconciler.reconcile('), isTrue);
      expect(body.contains('SyncService.instance.bumpRestoreCompleted()'),
          isTrue);
    });

    test('bg heal reconciles the exlog index (defense-in-depth c5a1f2)', () {
      final idx =
          restoring.indexOf('Future<void> _healAfterRestoreInBackground()');
      final body = restoring.substring(idx);
      expect(body.contains('reconcileExlogIndexes()'), isTrue,
          reason: 'post-restore heal must rebuild the exlog index as the union '
              'of present keys so any race/rogue drift self-heals');
    });
  });
}
