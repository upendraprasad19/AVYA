// Regression contract for bug c4f1a7 (2026-06-13 live web E2E, Obs#9): the DPDP
// delete-account button "did nothing" (opaque "Couldn't delete account") on an
// aged web session because the screen called a RAW client.functions.invoke
// WITHOUT refreshing the JWT first → the EF 401'd a stale token. A whole-codebase
// sweep found the same gap at 3 more authed callers. This pins the sweep + the
// 401-decode, complementing the mechanical gate
// scripts/check_authed_invoke_fresh_token.dart (empty baseline).
//
// Source-grep (presence-only) with comment-stripping — the refresh primitive
// (ensureFreshToken / callFunction) is exercised by supabase_service tests; this
// guards the callers from regressing back to a raw no-refresh invoke. Recurrence
// of §2.31 (diagnose d3a1c7). Per feedback_source_grep_strip_comments_first.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  group('Obs#9 (c4f1a7) — authed EF callers refresh the token first', () {
    test('delete_account_screen routes delete-account through callFunction (refreshes), not a raw invoke',
        () {
      final src = _strip(File(
              'lib/features/profile/screens/delete_account_screen.dart')
          .readAsStringSync());
      expect(src.contains('callFunction('), isTrue,
          reason:
              'the delete invoke must go through SupabaseService.callFunction '
              '(ensureFreshToken + cold-start retry), never a raw stale-token invoke');
      expect(src.contains('.functions.invoke('), isFalse,
          reason:
              'no raw client.functions.invoke in the delete screen — it sends '
              'whatever (possibly stale) token supabase-js holds → 401 on web');
    });

    test('delete_account_screen decodes a 401 to a distinct session-expired message',
        () {
      final src = _strip(File(
              'lib/features/profile/screens/delete_account_screen.dart')
          .readAsStringSync());
      expect(src.contains('e.status == 401'), isTrue,
          reason: 'a stale-token 401 must be decoded, not lumped into generic');
      expect(src.contains("'session_expired'"), isTrue,
          reason: 'the 401 maps to a session_expired message (sign out + retry)');
    });

    test('the 3 swept callers (assess-body-composition / redeem-referral) use callFunction',
        () {
      final ur = _strip(
          File('lib/shared/repositories/user_repository.dart').readAsStringSync());
      final rr = _strip(
          File('lib/features/profile/repositories/referral_repository.dart')
              .readAsStringSync());
      expect(ur.contains('.functions.invoke('), isFalse,
          reason: 'assess-body-composition must route through callFunction');
      expect(rr.contains('.functions.invoke('), isFalse,
          reason: 'redeem-referral must route through callFunction');
    });

    test('video_render_provider refreshes before its raw GET/POST invokes', () {
      final src = _strip(
          File('lib/features/train/providers/video_render_provider.dart')
              .readAsStringSync());
      // video-status is a GET with queryParameters (callFunction has no such
      // arg), so it keeps the raw invoke but MUST ensureFreshToken first.
      expect('ensureFreshToken'.allMatches(src).length, greaterThanOrEqualTo(2),
          reason:
              'both video-render-trigger and video-status invokes must refresh first');
    });

    test('the authed-invoke gate baseline is empty (sweep complete)', () {
      final entries = File('backups/authed_invoke_fresh_token_baseline.txt')
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
      expect(entries, isEmpty,
          reason:
              'every raw functions.invoke is fixed → no file may remain '
              'grandfathered in the gate baseline');
    });
  });
}
