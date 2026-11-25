import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/utils/step_timings.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// OI-348 Landing 3a, B6 (walk A1): after a confirm link is VERIFIED the
/// notifier says so (`loading` + `emailVerified`) while the account loads, and
/// a failure after that point never calls the spent link "invalid".
///
/// Drives the REAL `AuthNotifier.confirmEmail` (OI-205 guard, the real
/// `boundSignIn` ceiling, the real error mapping). Two seams only:
/// `verifyConfirmToken` (the link check) and `ensureLocalUserAfterConfirm`
/// (the account load, held on a Completer). `ensureSupabaseReady` is
/// overridden to true; `SupabaseService.isAuthenticated` reads false while
/// uninitialized, so the OI-205 guard passes as it does for a fresh device.
///
/// Limitation (round 2, R2-5): a stage emit moved BEFORE the null-user check
/// is not caught by (d), because the error emit resets the flag; harmless.

User _user() => User(
      id: '0b7f3c2e-1111-4222-8333-944455556666',
      appMetadata: const <String, dynamic>{},
      userMetadata: const <String, dynamic>{},
      aud: 'authenticated',
      createdAt: '2026-11-25T00:00:00Z',
      email: 'confirm@test.invalid',
    );

class _Notifier extends AuthNotifier {
  _Notifier({this.userIsNull = false, this.loadError});

  final bool userIsNull;
  final Object? loadError;
  final Completer<void> load = Completer<void>();
  bool loadStarted = false;
  AuthState2? stateWhenLoadStarted;

  @override
  Future<bool> ensureSupabaseReady() async => true;

  @override
  Future<AuthResponse> verifyConfirmToken(String tokenHash) async =>
      AuthResponse(user: userIsNull ? null : _user());

  @override
  Future<void> ensureLocalUserAfterConfirm(
      User user, StepTimings timings) async {
    loadStarted = true;
    stateWhenLoadStarted = state;
    if (loadError != null) throw loadError!;
    await load.future;
  }
}

