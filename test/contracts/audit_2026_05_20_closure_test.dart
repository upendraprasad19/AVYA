// test/contracts/audit_2026_05_20_closure_test.dart
//
// B4 deliverable per tech-debt audit 2026-05-20: assert the audit closure
// YAML validates per `scripts/validate_audit_closure.dart` (Gate 40) AND
// per `feedback_no_deferrals_tech_debt_class.md` contains NO `deferred:`
// key.
//
// The closure ledger at `docs/audit/2026_05_20_audit_closures.yaml`
// enumerates every finding ID 1..81. As the audit progresses, findings
// flip from "no terminal state" (open) to one of:
//   - closed_in_commit: <SHA> + verification: <gate or test>
//   - upstream_blocked: <package> + reopen_when: <condition>
//   - verified_clean: <evidence>
//
// This test gates the audit's no-deferrals discipline.

@Timeout(Duration(minutes: 3))
library;

// TIMEOUT RAISED FROM THE 30s DEFAULT (2026-08-13, diagnose 4f2a9e).
// This file spawns real subprocesses (`dart run` / shell), and a cold `dart run`
// costs seconds on its own — VM start plus kernel compile. Under the
// merge-commit regression-catalog walk, which runs ~700 tests concurrently,
// those subprocesses take long enough to blow the 30s PER-TEST default, and the
// walk reports failures for tests that pass standalone every time. Measured: one
// such file takes 33s wall with ZERO contention.
// Applied to the whole subprocess-spawning class, not only the files observed
// failing — fixing just the observed instances is what let this recur twice.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audit 2026-05-20 closure YAML validates (Gate 40)', () async {
    final result = await Process.run(
      'dart',
      ['run', 'scripts/validate_audit_closure.dart',
          'docs/audit/2026_05_20_audit_closures.yaml'],
      runInShell: true,
    );
    expect(
      result.exitCode,
      equals(0),
      reason: 'Gate 40 must PASS — closure YAML schema-valid + no `deferred:` key. '
          'stderr: ${result.stderr}\nstdout: ${result.stdout}',
    );
  });

  test('closure YAML contains no `deferred:` key (feedback_no_deferrals_tech_debt_class)', () {
    final content = File('docs/audit/2026_05_20_audit_closures.yaml')
        .readAsStringSync();
    // Strip YAML comments (anything after `#`) before scanning.
    final lines = content.split('\n');
    final nonCommentLines = lines.map((l) {
      final hashIdx = l.indexOf('#');
      return hashIdx < 0 ? l : l.substring(0, hashIdx);
    }).join('\n');

    final hits = RegExp(r'^\s*deferred\s*:', multiLine: true)
        .allMatches(nonCommentLines);
    expect(hits.length, equals(0),
        reason: 'NO `deferred:` key permitted in audit closure YAML per '
            'feedback_no_deferrals_tech_debt_class.md. Use terminal_state: '
            'closed_in_commit | upstream_blocked | verified_clean.');
  });

  test('closure YAML enumerates expected total_findings', () {
    final content = File('docs/audit/2026_05_20_audit_closures.yaml')
        .readAsStringSync();
    final match = RegExp(r'^total_findings:\s*(\d+)', multiLine: true)
        .firstMatch(content);
    expect(match, isNotNull,
        reason: 'closure YAML must declare `total_findings: <N>`.');
    final count = int.parse(match!.group(1)!);
    expect(count, equals(81),
        reason: 'audit 2026-05-20 surfaced 81 findings; '
            'closure must enumerate all of them.');
  });
}
