// test/contracts/sync_paused_state_test.dart
//
// Contract — closes-diagnose e5b2a9 (Unit D). While the backend is paused the
// banner says so; the existing queue-based states are unchanged.

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/providers/sync_state_provider.dart';
import 'package:icanbefitter/shared/widgets/sync_banner.dart';

class _Fixed extends SyncStateNotifier {
  _Fixed(this._s);
  final SyncState _s;
  @override
  SyncState build() => _s; // no connectivity/timer side effects in a unit test
}

void main() {
  group('SyncBanner', () {
    Future<void> pump(WidgetTester t, SyncState s) async {
      await t.pumpWidget(ProviderScope(
        overrides: [syncStateProvider.overrideWith(() => _Fixed(s))],
        child: const MaterialApp(home: Scaffold(body: SyncBanner())),
      ));
    }

    testWidgets('SyncPaused renders the reassuring copy', (t) async {
      await pump(t, const SyncPaused());
      expect(find.textContaining('Sync paused'), findsOneWidget);
      expect(find.textContaining('data is safe'), findsOneWidget);
      expect(find.textContaining('Retrying'), findsNothing,
          reason: 'the copy must fit one line on a 360dp phone — the Retry action carries the meaning');
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('SyncIdle renders nothing', (t) async {
      await pump(t, const SyncIdle());
      expect(find.textContaining('Sync paused'), findsNothing);
      expect(find.textContaining('waiting to sync'), findsNothing);
    });

    testWidgets('MIRROR: SyncQueued still renders its own copy, not the paused one', (t) async {
      await pump(t, const SyncQueued(2));
      expect(find.text('2 changes waiting to sync'), findsOneWidget);
      expect(find.textContaining('Sync paused'), findsNothing);
    });
  });

  group('shouldKickRetryOnConnectivity (the && is testable)', () {
    test('paused + connectivity returned → kick', () {
      expect(shouldKickRetryOnConnectivity([ConnectivityResult.wifi], paused: true), isTrue);
    });
    test('MIRROR: connectivity returned but NOTHING paused → no kick', () {
      expect(shouldKickRetryOnConnectivity([ConnectivityResult.wifi], paused: false), isFalse);
    });
    test('MIRROR: paused but connectivity is still none → no kick', () {
      expect(shouldKickRetryOnConnectivity([ConnectivityResult.none], paused: true), isFalse);
    });
  });

  group('wiring (presence — slice-scoped, comment-stripped)', () {
    String strip(String s) => s
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
    final src = strip(
        File('lib/shared/providers/sync_state_provider.dart').readAsStringSync());

    test('_stateFor checks the paused flag FIRST and returns SyncPaused', () {
      final i = src.indexOf('SyncState _stateFor(');
      expect(i, greaterThan(-1));
      final body = src.substring(i, i + 600);
      final paused = body.indexOf('SyncRetryController.instance.paused.value');
      final empty = body.indexOf('if (rawCount == 0)');
      expect(paused, greaterThan(-1), reason: 'inside _stateFor, not elsewhere in the file');
      expect(body.contains('SyncPaused()'), isTrue);
      expect(paused, lessThan(empty), reason: 'paused must outrank the queue states');
    });

    test('build() listens to the paused notifier and removes the listener in the EXISTING onDispose', () {
      expect(src.contains('paused.addListener('), isTrue);
      final d = src.indexOf('ref.onDispose(');
      // The FIRST `});` after `ref.onDispose(` closes that block (its body is
      // plain `?.cancel();` statements) — so a removal moved outside it is caught.
      final tail = src.substring(d, src.indexOf('});', d));
      expect(tail.contains('paused.removeListener('), isTrue,
          reason: 'the removal must live in the first onDispose block');
    });

    test('a connectivity restore kicks the retry controller only while paused', () {
      final c = src.indexOf('_connectivitySub =');
      final body = src.substring(c, c + 700);
      expect(body.contains('shouldKickRetryOnConnectivity('), isTrue);
      expect(body.contains('SyncRetryController.instance.paused.value'), isTrue);
      expect(body.contains('SyncRetryController.instance.retryNow()'), isTrue);
    });

    test('a paused-flag change recomputes the state through _stateFor', () {
      final i = src.indexOf('void _onPausedChanged()');
      expect(i, greaterThan(-1));
      expect(src.substring(i, (i + 160).clamp(0, src.length)).contains('_stateFor('), isTrue);
    });

    test('retryPausedSync honours the controller cooldown and drains the queue only when it holds work', () {
      final i = src.indexOf('Future<void> retryPausedSync()');
      expect(i, greaterThan(-1));
      final body = src.substring(i, (i + 420).clamp(0, src.length));
      expect(body.contains('manualRetryAllowed'), isTrue);
      expect(body.contains('pendingCountSync > 0'), isTrue);
    });

    test('the banner tap kicks the controller through the notifier', () {
      expect(src.contains('Future<void> retryPausedSync()'), isTrue);
      final b = strip(File('lib/shared/widgets/sync_banner.dart').readAsStringSync());
      expect(b.contains('retryPausedSync()'), isTrue);
    });
  });
}
