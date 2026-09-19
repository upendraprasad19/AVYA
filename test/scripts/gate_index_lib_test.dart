// Pure unit tests for scripts/gate_index_lib.dart.
//
// Every exclusion below is asserted AGAINST ITS TRUE CAUSE. An earlier draft of
// the rationale claimed the end-anchor excluded `// Gate: confirms docs/adr/…`;
// it does not (`\d+` does), and a test written from that draft would have
// encoded a false proposition and passed for the wrong reason.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/gate_index_lib.dart';

void main() {
  group('parseCanonicalGateNumber — accepts', () {
    test('the canonical form on its own line', () {
      expect(parseCanonicalGateNumber('// Gate: 44\n'), '44');
    });

    test('a letter-suffixed number (14b exists in this repo)', () {
      expect(parseCanonicalGateNumber('// Gate: 14b\n'), '14b');
    });

    test('the declaration anywhere inside the header window', () {
      final filler = List.filled(9, '// filler').join('\n');
      expect(parseCanonicalGateNumber('$filler\n// Gate: 7\n'), '7');
    });
  });

  group('parseCanonicalGateNumber — rejects, each for its true reason', () {
    test('`// Gate: confirms …` — rejected by \\d+, NOT the end anchor', () {
      // Verbatim from check_adr_index_fresh.dart:1. A regex that dropped the
      // end anchor but kept \d+ would STILL reject this, which is exactly why
      // naming the end anchor as the cause was wrong.
      const line = '// Gate: confirms docs/adr/INDEX.md is up-to-date.\n';
      expect(parseCanonicalGateNumber(line), isNull);
      // Prove the cause: the same text with a digit in that slot is accepted.
      expect(parseCanonicalGateNumber('// Gate: 3\n'), '3');
    });

    test('`// Mirrors Gate 17` — rejected by the START anchor', () {
      expect(parseCanonicalGateNumber('// Mirrors Gate 17\n'), isNull);
    });

    test('`// Gate 44 — title` — rejected by the MISSING COLON', () {
      expect(
        parseCanonicalGateNumber('// Gate 44 — Nested CLAUDE.md quality\n'),
        isNull,
      );
      // Prove the cause: adding the colon and dropping the trailer is accepted.
      expect(parseCanonicalGateNumber('// Gate: 44\n'), '44');
    });

    test('`// Gate: 13 — APK size…` — rejected by the END anchor', () {
      // THIS is the end anchor's actual job.
      expect(parseCanonicalGateNumber('// Gate: 13 — APK size\n'), isNull);
    });

    test('a declaration past the header window', () {
      final filler = List.filled(canonicalWindowLines, '// filler').join('\n');
      expect(parseCanonicalGateNumber('$filler\n// Gate: 99\n'), isNull);
    });
  });

  group('CRLF', () {
    test('a CRLF file still parses — the \\r must not kill the end anchor', () {
      // This repo has zero CRLF files today (.gitattributes eol=lf wins over
      // core.autocrlf=true). Without normalization the failure is SILENT and
      // maximally bad: every declaration reads as absent, so the generator
      // emits an index with zero numbers AND zero collisions — green, and
      // completely wrong.
      expect(parseCanonicalGateNumber('// header\r\n// Gate: 42\r\n'), '42');
    });

    test('normalizeNewlines strips \\r\\n only', () {
      expect(normalizeNewlines('a\r\nb'), 'a\nb');
      expect(normalizeNewlines('a\nb'), 'a\nb');
    });
  });

  group('extractPurpose', () {
    test('skips the filename line, blank comments, and the declaration', () {
      const src = '// scripts/check_foo.dart\n'
          '//\n'
          '// Gate: 12\n'
          '//\n'
          '// Edge function payload contracts.\n';
      expect(extractPurpose(src, 'check_foo.dart'),
          'Edge function payload contracts.');
    });

    test('strips a leading "Gate N —" so it does not restate the number', () {
      const src = '// scripts/check_foo.dart\n'
          '//\n'
          '// Gate 19 — Hive Map field-key drift detector\n';
      expect(extractPurpose(src, 'check_foo.dart'),
          'Hive Map field-key drift detector');
    });

    test('a line consumed to bare punctuation does NOT become the purpose', () {
      // B-pass P2-1. `_purposeStrip` eats "Gate (Track 2 of the … batch)"
      // leaving only ".", which a bare isEmpty check accepted — and the blank
      // comment line right after then ended the loop, so the real description
      // never surfaced. Two of 87 real rows rendered as a lone "." before this.
      // Verbatim shape from check_blast_radius_coverage.dart:1-5.
      const src = '// scripts/check_blast_radius_coverage.dart\n'
          '//\n'
          '// Gate (Track 2 of the six-industry-gap closure batch).\n'
          '//\n'
          '// Asserts that every top-level directory under lib/features/ is covered.\n';
      final p = extractPurpose(src, 'check_blast_radius_coverage.dart');
      expect(p, isNot('.'));
      expect(p, contains('Asserts that every top-level directory'));
    });

    test('falls back rather than throwing on a header-less file', () {
      expect(extractPurpose('void main() {}\n', 'check_foo.dart'),
          '(no header description)');
    });
  });

  group('parseBuildApk', () {
    test('maps a section to the first script it runs', () {
      const md = '### Gate 7 — SoT registry completeness\n'
          '```bash\ndart run scripts/check_sot_registry_completeness.dart\n```\n';
      final r = parseBuildApk(md);
      expect(r.claims, hasLength(1));
      expect(r.claims.single.script, 'check_sot_registry_completeness.dart');
      expect(r.claims.single.number, '7');
      expect(r.reserved, isEmpty);
    });

    test('a section with NO script is a reserved procedural number', () {
      const md = '### Gate 3.5 — Discipline-CI green on main\n'
          'echo checking...\n'
          '### Gate 7 — SoT\n'
          'dart run scripts/check_sot_registry_completeness.dart\n';
      final r = parseBuildApk(md);
      expect(r.reserved, contains('3.5'));
      expect(r.claims.single.number, '7');
    });
  });

  group('parseLedgerMints — BOTH orders', () {
    test('forward: `scripts/x.dart (Gate 45`', () {
      // Verbatim shape from 2026_05_20_audit_closures.yaml:632 — the ONLY
      // claim Gate 45 has anywhere in the repo.
      const y = 'verification: scripts/check_no_http_package.dart '
          '(Gate 45, hard-fail)';
      final c = parseLedgerMints(y, 'ledger.yaml');
      expect(c, hasLength(1));
      expect(c.single.script, 'check_no_http_package.dart');
      expect(c.single.number, '45');
    });

    test('reverse: `Gate 42 (x.dart)`', () {
      // Verbatim shape from oi_unit1_backlog.closure.yaml:70. A one-form regex
      // is how Gate 45 and Gate 7 stayed invisible through five surveys.
      const y = 'Gate 42 (check_sot_behavioral_test_paths.dart) PASS';
      final c = parseLedgerMints(y, 'ledger.yaml');
      expect(c, hasLength(1));
      expect(c.single.script, 'check_sot_behavioral_test_paths.dart');
      expect(c.single.number, '42');
    });

    test('backtick-wrapped script names are matched', () {
      const y = '`check_doc_internal_consistency.dart` (Gate 18, L25)';
      final c = parseLedgerMints(y, 'closed_issues.md');
      expect(c.single.script, 'check_doc_internal_consistency.dart');
      expect(c.single.number, '18');
    });

    test('prose mentioning a gate number without a script mints nothing', () {
      expect(parseLedgerMints('Gate 40 PASS — 11 entries', 'l.yaml'), isEmpty);
    });
  });

  group('findCollisions', () {
    GateClaim claim(String script, String number,
            [ClaimSource s = ClaimSource.header]) =>
        GateClaim(script: script, number: number, source: s, origin: 'o');

    test('two distinct scripts on one number collide', () {
      final c = findCollisions([claim('a.dart', '19'), claim('b.dart', '19')]);
      expect(c, hasLength(1));
      expect(c.single.number, '19');
      expect(c.single.scripts, {'a.dart', 'b.dart'});
    });

    test('THREE scripts on one number is one collision naming all three', () {
      final c = findCollisions([
        claim('a.dart', '18'),
        claim('b.dart', '18'),
        claim('c.dart', '18'),
      ]);
      expect(c, hasLength(1));
      expect(c.single.scripts, hasLength(3));
    });

    test('the SAME script claiming a number from 3 sources is NOT a collision',
        () {
      // The real corpus does this constantly: header + build-apk.md + ledger
      // all name the same script. Counting sources instead of distinct scripts
      // would manufacture collisions everywhere.
      final c = findCollisions([
        claim('a.dart', '7', ClaimSource.header),
        claim('a.dart', '7', ClaimSource.buildApk),
        claim('a.dart', '7', ClaimSource.ledger),
      ]);
      expect(c, isEmpty);
    });

    test('14 and 14b do not collide', () {
      expect(findCollisions([claim('a.dart', '14'), claim('b.dart', '14b')]),
          isEmpty);
    });

    test('collisions are ordered numerically, not lexically', () {
      final c = findCollisions([
        claim('a.dart', '44'), claim('b.dart', '44'),
        claim('c.dart', '7'), claim('d.dart', '7'),
        claim('e.dart', '19'), claim('f.dart', '19'),
      ]);
      expect(c.map((x) => x.number).toList(), ['7', '19', '44']);
    });
  });

  group('findDisagreements', () {
    test('one script given different numbers by its sources', () {
      final d = findDisagreements([
        GateClaim(
            script: 'a.dart',
            number: '23',
            source: ClaimSource.buildApk,
            origin: 'build-apk.md'),
        GateClaim(
            script: 'a.dart',
            number: '53',
            source: ClaimSource.header,
            origin: 'a.dart'),
      ]);
      expect(d, hasLength(1));
      expect(d.single.script, 'a.dart');
    });

    test('agreement across sources is not a disagreement', () {
      final d = findDisagreements([
        GateClaim(
            script: 'a.dart',
            number: '7',
            source: ClaimSource.buildApk,
            origin: 'b'),
        GateClaim(
            script: 'a.dart', number: '7', source: ClaimSource.header, origin: 'a'),
      ]);
      expect(d, isEmpty);
    });
  });

  group('findReservedConflicts', () {
    test('a script minting a reserved procedural number is a conflict', () {
      final r = findReservedConflicts([
        GateClaim(
            script: 'a.dart', number: '5', source: ClaimSource.header, origin: 'a')
      ], {'1', '2', '3', '3.5', '4', '5', '6'});
      expect(r, hasLength(1));
    });

    test('3.5 is compared as a STRING — parsing it as an int loses it', () {
      final r = findReservedConflicts([
        GateClaim(
            script: 'a.dart',
            number: '3.5',
            source: ClaimSource.header,
            origin: 'a')
      ], {'3.5'});
      expect(r, hasLength(1), reason: 'int.parse("3.5") throws / truncates to 3');
    });

    test('a normal gate number is not a reserved conflict', () {
      final r = findReservedConflicts([
        GateClaim(
            script: 'a.dart', number: '42', source: ClaimSource.header, origin: 'a')
      ], {'1', '2', '3', '3.5', '4', '5', '6'});
      expect(r, isEmpty);
    });
  });

  group('nextFreeNumber', () {
    test('skips both claimed and reserved numbers', () {
      final claims = [
        GateClaim(
            script: 'a.dart', number: '1', source: ClaimSource.header, origin: 'a'),
        GateClaim(
            script: 'b.dart', number: '3', source: ClaimSource.header, origin: 'b'),
      ];
      expect(nextFreeNumber(claims, {'2'}), 4);
    });

    test('a letter suffix occupies its base integer', () {
      final claims = [
        GateClaim(
            script: 'a.dart',
            number: '1b',
            source: ClaimSource.header,
            origin: 'a'),
      ];
      expect(nextFreeNumber(claims, {}), 2);
    });
  });
}
