import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../supabase/supabase_test_helper.dart';

/// Guards the one line that lets `test/supabase/` reach the network at all.
///
/// `SupabaseTestHelper` MUST call `TestWidgetsFlutterBinding.ensureInitialized()`
/// — `Supabase.initialize()` needs the shared_preferences platform channel — but
/// that binding installs an `HttpOverrides` whose mock `HttpClient` answers every
/// request with 400 and never touches the network.
///
/// The resulting failure is actively misleading rather than merely unhelpful:
/// sign-in throws `AuthUnknownException(... status code 400)`, which reads like
/// a rejected anon key, so the natural response is to go re-verify credentials
/// that were never the problem. That is what a red `main` looked like on
/// 2026-08-12 the first time the CI job ran with real secrets (OI-105).
void main() {
  test('the binding\'s mock HttpClient is removed, so real requests can go out',
      () {
    // Baseline: prove the mock is actually installed by the binding, so this
    // test cannot pass vacuously on a Flutter version that stopped doing it.
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(HttpOverrides.current, isNotNull,
        reason: 'precondition: the test binding installs an HttpOverrides. If '
            'this fails, Flutter changed and the guard below may be moot — '
            'check before deleting it.');

    // ignore: invalid_use_of_visible_for_testing_member
    SupabaseTestHelper.debugRemoveHttpMock();

    expect(HttpOverrides.current, isNull,
        reason: 'without this, every Supabase call in test/supabase/ gets a '
            'fabricated 400 from Flutter and no request ever leaves the '
            'process — the tests cannot integrate with anything');
  });
}