void main() {
  final logged = <String>[];
  final nonFatals = <String>[];
  final notifiers = <_Notifier>[];

  setUp(() {
    logged.clear();
    nonFatals.clear();
    ErrorTelemetry.debugOnLogEventForTests = (op, {message}) => logged.add(op);
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required reason, extra}) => nonFatals.add(reason);
    AuthNotifier.confirmVerifiedStageDisabledForTest = null;
  });

  tearDown(() {
    for (final n in notifiers) {
      if (!n.load.isCompleted) n.load.complete();
    }
    notifiers.clear();
    ErrorTelemetry.debugOnLogEventForTests = null;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    AuthNotifier.confirmVerifiedStageDisabledForTest = null;
  });

  (ProviderContainer, _Notifier) make(_Notifier fake) {
    notifiers.add(fake);
    final c = ProviderContainer(
      overrides: [authNotifierProvider.overrideWith(() => fake)],
    );
    addTearDown(c.dispose);
    return (c, c.read(authNotifierProvider.notifier) as _Notifier);
  }

  test('(a)(b) verified link: loading + emailVerified while the account '
      'loads, then success with the flag cleared', () async {
    final (c, n) = make(_Notifier());
    final run = n.confirmEmail('hash-a');
    await pumpEventQueue();

    expect(n.loadStarted, isTrue);
    final mid = c.read(authNotifierProvider);
    expect(mid.status, AuthStatus.loading);
    expect(mid.emailVerified, isTrue,
        reason: 'the stage must be set BEFORE the account load starts');
    expect(n.stateWhenLoadStarted?.emailVerified, isTrue);

    n.load.complete();
    await run;
    final end = c.read(authNotifierProvider);
    expect(end.status, AuthStatus.success);
    expect(end.emailVerified, isFalse,
        reason: 'not sticky: success clears it');
  });

  test('(c) kill switch ON: no intermediate stage (pre-fix sequence)',
      () async {
    AuthNotifier.confirmVerifiedStageDisabledForTest = true;
    final (c, n) = make(_Notifier());
    final run = n.confirmEmail('hash-c');
    await pumpEventQueue();

    final mid = c.read(authNotifierProvider);
    expect(mid.status, AuthStatus.loading);
    expect(mid.emailVerified, isFalse);

    n.load.complete();
    await run;
    expect(c.read(authNotifierProvider).status, AuthStatus.success);
  });

  test('(d) null user: "invalid or has expired", never the verified stage',
      () async {
    final (c, n) = make(_Notifier(userIsNull: true));
    await n.confirmEmail('hash-d');
    final s = c.read(authNotifierProvider);
    expect(s.status, AuthStatus.error);
    expect(s.errorMessage, 'This confirmation link is invalid or has expired.');
    expect(s.emailVerified, isFalse);
    expect(n.loadStarted, isFalse);
  });

  test('(e) the REAL 40 s ceiling fires while verified -> '
      'confirmedButSlowMessage, not the old timeout text', () {
    fakeAsync((async) {
      final (c, n) = make(_Notifier());
      n.confirmEmail('hash-e');
      async.flushMicrotasks();
      expect(c.read(authNotifierProvider).emailVerified, isTrue);

      async.elapse(AuthNotifier.signInTimeout + const Duration(seconds: 1));
      async.flushMicrotasks();

      final s = c.read(authNotifierProvider);
      expect(s.status, AuthStatus.error);
      expect(s.errorMessage, AuthNotifier.confirmedButSlowMessage);
      expect(s.errorMessage, isNot(contains('invalid or has expired')));
      expect(logged, contains('auth_confirm_email_timeout'));
      expect(nonFatals, contains('auth_confirm_email_timeout'));
    });
  });

  test('(f) kill switch ON + ceiling: the old timeout text, unchanged', () {
    AuthNotifier.confirmVerifiedStageDisabledForTest = true;
    fakeAsync((async) {
      final (c, n) = make(_Notifier());
      n.confirmEmail('hash-f');
      async.flushMicrotasks();
      async.elapse(AuthNotifier.signInTimeout + const Duration(seconds: 1));
      async.flushMicrotasks();

      final s = c.read(authNotifierProvider);
      expect(s.status, AuthStatus.error);
      expect(s.errorMessage,
          'Confirmation is taking longer than usual. Check your connection and try again.');
    });
  });

  test('(g1) verified, then a generic load error -> confirmedButSlowMessage',
      () async {
    final (c, n) = make(_Notifier(loadError: Exception('boom')));
    await n.confirmEmail('hash-g1');
    final s = c.read(authNotifierProvider);
    expect(s.status, AuthStatus.error);
    expect(s.errorMessage, AuthNotifier.confirmedButSlowMessage);
  });

  test('(g2) verified, then the cross-account StateError -> its own message',
      () async {
    final (c, n) = make(_Notifier(
        loadError: StateError('Cross-account clear partial-failed')));
    await n.confirmEmail('hash-g2');
    final s = c.read(authNotifierProvider);
    expect(s.status, AuthStatus.error);
    expect(s.errorMessage,
        'Couldn’t clean up the previous session. Please sign in again.');
  });

  test('(h) a second confirmEmail starts without the verified flag', () async {
    final (c, n) = make(_Notifier());
    final run = n.confirmEmail('hash-h');
    await pumpEventQueue();
    expect(c.read(authNotifierProvider).emailVerified, isTrue);
    n.load.complete();
    await run;

    // The next call's FIRST emit (before verify) must read not-verified.
    final states = <AuthState2>[];
    c.listen<AuthState2>(authNotifierProvider, (_, s) => states.add(s),
        fireImmediately: false);
    // Re-run on the same notifier instance: its load is already complete.
    await n.confirmEmail('hash-h2');
    expect(states.first.status, AuthStatus.loading);
    expect(states.first.emailVerified, isFalse);
  });
}
