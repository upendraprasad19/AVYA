import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #12.5 / Class 5b — pin the 409 already_pro catch path.
///
/// **History:** APK 12.4 install (2026-05-06) showed founder a generic
/// "Couldn't start payment. Check your connection..." toast when
/// tapping GO PRO, even though the server correctly returned 409 with
/// `error_code: 'already_pro'`. Root cause: `supabase_flutter ^2.12.0`'s
/// `client.functions.invoke()` THROWS `FunctionException` for non-2xx
/// responses, so the existing `if (resp.status == 409)` branch in the
/// try block was DEAD CODE. The fix moves the 409 detection into the
/// catch block, parsing `e.status` + `e.details['error_code']`.
///
/// These tests guard against regression — if someone refactors the
/// catch block back to a generic catch-all, this test fails noisily
/// before shipping.
void main() {
  late String razorpaySource;

  setUpAll(() {
    final file = File('lib/core/services/razorpay_service.dart');
    expect(file.existsSync(), isTrue,
        reason: 'razorpay_service.dart must exist');
    razorpaySource = file.readAsStringSync();
  });

  group('razorpay_service: 409 already_pro handling', () {
    test('imports FunctionException', () {
      expect(razorpaySource, contains('FunctionException'),
          reason:
              'Must import FunctionException from supabase_flutter to detect '
              '409 responses (which throw, not return resp.status=409).');
    });

    test('catch block detects FunctionException with status 409', () {
      // The detection pattern: `e is FunctionException` + `status == 409`.
      expect(razorpaySource, contains('e is FunctionException'),
          reason: 'Catch block must check for FunctionException type');
      expect(razorpaySource, contains('status == 409'),
          reason: 'Catch block must check for status == 409');
    });

    test('catch block routes 409 already_pro through _handleAlreadyProResponse',
        () {
      // Ensures the catch path reaches the same handler the (now dead)
      // try-block path called.
      expect(razorpaySource, contains("'already_pro'"),
          reason:
              'Must check error_code == "already_pro" inside FunctionException details');
      expect(razorpaySource, contains('_handleAlreadyProResponse'),
          reason: 'Must invoke shared handler so try + catch paths agree');
    });

    test('_handleAlreadyProResponse writes server-truth state locally', () {
      // The handler must call writeSubscriptionState — that's how local
      // PRO state gets unlocked when server says we're already PRO.
      final idx = razorpaySource.indexOf('_handleAlreadyProResponse');
      expect(idx, greaterThan(0));
      // Method body lives below the declaration; check the method name
      // is followed by writeSubscriptionState within reasonable distance.
      final body = razorpaySource.substring(idx);
      expect(body, contains('writeSubscriptionState'),
          reason:
              'PRO toast must write isPro=true to local Hive — reading server truth and discarding it would break the unlock.');
      expect(body, contains('clearPaymentInFlight'),
          reason:
              'Must clear payment grace window so subsequent refreshes behave normally.');
    });

    test('order failure toast surfaces server error when available', () {
      // Class 2b — toast shouldn't always say "Check your connection".
      // When the server returns an actionable error message, surface it.
      final idx = razorpaySource.indexOf('_showOrderCreationFailure');
      expect(idx, greaterThan(0));
      final body = razorpaySource.substring(idx);
      expect(body, contains('serverError'),
          reason: 'Method must accept and surface server-supplied error text');
    });

    test('extractServerError filters Internal server error noise', () {
      // We don't want to surface the generic "Internal server error" since
      // it's no more useful than the stock toast. Skip those.
      expect(razorpaySource, contains('Internal server error'),
          reason: 'Should explicitly filter out the generic 5xx sentinel');
    });
  });
}
