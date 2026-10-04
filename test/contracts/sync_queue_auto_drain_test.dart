// Regression test for diagnose (this batch): `sync_queue.dart`'s own doc
// comment promised THREE automatic drain triggers (app launch, connectivity
// restore, a 5-min periodic timer) plus the manual "Retry now" tap, but only
// app launch and the manual tap were ever actually wired. An offline write
// could sit queued indefinitely until the user relaunched the app or noticed
// the "N changes waiting to sync" banner and tapped Retry themselves.
//
// `Connectivity().onConnectivityChanged` needs a platform channel a plain
// unit test can't exercise, so — same pattern as
// `sync_queue_progress_marker_test.dart` in this same directory, which pins
// its (also live-Supabase-dependent) executor wiring structurally — this
// file pins the DECISION logic behaviorally (a pure extracted function, real
// production code, not a copy) and the WIRING structurally via source-grep.
//
// Run: flutter test test/contracts/sync_queue_auto_drain_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:icanbefitter/core/services/sync_queue.dart';
import 'package:icanbefitter/shared/providers/sync_state_provider.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ')
    .split('\n')
    .map((l) {
      final m = RegExp(r'(?<!:)//').firstMatch(l);
      return m == null ? l : l.substring(0, m.start);
    })
    .join('\n');

void main() {
  group('shouldDrainOnConnectivityChange (behavioral — pure function)', () {
    test('none alone -> does not drain', () {
      expect(
        shouldDrainOnConnectivityChange(const [ConnectivityResult.none]),
        isFalse,
      );
    });

    test('wifi restored -> drains', () {
      expect(
        shouldDrainOnConnectivityChange(const [ConnectivityResult.wifi]),
        isTrue,
      );
    });

    test('mobile restored -> drains', () {
      expect(
        shouldDrainOnConnectivityChange(const [ConnectivityResult.mobile]),
        isTrue,
      );
    });

    test('empty list (platform reported nothing) -> does not drain', () {
      expect(shouldDrainOnConnectivityChange(const []), isFalse);
    });

    test('mixed none + wifi (multi-adapter device) -> drains', () {
      expect(
        shouldDrainOnConnectivityChange(
          const [ConnectivityResult.none, ConnectivityResult.wifi],
        ),
        isTrue,
      );
    });
  });

  group('auto-drain interval', () {
    test('syncQueueAutoDrainInterval is 5 minutes', () {
      expect(syncQueueAutoDrainInterval, const Duration(minutes: 5));
    });
  });

  group('isSyncAutoDrainDisabled (behavioral — §4.6 kill-switch, B-pass '
      'Finding 3)', () {
    test('true disables', () {
      expect(isSyncAutoDrainDisabled(true), isTrue);
    });
    test('false does not disable', () {
      expect(isSyncAutoDrainDisabled(false), isFalse);
    });
    test('null (configBox key absent — the production default) does not '
        'disable', () {
      expect(isSyncAutoDrainDisabled(null), isFalse);
    });
    test('a non-bool value does not disable (fail toward fix-active, not '
        'toward silently disabling)', () {
      expect(isSyncAutoDrainDisabled('true'), isFalse);
    });
  });

  group('wiring (structural — connectivity_plus needs a platform channel a '
      'unit test cannot exercise, same justification as '
      'sync_queue_progress_marker_test.dart for its live-Supabase executors)',
      () {
    late String providerSrc;
    late String queueSrc;

    setUpAll(() {
      providerSrc = _strip(
        File('lib/shared/providers/sync_state_provider.dart')
            .readAsStringSync(),
      );
      queueSrc = _strip(
        File('lib/core/services/sync_queue.dart').readAsStringSync(),
      );
    });

    test('build() subscribes to Connectivity().onConnectivityChanged', () {
      expect(providerSrc, contains('Connectivity().onConnectivityChanged'));
    });

    test('the connectivity listener gates through shouldDrainOnConnectivityChange '
        'before calling drain()', () {
      final i = providerSrc.indexOf('_connectivitySub =');
      expect(i, isNot(-1));
      final body = providerSrc.substring(i, i + 400);
      final gateAt = body.indexOf('shouldDrainOnConnectivityChange(');
      final drainAt = body.indexOf('SyncQueue.instance.drain()');
      expect(gateAt, isNot(-1));
      expect(drainAt, greaterThan(gateAt),
          reason: 'drain() must be called INSIDE the gated branch, not '
              'unconditionally on every connectivity event');
    });

    test('build() starts a Timer.periodic at syncQueueAutoDrainInterval that '
        'calls drain()', () {
      final i = providerSrc.indexOf('_drainTimer =');
      expect(i, isNot(-1));
      final body = providerSrc.substring(i, i + 200);
      expect(body, contains('Timer.periodic(syncQueueAutoDrainInterval'));
      expect(body, contains('SyncQueue.instance.drain()'));
    });

    test('BOTH the connectivity listener and the periodic timer check '
        '_autoDrainDisabled before draining (§4.6 kill-switch, B-pass '
        'Finding 3)', () {
      final connAt = providerSrc.indexOf('_connectivitySub =');
      final connBody = providerSrc.substring(connAt, connAt + 400);
      expect(connBody, contains('if (_autoDrainDisabled) return;'));

      final timerAt = providerSrc.indexOf('_drainTimer =');
      final timerBody = providerSrc.substring(timerAt, timerAt + 200);
      expect(timerBody, contains('if (_autoDrainDisabled) return;'));
    });

    test('_autoDrainDisabled reads the disable_sync_auto_drain configBox key '
        'through the pure isSyncAutoDrainDisabled predicate, defensively '
        '(same try/catch pattern as sync_service.dart\'s kill-switches)', () {
      final i = providerSrc.indexOf('bool get _autoDrainDisabled');
      expect(i, isNot(-1));
      final body = providerSrc.substring(i, i + 300);
      expect(body, contains("configBox.get('disable_sync_auto_drain')"));
      expect(body, contains('isSyncAutoDrainDisabled('));
      expect(body, contains('catch (_)'));
      expect(body, contains('return false;'),
          reason: 'an unreadable configBox must default to fix-ACTIVE, not '
              'disabled');
    });

    test('SyncQueue.drain() has an in-flight guard (B-pass Finding 4 — two '
        'auto-drain triggers now exist, making overlapping calls routine '
        'rather than requiring a user double-tap)', () {
      // ⚠ Anchor repointed 2026-09-17 (branch sync-banner-force-retry):
      // `Future<void> drain()` no longer occurs once the signature gained
      // `{bool force = false}` — the old anchor returned −1 and failed
      // BOTH tests here before any window was evaluated. Window widened
      // 500 → 800 (the force-sticky body + finally resets push
      // `_draining = false;` to ~736 chars from the anchor — plan-review
      // rounds 1+2). Repoint, never loosen: the contains() assertions
      // below are unchanged.
      final i = queueSrc.indexOf('Future<void> drain(');
      expect(i, isNot(-1));
      final body = queueSrc.substring(i, i + 800);
      expect(body, contains('if (_draining)'));
      expect(body, contains('_draining = true;'));
      expect(body, contains('_draining = false;'));
    });

    test('SyncQueue.drain() coalesces an overlapping call into a GUARANTEED '
        'rerun rather than silently dropping it (plan-review round 2 Finding '
        '1 — the manual "Retry now" tap shares this same in-flight guard, '
        'and a bare "if (_draining) return;" would make Retry a silent '
        'no-op with zero indication to the user)', () {
      // Anchor + window: same 2026-09-17 repoint as the guard test above.
      final i = queueSrc.indexOf('Future<void> drain(');
      final body = queueSrc.substring(i, i + 800);
      expect(body, contains('_rerunRequested = true;'),
          reason: 'an overlapping call must set the rerun flag, not just '
              'return, or the caller\'s request is lost entirely');
      expect(body, contains('do {'));
      expect(body, contains('_rerunRequested = false;'));
      expect(body, contains('} while (_rerunRequested);'),
          reason: 'the already-running call must loop again if a rerun was '
              'requested WHILE it ran, guaranteeing a fresh pass starts '
              'after every drain() call returns');
    });

    test('SyncQueue.drain() merges a mid-pass force request at the TOP of '
        'the loop and resets ALL rerun state in finally (plan-review round '
        '2 Findings 1+3 — a bottom-merge consumed the force one pass late, '
        'and a surviving flag poisoned the next drain with a forced pass)',
        () {
      final i = queueSrc.indexOf('Future<void> drain(');
      final body = queueSrc.substring(i, i + 800);
      expect(body, contains('if (rerunWasForce) passForce = true;'),
          reason: 'the force must be applied at the TOP of the pass, '
              'before the ops loop — a merge at the loop BOTTOM is one '
              'pass late and can be dropped entirely');
      expect(body, contains('final rerunWasForce = _rerunForce;'));
      expect(body, contains('_rerunForce = false;'));
      expect(body, contains('_rerunRequested = false;\n      _rerunForce = false;'),
          reason: 'the finally block must reset BOTH rerun flags alongside '
              '_draining so an exception mid-pass cannot leak a forced '
              'pass into the next drain call');
      expect(body, contains('if (!passForce && !_isDue(op, now)) continue;'),
          reason: 'the due filter must stay gated on the per-pass force — '
              'removing `!passForce && ` makes plain auto passes force '
              '(reddened by the force-retry behavioral test)');
    });

    test('ref.onDispose cancels the connectivity subscription and the timer '
        '(not just the pre-existing pending-count subscription)', () {
      final i = providerSrc.indexOf('ref.onDispose(');
      expect(i, isNot(-1));
      final body = providerSrc.substring(i, i + 300);
      expect(body, contains('_connectivitySub?.cancel()'));
      expect(body, contains('_drainTimer?.cancel()'));
    });
  });

  group('banner grace + force-retry constants (this batch)', () {
    test('syncBannerGraceWindow is 6 minutes (one 5-min drain tick + slack)',
        () {
      expect(syncBannerGraceWindow, const Duration(minutes: 6));
    });

    test('syncBannerDisplayRefreshInterval is 1 minute', () {
      expect(syncBannerDisplayRefreshInterval, const Duration(minutes: 1));
    });
  });

  group('syncBannerDisplayCount (behavioral — the banner display grace '
      'policy, this batch)', () {
    final now = DateTime(2026, 9, 17, 12);

    PendingSyncOp op(String id, Duration age) => PendingSyncOp(
          id: id,
          opType: 't',
          payload: const <String, dynamic>{},
          retryCount: 1,
          firstAttemptAt: now.subtract(age),
        );

    test('empty queue -> 0', () {
      expect(syncBannerDisplayCount(const [], now), 0);
    });

    test('an op aged exactly the grace window IS counted (>= boundary)', () {
      expect(
        syncBannerDisplayCount([op('a', syncBannerGraceWindow)], now),
        1,
      );
    });

    test('an op aged just under the grace window is NOT counted '
        '(this is the mutation target: grace -> Duration.zero reddens '
        'this assertion)', () {
      expect(
        syncBannerDisplayCount(
          [op('a', syncBannerGraceWindow - const Duration(seconds: 1))],
          now,
        ),
        0,
      );
    });

    test('mixed ages -> only the aged ops are counted', () {
      expect(
        syncBannerDisplayCount(
          [
            op('young', const Duration(minutes: 2)),
            op('aged', const Duration(minutes: 7)),
            op('also-young', const Duration(seconds: 30)),
            op('also-aged', const Duration(hours: 26)),
          ],
          now,
        ),
        2,
      );
    });

    test('a FUTURE-dated op (clock edge) is never counted', () {
      expect(
        syncBannerDisplayCount(
          [op('future', const Duration(minutes: -1))],
          now,
        ),
        0,
      );
    });
  });

  group('banner grace + force-retry kill-switch predicates (behavioral, '
      'same §4.6 table as isSyncAutoDrainDisabled)', () {
    test('isSyncBannerGraceDisabled', () {
      expect(isSyncBannerGraceDisabled(true), isTrue);
      expect(isSyncBannerGraceDisabled(false), isFalse);
      expect(isSyncBannerGraceDisabled(null), isFalse,
          reason: 'configBox key absent — the production default must keep '
              'the grace policy ACTIVE');
      expect(isSyncBannerGraceDisabled('true'), isFalse,
          reason: 'a non-bool value fails toward fix-active');
    });

    test('isSyncForceRetryDisabled', () {
      expect(isSyncForceRetryDisabled(true), isTrue);
      expect(isSyncForceRetryDisabled(false), isFalse);
      expect(isSyncForceRetryDisabled(null), isFalse);
      expect(isSyncForceRetryDisabled('true'), isFalse);
    });
  });

  group('banner grace + force-retry wiring (structural, this batch)', () {
    late String providerSrc;

    setUpAll(() {
      providerSrc = _strip(
        File('lib/shared/providers/sync_state_provider.dart')
            .readAsStringSync(),
      );
    });

    test('build() starts the 1-min display-aging timer AFTER the drain '
        'timer, early-exiting on an empty queue (round 2 Finding 9: the '
        '`_drainTimer =` first-occurrence grep must keep landing on the '
        'auto-drain timer)', () {
      final displayAt = providerSrc.indexOf('_displayTimer =');
      expect(displayAt, isNot(-1));
      final drainTimerAt = providerSrc.indexOf('_drainTimer =');
      expect(drainTimerAt, isNot(-1));
      expect(drainTimerAt, lessThan(displayAt));
      final body = providerSrc.substring(displayAt, displayAt + 400);
      expect(body,
          contains('Timer.periodic(syncBannerDisplayRefreshInterval'));
      expect(body, contains('if (raw == 0) return;'));
      expect(body, contains('_stateFor('));
    });

    test('ref.onDispose also cancels the display timer', () {
      final i = providerSrc.indexOf('ref.onDispose(');
      final body = providerSrc.substring(i, i + 400);
      expect(body, contains('_displayTimer?.cancel()'));
    });

    test('ALL state producers funnel through _stateFor (seed, stream '
        'event, display timer — round 1 Finding 4)', () {
      expect(
        providerSrc,
        contains('return _stateFor(SyncQueue.instance.pendingCountSync);'),
      );
      final onCountAt = providerSrc.indexOf('void _onCount(');
      final body = providerSrc.substring(onCountAt, onCountAt + 200);
      expect(body, contains('_stateFor('));
    });

    test('_stateFor applies the grace policy behind its kill-switch', () {
      final i = providerSrc.indexOf('SyncState _stateFor(');
      final body = providerSrc.substring(i, i + 600);
      expect(body, contains('_bannerGraceDisabled'));
      expect(body, contains('syncBannerDisplayCount('));
      expect(body, contains('return const SyncIdle();'));
      expect(body, contains('SyncQueued(rawCount)'),
          reason: 'kill-switch ON must restore the RAW count exactly');
    });

    test('retryNow forces the drain behind the kill-switch, with the '
        'plain drain as its fallback', () {
      final retryAt = providerSrc.indexOf('Future<void> retryNow()');
      expect(retryAt, isNot(-1));
      // retryNow is the file's LAST member — clamp the window to EOF.
      final end =
          retryAt + 500 > providerSrc.length ? providerSrc.length : retryAt + 500;
      final body = providerSrc.substring(retryAt, end);
      expect(body, contains('_forceRetryDisabled'));
      expect(body, contains('drain(force: true)'));
      expect(body, contains('SyncQueue.instance.drain()'),
          reason: 'the kill-switch fallback must be the PLAIN drain');
    });

    test('the AUTO drains (connectivity, periodic timer) stay UNFORCED — '
        'force is per-call, never ambient', () {
      final connAt = providerSrc.indexOf('_connectivitySub =');
      final connBody = providerSrc.substring(connAt, connAt + 400);
      expect(connBody, isNot(contains('force: true')));
      final timerAt = providerSrc.indexOf('_drainTimer =');
      final timerBody = providerSrc.substring(timerAt, timerAt + 200);
      expect(timerBody, isNot(contains('force: true')));
    });

    test('the splash-screen app-launch drain stays plain too', () {
      final splashSrc = _strip(
        File('lib/features/auth/screens/splash_screen.dart')
            .readAsStringSync(),
      );
      expect(splashSrc, contains('SyncQueue.instance.drain()'));
      expect(splashSrc, isNot(contains('force: true')));
    });

    test('the two new kill-switch getters read their configBox keys '
        'defensively (unreadable configBox defaults to fix-ACTIVE, same '
        'pattern as _autoDrainDisabled)', () {
      expect(
        providerSrc,
        contains("configBox.get('disable_sync_banner_grace')"),
      );
      expect(
        providerSrc,
        contains("configBox.get('disable_sync_force_retry')"),
      );
      for (final marker in ['_bannerGraceDisabled', '_forceRetryDisabled']) {
        final i = providerSrc.indexOf('bool get $marker');
        expect(i, isNot(-1), reason: marker);
        final body = providerSrc.substring(i, i + 300);
        expect(body, contains('catch (_)'), reason: marker);
        expect(body, contains('return false;'),
            reason: '$marker must default to fix-ACTIVE when unreadable');
      }
    });
  });

  group('the pubspec dependency this fix required', () {
    test('connectivity_plus is a real pubspec.yaml dependency, not just an '
        'import that happens to resolve transitively', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        RegExp(r'^\s*connectivity_plus:', multiLine: true).hasMatch(pubspec),
        isTrue,
        reason: 'pre-fix this package was absent entirely — grep pubspec.yaml, '
            'not just lib/, since a stray import with no declared dependency '
            'would still analyze/compile against the resolved package graph '
            'today but is one `flutter pub upgrade` away from breaking',
      );
    });
  });
}
