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

  test('the live private.grant_referral_days inserts kReferralTrialPlan', () {
    // The name is interpolated into the helper's regex; the escaped dot keeps
    // it literal. Last CREATE OR REPLACE wins (CLAUDE.md 4.9).
    const fn = r'private\.grant_referral_days';
    final file = latestMigrationDefining(fn);
    expect(file, isNotNull, reason: 'no migration defines $fn');
    final block = functionBlock(file!.readAsStringSync(), fn);
    expect(block, isNotNull);
    final insert = RegExp(
      r"INSERT\s+INTO\s+(?:public\.)?subscriptions[\s\S]*?VALUES\s*\(\s*p_user_id\s*,\s*'([a-z_]+)'",
      caseSensitive: false,
    ).firstMatch(block!);
    expect(insert, isNotNull, reason: 'insert not found in ${file.path}');
    expect(insert!.group(1), kReferralTrialPlan);
  });
}
