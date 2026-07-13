// Contract / regression test for diagnose a9d3f1 (2026-07-13).
//
// BUG: migration 101 created the three `public.founder_metrics_*()` functions
// as SECURITY DEFINER with only `REVOKE ALL FROM PUBLIC` (mirroring migration
// 093). But 093's function lives in the `private` schema — its protection was
// schema-invisibility, not the revoke. In `public`, Supabase's platform default
// privileges GRANT EXECUTE to `anon` + `authenticated` DIRECTLY (not via
// PUBLIC), so REVOKE FROM PUBLIC was a no-op for those roles and — because the
// functions are SECURITY DEFINER (bypass RLS) — any anon caller could `.rpc()`
// them and read live aggregate business metrics. Caught by the migration-101
// post-apply privilege check; fixed by migration 103's explicit role revokes.
//
// This test pins the FIX in the committed source: if anyone deletes migration
// 103 or removes its role-revokes, this fails. (The LIVE privilege state —
// has_function_privilege('anon', ...) = false — is verified out-of-band at
// apply time; a unit test can't reach the live catalog. Source presence here +
// the live check together are the rule-21 regression guard.)
//
// Comments are stripped BEFORE matching (feedback_source_grep_strip_comments_first)
// so a commented-out revoke can never satisfy the assertion.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _stripSqlComments(String sql) {
  // Block comments /* ... */ then line comments -- ... to EOL.
  final noBlock = sql.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ');
  final noLine = noBlock.replaceAll(RegExp(r'--[^\n]*'), ' ');
  return noLine.toLowerCase();
}

void main() {
  test('migration 103 revokes EXECUTE from anon + authenticated on all three '
      'public.founder_metrics_* functions (anon-executable SECURITY DEFINER fix a9d3f1)', () {
    final f = File('supabase/migrations/103_admin_metrics_revoke_from_roles.sql');
    expect(f.existsSync(), isTrue,
        reason: 'migration 103 (the anon-exec security fix) must exist');

    final sql = _stripSqlComments(f.readAsStringSync());

    for (final fn in [
      'founder_metrics_for_admin_api',
      'founder_metrics_engagement',
      'founder_metrics_ops',
    ]) {
      // A single `revoke execute on function public.<fn>() from anon, authenticated;`
      // statement (whitespace-flexible) covering BOTH roles.
      final pattern = RegExp(
        'revoke\\s+execute\\s+on\\s+function\\s+public\\.$fn\\s*\\(\\s*\\)\\s+from\\s+[^;]*\\banon\\b[^;]*\\bauthenticated\\b',
      );
      expect(pattern.hasMatch(sql), isTrue,
          reason: 'migration 103 must revoke EXECUTE on public.$fn() from '
              'anon + authenticated (not just PUBLIC). Removing this re-opens '
              'the anon-readable-business-metrics leak (a9d3f1).');
    }
  });
}
