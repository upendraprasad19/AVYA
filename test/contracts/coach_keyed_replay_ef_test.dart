// SOURCE PINS (presence only) — OI-505 fix 4 (plan
// docs/plans/2026-11-13-coach-late-link-timeout-retry.md, diagnose d9a3b5):
// a Retry of a finished coach turn reuses it instead of reserving a second row.
//
// Writer: the app's Retry button sets `client_retry: true` on the chat body
// (ai_service.dart, both transports) with the turn's `client_key`.
// Reader: ai-proxy's handler, through _shared/chat_dedup.ts
// `resolveKeyedReplay` (behavioural Deno tests: _shared/chat_dedup_keyed_test.ts).
//
// ai-proxy starts `serve(` at module scope and cannot be imported by a Deno
// test, so the handler's WIRING is pinned here as presence: the call order is
// also proven by the live smoke after the deploy (registry entry is
// `presence_only: true` for that reason).
import 'package:flutter_test/flutter_test.dart';

import '../helpers/read_screen_source.dart';

int _count(String h, String n) => RegExp(RegExp.escape(n)).allMatches(h).length;

void main() {
  final proxy = readSourceFileStripped('supabase/functions/ai-proxy/index.ts');
  final dedup = readSourceFileStripped('supabase/functions/_shared/chat_dedup.ts');
  final ai = readSourceFileStripped('lib/core/services/ai_service.dart');

  group('ai-proxy handler wiring', () {
    test('client_retry is destructured from the body and passed as received (strictly true is checked in the resolver)', () {
      expect(_count(proxy, 'client_retry,\n    } = body;'), 1);
      expect(_count(proxy, 'clientRetry: client_retry,'), 1);
      expect(proxy, isNot(contains('client_retry === true')),
          reason: 'the strict compare lives in resolveKeyedReplay, once');
    });

    test('the resolver runs after the cap/auth block, before the text dedup and before the reservation', () {
      final isPro = proxy.indexOf('const isProUser = await checkPro(');
      final keyed = proxy.indexOf('await resolveKeyedReplay({');
      final dedupAt = proxy.indexOf('const dedupCutoff');
      final reserve = proxy.indexOf('const chatReservation = await supabaseClient');
      expect(_count(proxy, 'resolveKeyedReplay({'), 1);
      expect(isPro, greaterThanOrEqualTo(0));
      expect(keyed, greaterThan(isPro));
      expect(dedupAt, greaterThan(keyed));
      expect(reserve, greaterThan(dedupAt));
    });

    test('the key is sanitized, the kill switch is the exact "1" compare, the lookup is scoped to user + key + channel', () {
      expect(proxy, contains('clientKey: sanitizeClientKey(client_key),'));
      expect(proxy,
          contains('killSwitch: Deno.env.get("DISABLE_CLIENT_KEY_REPLAY") === "1",'));
      final at = proxy.indexOf('fetchRows: async (turnKey)');
      expect(at, greaterThan(0));
      final body = proxy.substring(at, proxy.indexOf('});', at));
      expect(body, contains('.eq("user_id", userId)'));
      expect(body, contains('.eq("client_key", turnKey)'));
      expect(body, contains('.eq("channel", "app")'));
      expect(body, contains('.limit(5)'));
      for (final col in ['id', 'user_message', 'ai_response', 'model_used', 'tokens_used', 'tool_calls', 'created_at']) {
        expect(body, contains(col));
      }
    });

    test('the 503 answer reads keyed.status and keyed.body; a replay replaces recentDup and takes the EXISTING replay branch', () {
      expect(proxy, contains('JSON.stringify(keyed.body)'));
      expect(proxy, contains('status: keyed.status,'));
      expect(proxy, contains('if (keyed.kind === "replay") recentDup = keyed.row'));
      expect(proxy, contains('let { data: recentDup } = await supabaseClient'));
      expect(_count(proxy, 'logWriteClaimDetection('), 2,
          reason: 'no third detector call site (coach_write_claim_wiring_test)');
    });

    test('the resolution UPDATE stores the legacy-actions marker when the reply had log tags', () {
      expect(proxy, contains('name: LEGACY_LOG_ACTIONS_MARKER,'));
      expect(proxy, contains('tool_calls: storedToolCalls,'));
      expect(proxy, contains('args: { count: extracted.actions.length },'));
    });
  });

  group('_shared/chat_dedup.ts constants', () {
    test('the unreplayable statuses, the stale-pending window and the age cap are what the plan says', () {
      expect(dedup, contains('"queued_for_user_confirmation",'));
      expect(dedup, contains('"tile_requested",'));
      expect(dedup, contains('"legacy_log_actions",'));
      expect(dedup, contains('KEYED_PENDING_STALE_MS = 150_000'));
      expect(dedup, contains('KEYED_MAX_REPLAY_AGE_MS = 6 * 60 * 60 * 1000'));
      expect(dedup, contains('args.clientRetry !== true'));
    });
  });

  group('client', () {
    test('both chat transports send client_retry only through the clientRetry flag; no media body does', () {
      expect(_count(ai, "if (clientRetry) 'client_retry': true,"), 2,
          reason: 'invoke body and direct-HTTP body of chat');
      expect(ai, isNot(contains("'client_retry': false")));
      final media = ai.indexOf('Future<AiChatResponse> chatWithMedia(');
      expect(media, greaterThan(0));
      expect(ai.substring(media, ai.indexOf('Future<', media + 10)),
          isNot(contains('client_retry')));
    });
  });
}
