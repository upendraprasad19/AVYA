// Unit tests for scripts/gate_test_ledger_lib.dart — the rule-24 ledger that
// scripts/check_gate_test_ledger.dart enforces.
//
// Pure: no filesystem. File existence and file contents are injected, so every
// branch is reachable deterministically.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/gate_test_ledger_lib.dart';

/// A test file that WOULD satisfy the red-path check, for injection.
const _goodTest = '''
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('check_alpha blocks a violation', () {
    expect(result.exitCode, 1);
  });
}
''';

/// Names the gate but only ever asserts the happy path — the Gate-44 shape.
const _happyPathOnlyTest = '''
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('check_alpha passes on a clean tree', () {
    expect(result.exitCode, 0);
    expect(everything, isNotEmpty);
  });
}
''';

List<LedgerViolation> run(
  String yaml, {
  required Set<String> onDisk,
  Set<String> grandfathered = const {'check_old.dart'},
  Map<String, String> files = const {},
}) =>
    checkLedger(
      ledger: parseLedger(yaml),
      gatesOnDisk: onDisk,
      grandfathered: grandfathered,
      testFileExists: files.containsKey,
      readTestFile: (p) => files[p],
    );

void main() {
  group('parseLedger', () {
    test('reads all three states', () {
      final l = parseLedger('''
check_a.dart:
  grandfathered: 2026-08-10

check_b.dart:
  test_exempt: "Needs a built APK."

check_c.dart:
  mutation_proven: true
  test_path:
    - test/scripts/x_test.dart
    - test/scripts/y_test.dart
  evidence: "Neutering X reddens 4."
''');
      expect(l['check_a.dart']!.state, LedgerState.grandfathered);
      expect(l['check_a.dart']!.grandfatheredDate, '2026-08-10');
      expect(l['check_b.dart']!.state, LedgerState.testExempt);
      expect(l['check_b.dart']!.reason, 'Needs a built APK.');
      expect(l['check_c.dart']!.state, LedgerState.mutationProven);
      expect(l['check_c.dart']!.testPaths, hasLength(2));
      expect(l['check_c.dart']!.evidence, 'Neutering X reddens 4.');
    });

    test('a scalar test_path is accepted as a one-element list', () {
      final l = parseLedger('''
check_c.dart:
  mutation_proven: true
  test_path: test/scripts/x_test.dart
  evidence: "e"
''');
      expect(l['check_c.dart']!.testPaths, ['test/scripts/x_test.dart']);
    });

    test('TWO state keys on one gate is a FormatException', () {
      expect(
        () => parseLedger('''
check_a.dart:
  grandfathered: 2026-08-10
  test_exempt: "also this"
'''),
        throwsA(isA<FormatException>()),
      );
    });

    test('no state key at all is a FormatException', () {
      expect(
        () => parseLedger('check_a.dart:\n  evidence: "orphan"\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('CRLF input parses', () {
      final l = parseLedger('check_a.dart:\r\n  grandfathered: 2026-08-10\r\n');
      expect(l['check_a.dart']!.state, LedgerState.grandfathered);
    });
  });

  group('checkLedger — coverage', () {
    test('a gate on disk with NO ledger entry is a violation', () {
      final v = run('check_old.dart:\n  grandfathered: 2026-08-10\n',
          onDisk: {'check_old.dart', 'check_new.dart'});
      expect(v, isNotEmpty);
      expect(v.single.gate, 'check_new.dart');
      expect(v.single.message, contains('missing from'));
    });

    test('a ledger entry with no script on disk is stale bookkeeping', () {
      final v = run('check_gone.dart:\n  grandfathered: 2026-08-10\n',
          onDisk: <String>{}, grandfathered: {'check_gone.dart'});
      expect(v, isNotEmpty);
      expect(v.single.message, contains('no scripts/'));
    });
  });

  group('checkLedger — the grandfather list is closed BY NAME', () {
    test('a NEW gate writing the magic date does NOT join the list', () {
      // This is the whole point. A date-equality check closes nothing: both
      // gates born in this batch carry 2026-08-10 themselves.
      final v = run('check_new.dart:\n  grandfathered: 2026-08-10\n',
          onDisk: {'check_new.dart'}, grandfathered: {'check_old.dart'});
      expect(v, isNotEmpty);
      expect(v.single.message, contains('not on the closed grandfather list'));
    });

    test('a listed gate with the right date passes', () {
      final v = run('check_old.dart:\n  grandfathered: 2026-08-10\n',
          onDisk: {'check_old.dart'});
      expect(v, isEmpty);
    });

    test('a listed gate with a DIFFERENT date is a violation', () {
      final v = run('check_old.dart:\n  grandfathered: 2026-09-01\n',
          onDisk: {'check_old.dart'});
      expect(v, isNotEmpty);
      expect(v.single.message, contains('expected "2026-08-10"'));
    });
  });

  group('checkLedger — mutation_proven', () {
    const yamlOk = '''
check_alpha.dart:
  mutation_proven: true
  test_path:
    - test/scripts/alpha_test.dart
  evidence: "Neutering the X check reddens 3 tests."
''';

    test('a complete, backed claim passes', () {
      final v = run(yamlOk,
          onDisk: {'check_alpha.dart'},
          files: {'test/scripts/alpha_test.dart': _goodTest});
      expect(v, isEmpty);
    });

    test('empty evidence is a violation', () {
      final v = run(
          yamlOk.replaceFirst(
              'evidence: "Neutering the X check reddens 3 tests."',
              'evidence: ""'),
          onDisk: {'check_alpha.dart'},
          files: {'test/scripts/alpha_test.dart': _goodTest});
      expect(v, isNotEmpty);
      expect(v.first.message, contains('non-empty evidence'));
    });

    test('no test_path is a violation', () {
      final v = run('''
check_alpha.dart:
  mutation_proven: true
  evidence: "e"
''', onDisk: {'check_alpha.dart'});
      expect(v, isNotEmpty);
      expect(v.single.message, contains('at least one test_path'));
    });

    test('a test_path that does not exist is a violation', () {
      final v = run(yamlOk, onDisk: {'check_alpha.dart'}, files: const {});
      expect(v, isNotEmpty);
      expect(v.first.message, contains('does not exist'));
    });

    test('a test that never NAMES the gate is a violation', () {
      final v = run(yamlOk, onDisk: {'check_alpha.dart'}, files: {
        'test/scripts/alpha_test.dart':
            "void main() { expect(r.exitCode, 1); }",
      });
      expect(v, isNotEmpty);
      expect(v.first.message, contains('references this gate by name'));
    });

    test('a HAPPY-PATH-ONLY test is a violation — the Gate-44 shape', () {
      // The single most important assertion in this file. The test names the
      // gate and exists; it just never proves the gate can FAIL.
      final v = run(yamlOk, onDisk: {'check_alpha.dart'}, files: {
        'test/scripts/alpha_test.dart': _happyPathOnlyTest,
      });
      expect(v, isNotEmpty);
      expect(v.first.message, contains('red-path assertion'));
    });
  });

  group('containsRedPathAssertion', () {
    test('accepts the exit-code family', () {
      expect(containsRedPathAssertion('expect(r.exitCode, 1);'), isTrue);
      expect(containsRedPathAssertion('expect(r.exitCode, isNot(0));'), isTrue);
      expect(containsRedPathAssertion('expect(r.exitCode, isNonZero);'), isTrue);
    });

    test('accepts the findings-collection family (pure lib tests)', () {
      expect(containsRedPathAssertion('expect(violations, isNotEmpty);'), isTrue);
      expect(containsRedPathAssertion('expect(collisions, hasLength(1));'), isTrue);
    });

    test('REJECTS bare isNotEmpty — it appears in hundreds of unrelated asserts',
        () {
      // Accepting it would make this check pass for almost any file, which is
      // the Gate-44 failure wearing a different hat.
      expect(containsRedPathAssertion('expect(names, isNotEmpty);'), isFalse);
    });

    test('REJECTS a green-only exit assertion', () {
      expect(containsRedPathAssertion('expect(r.exitCode, 0);'), isFalse);
    });
  });
}
