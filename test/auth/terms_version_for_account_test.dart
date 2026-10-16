// OI-305 (2026-10-16): the Google / phone consent-fallback stamp must not label
// an account that predates the v2 privacy policy with v2.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/auth_session_bootstrapper.dart';

void main() {
  test('the current version is v2 and v2 took effect at IST midnight of '
      '2026-10-16', () {
    expect(AppConstants.termsVersion, 'v2');
    expect(AppConstants.termsV2EffectiveFromUtc, '2026-10-15T18:30:00Z');
  });

  test('an account created before the v2 policy is stamped v1', () {
    expect(
      AuthSessionBootstrapper.termsVersionForAccountCreatedAt(
        '2026-10-15T18:29:59Z',
      ),
      'v1',
    );
    expect(
      AuthSessionBootstrapper.termsVersionForAccountCreatedAt(
        '2026-03-01T10:00:00.000000+00:00',
      ),
      'v1',
    );
  });

  test('an account created at or after the v2 policy is stamped v2', () {
    expect(
      AuthSessionBootstrapper.termsVersionForAccountCreatedAt(
        '2026-10-15T18:30:00Z',
      ),
      'v2',
    );
    expect(
      AuthSessionBootstrapper.termsVersionForAccountCreatedAt(
        '2026-11-02T08:00:00+00:00',
      ),
      'v2',
    );
  });

  test('a missing or unparseable created_at reads as the current version', () {
    expect(AuthSessionBootstrapper.termsVersionForAccountCreatedAt(null), 'v2');
    expect(AuthSessionBootstrapper.termsVersionForAccountCreatedAt(''), 'v2');
    expect(
      AuthSessionBootstrapper.termsVersionForAccountCreatedAt('not a date'),
      'v2',
    );
  });

  // Round-2 lens A (P2): the pure function above is only half the protection.
  // Reverting the two call-site lines to AppConstants.termsVersion (the exact
  // bug this batch prevents) reddened nothing. Comment-stripped source pin of
  // the fallback body: presence of the wiring, absence of the constant.
  test('ensureTermsConsentFallback stamps the version it derives from '
      'created_at, in the cloud update AND the Hive write', () {
    final src = File('lib/core/services/auth_session_bootstrapper.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'//[^\n]*'), '');
    final start = src.indexOf('Future<void> ensureTermsConsentFallback(');
    expect(start, greaterThan(0));
    final end = src.indexOf('\n  }\n', start);
    expect(end, greaterThan(start));
    final body = src.substring(start, end);

    expect(
      body.contains('final version = termsVersionForAccountCreatedAt(stamp);'),
      isTrue,
      reason: 'the version must be derived from the stamped created_at',
    );
    expect(body.contains("'terms_version': version"), isTrue,
        reason: 'the cloud update must write the derived version');
    expect(body.contains("userBox.put('terms_version', version)"), isTrue,
        reason: 'the Hive write must store the derived version');
    expect(body.contains('AppConstants.termsVersion'), isFalse,
        reason: 'the fallback must never stamp the current version blindly');
  });
}
