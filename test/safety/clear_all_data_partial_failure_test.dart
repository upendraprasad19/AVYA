// Test #10.1 — Partial-failure semantics for `UserRepository.clearAllData()`.
//
// Pre-fix bug: `clearAllData()` was sequential `await box.clear()` calls.
// One throwing GuardedBox aborted the whole chain — leaving `configBox`
// (and any boxes ordered after the throw) populated. That stale state
// is exactly what leaked across signOut → signUp.
//
// Post-fix contract: every box.clear() runs inside its own try/catch.
// Failures are collected into `ClearResult.failures` and the caller
// can detect partial failure to escalate (e.g., force-signOut).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

void main() {
  group('ClearResult contract', () {
    test('isClean when failures is empty', () {
      const r = ClearResult(<String, Object>{});
      expect(r.isClean, isTrue);
      expect(r.hasFailures, isFalse);
    });

    test('hasFailures when failures non-empty', () {
      final r = ClearResult({'userBox': StateError('owner mismatch')});
      expect(r.isClean, isFalse);
      expect(r.hasFailures, isTrue);
      expect(r.failedFor('userBox'), isTrue);
      expect(r.failedFor('configBox'), isFalse);
    });

    test('toString shape', () {
      const cleanR = ClearResult(<String, Object>{});
      expect(cleanR.toString(), 'ClearResult(clean)');
      final dirtyR = ClearResult({
        'userBox': Exception('a'),
        'workoutBox': Exception('b'),
      });
      expect(dirtyR.toString(), contains('failures='));
      expect(dirtyR.toString(), contains('userBox'));
      expect(dirtyR.toString(), contains('workoutBox'));
    });
  });
}
