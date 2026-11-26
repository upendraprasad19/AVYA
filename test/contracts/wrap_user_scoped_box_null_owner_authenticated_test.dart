// FIX-1 Part A (e2e-2026-06-21 P0) — BEHAVIORAL contract for the
// owner-null-but-authenticated transient in `wrapUserScopedBox`.
//
// Root cause: on a sign-out → sign-in as a DIFFERENT user (and on a
// cold-boot deep-link), `HiveUserSession` owner is cleared to null before
// `openForUser` for the new user runs, WHILE every user-scoped Riverpod
// provider rebuilds on the `authUserIdTokenProvider='<anon>'` signal and
// reads user-scoped Hive. The disagreement guard in `wrapUserScopedBox`
// only serves `GuardedBox.empty` when the Hive owner is NON-null and
// disagrees; the owner-NULL case fell through to
// `throw StateError('HiveUserSession not opened …')` → blank Home.
//
// FIX (Part A): serve `GuardedBox.empty` (reads → null/empty, writes →
// throw-loud) when owner==null but a Supabase session is authenticated;
// Layer B (`currentOwnerListenable`) re-invalidates the watchers once
// `openForUser` sets the owner. Keep the loud throw ONLY when
// UNAUTHENTICATED — a genuine read-before-openForUser ordering bug.
//
// BEHAVIORAL (not source-grep): drives `wrapUserScopedBox` through the real
// owner-null path via the `debugAuthUidResolverForTests` seam (the
// production `Supabase.instance` read can't be initialised in a pure-VM
// unit test).
//
// Run: flutter test test/contracts/wrap_user_scoped_box_null_owner_authenticated_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('null_owner_auth_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    HiveService.debugMarkInitializedForTests();
  });

  setUp(() async {
    // Null the Hive owner — the transient window we are pinning.
    await HiveUserSession.closeAll();
  });

  tearDown(() {
    debugAuthUidResolverForTests = null; // never leak the seam across tests
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('wrapUserScopedBox — owner-null-but-authenticated transient', () {
    test(
        'owner==null + AUTHENTICATED → serves GuardedBox.empty (no throw); '
        'reads return null/empty, writes throw loud', () async {
      // A valid session exists but openForUser(newUser) has not run yet.
      debugAuthUidResolverForTests =
          () => 'cccc1111-cccc-cccc-cccc-cccccccccccc';
      expect(HiveUserSession.currentOwnerFullId, isNull,
          reason: 'precondition — owner cleared (sign-out / cold-boot window).');

      // RED before Part A: throws StateError('HiveUserSession not opened …')
      // → blank Home. GREEN after Part A: returns an empty stub.
      final box = wrapUserScopedBox<dynamic>(HiveService.userBoxName);

      // Reads serve empty → the screen renders an empty state, not a crash.
      expect(box.get('profile'), isNull);
      expect(box.isEmpty, isTrue);
      // Writes still fail loud so an inflight fire-and-forget sync can NEVER
      // leak into the wrong box during the race.
      expect(() => box.put('k', 'v'), throwsA(isA<StateError>()));
    });

    test(
        'owner==null + UNAUTHENTICATED → STILL throws (a genuine '
        'read-before-openForUser ordering bug must fail loud)', () async {
      debugAuthUidResolverForTests = () => null; // no session at all
      expect(HiveUserSession.currentOwnerFullId, isNull);

      expect(
        () => wrapUserScopedBox<dynamic>(HiveService.userBoxName),
        throwsA(isA<StateError>()),
        reason: 'a read with NO session is a real call-ordering bug — the '
            'loud throw must remain so it is never silently masked.',
      );
    });
  });
}
