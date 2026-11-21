// test/contracts/promo_usable_rule_writer_to_reader_test.dart
//
// payment-hardening U3 (OI-366, diagnose f2c9a8). Writer: _shared/promo_rules.ts promoUsableAt, the ONE rule for
// "can this code be used for a NEW purchase now" (inactive, expired by the IST day, exhausted). Readers: the two
// STRICT doors, validate-promo and create-razorpay-order. The payment writers (verify-payment, razorpay-webhook)
// must NOT read it: their tolerant derivePlanFromAmount keeps a payment already made at the discount recordable
// when the code lapses before capture (docs/architecture/payment.md rule 2). Behaviour:
// _shared/promo_rules_test.ts (the rule table) and the strict-door Deno tests.
//
// Run: flutter test test/contracts/promo_usable_rule_writer_to_reader_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  group('promo_usable_rule', () {
    test('both strict doors import and call promoUsableAt', () {
      for (final f in [
        'supabase/functions/validate-promo/index.ts',
        'supabase/functions/create-razorpay-order/index.ts',
      ]) {
        final code = _code(f);
        expect(code, contains('import { promoUsableAt } from "../_shared/promo_rules.ts";'), reason: f);
        expect(RegExp(r'promoUsableAt\(promo').hasMatch(code), isTrue, reason: f);
      }
    });

    test('validate-promo answers every usability itself: an exhaustive default that REFUSES', () {
      // Unreachable today (four members, four cases); it decides what a fifth member gets before anyone adds a
      // case for it. `never` makes CI's deno check fail on a fifth member; this pins the answer (B-pass
      // 657e30b88cac finding 1: flipping it to valid left every test green).
      final code = _code('supabase/functions/validate-promo/index.ts');
      final at = code.indexOf('switch (usability) {');
      expect(at, greaterThanOrEqualTo(0));
      final def = code.indexOf('default: {', at);
      expect(def, greaterThan(at));
      final end = code.indexOf('\n        }', def); // the default block's own closing brace
      expect(end, greaterThan(def));
      final block = code.substring(def, end);
      expect(block, contains('const unhandled: never = usability;'));
      expect(block, contains('return answer({ valid: false, reason: CHECK_UNAVAILABLE_REASON });'));
      expect(block.contains('valid: true'), isFalse);
    });

    test('the tolerant payment writers do NOT use the strict rule', () {
      for (final f in [
        'supabase/functions/verify-payment/index.ts',
        'supabase/functions/razorpay-webhook/index.ts',
      ]) {
        expect(_code(f).contains('promo_rules'), isFalse, reason: '$f must stay tolerant (payment.md rule 2)');
      }
    });

    test('the rule compares the IST calendar day and refuses a non-date valid_until', () {
      final code = _code('supabase/functions/_shared/promo_rules.ts');
      expect(code, contains('if (istDateStr(now) > until) return "expired";'));
      expect(code, contains(r'const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;'));
      expect(code, contains('if (!DATE_RE.test(until)) return "expired";'));
      expect(code, contains('if (promo.is_active !== true) return "inactive";'));
    });
  });
}
