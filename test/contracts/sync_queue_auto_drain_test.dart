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
      final i = queueSrc.indexOf('Future<void> drain()');
      expect(i, isNot(-1));
      final body = queueSrc.substring(i, i + 500);
      expect(body, contains('if (_draining)'));
      expect(body, contains('_draining = true;'));
      expect(body, contains('_draining = false;'));
    });

    test('SyncQueue.drain() coalesces an overlapping call into a GUARANTEED '
        'rerun rather than silently dropping it (plan-review round 2 Finding '
        '1 — the manual "Retry now" tap shares this same in-flight guard, '
        'and a bare "if (_draining) return;" would make Retry a silent '
        'no-op with zero indication to the user)', () {
      final i = queueSrc.indexOf('Future<void> drain()');
      final body = queueSrc.substring(i, i + 500);
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

    test('ref.onDispose cancels the connectivity subscription and the timer '
        '(not just the pre-existing pending-count subscription)', () {
      final i = providerSrc.indexOf('ref.onDispose(');
      expect(i, isNot(-1));
      final body = providerSrc.substring(i, i + 300);
      expect(body, contains('_connectivitySub?.cancel()'));
      expect(body, contains('_drainTimer?.cancel()'));
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
