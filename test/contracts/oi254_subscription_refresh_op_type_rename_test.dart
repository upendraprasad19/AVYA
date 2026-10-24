// OI-254 closure (B2a-2b, diagnose — see docs/diagnoses/).
//
// Migration 147's alert_client_errors_spike `cnt` metric deliberately does
// NOT filter out event/info-coded rows (that guard would regress migration
// 087/f0b9d3's own P0 fix — see
// test/contracts/ops_alerts_spike_breadth_test.dart's "cnt is DELIBERATELY
// NOT scoped..." test). That means `cnt` inherits the outer
// breadcrumb-reinclusion regex
// `(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)`,
// which a self-triggered B-pass (docs/reviews/46c9b9ff3bde-review.md,
// finding 1) found ALSO swept in the routine, expected
// "no active subscription row" outcome purely because its old name ended
// in `_null` — not because it is an anomaly. The real fix, per that
// review, is a CLIENT-side rename (not a SQL patch): this test pins it.
//
// Writer: lib/core/services/subscription_service.dart (refreshFromSupabase)
// Reader: alert_client_errors_spike's outer regex (supabase/migrations/
//   147_alert_client_errors_spike_breadth.sql) — this test asserts the NEW
//   name structurally cannot match that regex, closing OI-254 from the
//   client side without touching the immutable migration.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Mirrors migration 147's exact outer op_type reinclusion regex (SQL `~*`,
// case-insensitive) — see supabase/migrations/
// 147_alert_client_errors_spike_breadth.sql, the
// `op_type ~* '(fail|error|crash|fallback|unknown|exception|timeout|denied|
// _null)'` clause. Kept as a literal string (not imported) because this is
// SQL text, not Dart — the parity is proven by re-deriving both sides from
// the migration file below, not by trusting this copy alone.
final RegExp _failureShapedOpTypeRegex = RegExp(
  r'(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)',
  caseSensitive: false,
);

void main() {
  late final String subscriptionServiceSrc;
  late final String registrySrc;
  late final String migration147;

  setUpAll(() {
    subscriptionServiceSrc =
        File('lib/core/services/subscription_service.dart').readAsStringSync();
    registrySrc = File('docs/sot_registry.yaml').readAsStringSync();
    migration147 = File(
      'supabase/migrations/147_alert_client_errors_spike_breadth.sql',
    ).readAsStringSync();
  });

  test('migration 147 still carries the exact regex this test mirrors '
      '(parity guard — if this fails, update _failureShapedOpTypeRegex '
      'above to match, then re-verify the assertions below)', () {
    expect(
      migration147.contains(
        r"op_type ~* '(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)'",
      ),
      isTrue,
      reason: 'the regex this test mirrors must still be the live one — '
          'an applied migration is immutable, so this should never drift, '
          'but a FUTURE migration replacing 147 could change it',
    );
  });

  test('subscription_service.dart no longer EMITS the old, regex-matching '
      'op_type name (a documentation reference explaining the rename is '
      'fine — this checks the actual logEvent call site, not the whole '
      'file)', () {
    expect(
      subscriptionServiceSrc.contains(
        "ErrorTelemetry.logEvent(\n            'subscription_refresh_query_returned_null')",
      ),
      isFalse,
      reason: 'OI-254: the old name matched the failure-shaped regex via '
          'its "_null" suffix despite describing a routine, expected '
          'state (no active subscription row) — the EMITTING call site '
          'must use the new name, not just be documented as renamed',
    );
  });

  test('subscription_service.dart emits the new op_type name at the '
      'no-active-row branch', () {
    expect(
      subscriptionServiceSrc.contains(
        "ErrorTelemetry.logEvent(\n            'subscription_refresh_no_active_row')",
      ),
      isTrue,
      reason: 'the no-active-row branch (refreshFromSupabase, response == '
          'null) must emit the renamed op_type',
    );
  });

  test('the new op_type name structurally CANNOT match migration 147\'s '
      'failure-shaped reinclusion regex — this is what actually closes '
      'OI-254 (mutation-proven: reverting to the old name reddens this)',
      () {
    const newName = 'subscription_refresh_no_active_row';
    expect(
      _failureShapedOpTypeRegex.hasMatch(newName),
      isFalse,
      reason: 'the whole point of the rename is that the alert can no '
          'longer sweep this event in via the outer regex; a name '
          'containing any of fail/error/crash/fallback/unknown/exception/'
          'timeout/denied/_null would reopen OI-254',
    );
    // Positive control — the regex DOES match the old name, proving this
    // assertion is not vacuously true for any string.
    expect(
      _failureShapedOpTypeRegex
          .hasMatch('subscription_refresh_query_returned_null'),
      isTrue,
      reason: 'positive control: the OLD name must match (via "_null") — '
          'if this ever fails, the regex constant above has drifted from '
          'migration 147 and the test above is no longer meaningful',
    );
  });

  test('docs/sot_registry.yaml failure_op_types reflects the rename', () {
    expect(
      registrySrc.contains(
        'failure_op_types: [subscription_refresh_grace_skip, '
        'subscription_refresh_expired_state, '
        'subscription_refresh_no_active_row]',
      ),
      isTrue,
      reason: 'the subscription_payment_grace_window SoT entry\'s '
          'documented telemetry op_types must stay in sync with the '
          'actual emitter',
    );
    expect(
      registrySrc.contains('subscription_refresh_query_returned_null'),
      isFalse,
      reason: 'no stale reference to the old op_type name should remain '
          'in the registry',
    );
  });
}
