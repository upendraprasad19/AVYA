// Hermes h6F2 (L40, diagnose e8c3a1) — Postgres echoes the offending row's
// VALUES into its error text (`details: Failing row contains (...)`,
// `Key (col)=(value) already exists.`, `invalid input syntax for type
// uuid: "value"`). PostgrestException.toString() carries that text, and every
// telemetry sink (`client_errors` via log-client-error, Crashlytics) used to
// ship it verbatim — including raw AI-coach chat text from a failed
// `ai_coach_interactions` upsert. [ErrorTelemetry.redactRowValues] is the one
// redactor every sink runs the text through.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

const _secret = 'my knee hurts since the divorce';

void main() {
  group('ErrorTelemetry.redactRowValues', () {
    test('Failing row contains (...) inside a real PostgrestException string',
        () {
      final raw = const PostgrestException(
        message:
            'null value in column "model_used" violates not-null constraint',
        code: '23502',
        details:
            'Failing row contains (c0ffee, u1, in_app_orphan, , $_secret, null).',
        hint: null,
      ).toString();
      expect(raw, contains(_secret), reason: 'fixture must carry the value');

      final out = ErrorTelemetry.redactRowValues(raw);
      expect(out, isNot(contains(_secret)));
      expect(out, contains('Failing row contains (<redacted>)'));
      // The diagnostic parts survive: message, SQLSTATE code, the hint slot.
      expect(out, contains('violates not-null constraint'));
      expect(out, contains('code: 23502'));
      expect(out, contains('hint: null'));
    });

    test('a truncated Failing row (no closing paren) is redacted to the end',
        () {
      // _enqueueTelemetryFailure keeps only 500 chars, so a queued entry can
      // end mid-row; the drain re-sends it through the same redactor.
      const raw = 'PostgrestException(message: x, code: 23514, details: '
          'Failing row contains (id-1, u1, $_secret and more text that got cut';
      final out = ErrorTelemetry.redactRowValues(raw);
      expect(out, isNot(contains(_secret)));
      expect(out, endsWith('Failing row contains (<redacted>)'));
    });

    test('Key (cols)=(values) keeps the column names, drops the values', () {
      final raw = const PostgrestException(
        message: 'duplicate key value violates unique constraint "u_meal"',
        code: '23505',
        details: 'Key (user_id, name)=(u1, $_secret) already exists.',
      ).toString();
      final out = ErrorTelemetry.redactRowValues(raw);
      expect(out, isNot(contains(_secret)));
      expect(out, contains('Key (user_id, name)=(<redacted>) already exists.'));
    });

    test('a Key value that itself contains ")" is redacted whole, up to the '
        'structural suffix', () {
      const raw = 'details: Key (name)=(a) b) is not present in table "t".';
      final out = ErrorTelemetry.redactRowValues(raw);
      expect(out, isNot(contains('a) b')));
      expect(out, contains('Key (name)=(<redacted>) is not present'));
    });

    test('invalid input syntax for type X: "value" drops the value', () {
      final raw = const PostgrestException(
        message: 'invalid input syntax for type uuid: "$_secret"',
        code: '22P02',
      ).toString();
      final out = ErrorTelemetry.redactRowValues(raw);
      expect(out, isNot(contains(_secret)));
      expect(out, contains('invalid input syntax for type uuid: "<redacted>"'));
      expect(out, contains('code: 22P02'));
    });

    test('text with no row values passes through byte-identical', () {
      const raw = 'PostgrestException(message: permission denied for table '
          'x, code: 42501, details: null, hint: null)';
      expect(ErrorTelemetry.redactRowValues(raw), raw);
      expect(ErrorTelemetry.redactRowValues('SocketException: timed out'),
          'SocketException: timed out');
    });
  });
}
