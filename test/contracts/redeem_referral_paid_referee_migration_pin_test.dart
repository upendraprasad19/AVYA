// Cross-file pin: the Edge Function's "paid" predicate (unit S2) is the SAME predicate migration 159 refuses on.
//
// Three literals live in two files and nothing else ties them together: the plan list (`monthly`, `yearly`), the
// "has a Razorpay payment id" clause, and the exception text the RPC raises (`referee_has_paid_plan`) which the Edge
// Function maps to a clean 400. Edit one side alone (a third plan name, a renamed exception) and every single-file test
// stays green while a paid friend is either redeemed or answered with a generic 500.
//
// THIS TEST NEEDS migration 159 ON THE BRANCH. It is red on a branch that does not contain
// supabase/migrations/159_referral_reward_on_conversion.sql (unit S1 of docs/plans/referral-pay-on-conversion.md), and
// that is deliberate: it makes the merge order S1 -> S2 a CI fact (safe_pr_merge.sh refuses a red head), so the Edge
// Function can never reach `main` ahead of the RPC refusal it maps. Merge origin/main into the branch once S1 is there.
//
// Source-grep (SQL comments stripped, whitespace squashed): PRESENCE of the shared literals only. The behaviour of each
// side is proved elsewhere (test/sql/referral_pay_on_conversion_live_verify.sql R5/R11 for the RPC,
// supabase/functions/redeem-referral/index_test.ts for the Edge Function).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migPath = 'supabase/migrations/159_referral_reward_on_conversion.sql';
const _efPath = 'supabase/functions/redeem-referral/index.ts';

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

String _stripSqlComments(String src) => src.split('\n').map((line) {
      final i = line.indexOf('--');
      return i == -1 ? line : line.substring(0, i);
    }).join('\n');

/// The squashed, comment-free body of public.redeem_referral_atomic in migration 159.
String _redeemBody() {
  final f = File(_migPath);
  if (!f.existsSync()) {
    fail('$_migPath is not on this branch. Unit S2 (this Edge Function change) must merge AFTER unit S1 (migration 159): '
        'merge origin/main into the branch once S1 is on main, then re-run.');
  }
  final sql = _squash(_stripSqlComments(f.readAsStringSync()));
  final start = sql.indexOf('CREATE OR REPLACE FUNCTION public.redeem_referral_atomic(');
  expect(start, greaterThanOrEqualTo(0), reason: 'migration 159 must define public.redeem_referral_atomic');
  final end = sql.indexOf(r'$function$;', start);
  expect(end, greaterThan(start));
  return sql.substring(start, end);
}

/// The text of the refusal clause: `IF EXISTS ( ... ) THEN RAISE EXCEPTION '<msg>' USING ERRCODE = 'P0001'; END IF;`.
final _refusal = RegExp(
  r"IF EXISTS \( SELECT 1 FROM subscriptions WHERE (?<where>.*?) \) THEN RAISE EXCEPTION '(?<msg>[a-z_]+)' USING ERRCODE = '(?<code>[A-Z0-9]+)'; END IF;",
);

List<String> _planList(String sqlFragment) {
  final m = RegExp(r"plan IN \((?<list>[^)]*)\)").firstMatch(sqlFragment);
  expect(m, isNotNull, reason: 'no `plan IN (...)` in: $sqlFragment');
  return RegExp(r"'([a-z_]+)'").allMatches(m!.namedGroup('list')!).map((x) => x.group(1)!).toList();
}

void main() {
  late String ef;
  late String efSquashed;
  setUpAll(() {
    ef = File(_efPath).readAsStringSync();
    efSquashed = _squash(ef);
  });

  group('the Edge Function paid predicate equals the RPC refusal of migration 159', () {
    test('the RPC refuses a plan in (monthly, yearly) WITH a payment id, at ANY status, raising referee_has_paid_plan / P0001', () {
      final m = _refusal.firstMatch(_redeemBody());
      expect(m, isNotNull, reason: 'the IF EXISTS ... RAISE refusal clause of redeem_referral_atomic was not found');
      final where = m!.namedGroup('where')!;
      expect(_planList(where), ['monthly', 'yearly']);
      expect(where, contains('user_id = p_referee_id'));
      expect(where, contains('razorpay_payment_id IS NOT NULL'));
      expect(where.toLowerCase().contains('status'), isFalse,
          reason: 'the RPC refusal counts a row of ANY status; the Edge Function read must not add a status filter either');
      expect(m.namedGroup('msg'), 'referee_has_paid_plan');
      expect(m.namedGroup('code'), 'P0001');
    });

    test('the Edge Function PAID_PLANS is exactly the RPC plan list (same names, same order)', () {
      final m = _refusal.firstMatch(_redeemBody())!;
      final rpcPlans = _planList(m.namedGroup('where')!);
      final efMatch = RegExp(r'const PAID_PLANS = \[(?<list>[^\]]*)\];').firstMatch(ef);
      expect(efMatch, isNotNull, reason: 'const PAID_PLANS = [...] not found in $_efPath');
      final efPlans = RegExp(r'"([a-z_]+)"').allMatches(efMatch!.namedGroup('list')!).map((x) => x.group(1)!).toList();
      expect(efPlans, rpcPlans);
    });

    test('the Edge Function read asks for a payment id present and carries NO status filter, like the RPC', () {
      final start = efSquashed.indexOf('.from("subscriptions")');
      expect(start, greaterThanOrEqualTo(0));
      final end = efSquashed.indexOf('.limit(1);', start);
      expect(end, greaterThan(start));
      final read = efSquashed.substring(start, end);
      expect(read, contains('.in("plan", PAID_PLANS)'));
      expect(read, contains('.not("razorpay_payment_id", "is", null)'));
      expect(read.contains('"status"'), isFalse, reason: 'a status filter here would let a cancelled paid friend through the pre-check');
    });

    test('the Edge Function maps exactly the exception text the RPC raises, to a 400', () {
      final msg = _refusal.firstMatch(_redeemBody())!.namedGroup('msg')!;
      expect(efSquashed, contains('rpcErr.message.includes("$msg")'));
    });

    test('the hourly reward job reconciles over the same plan list as the RPC refusal', () {
      final body = _redeemBody();
      final rpcPlans = _planList(_refusal.firstMatch(body)!.namedGroup('where')!);
      final sql = _squash(_stripSqlComments(File(_migPath).readAsStringSync()));
      final job = sql.indexOf('CREATE OR REPLACE FUNCTION private.process_referral_conversions()');
      expect(job, greaterThanOrEqualTo(0));
      final jobPlans = _planList(sql.substring(job, sql.indexOf(r'$function$;', job)));
      expect(jobPlans, rpcPlans, reason: '"paid" must mean the same plans to the redemption refusal and to the reward job');
    });
  });
}
