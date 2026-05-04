import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for Bug A's silent-swallow class.
///
/// _ensureLocalUser previously caught all errors with just debugPrint,
/// hiding 23505/23503 violations for 48h. This test pins the requirement
/// that errors get logged to `client_errors` so they're visible.
void main() {
  test('_ensureLocalUser logs errors to client_errors edge function', () {
    final source = File(
      'lib/features/auth/providers/auth_provider.dart',
    ).readAsStringSync();

    // Find the _ensureLocalUser method body
    final ensureStart = source.indexOf('Future<void> _ensureLocalUser(');
    expect(ensureStart, isNot(-1),
        reason: '_ensureLocalUser must exist on AuthNotifier');

    // The method runs from declaration to the next top-level method
    // declaration. Test #10.1 — bumped to 8000 chars because the
    // verify-after-clear + UserConfigMigrator block added ~50 lines.
    final body = source.substring(
      ensureStart,
      (ensureStart + 8000).clamp(0, source.length),
    );

    // Must call log-client-error Edge Function on catch path
    expect(
      body.contains('log-client-error'),
      isTrue,
      reason:
          '_ensureLocalUser catch blocks must call the log-client-error '
          'Edge Function so silent FK / UNIQUE violations show up in '
          'client_errors. Bug A hid for 48h because of silent swallow.',
    );

    // Must check for Postgres error codes 23505/23503 explicitly so the
    // error type is preserved in the log payload.
    expect(
      body.contains('23505') || body.contains('23503'),
      isTrue,
      reason:
          'Catch path should detect 23505 (unique_violation) and '
          '23503 (foreign_key_violation) so the AI-readable error_type '
          'is correct.',
    );
  });
}
