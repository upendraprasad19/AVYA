import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

/// Behavioral (not source-grep) coverage for `AuthNotifier.checkEmailRegistered`.
///
/// `email_registration_gate_state_machine_test.dart` pins the invariant
/// ("never reaches AuthStatus.success") via a source-string check, which
/// can't tell the difference between the invariant actually holding at
/// runtime and the literal string `AuthStatus.success` merely being absent
/// from the method body. These fakes override only the network leaf
/// (`rpcEmailIsRegistered` + `ensureSupabaseReady`) so the *real*
/// `checkEmailRegistered` state-machine logic — loading → idle/error,
/// telemetry on failure — actually executes.
class _FakeRpcSuccessNotifier extends AuthNotifier {
  _FakeRpcSuccessNotifier(this._registered);
  final bool _registered;

  @override
  Future<bool> ensureSupabaseReady() async => true;

  @override
  Future<bool> rpcEmailIsRegistered(String trimmedEmail) async =>
      _registered;
}

class _FakeRpcErrorNotifier extends AuthNotifier {
  @override
  Future<bool> ensureSupabaseReady() async => true;

  @override
  Future<bool> rpcEmailIsRegistered(String trimmedEmail) async {
    throw Exception('network unreachable');
  }
}

void main() {
  setUp(() {
    ErrorTelemetry.debugOnLogEventForTests = null;
  });

  tearDown(() {
    ErrorTelemetry.debugOnLogEventForTests = null;
  });

  test('registered email: returns true, status is idle, never success', () async {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(() => _FakeRpcSuccessNotifier(true)),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authNotifierProvider.notifier);
    final result = await notifier.checkEmailRegistered('taken@example.com');

    expect(result, isTrue);
    final state = container.read(authNotifierProvider);
    expect(state.status, AuthStatus.idle);
    expect(state.status, isNot(AuthStatus.success));
  });

  test('unregistered email: returns false, status is idle', () async {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider
            .overrideWith(() => _FakeRpcSuccessNotifier(false)),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authNotifierProvider.notifier);
    final result =
        await notifier.checkEmailRegistered('unclaimed@example.com');

    expect(result, isFalse);
    expect(container.read(authNotifierProvider).status, AuthStatus.idle);
  });

  test('RPC failure: returns null, status is error, telemetry fires', () async {
    final loggedOpTypes = <String>[];
    ErrorTelemetry.debugOnLogEventForTests = (opType, {message}) {
      loggedOpTypes.add(opType);
    };

    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(() => _FakeRpcErrorNotifier()),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authNotifierProvider.notifier);
    final result = await notifier.checkEmailRegistered('broken@example.com');

    expect(result, isNull);
    final state = container.read(authNotifierProvider);
    expect(state.status, AuthStatus.error);
    expect(state.status, isNot(AuthStatus.success));
    expect(loggedOpTypes, contains('auth_email_check_failed'));
  });
}
