@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_test_helper.dart';

/// Behavioural guard for migration 128's security model (OI-162 slice 1,
/// diagnose d3a7f1) — model UPDATED by migration 130 (OI-162 slice 4,
/// diagnose f2c8d5, 2026-09-11), see the correction below.
///
/// `usage_counters` has RLS ENABLED WITH NO POLICY, and `consume_quota` is
/// `SECURITY INVOKER`. Together that means: service_role and postgres (both
/// `rolbypassrls`) can write; **everyone else is refused.**
///
/// ⚠ **CORRECTED (Hermes L22 + L35, independently, 2026-09-11): migration 130
/// REVOKED EXECUTE on `consume_quota` from PUBLIC/anon/authenticated.** Before
/// 130, RLS was the ONLY guard — a normal client held EXECUTE (this project's
/// schema-level default privileges hand it out to every new public function,
/// diagnose a9d3f1) and the refusal came from the function's OWN internal
/// write hitting RLS's default-deny. **After 130, EXECUTE-revoke is now the
/// FIRST barrier a normal client hits** — the call never reaches the function
/// body at all, so RLS is unreached for the common case and has become a
/// SECOND, defense-in-depth layer.
///
/// Both barriers raise SQLSTATE **42501** with DIFFERENT message text —
/// verified live, 2026-09-11, via `SET LOCAL ROLE authenticated` in a
/// `BEGIN…ROLLBACK` against prod (Management API, no DDL — see the diagnose
/// doc's Part B for the transcript):
///   - EXECUTE-revoke: `permission denied for function consume_quota`
///   - RLS-zero-policy (direct `INSERT` into `usage_counters`, bypassing the
///     function entirely): `new row violates row-level security policy for
///     table "usage_counters"`
/// Because both are 42501, the SQLSTATE-only check below (kept from the
/// pre-130 design) can no longer tell them apart — this is exactly why test 2
/// below now asserts on MESSAGE TEXT, not just SQLSTATE.
///
/// **The second-layer claim (RLS still blocks the internal write if EXECUTE
/// were ever restored) is NOT independently re-verified live in this batch —
/// it is a logical corollary, stated so, not re-proven.** Re-proving it live
/// would require a transactional `GRANT EXECUTE ... TO authenticated` (even
/// inside a `ROLLBACK`), which the live-apply classifier correctly refuses
/// without explicit human authorization (CLAUDE.md §4.3 "Live prod apply
/// needs its own explicit go"); this batch did not seek that authorization
/// for a defense-in-depth check the primary fix does not depend on. The
/// corollary itself: `consume_quota` is `SECURITY INVOKER`, so its internal
/// write runs AS THE CALLING ROLE, and the direct-`INSERT`-as-`authenticated`
/// probe above already proves THAT role's writes are blocked by RLS
/// independent of any function or grant — so if EXECUTE were restored, the
/// function's internal write would hit the identical, already-proven barrier.
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
    if (!setUpSucceeded) return;
    // Cleanup is hygiene, not an assertion (CLAUDE.md 4.9) -- same unguarded
    // signOut that reddened ai_proxy_test.dart on 2026-09-10.
    try {
      await SupabaseTestHelper.signOut();
    } catch (_) {}
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
            'means EITHER migration 130\'s EXECUTE revoke was reverted (or '
            'never applied) AND RLS is disabled/permissive, OR the function '
            'was switched to DEFINER mode — any of which re-opens the '
            'cross-account quota-burn surface migrations 128+130 exist to '
            'prevent. Two independent layers must BOTH fail for this to '
            'succeed; see the file header for which layer is hit first today.');
    expect(caught!.code, '42501',
        reason: 'expected an RLS refusal (SQLSTATE 42501); got code '
            '"${caught.code}" / message "${caught.message}". Assert the '
            'SQLSTATE, not the HTTP status — PostgREST returns 401 here.');
  });

  test(
      'the refusal is EXECUTE-revoke (migration 130), not a broken/missing '
      'function', () async {
    expect(setUpSucceeded, isTrue, reason: 'sign-in did not complete');

    // ⚠ CORRECTED (Hermes L22 + L35, 2026-09-11): this test used to be named
    // "the refusal is RLS, not a missing EXECUTE grant" and asserted ONLY
    // `caught.code isNot 42883/PGRST202`. Post-migration-130 that assertion
    // is a TAUTOLOGY — a missing-EXECUTE refusal ALSO carries code 42501
    // (never 42883/PGRST202), so it was green whether or not EXECUTE was
    // actually revoked. See the file header for the live-verified message
    // text of each cause; this test now asserts on MESSAGE, which is the
    // only field that still discriminates.
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
            'The security model must be a reachable function being refused, '
            'not the function being unreachable.');
    expect(caught?.code, isNot('PGRST202'),
        reason: 'consume_quota is missing from the PostgREST schema cache.');
    expect(caught?.code, '42501',
        reason: 'the refusal must still be a permission error, not some '
            'other failure mode entirely');
    expect(
      caught?.message.contains('permission denied for function') ?? false,
      isTrue,
      reason: 'expected the EXECUTE-revoke message '
          '"permission denied for function consume_quota" (migration 130\'s '
          'primary guard for a normal client); got '
          '"${caught?.message}". A DIFFERENT 42501 message here — e.g. '
          '"new row violates row-level security policy for table '
          '\\"usage_counters\\"" — would mean EXECUTE was restored to '
          'authenticated and only the RLS second layer caught the call: '
          'still safe today, but a real regression against migration 130\'s '
          'intent that this assertion exists to catch.',
    );
  });
}
