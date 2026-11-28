// OI-341 Piece B2b — wiring pins for the stacked-trial client
// (docs/plans/oi341-piece-b2b-client.md section 3, P1-P6).
//
// PRESENCE ONLY. The checkout and confirmation pipeline runs against the
// singleton Supabase client and the Razorpay SDK, so its decisions are pure
// functions with their own behavioural tests (test/core/
// payment_end_estimate_test.dart). These pins prove the service CALLS them,
// on comment-stripped source.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/migration_cap_reader.dart' show stripDartComments;

/// The text of the method that starts at [signature] (up to the next
/// two-space-indented member declaration).
String methodBody(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'not found: $signature');
  final next = RegExp(r'\n  (?:static |Future<|void |String |bool |@)')
      .firstMatch(src.substring(start + signature.length));
  final end = next == null ? src.length : start + signature.length + next.start;
  return src.substring(start, end);
}

void main() {
  late String src;

  setUpAll(() {
    src = stripDartComments(
        File('lib/core/services/razorpay_service.dart').readAsStringSync());
  });

  test('P1 both 409 paths classify and route the trial case before alreadyPro',
      () {
    final response = RegExp(
            r'if \(resp\.status == 409\) \{[\s\S]*?switch \(classifyOrderConflict\(data\)\) \{\s*case OrderConflict\.trialUpgradeUnavailable:[\s\S]*?onFailure\?\.call\(\);\s*return;\s*case OrderConflict\.alreadyPro:')
        .hasMatch(src);
    expect(response, isTrue, reason: 'response path');
    final caught = RegExp(
            r'final conflict = classifyOrderConflict\(m\);[\s\S]*?if \(conflict == OrderConflict\.trialUpgradeUnavailable\) \{[\s\S]*?onFailure\?\.call\(\);\s*return;\s*\}\s*await _handleAlreadyProResponse\(m\);\s*onSuccess\?\.call\(\);')
        .hasMatch(src);
    expect(caught, isTrue, reason: 'FunctionException path');
  });

  test('P2 the confirmation resolves its record before the first await, and '
      'nothing re-reads the fields later', () {
    final confirmed =
        methodBody(src, 'Future<void> handlePaymentConfirmed({');
    final resolveAt = confirmed.indexOf('resolveConfirmedCheckout(');
    final firstAwait = confirmed.indexOf('await ');
    expect(resolveAt, greaterThan(0));
    expect(resolveAt, lessThan(firstAwait));
    final afterResolve = confirmed.substring(
        confirmed.indexOf(';', resolveAt) + 1);
    expect(afterResolve, isNot(contains('_pendingPlan')));
    expect(afterResolve, isNot(contains('_pendingCheckouts.lookup')));
    for (final sig in [
      'Future<void> _pollAndActivate({',
      'void _scheduleVerificationRetry({',
    ]) {
      final body = methodBody(src, sig);
      expect(body, isNot(contains('_pendingPlan')), reason: sig);
      expect(body, isNot(contains('_pendingCheckouts')), reason: sig);
    }
  });

  test('P3 records are cleared on user change, never at checkout start', () {
    final onUserChanged = methodBody(src, 'void _onUserChanged() {');
    expect(onUserChanged, contains('_pendingCheckouts.clear();'));
    final open = methodBody(src, 'Future<void> openCheckout({');
    expect(open, isNot(contains('_pendingCheckouts.clear()')));
  });

  test('P4 every end-date estimate carries the captured stacks-after', () {
    expect(src, isNot(contains('_computeEndDate')));
    final calls = RegExp(r'estimatePaidEndDate\(([^;]*?)\)').allMatches(src);
    expect(calls.length, 3);
    for (final c in calls) {
      expect(c.group(1), contains('stacksAfter: stacksAfter'),
          reason: c.group(0));
    }
    // The two server-reply fallbacks go through the captured closure.
    expect(
        RegExp(r'\? endDate : fallbackEndDate\(plan\)').allMatches(src).length,
        2);
  });

  test('P5 openCheckout records the parsed value under the order id and '
      'passes it to the options', () {
    final open = methodBody(src, 'Future<void> openCheckout({');
    expect(
        RegExp(r"stacksAfter = parseStacksAfter\(data\['stacks_after'\]")
            .hasMatch(open),
        isTrue);
    expect(
        RegExp(r'_pendingCheckouts\.record\(\s*orderId,\s*PendingCheckout\(plan: plan, stacksAfter: stacksAfter\)\)')
            .hasMatch(open),
        isTrue);
    expect(RegExp(r'notes: notes,\s*stacksAfter: stacksAfter,').hasMatch(open),
        isTrue);
  });

  test('P6 the trial branch keeps the heal', () {
    expect(
        'await _handleAlreadyProResponse('.allMatches(src).length, 4,
        reason: 'two paths x (trial, alreadyPro)');
    expect(
        RegExp(r'_handleAlreadyProResponse\(\w+,\s*trialUpgradeUnavailable: true\)')
            .allMatches(src)
            .length,
        2);
  });

  test('P7 the live 409 path enters only for a classified conflict, and a '
      'trial refusal never falls through to the server text', () {
    expect(
        RegExp(r'final conflict = classifyOrderConflict\(m\);\s*if \(conflict != OrderConflict\.other\) \{\s*try \{\s*if \(conflict == OrderConflict\.trialUpgradeUnavailable\) \{')
            .hasMatch(src),
        isTrue);
    expect(
        src.contains(
            'final trialRefusal = isTrialRefusal(status: status, details: details);'),
        isTrue);
    expect(
        RegExp(r'serverError: trialRefusal\s*\?\s*PaymentCopy\.trialUpgradeUnavailable\s*:\s*_extractServerError\(details\)')
            .hasMatch(src),
        isTrue);
  });

  test('P8 the feedback text comes from orderConflictMessage with the flag',
      () {
    expect(
        RegExp(r'_showAlreadyProFeedback\(orderConflictMessage\(\s*trialUpgradeUnavailable: trialUpgradeUnavailable, endLabel: endLabel\)\)')
            .hasMatch(src),
        isTrue);
  });

  test('P9 the order record is written only for the same signed-in user', () {
    final open = methodBody(src, 'Future<void> openCheckout({');
    expect(
        RegExp(r'if \(SupabaseService\.instance\.currentUser\?\.id == user\.id\) \{\s*_pendingCheckouts\.record\(')
            .hasMatch(open),
        isTrue);
  });
}
