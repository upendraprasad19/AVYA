// test/contracts/proactive_coach_promotion_test.dart
//
// Contract — Theme C (closes-diagnose 8b1f33).
//
// Pins the source-level shape of:
//   - Migration 073 (Postgres trigger that fires the Edge Function)
//   - Edge Function `proactive-coach-promotion` (writes to
//     ai_coach_interactions + sends OneSignal push)
//
// 2026-05-29 audit EF-1 (closes-diagnose 9e1d4c): this test PREVIOUSLY
// enshrined the bug — it asserted the function inserts into
// `coach_interactions` with role/metadata, a table+columns that do not
// exist in the live DB. A pure source-grep test that never verified the
// table is real = `feedback_source_grep_false_confidence.md`. Live schema
// verified during the audit: the chat table is `ai_coach_interactions`
// with columns user_message (NOT NULL) / ai_response / channel /
// model_used / tool_calls. Assertions below now pin the CORRECT contract
// AND add NEGATIVE assertions (the nonexistent table/columns must be
// ABSENT) that would have caught EF-1.
//
// Source-grep with comment-stripping per
// `feedback_source_grep_strip_comments_first.md`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _stripDartComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    // Negative lookbehind on `:` so URLs (e.g. https://onesignal.com)
    // don't get eaten by the line-comment strip.
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

String _stripSqlComments(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('--'))
    .join('\n');

