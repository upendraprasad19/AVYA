// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

void main() {
  // OBS-6 residual (a7f2e1, 2026-07-02): authUserIdTokenProvider now reads the
  // LIVE auth uid, NOT the cached currentUserProvider. In a pure-VM test the
  // Supabase singleton isn't initialised, so inject the uid via the shared
  // `debugAuthUidResolverForTests` seam (the same seam guarded_box uses). The
  // old `currentUserProvider.overrideWith(...)` no longer feeds the token.
  //
  // Reset the static listenable + the auth-uid seam between tests so cross-test
  // leakage can't give a false pass.
  setUp(() {
    HiveUserSession.currentOwnerListenable.value = null;
    debugAuthUidResolverForTests = null;
  });

  tearDown(() {
    HiveUserSession.currentOwnerListenable.value = null;
    debugAuthUidResolverForTests = null;
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer(overrides: [
      // authStateProvider is a StreamProvider — override with an empty stream so
      // it doesn't error out under test (still provides the reactivity watch).
      authStateProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('token returns <anon> when authUid and hiveOwner disagree', () {
    // Simulate: Supabase has flipped to sumitId but openForUser hasn't
    // caught up yet — Hive still owned by upendraId.
    HiveUserSession.currentOwnerListenable.value = 'upendra-id-aaaa-bbbb';
    debugAuthUidResolverForTests = () => 'sumit-id-cccc-dddd';

    final token = makeContainer().read(authUserIdTokenProvider);
    expect(token, '<anon>',
        reason: 'Disagreement must produce <anon>, not the auth uid.');
  });

  test('token returns authUid when authUid and hiveOwner agree', () {
    HiveUserSession.currentOwnerListenable.value = 'sumit-id-cccc-dddd';
    debugAuthUidResolverForTests = () => 'sumit-id-cccc-dddd';

    final token = makeContainer().read(authUserIdTokenProvider);
    expect(token, 'sumit-id-cccc-dddd');
  });

  test('token flips from <anon> to authUid when openForUser completes',
      () async {
    HiveUserSession.currentOwnerListenable.value = 'upendra-id-aaaa-bbbb';
    // Live auth is already sumit (auth fired before openForUser caught up).
    debugAuthUidResolverForTests = () => 'sumit-id-cccc-dddd';

    final container = makeContainer();
    expect(container.read(authUserIdTokenProvider), '<anon>');

    // Simulate openForUser completing — listenable flips to sumit.
    HiveUserSession.currentOwnerListenable.value = 'sumit-id-cccc-dddd';
    // Pump microtasks so the listener can fire and providers re-emit.
    await Future<void>.delayed(Duration.zero);

    expect(container.read(authUserIdTokenProvider), 'sumit-id-cccc-dddd');
  });
}
