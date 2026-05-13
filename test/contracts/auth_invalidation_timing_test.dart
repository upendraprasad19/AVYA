// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  // Reset the static listenable between tests so cross-test leakage can't
  // give a false pass.
  setUp(() {
    HiveUserSession.currentOwnerListenable.value = null;
  });

  tearDown(() {
    HiveUserSession.currentOwnerListenable.value = null;
  });

  test('token returns <anon> when authUid and hiveOwner disagree', () {
    // Simulate: Supabase has flipped to sumitId but openForUser hasn't
    // caught up yet — Hive still owned by upendraId.
    HiveUserSession.currentOwnerListenable.value = 'upendra-id-aaaa-bbbb';

    final container = ProviderContainer(overrides: [
      // Pretend Supabase says sumit.
      currentUserProvider.overrideWith((ref) =>
          _FakeUser('sumit-id-cccc-dddd')),
      // authStateProvider is a StreamProvider — override with a finished
      // stream so it doesn't error out under test.
      authStateProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(container.dispose);

    final token = container.read(authUserIdTokenProvider);
    expect(token, '<anon>',
        reason: 'Disagreement must produce <anon>, not the auth uid.');
  });

  test('token returns authUid when authUid and hiveOwner agree', () {
    HiveUserSession.currentOwnerListenable.value = 'sumit-id-cccc-dddd';

    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) =>
          _FakeUser('sumit-id-cccc-dddd')),
      authStateProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(container.dispose);

    final token = container.read(authUserIdTokenProvider);
    expect(token, 'sumit-id-cccc-dddd');
  });

  test('token flips from <anon> to authUid when openForUser completes',
      () async {
    HiveUserSession.currentOwnerListenable.value = 'upendra-id-aaaa-bbbb';

    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) =>
          _FakeUser('sumit-id-cccc-dddd')),
      authStateProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(container.dispose);

    expect(container.read(authUserIdTokenProvider), '<anon>');

    // Simulate openForUser completing — listenable flips.
    HiveUserSession.currentOwnerListenable.value = 'sumit-id-cccc-dddd';
    // Pump microtasks so the listener can fire and providers re-emit.
    await Future<void>.delayed(Duration.zero);

    expect(container.read(authUserIdTokenProvider), 'sumit-id-cccc-dddd');
  });
}

/// Minimal fake matching only the `.id` accessor used by
/// `authUserIdTokenProvider`. Implements the supabase_flutter `User`
/// surface via `noSuchMethod` so Riverpod's type system accepts the
/// override without dragging in the full constructor.
class _FakeUser implements User {
  _FakeUser(this.id);

  @override
  final String id;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
