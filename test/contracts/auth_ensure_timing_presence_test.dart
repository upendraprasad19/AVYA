import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source_scan.dart';

/// OI-348 Landing 3a (B6): PRESENCE pins for the timing WIRING only.
/// `_ensureLocalUser` / `hydrateFromCloud` need a live Supabase + Hive
/// session, so no VM test reaches them; the reporting logic itself is
/// behavioural in `auth_ensure_timing_runner_test.dart` and
/// `test/core/step_timings_test.dart`.
List<String> _lapsIn(String s) => RegExp(r"""\.lap\('([a-z_]+)'\)""")
    .allMatches(s)
    .map((m) => m.group(1)!)
    .toList();

void main() {
  final auth = stripDartComments(
      File('lib/features/auth/providers/auth_provider.dart').readAsStringSync());
  final boot = stripDartComments(
      File('lib/core/services/auth_session_bootstrapper.dart')
          .readAsStringSync());

  test('_ensureLocalUser runs its body through runTimed and logs '
      'auth_ensure_timing', () {
    final start = auth.indexOf('Future<void> _ensureLocalUser(');
    final end = auth.indexOf('Future<void> _ensureLocalUserBody(');
    expect(start, isNot(-1));
    expect(end, greaterThan(start));
    final wrapper = auth.substring(start, end);
    expect(wrapper, contains('runTimed<void>('));
    expect(wrapper, contains('_ensureLocalUserBody(user, t,'));
    expect(wrapper, contains("ErrorTelemetry.logEvent('auth_ensure_timing'"));
  });

  test('body laps, in order', () {
    final start = auth.indexOf('Future<void> _ensureLocalUserBody(');
    final body = auth.substring(start);
    expect(_lapsIn(body),
        ['open', 'guard', 'migrators', 'terms', 'hydrate_failed', 'binds']);
    expect(body, contains('hydrateFromCloud(user, timings: t)'));
  });

  test('confirm and sign-in time their auth call', () {
    expect(auth, contains("timings.lap('verify')"));
    expect(auth, contains("timings.lap('sign_in')"));
    expect(auth, contains('_ensureLocalUser(response.user!, timings: timings)'));
  });

  test('hydrateFromCloud laps, in order', () {
    final start = boot.indexOf('Future<void> hydrateFromCloud(');
    final end = boot.indexOf('Future<void> pushOneSignalPlayerId(', start);
    expect(_lapsIn(boot.substring(start, end)), [
      'h_lock',
      'h_users_upsert',
      'h_users_active',
      'h_users_name',
      'h_terms_sync',
      'h_users_failed',
      'h_profile_read',
      'h_profile_merge',
      'h_progress_read',
      'h_terms_read',
      'h_plan_gen_failed',
      'h_plan_gen',
      'h_progress_failed',
      'h_profile_branch',
      'h_profile_branch',
      'h_profile_failed',
      'h_stub',
      'h_tail',
    ]);
  });
}
