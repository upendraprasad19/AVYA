// Regression guard — diagnose 2026-05-30-rank-promotion-dispatch-trigger-
// columns (f4b2c9).
//
// The AFTER INSERT trigger function private.dispatch_proactive_coach_promotion
// (on rank_promotions) referenced columns that do not exist — NEW.created_at
// (rank_promotions has only achieved_at) and client_errors(message, severity)
// (real columns: error_message, error_code; plus NOT NULL client_version +
// platform). Because the WHEN OTHERS handler re-raised the same broken insert,
// the exception escaped the trigger and ABORTED every rank_promotions INSERT —
// no user could be promoted. Migration 078 rewrites the function.
//
// This is a source-grep guard on the migration that defines the canonical
// trigger body. The authoritative behavioral proof is the live rollback-
// transaction test recorded in the diagnose-doc (OLD fn -> 42703; applied NEW
// fn -> insert succeeds). flutter test cannot reach the live DB, so we pin the
// migration source here.
//
// Run: flutter test test/contracts/dispatch_proactive_coach_promotion_columns_test.dart

import 'dart:io';
import 'package:test/test.dart';

const _migration =
    'supabase/migrations/078_fix_dispatch_proactive_coach_promotion_columns.sql';

/// Strip SQL `-- ...` line comments so absence assertions don't false-positive
/// on the header that DESCRIBES the bug (it mentions message/severity/created_at).
String _stripSqlComments(String src) =>
    src.replaceAll(RegExp(r'--[^\n]*'), '');

void main() {
  group('dispatch_proactive_coach_promotion trigger columns (f4b2c9)', () {
    late String code;

    setUpAll(() {
      final f = File(_migration);
      expect(f.existsSync(), isTrue,
          reason: 'migration 078 must exist');
      code = _stripSqlComments(f.readAsStringSync());
    });

    test('redefines the dispatch trigger function', () {
      expect(
        code.contains(
            'CREATE OR REPLACE FUNCTION private.dispatch_proactive_coach_promotion'),
        isTrue,
      );
    });

    test('does NOT reference NEW.created_at (no such column on rank_promotions)',
        () {
      expect(code.contains('NEW.created_at'), isFalse,
          reason:
              'rank_promotions has no created_at column — use NEW.achieved_at '
              '(the NOT NULL timestamp).');
      expect(code.contains('NEW.achieved_at'), isTrue,
          reason: 'dispatch body must read NEW.achieved_at');
    });

    test('client_errors inserts use real columns, not message/severity', () {
      // Bad legacy column list was: (user_id, op_type, message, severity).
      // `error_message` legitimately contains the substring "message", so we
      // assert on the exact bad sequence "op_type, message" instead.
      expect(code.contains('op_type, message'), isFalse,
          reason:
              'client_errors has no `message` column — use error_message.');
      expect(code.contains('severity'), isFalse,
          reason:
              'client_errors has no `severity` column — use error_code.');
      for (final col in const [
        'error_code',
        'error_message',
        'client_version',
        'platform',
      ]) {
        expect(code.contains(col), isTrue,
            reason: 'client_errors insert must include $col '
                '(error_code/client_version/platform are NOT NULL).');
      }
    });

    test('exception handler is defensive (nested swallow) so telemetry failure '
        'can never abort the rank_promotions insert', () {
      // Outer handler + nested handler => "EXCEPTION WHEN OTHERS" appears twice,
      // and the inner block swallows via NULL.
      final occurrences =
          RegExp(r'EXCEPTION WHEN OTHERS THEN').allMatches(code).length;
      expect(occurrences, greaterThanOrEqualTo(2),
          reason:
              'the WHEN OTHERS handler must wrap its telemetry insert in a '
              'nested BEGIN/EXCEPTION ... NULL so a telemetry failure cannot '
              'roll back the promotion.');
      expect(code.contains('NULL;'), isTrue,
          reason: 'nested handler must swallow (NULL;) on telemetry failure.');
    });
  });
}
