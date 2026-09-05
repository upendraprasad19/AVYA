@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_test_helper.dart';

/// Behavioural guard for migration 128's security model (OI-162 slice 1,
/// diagnose d3a7f1).
///
/// `usage_counters` has RLS ENABLED WITH NO POLICY, and `consume_quota` is
/// `SECURITY INVOKER`. Together that means: service_role and postgres (both
/// `rolbypassrls`) can write; **everyone else is refused, even though they hold
/// EXECUTE on the function.** The EXECUTE grant is deliberately not the guard —
/// this project's schema-level default privileges hand EXECUTE on every new
/// public function to anon and authenticated anyway (diagnose a9d3f1), so a
/// design that relied on grants would be relying on something it does not
/// control.
///
/// ⚠ THIS FILE'S DIRECTORY IS LOAD-BEARING. CI's `supabase-tests` job is the
/// only one carrying live Supabase secrets and it runs exactly
/// `flutter test test/supabase/` and `flutter test test/edge_functions/`
/// (`.github/workflows/test.yml:441,465`). The same file under
/// `test/contracts/` — where its source-grep sibling correctly lives — would be
/// picked up only by the credential-less unit job, hit the `hasCredentials`
/// guard below, and **skip forever while reading green**. A review round caught
/// exactly that in the plan.
///
/// ⚠ ASSERT THE SQLSTATE, NOT THE HTTP STATUS. PostgREST answers this refusal
/// with **HTTP 401** (not 403) and body `{"code":"42501", …}`. `postgrest`
/// 2.9.1 builds `PostgrestException.code` from the BODY's `code`, falling back
/// to the status only when the body has none — so `.code` is `'42501'`. Verified
/// against the pinned package source, not assumed.
void main() {
  if (!SupabaseTestHelper.hasCredentials) {
    test(
        'SKIPPED: SUPABASE_URL / _ANON_KEY / _TEST_EMAIL / _TEST_PASSWORD '
        'not all set', () {});
    return;
  }

  late SupabaseClient client;
  var setUpSucceeded = false;

  setUpAll(() async {
    await SupabaseTestHelper.init();
    await SupabaseTestHelper.signIn();
    client = SupabaseTestHelper.client;
    setUpSucceeded = true;
  });

  tearDownAll(() async {
    if (setUpSucceeded) await SupabaseTestHelper.signOut();
  });

  test('an authenticated client CANNOT write via consume_quota (RLS refuses)',
      () async {
    expect(setUpSucceeded, isTrue, reason: 'sign-in did not complete');

    PostgrestException? caught;
    try {
      await client.rpc('consume_quota', params: {
        'p_user_id': SupabaseTestHelper.userId,
        'p_quota_key': 'rls_probe',
        'p_window_start': '1970-01-01T00:00:00Z',
        'p_limit': 5,
      });
    } on PostgrestException catch (e) {
      caught = e;
    }

    expect(caught, isNotNull,
        reason: 'consume_quota SUCCEEDED for an authenticated caller. That '
            'means RLS is disabled, a permissive policy was added to '
            'usage_counters, or the function was switched to DEFINER mode — '
            'any of which re-opens the cross-account quota-burn surface '
            'migration 128 exists to prevent.');
    expect(caught!.code, '42501',
        reason: 'expected an RLS refusal (SQLSTATE 42501); got code '
            '"${caught.code}" / message "${caught.message}". Assert the '
            'SQLSTATE, not the HTTP status — PostgREST returns 401 here.');
  });

  test('the refusal is RLS, not a missing EXECUTE grant', () async {
    expect(setUpSucceeded, isTrue, reason: 'sign-in did not complete');

    // A missing grant surfaces as 42883 (undefined_function) or a PGRST202
    // schema-cache miss, NOT 42501. Distinguishing them matters: if the design
    // ever drifted to relying on grants, this test would still see a failure
    // and could be misread as proof the security model holds. It does not hold
    // for the same reason — grants here are handed out by a schema default we
    // do not control.
    PostgrestException? caught;
    try {
      await client.rpc('consume_quota', params: {
        'p_user_id': SupabaseTestHelper.userId,
        'p_quota_key': 'rls_probe_2',
        'p_window_start': '1970-01-01T00:00:00Z',
        'p_limit': 1,
      });
    } on PostgrestException catch (e) {
      caught = e;
    }

    expect(caught?.code, isNot('42883'),
        reason: 'consume_quota is not callable at all (undefined function). '
            'The security model must be RLS refusing a reachable function, '
            'not the function being unreachable.');
    expect(caught?.code, isNot('PGRST202'),
        reason: 'consume_quota is missing from the PostgREST schema cache.');
  });
}
