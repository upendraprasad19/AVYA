// ignore_for_file: invalid_use_of_visible_for_testing_member
//
// Regression test for OBS-6 residual (diagnose 2026-07-02-session-token-stale-authuid-a7f2e1).
//
// BUG: on an in-session account switch (sign-out userA → sign-in userB),
// authUserIdTokenProvider derived its authUid from `currentUserProvider` — a
// plain non-reactive Provider that caches SupabaseService.currentUser on first
// read and is never invalidated. So the owner-edge rebuild re-read the STALE
// cached uid (userA) → authUid(A) != hiveOwner(B) → token stuck '<anon>' →
// every mixin tab's `isSessionTearingDown` gate stuck on the skeleton until a
// full reload. FIX (OPT-1): read the LIVE auth uid (the same source guarded_box
// uses), kill-switched by configBox['disable_live_auth_token_read'].
//
// RED→GREEN: test 1 asserts the token recovers to the LIVE uid even when the
// cached currentUserProvider is stale — it FAILS against the pre-fix code (which
// read the cached provider → '<anon>') and PASSES with the live read.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('sess_token_test_');
    Hive.init(tmp.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  setUp(() async {
    if (!Hive.isBoxOpen(HiveService.configBoxName)) {
      await Hive.openBox<dynamic>(HiveService.configBoxName);
    }
    await Hive.box<dynamic>(HiveService.configBoxName).clear();
    HiveUserSession.currentOwnerListenable.value = null;
    debugAuthUidResolverForTests = null;
  });

  tearDown(() async {
    if (Hive.isBoxOpen(HiveService.configBoxName)) {
      await Hive.box<dynamic>(HiveService.configBoxName).clear();
    }
    HiveUserSession.currentOwnerListenable.value = null;
    debugAuthUidResolverForTests = null;
  });

  ProviderContainer makeContainer({User? cachedUser}) {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => const Stream.empty()),
      if (cachedUser != null)
        currentUserProvider.overrideWith((ref) => cachedUser),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test(
      'FIX (default): token recovers to the LIVE authUid on account-switch even '
      'when the cached currentUserProvider is STALE', () {
    // Owner has flipped to userB (openForUser completed). The cached
    // currentUserProvider is still userA (never invalidated). Live auth = userB.
    HiveUserSession.currentOwnerListenable.value = 'user-b-2222';
    debugAuthUidResolverForTests = () => 'user-b-2222'; // LIVE uid
    final token = makeContainer(cachedUser: _FakeUser('user-a-1111'))
        .read(authUserIdTokenProvider);

    // Pre-fix read currentUserProvider('user-a-1111') != owner → '<anon>'.
    // Post-fix reads live 'user-b-2222' == owner → 'user-b-2222'.
    expect(token, 'user-b-2222',
        reason: 'The gate must use the LIVE authUid, not the stale cache.');
  });

  test('FIX (default): cross-account isolation — live authUid != owner → <anon>',
      () {
    HiveUserSession.currentOwnerListenable.value = 'user-b-2222';
    debugAuthUidResolverForTests = () => 'user-a-1111'; // live authUid = A
    final token = makeContainer().read(authUserIdTokenProvider);
    expect(token, '<anon>',
        reason: 'A live authUid that disagrees with the Hive owner must never '
            'resolve — no cross-account leak.');
  });

  test(
      'KILL-SWITCH: disable_live_auth_token_read reverts to the cached '
      'currentUserProvider path verbatim', () async {
    await Hive.box<dynamic>(HiveService.configBoxName)
        .put('disable_live_auth_token_read', true);
    HiveUserSession.currentOwnerListenable.value = 'user-a-1111';
    debugAuthUidResolverForTests = () => 'user-b-2222'; // live — must be IGNORED
    final token = makeContainer(cachedUser: _FakeUser('user-a-1111'))
        .read(authUserIdTokenProvider);
    // Kill-switch ON → reads currentUserProvider('user-a-1111') == owner → uid.
    expect(token, 'user-a-1111',
        reason: 'Kill-switch must read the cached provider, ignoring the live seam.');
  });

  test('KILL-SWITCH: isolation still holds — cached uid != owner → <anon>',
      () async {
    await Hive.box<dynamic>(HiveService.configBoxName)
        .put('disable_live_auth_token_read', true);
    HiveUserSession.currentOwnerListenable.value = 'user-b-2222';
    final token = makeContainer(cachedUser: _FakeUser('user-a-1111'))
        .read(authUserIdTokenProvider);
    expect(token, '<anon>',
        reason: 'The cross-account gate must hold in the kill-switch state too.');
  });
}

/// Minimal fake matching only the `.id` accessor used by the cached
/// `currentUserProvider` read path.
class _FakeUser implements User {
  _FakeUser(this.id);

  @override
  final String id;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
