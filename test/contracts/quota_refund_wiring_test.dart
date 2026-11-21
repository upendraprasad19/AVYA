// test/contracts/quota_refund_wiring_test.dart
//
// Part B (gemini3-limits-caching) — SOURCE-PRESENCE pins for the failed-turn
// refund. Presence only (rule 21): the behavioural proof is
//   - supabase/functions/_shared/quota_refund_test.ts + tool-loop_failure_kind_test.ts
//     (which failures refund, and that the RPC wrapper never throws), and
//   - test/sql/gemini3_limits_refund_live_verify.sql (latch, budget, used>0, ACL, window)
//     run live by the founder after migration 153 is applied.
//
// What these pins protect:
//   1. refund_quota's SQL shape: SECURITY INVOKER, latch on model_used='pending',
//      budget spent AFTER the latch, `used > 0` guard, service_role-only ACL that
//      names PUBLIC, anon AND authenticated (the platform default privileges grant
//      the last two directly), and NO "SECURITY DEFINER" text anywhere (the plan-review
//      gate grades such a file catastrophic).
//   2. ai-proxy wiring ORDER: the refund RPC runs BEFORE the row is stamped, because
//      the latch matches model_used='pending' — a stamp-then-refund order refunds nothing.
//   3. Prediction and PRO media never call it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/migration_cap_reader.dart';

