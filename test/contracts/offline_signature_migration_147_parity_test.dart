// Offline-noise signature parity (B2a-2b, diagnose — see docs/diagnoses/).
//
// Writer: supabase/migrations/147_alert_client_errors_spike_breadth.sql
//   (the alert_client_errors_spike job's offline-noise exclusion clause —
//   immutable once applied; read-only reference here, never edited).
// Reader: lib/core/services/sync_error.dart (isOfflineNoiseSignature,
//   SyncError.isOfflineNoise) — the client-side mirror of the SAME
//   classification, so the two sides agree on what counts as offline noise.
//
// The critical, easy-to-get-wrong detail this test exists to pin: migration
// 147's exclusion has THREE regex clauses and only TWO of them are
// case-insensitive. The signature (network-loss phrases) and the status
// override (`status(Code)?: ?[1-9][0-9]{2}`) use SQL's `~*` (case-insensitive).
// The exception-type override (`PostgrestException|FunctionsHttpException|
// FunctionsRelayException|AuthApiException`) uses plain `~` (case-SENSITIVE).
// A Dart mirror that makes all three case-insensitive would silently treat a
// lowercased exception name as a real server answer when the SQL would not —
// classifying differently than the alert it exists to mirror.

import 'dart:io';

import 'package:icanbefitter/core/services/sync_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late final String migration147;

  setUpAll(() {
    migration147 = File(
      'supabase/migrations/147_alert_client_errors_spike_breadth.sql',
    ).readAsStringSync();
  });

  group('parity guard — migration 147 still carries the exact regex '
      'literals this file mirrors (if any of these fail, migration 147 '
      'has been read incorrectly or a NEW migration replaced it — update '
      'the Dart mirror in lib/core/services/sync_error.dart to match, '
      'then re-verify every assertion below)', () {
    test('signature regex literal (case-insensitive ~*)', () {
      expect(
        migration147.contains(
          r"~* '(failed host lookup|socketexception|connection (refused|reset|closed|abort)|network is unreachable|software caused connection abort|failed to fetch|load failed|xmlhttprequest error)'",
        ),
        isTrue,
      );
    });

    test('status-override regex literal (case-insensitive ~*)', () {
      expect(
        migration147.contains(r"~* 'status(Code)?: ?[1-9][0-9]{2}'"),
        isTrue,
      );
    });

    test('type-override regex literal (case-SENSITIVE ~, not ~*)', () {
      // Deliberately match the bare ` ~ '...'` form (single tilde, no `*`)
      // to distinguish it from the other two clauses' `~*` — a naive
      // `contains` on just the alternation would also match if this
      // clause were accidentally changed to `~*`.
      expect(
        migration147.contains(
          r"~ '(PostgrestException|FunctionsHttpException|FunctionsRelayException|AuthApiException)'",
        ),
        isTrue,
      );
      expect(
        migration147.contains(
          r"~* '(PostgrestException|FunctionsHttpException|FunctionsRelayException|AuthApiException)'",
        ),
        isFalse,
        reason: 'this clause must stay case-SENSITIVE (~) — if it now '
            'reads ~* (case-insensitive), the Dart mirror\'s '
            'caseSensitive:true on _offlineNoiseTypeOverride is stale '
            'and must be relaxed to match',
      );
    });
  });

  group('isOfflineNoiseSignature — mirrors migration 147\'s exclusion '
      'exactly', () {
    test('a bare connectivity-loss message IS offline noise (signature '
        'matches, no override)', () {
      expect(
        isOfflineNoiseSignature('SocketException: Failed host lookup'),
        isTrue,
      );
      expect(
        isOfflineNoiseSignature('Connection refused'),
        isTrue,
      );
      expect(
        isOfflineNoiseSignature('Connection reset by peer'),
        isTrue,
      );
      expect(
        isOfflineNoiseSignature('Network is unreachable'),
        isTrue,
      );
    });

    test('a connectivity-loss message WITH a real HTTP status code is NOT '
        'offline noise (status override cancels it)', () {
      expect(
        isOfflineNoiseSignature('Connection refused, status: 503'),
        isFalse,
      );
      expect(
        isOfflineNoiseSignature('Failed to fetch (statusCode: 500)'),
        isFalse,
      );
    });

    test('a connectivity-loss message WITH a server-answered exception '
        'type is NOT offline noise (type override cancels it)', () {
      expect(
        isOfflineNoiseSignature(
          'PostgrestException: Failed host lookup during retry',
        ),
        isFalse,
      );
      expect(
        isOfflineNoiseSignature(
          'FunctionsHttpException: connection reset',
        ),
        isFalse,
      );
    });

    test('CASE-SENSITIVITY parity: a LOWERCASED exception-type name does '
        'NOT cancel the signature match — matching migration 147\'s `~` '
        '(case-sensitive) behavior exactly, unlike the other two clauses '
        'which are `~*` (case-insensitive). This is the assertion that '
        'would break if the Dart mirror used caseSensitive:false here.',
        () {
      expect(
        isOfflineNoiseSignature(
          'postgrestexception: connection refused',
        ),
        isTrue,
        reason: 'migration 147\'s type-override clause is case-sensitive '
            '(~, not ~*) — a lowercased exception name does NOT match it, '
            'so the message is still classified as offline noise, exactly '
            'as the live SQL would',
      );
    });

    test('a bare timeout is NOT offline noise — migration 147 deliberately '
        'does not exclude client timeouts (undercounting a real incident '
        'is worse than occasionally counting a stalled request)', () {
      expect(isOfflineNoiseSignature('Request timeout'), isFalse);
      expect(isOfflineNoiseSignature('TimeoutException after 30s'), isFalse);
    });

    test('an unrelated server-side validation message is NOT offline '
        'noise (signature never matches — not just cancelled by an '
        'override)', () {
      expect(
        isOfflineNoiseSignature('duplicate key value violates unique '
            'constraint'),
        isFalse,
      );
    });
  });

  group('SyncError.isOfflineNoise getter', () {
    test('null-safe: an error with no message is never offline-noise-shaped',
        () {
      final err = UnknownError(at: DateTime.now());
      expect(err.message, isNull);
      expect(err.isOfflineNoise, isFalse);
    });

    test('a NetworkError built from a real connectivity-loss message IS '
        'offline noise', () {
      final err = NetworkError(
        message: 'SocketException: Failed host lookup',
        at: DateTime.now(),
      );
      expect(err.isOfflineNoise, isTrue);
    });

    test('a NetworkError built from a bare timeout message is NOT offline '
        'noise — NetworkError classification and offline-noise '
        'classification answer DIFFERENT questions (a timeout is '
        'transient/retryable per isTransient, but not "offline" per '
        'migration 147\'s signature)', () {
      final err = NetworkError(
        message: 'TimeoutException after 30s',
        at: DateTime.now(),
      );
      expect(err.isTransient, isTrue);
      expect(err.isOfflineNoise, isFalse);
    });
  });
}