void main() {
  group('Migration 073 — trigger + pg_net dispatch', () {
    final src = _stripSqlComments(
        File('supabase/migrations/073_proactive_coach_promotion_trigger.sql')
            .readAsStringSync());

    test('declares trigger function in private schema', () {
      expect(
        RegExp(r'CREATE OR REPLACE FUNCTION\s+'
                r'private\.dispatch_proactive_coach_promotion')
            .hasMatch(src),
        isTrue,
        reason: 'trigger function must live in private schema (cron-style '
            'auth pattern). Public schema would expose it via PostgREST.',
      );
    });

    test('runs SECURITY DEFINER', () {
      expect(
        src.contains('SECURITY DEFINER'),
        isTrue,
        reason: 'trigger must be SECURITY DEFINER so it can call '
            'private.morning_alert_get_service_key() and net.http_post '
            'regardless of the INSERT-caller privilege.',
      );
    });

    test('resolves service_role_key from Vault (not hardcoded)', () {
      expect(
        src.contains('private.morning_alert_get_service_key()'),
        isTrue,
        reason: 'service_role_key must come from Vault per the canonical '
            'cron-auth pattern (Audit 2026-05-12). Hardcoding the key in '
            'DDL is forbidden.',
      );
    });

    test('dispatches via pg_net.http_post', () {
      expect(
        RegExp(r'net\.http_post\s*\(').hasMatch(src),
        isTrue,
        reason: 'must use pg_net for async HTTP dispatch (returns '
            'immediately; delivery happens out-of-transaction).',
      );
    });

    test('attaches AFTER INSERT trigger on rank_promotions', () {
      expect(
        RegExp(r'CREATE TRIGGER\s+trg_dispatch_proactive_coach_promotion\s+'
                r'AFTER\s+INSERT\s+ON\s+public\.rank_promotions')
            .hasMatch(src),
        isTrue,
        reason: 'trigger must fire AFTER INSERT on rank_promotions — the '
            'INSERT must commit first so the Edge Function reads the '
            'committed row.',
      );
    });

    test('errors never propagate to the parent transaction', () {
      expect(
        src.contains('EXCEPTION WHEN OTHERS'),
        isTrue,
        reason: 'trigger MUST swallow exceptions — the rank_promotions '
            'INSERT is the source of truth; the dispatch is additive. '
            'A failed dispatch must NOT roll back the promotion record.',
      );
    });

    test('emits dispatch telemetry to client_errors', () {
      expect(
        src.contains("'proactive_coach_promotion_dispatched'"),
        isTrue,
        reason: 'must telemetry the successful dispatch with request_id '
            '+ rank_code so we can answer "did this fire?" via SQL.',
      );
      expect(
        src.contains("'proactive_coach_promotion_dispatch_failed'"),
        isTrue,
        reason: 'must telemetry the failure cases (missing key, '
            'exception path).',
      );
    });
  });

  group('Edge Function — proactive-coach-promotion', () {
    final src = _stripDartComments(
        File('supabase/functions/proactive-coach-promotion/index.ts')
            .readAsStringSync());

    test('verify_jwt=false (invoked by trigger using service_role_key)', () {
      // verify_jwt config is set in the deploy invocation, not the
      // source. But the source must NOT call SupabaseAuth.verify or
      // require Authorization header validation — we already trust the
      // trigger.
      expect(
        src.contains('createClient(SUPABASE_URL, SERVICE_ROLE_KEY)'),
        isTrue,
        reason: 'Edge Function uses service-role client — trigger is '
            'the only legitimate caller and brings service_role_key as '
            'Authorization Bearer.',
      );
    });

    test('inserts into ai_coach_interactions (the real chat table)', () {
      expect(
        RegExp(r'from\("ai_coach_interactions"\)').hasMatch(src),
        isTrue,
        reason: 'must insert into ai_coach_interactions — the canonical '
            'chat table verified live 2026-05-29.',
      );
    });

    test('does NOT reference the nonexistent coach_interactions table', () {
      // EF-1 regression guard: the bug was inserting into a table that
      // does not exist. `ai_coach_interactions` legitimately contains the
      // substring "coach_interactions", so assert the bare table name is
      // never the `.from(...)` target.
      expect(
        RegExp(r'from\("coach_interactions"\)').hasMatch(src),
        isFalse,
        reason: 'coach_interactions does not exist in the live DB — '
            'inserting into it returns 500 before the OneSignal push '
            '(audit EF-1).',
      );
    });

    test('maps to real ai_coach_interactions columns (not role/metadata)',
        () {
      expect(
        RegExp(r'ai_response:').hasMatch(src),
        isTrue,
        reason: 'congrats text goes in ai_response (the assistant turn).',
      );
      expect(
        RegExp(r'channel:\s*"in_app"').hasMatch(src),
        isTrue,
        reason: 'channel must be "in_app" (the AVYA in-app coach surface).',
      );
      // user_message is NOT NULL on ai_coach_interactions — a proactive
      // turn has no user prompt, so it must be present (empty string).
      expect(
        RegExp(r'user_message:').hasMatch(src),
        isTrue,
        reason: 'user_message column is NOT NULL — must be supplied.',
      );
      // Negative: role/content/metadata are columns that do NOT exist.
      expect(
        RegExp(r'\brole:\s*"assistant"').hasMatch(src),
        isFalse,
        reason: 'ai_coach_interactions has no `role` column (audit EF-1).',
      );
      expect(
        RegExp(r'\bmetadata:').hasMatch(src),
        isFalse,
        reason: 'ai_coach_interactions has no `metadata` column — the '
            'proactive tag lives in tool_calls jsonb instead (audit EF-1).',
      );
    });

    test('tags proactive_promotion + rank_code in tool_calls jsonb', () {
      expect(
        RegExp(r'kind:\s*"proactive_promotion"').hasMatch(src),
        isTrue,
        reason: 'tool_calls.kind must be "proactive_promotion" so the '
            'client + future filters can distinguish proactive messages '
            'from user-initiated chat turns.',
      );
      expect(
        src.contains('rank_code'),
        isTrue,
        reason: 'tool_calls must carry rank_code for downstream filtering.',
      );
    });

    test('telemetry uses real client_errors columns (error_message), '
        'not message/severity', () {
      expect(
        RegExp(r'error_message:').hasMatch(src),
        isTrue,
        reason: 'client_errors has error_message, not message (audit EF-1 '
            'compounding bug: the failure telemetry also silently failed).',
      );
      expect(
        RegExp(r'\bseverity:').hasMatch(src),
        isFalse,
        reason: 'client_errors has no `severity` column.',
      );
    });

    test('RANK_LABELS uses canonical ladder codes (matches '
        'rank_ladder_data.dart)', () {
      // Canonical codes per kRankLadder: SD2,SD1,LS,PO,CPO,MCPO,SubLt,Lt,
      // LtCdr,Cdr,Capt. The buggy map used PO2/PO1/ENS/LTJG/LCDR/CDR/CAPT.
      for (final code in ['LS:', 'PO:', 'MCPO:', 'SubLt:', 'LtCdr:']) {
        expect(src.contains(code), isTrue,
            reason: 'RANK_LABELS missing canonical code $code (audit EF-1).');
      }
      for (final ghost in ['PO2:', 'PO1:', 'ENS:', 'LTJG:']) {
        expect(src.contains(ghost), isFalse,
            reason: 'RANK_LABELS uses nonexistent code $ghost (audit EF-1).');
      }
    });

    test('sends OneSignal push with deep_link to /ai-coach', () {
      expect(
        src.contains('onesignal.com/api/v1/notifications'),
        isTrue,
        reason: 'must POST to OneSignal notifications endpoint.',
      );
      expect(
        src.contains('include_external_user_ids'),
        isTrue,
        reason: 'must target the specific user_id via '
            'include_external_user_ids (set by client on sign-in).',
      );
      expect(
        src.contains('deep_link'),
        isTrue,
        reason: 'push payload must include deep_link so tapping the '
            'notification opens AI Coach.',
      );
      expect(
        src.contains('/ai-coach'),
        isTrue,
        reason: 'deep_link target must be /ai-coach where the '
            'proactive message will be visible.',
      );
    });

    test('emits success + failure telemetry op types', () {
      // TypeScript source uses double quotes — match either.
      expect(
        src.contains("'proactive_coach_promotion_dispatched'") ||
            src.contains('"proactive_coach_promotion_dispatched"'),
        isTrue,
        reason: 'must emit dispatched op_type on success.',
      );
      expect(
        src.contains("'proactive_coach_promotion_failed'") ||
            src.contains('"proactive_coach_promotion_failed"'),
        isTrue,
        reason: 'must emit failed op_type on every error path.',
      );
    });

    test('Gemini model is gemini-2.5-flash (cheap path for short text)',
        () {
      // Per docs/architecture/ai.md model matrix — flash for text
      // analysis-class tasks (the congrats is 80-120 words, not weekly
      // report depth).
      expect(
        src.contains('gemini-2.5-flash'),
        isTrue,
        reason: 'use gemini-2.5-flash for short proactive messages. '
            '2.5-pro is reserved for weekly report (PRO-only).',
      );
    });

    test('system prompt enforces "no emojis" + military lexicon sparingly',
        () {
      // The prompt is the brand voice — pin both rules.
      expect(
        src.contains('NO emojis'),
        isTrue,
        reason: 'AVYA brand voice forbids emojis (Wardroom + Indian '
            'Navy style).',
      );
      expect(
        src.contains('Military lexicon'),
        isTrue,
        reason: 'prompt must explicitly steer the model toward the '
            'military lexicon brand voice.',
      );
    });
  });
}