void main() {
  late String sql;
  late String block;
  late String proxy;

  setUpAll(() {
    final mig = latestMigrationDefining('refund_quota');
    expect(mig, isNotNull, reason: 'no migration defines refund_quota');
    sql = mig!.readAsStringSync();
    block = functionBlock(sql, 'refund_quota')!;
    proxy = stripDartComments(
        File('supabase/functions/ai-proxy/index.ts').readAsStringSync());
  });

  group('refund_quota — SQL shape', () {
    test('SECURITY INVOKER, and the words SECURITY DEFINER appear nowhere in the file', () {
      expect(sql.contains('SECURITY INVOKER'), isTrue);
      expect(RegExp('SECURITY\\s+DEFINER', caseSensitive: false).hasMatch(sql), isFalse,
          reason: 'check_plan_review_record_exists.dart grades any SECURITY DEFINER '
              'text (comments included) catastrophic and demands a hermes pass.');
    });

    test('the latch is ONE UPDATE on model_used = pending, before the budget is spent', () {
      final b = stripSqlComments(block);
      final latch = b.indexOf(RegExp(r"AND\s+model_used\s*=\s*'pending'"));
      final budget = b.indexOf("consume_quota(v_user, 'refund_budget'");
      final decrement = b.indexOf('used = used - 1');
      expect(latch, greaterThanOrEqualTo(0), reason: 'no pending latch');
      expect(budget, greaterThan(latch),
          reason: 'the budget is spent BEFORE the latch: a replayed call would burn it');
      expect(decrement, greaterThan(budget));
    });

    test('the decrement is guarded against going negative and keyed on the row window', () {
      final b = stripSqlComments(block);
      expect(RegExp(r'AND\s+used\s*>\s*0').hasMatch(b), isTrue);
      expect(RegExp(r"v_window\s*:=\s*date_trunc\('day',\s*COALESCE\(v_created,\s*now\(\)\)\s+AT\s+TIME\s+ZONE\s+'Asia/Kolkata'\)")
              .hasMatch(b),
          isTrue,
          reason: "the window must be the IST day of the ROW's created_at, not now()");
    });

    test('the ledger row is checked BEFORE the budget is spent, and the latch cannot be re-armed', () {
      final b = stripSqlComments(block);
      final precheck = b.indexOf(RegExp(
          r'PERFORM\s+1\s+FROM\s+public\.usage_counters[\s\S]*?AND\s+used\s*>\s*0[\s\S]*?FOR\s+UPDATE'));
      final budget = b.indexOf("consume_quota(v_user, 'refund_budget'");
      expect(precheck, greaterThanOrEqualTo(0),
          reason: 'no used > 0 ledger pre-check: a refund with nothing to give back would burn the budget');
      expect(budget, greaterThan(precheck));
      expect(RegExp(r"IF\s+v_label\s*=\s*'pending'\s+THEN\s+v_label\s*:=\s*'failed'")
              .hasMatch(b),
          isTrue,
          reason: "p_label = 'pending' would leave the row latchable twice");
    });

    test('channel -> key map covers the four reservation channels', () {
      final b = stripSqlComments(block);
      for (final pair in const {
        "'app'": "'chat_app'",
        "'scan_meal'": "'vision_analysis'",
        "'cart_auditor'": "'vision_analysis'",
        "'food_text_analysis'": "'food_text'",
      }.entries) {
        expect(RegExp('WHEN\\s+${pair.key}\\s+THEN\\s+${pair.value}').hasMatch(b), isTrue,
            reason: '${pair.key} -> ${pair.value} missing from refund_quota');
      }
    });

    test('ACL: revoked from PUBLIC, anon and authenticated; granted to service_role only', () {
      final s = stripSqlComments(sql);
      expect(
          RegExp(r'REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.refund_quota\(uuid,\s*text\)\s+FROM\s+PUBLIC,\s*anon,\s*authenticated')
              .hasMatch(s),
          isTrue,
          reason: 'REVOKE must name anon + authenticated: the default privileges '
              'grant them EXECUTE directly, not via PUBLIC (migration 130 / f2c8d5).');
      expect(
          RegExp(r'GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.refund_quota\(uuid,\s*text\)\s+TO\s+service_role')
              .hasMatch(s),
          isTrue);
    });
  });

  group('ai-proxy wiring', () {
    /// The text from one `refundReservation(` call up to the NEXT resolve/stamp
    /// call, so the order can be asserted per site.
    int idx(String needle, [int from = 0]) => proxy.indexOf(needle, from);

    test('every failure site refunds BEFORE it stamps the row', () {
      // food
      final foodRefund = idx('refundReservation(supabaseClient, reservationId, "failed_gemini", "food")');
      final foodStamp = idx('await resolvePlaceholder(\n          "failed_gemini"');
      expect(foodRefund, greaterThan(0), reason: 'food site does not refund');
      expect(foodStamp, greaterThan(foodRefund), reason: 'food stamps before it refunds');

      // vision: both scan and cart
      var from = 0;
      for (var n = 0; n < 2; n++) {
        final r = idx('refundReservation(supabaseClient, visionReservationId, "failed_gemini", "vision")', from);
        expect(r, greaterThan(0), reason: 'vision site #$n does not refund');
        final st = idx('await resolveVisionPlaceholder("failed_gemini"', r);
        expect(st, greaterThan(r), reason: 'vision site #$n stamps before it refunds');
        from = st;
      }

      // chat: success-path hard failure (transport only) then the stamp UPDATE
      final chatRefund = idx('loop.hadHardFailure && loop.failureKind === "transport"');
      final chatStamp = idx('model_used: rowModelUsed');
      expect(chatRefund, greaterThan(0), reason: 'chat does not gate the refund on failureKind transport');
      expect(chatStamp, greaterThan(chatRefund), reason: 'chat stamps before it refunds');

      // chat: runToolLoop-threw catch — refund BEFORE the stamp UPDATE
      final threwRefund = idx('MODEL_USED_LOOP_THREW_SENTINEL,\n          "chat",');
      final threwStamp = idx('ai_response: "[failed] runToolLoop threw"');
      expect(threwRefund, greaterThan(0));
      expect(threwStamp, greaterThan(threwRefund),
          reason: 'the threw-catch stamps the row before it refunds: the latch finds no pending row');
    });

    test('the chat 200 body reports whether the server actually refunded', () {
      expect(proxy, contains('turnRefunded = (await refundReservation('));
      expect(proxy, contains('refunded: turnRefunded'));
    });

    test('only refundable failures refund: a gate on every non-chat site, none on parse failures', () {
      expect('refundableGeminiChatFailure({ lastError, deterministicFailure, blockSeen })'.allMatches(proxy).length, 3,
          reason: 'food + scan + cart must each gate the refund on refundableGeminiChatFailure '
              'INCLUDING the sticky blockSeen (a fallback transport failure must not launder a block)');
      expect(
          RegExp(r'if \(refundableGeminiChatFailure\(\{ lastError, deterministicFailure, blockSeen \}\)\) \{\s*await refundReservation\(supabaseClient, visionReservationId')
              .allMatches(proxy)
              .length,
          2,
          reason: 'the gate must WRAP the refund call at both vision sites');
      expect(
          proxy.contains('!reservationReused && refundableGeminiChatFailure('), isTrue,
          reason: 'a food dedup hit reuses another request\'s row and must never refund');
      expect(proxy.contains('if (reservationId && !reservationReused) openReservation'), isTrue,
          reason: 'a reused food row must not be refunded by the outer catch either');
      // failed_parse resolves must NOT be preceded by a refund call within the catch
      for (final m in RegExp(r'"failed_parse"').allMatches(proxy)) {
        final window = proxy.substring((m.start - 400).clamp(0, proxy.length), m.start);
        expect(window.contains('refundReservation'), isFalse,
            reason: 'a parse failure (the model answered, tokens were spent) must not refund');
      }
    });

    test('the outer catch refunds the hoisted open reservation, and prediction never refunds', () {
      expect(proxy, contains('let openReservation: { id: string; tag: string } | undefined;'));
      final catchAt = idx('} catch (err_) {');
      expect(catchAt, greaterThan(0));
      expect(proxy.substring(catchAt), contains('refundReservation('));
      final pred = idx('if (type === "prediction")');
      final predEnd = idx('if (!message || typeof message !== "string")', pred);
      expect(proxy.substring(pred, predEnd).contains('refundReservation'), isFalse,
          reason: 'prediction has no reservation row; refunding there would be a no-op at best');
    });

    test('ai-media-proxy never calls refund_quota (PRO media is not refunded)', () {
      final media = File('supabase/functions/ai-media-proxy/index.ts').readAsStringSync();
      expect(media.contains('refund_quota'), isFalse);
      expect(media.contains('refundReservation'), isFalse);
    });
  });
}
