// test/scripts/safe_wrapper_not_piped_lib_test.dart
//
// Unit tests for the pure logic behind scripts/check_safe_wrapper_not_piped.dart
// (scripts/safe_wrapper_not_piped_lib.dart). Pure, no I/O.
//
// Mutation proof (re-run directly by the coordinating session, not the
// building fork, which reported a stale/wrong test count — see
// docs/audit/gate_test_ledger.yaml): neutering isPipedThroughHeadOrTail to
// always return false reddens both BAD-case tests, 2 of 6 total. Reverted;
// 6/6 green.

import 'package:flutter_test/flutter_test.dart';
import '../../scripts/safe_wrapper_not_piped_lib.dart';

void main() {
  group('isPipedThroughHeadOrTail', () {
    test('BAD: safe_push.sh piped through tail', () {
      final isViolation =
          isPipedThroughHeadOrTail('sh scripts/safe_push.sh | tail -25');
      expect(isViolation, isTrue);
    });

    test('BAD: safe_commit.sh piped through head', () {
      expect(
          isPipedThroughHeadOrTail(
              'sh scripts/safe_commit.sh "msg" | head -n 10'),
          isTrue);
    });

    test('GOOD mirror: safe_push.sh with no pipe at all (the actual fix)', () {
      expect(isPipedThroughHeadOrTail('sh scripts/safe_push.sh'), isFalse);
    });

    test('GOOD: an UNRELATED pipe precedes the wrapper mention', () {
      expect(
          isPipedThroughHeadOrTail(
              'cat build.log | tail -5 && sh scripts/safe_push.sh "msg"'),
          isFalse);
    });

    test('GOOD: word-boundary — piping into tailwindcss is not `tail`', () {
      expect(
          isPipedThroughHeadOrTail(
              'sh scripts/safe_push.sh "msg" | tailwindcss build'),
          isFalse);
    });

    test('GOOD: wrapper output redirected to a file, then tail reads the file', () {
      expect(
          isPipedThroughHeadOrTail(
              'sh scripts/safe_commit.sh "msg" > log.txt; tail -20 log.txt'),
          isFalse);
    });
  });
}
