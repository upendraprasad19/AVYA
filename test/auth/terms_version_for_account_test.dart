// OI-305 (2026-10-16): the Google / phone consent-fallback stamp must not label
// an account that predates the v2 privacy policy with v2.
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
}
