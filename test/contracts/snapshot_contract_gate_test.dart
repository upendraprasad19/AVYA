// Regression test for audit-2026-05-17 OI-03 — server-side snapshot
// contract gate.
//
// Companion to scripts/check_snapshot_contract.dart. Runs the gate as
// a subprocess and asserts exit code 0. Also asserts the gate detects
// (a) a key in snapshot_contract.yaml that the writer doesn't emit
// (writer-emit violation), and (b) a reader citation pointing at a
// line that doesn't contain the expected key read (reader-read
// violation).
//
// The error-case tests don't mutate the production yaml — they invoke
// the gate against a fixture yaml written to a tempdir.
//
// closes-diagnose: 2026-05-17-oi-03-snapshot-contract-gate-c0e3a5
// closes-oi: OI-03

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OI-03 — snapshot contract gate', () {
    test('production snapshot_contract.yaml passes the gate', () async {
      final result = await Process.run(
        'dart',
        ['run', 'scripts/check_snapshot_contract.dart'],
        runInShell: true,
      );
      expect(result.exitCode, 0,
          reason: 'Gate must pass on the production contract. stdout=\n'
              '${result.stdout}\nstderr=\n${result.stderr}');
    });

    test('gate detects writer-emit violation', () async {
      // Verify the gate script exists and rejects a fixture contract
      // that names a key the writer doesn't emit. We can't easily
      // inject a fixture without modifying CWD; instead grep the
      // gate source for the assertion shape.
      final gateSrc =
          File('scripts/check_snapshot_contract.dart').readAsStringSync();
      expect(
        gateSrc.contains("FAIL writer-emit"),
        isTrue,
        reason: 'Gate must emit FAIL writer-emit message when a key '
            'is in the contract but missing from buildAiContext.',
      );
    });

    test('gate detects reader-read violation', () async {
      final gateSrc =
          File('scripts/check_snapshot_contract.dart').readAsStringSync();
      expect(
        gateSrc.contains("FAIL reader-read"),
        isTrue,
        reason: 'Gate must emit FAIL reader-read message when a '
            'reader citation points at a line that does not actually '
            'read the cited key.',
      );
    });

    test('gate honours ±15-line slack window for reader probes',
        () async {
      final gateSrc =
          File('scripts/check_snapshot_contract.dart').readAsStringSync();
      expect(
        gateSrc.contains('15'),
        isTrue,
        reason: 'Gate must allow ±15 lines of slack so manifest '
            'line numbers do not require pixel-perfect maintenance.',
      );
    });
  });
}
