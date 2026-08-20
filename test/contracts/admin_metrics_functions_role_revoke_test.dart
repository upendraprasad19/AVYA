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

  // ── Added by the FOB-5 B-pass (migration 120, 2026-08-20). ──────────────
  //
  // The test above pins migration 103 BY NAME, and 103 is no longer the
  // migration that owns the ACL. Migration 120 DROPs and recreates
  // founder_metrics_engagement (mandatory — adding columns to a `returns
  // table` list raises 42P13 under CREATE OR REPLACE), and a DROP+CREATE does
  // NOT preserve the ACL: Supabase's default privileges on schema public
  // re-grant EXECUTE to anon + authenticated on the fresh function. So 103's
  // revokes protect nothing on a replay past 120 — delete 120's own revoke
  // lines and the a9d3f1 leak reopens while the test above stays green.
  //
  // Written against the MIGRATION SET rather than a named file, so it cannot go
  // stale when 121, 122 … arrive. Cutoff is >103 because 101 is the historical
  // bug itself (it creates all three with no role revoke) and 103 is its fix;
  // neither may be rewritten.
  test('EVERY post-103 migration that creates or drops a public.founder_metrics_* '
      'function re-asserts the anon + authenticated revoke (a9d3f1 replay guard)',
      () {
    final dir = Directory('supabase/migrations');
    expect(dir.existsSync(), isTrue);

    final touching = RegExp(
        r'(create|drop)\s+(or\s+replace\s+)?function\s+(if\s+exists\s+)?'
        r'public\.(founder_metrics_[a-z_]+)\s*\(');

    var checked = 0;
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      if (!name.endsWith('.sql')) continue;
      final number = int.tryParse(name.split('_').first);
      if (number == null || number <= 103) continue;

      final sql = _stripSqlComments(file.readAsStringSync());
      final fns = touching.allMatches(sql).map((m) => m.group(4)!).toSet();
      if (fns.isEmpty) continue;

      for (final fn in fns) {
        checked++;
        final pattern = RegExp(
          'revoke\\s+execute\\s+on\\s+function\\s+public\\.$fn\\s*\\(\\s*\\)\\s+'
          'from\\s+[^;]*\\banon\\b[^;]*\\bauthenticated\\b',
        );
        expect(pattern.hasMatch(sql), isTrue,
            reason: 'migration $name creates or drops public.$fn(), which '
                'RESETS its ACL — Supabase default privileges then re-grant '
                'EXECUTE to anon + authenticated. It must therefore carry its '
                'OWN `revoke execute on function public.$fn() from anon, '
                'authenticated;`. Migration 103 does not cover it: 103 revoked '
                'on the function object that this migration replaced. Without '
                'the revoke here, a replay re-opens the anon-readable business '
                'metrics leak (a9d3f1).');
      }
    }

    expect(checked, greaterThan(0),
        reason: 'this guard must actually be exercising something — if no '
            'post-103 migration touches a founder_metrics_* function the scan '
            'silently passes, which is the Gate-44 shape (a test that cannot '
            'fail). Migration 120 is the current subject.');
  });
}
