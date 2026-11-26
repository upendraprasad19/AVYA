// OI-341 Piece B2b — the client's referral-trial plan name must equal the
// server's: the door's REFERRAL_TRIAL_PLAN and the literal the LIVE definition
// of private.grant_referral_days inserts. A drift silently hides the paywall
// stacking line and turns a trial user's 409 into "already PRO".
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/subscription_plans.dart';

import '../helpers/migration_cap_reader.dart';

void main() {
  test('create-razorpay-order REFERRAL_TRIAL_PLAN equals kReferralTrialPlan',
      () {
    final src = File('supabase/functions/create-razorpay-order/index.ts')
        .readAsStringSync();
    final m = RegExp(r'''const\s+REFERRAL_TRIAL_PLAN\s*=\s*["']([^"']+)["']''')
        .firstMatch(src);
    expect(m, isNotNull, reason: 'REFERRAL_TRIAL_PLAN not found');
    expect(m!.group(1), kReferralTrialPlan);
  });

  test('the live referral-days helpers insert kReferralTrialPlan', () {
    // Since migration 182 (OI-519) private.grant_referral_days is a wrapper (a
    // Play subscriber's days are queued as a Google defer) and the INSERT
    // lives in private.grant_referral_days_direct, which the wrapper calls.
    // Every subscriptions INSERT across the live definitions of both must
    // carry kReferralTrialPlan, and there must be at least one. The names are
    // interpolated into the helper's regex; the escaped dot keeps them
    // literal, and its word boundary keeps the wrapper from matching
    // _direct. Last CREATE OR REPLACE wins (CLAUDE.md 4.9).
    final plans = <String>[];
    for (final fn in const [
      r'private\.grant_referral_days',
      r'private\.grant_referral_days_direct',
    ]) {
      final file = latestMigrationDefining(fn);
      expect(file, isNotNull, reason: 'no migration defines $fn');
      final block = functionBlock(file!.readAsStringSync(), fn);
      expect(block, isNotNull, reason: fn);
      for (final m in RegExp(
        r"INSERT\s+INTO\s+(?:public\.)?subscriptions[\s\S]*?VALUES\s*\(\s*p_user_id\s*,\s*'([a-z_]+)'",
        caseSensitive: false,
      ).allMatches(block!)) {
        plans.add(m.group(1)!);
      }
      if (fn.endsWith('grant_referral_days')) {
        expect(block, contains('PERFORM private.grant_referral_days_direct(p_user_id, p_days)'),
            reason: 'the wrapper must reach the inserting helper');
      }
    }
    expect(plans, isNotEmpty, reason: 'no referral-days INSERT found');
    expect(plans.toSet(), {kReferralTrialPlan});
  });
}
