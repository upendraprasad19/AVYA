// test/scripts/sync_resolver_checks_test.dart
//
// The three checks that stand between the record merge and `git add` (docs/plans/sync-resolver.md
// section 4.4): V-a line counts, V-b agreement with git outside its conflict hunks, V-c emitter
// fidelity. Each is tested on the case it can catch, and its documented blind spots and false
// positives are PINNED as expected outcomes so that a later "fix" is a conscious change.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/sync_resolver_lib.dart';
import '../helpers/sync_resolver_fixtures.dart';

final FileSpec _oiSpec = specOf('docs/audit/open_issues.md');
final FileSpec _regSpec = specOf('docs/sot_registry.yaml');
final FileSpec _migSpec = specOf('backups/applied_migrations.json');

void main() {
  final base = board([oi(1), oi(2)]);

  group('V-a, line counts (checkCounts)', () {
    test('a correct merge passes', () {
      expect(checkCounts(base, board([oi(1), oi(2), oi(3)]), board([oi(1), oi(2), oi(4)]), board([oi(1), oi(2), oi(4), oi(3)])), isEmpty);
    });

    test('FAILS on a dropped line that is unique to a changed record', () {
      final ours = board([oi(1), oi(2, body: '- **Status**: CLOSED')]);
      final out = board([oi(1), '## OI-2 — probe\n\n\n']);
      final bad = checkCounts(base, ours, base, out);
      expect(bad, hasLength(1));
      expect(bad.single, contains('CLOSED'));
    });

    test('FAILS on a duplicated record', () {
      expect(checkCounts(base, base, base, board([oi(1), oi(2), oi(2)])), isNotEmpty);
    });

    test('FAILS on a dropped UNCHANGED record', () {
      expect(checkCounts(base, base, base, board([oi(1)])), isNotEmpty);
    });

    test('FAILS on a RESURRECTED deletion (a record one side deleted and the other left alone, kept)', () {
      final ours = board([oi(1)]);
      expect(checkCounts(base, ours, base, board([oi(1)])), isEmpty);
      final bad = checkCounts(base, ours, base, board([oi(1), oi(2)]));
      expect(bad, isNotEmpty);
      expect(bad.first, contains('OI-2'));
    });

    test('FAILS on an output that holds the additions only', () {
      expect(checkCounts(base, board([oi(1), oi(2), oi(3)]), board([oi(1), oi(2), oi(4)]), board([oi(3), oi(4)])), isNotEmpty);
    });

    test('passes a line both sides added, once or twice', () {
      final both = board([oi(1), oi(2), oi(5)]);
      expect(checkCounts(base, both, both, both), isEmpty);
      // two copies are tolerated by the 1-or-2 rule (the interval allows the net count)
      expect(checkCounts(base, both, both, board([oi(1), oi(2), oi(5), oi(5)])), isEmpty);
    });

    test('blank-line and trailing-comma differences are not differences', () {
      final b = migrations([migrationEl('001_a')]);
      final o = '[\n${migrationEl('001_a')},\n${migrationEl('002_b')}\n]\n';
      expect(checkCounts(b, o, b, '[\n\n${migrationEl('001_a')},\n\n${migrationEl('002_b')}\n]\n', comma: true), isEmpty);
      expect(checkCounts(b, o, b, '[\n${migrationEl('001_a')},\n${migrationEl('002_b')},\n]\n', comma: true), isEmpty);
    });

    test('FAILS on a deletion by theirs that ours left alone, kept (the exact rule; the bounds alone allow 0..1)', () {
      final theirs = board([oi(1)]);
      expect(checkCounts(base, base, theirs, board([oi(1)])), isEmpty);
      final bad = checkCounts(base, base, theirs, board([oi(1), oi(2)]));
      expect(bad, isNotEmpty);
      expect(bad.first, contains('OI-2'));
      expect(bad.first, contains('expected 0'));
    });

    test('trailing whitespace is not a difference', () {
      expect(checkCounts('a\n', 'a\n', 'a  \n', 'a\n'), isEmpty);
      expect(checkCounts('a\n', 'a  \n', 'a\n', 'a\n'), isEmpty);
    });

    test('PINNED blind spot: a status line shared by two records both sides ADDED can lose one copy undetected', () {
      final o = board([oi(1), oi(2), oi(3)]);
      final t = board([oi(1), oi(2), oi(4)]);
      // the base holds the line twice, each side three times; the right answer is four, two is accepted
      final out = board([oi(1), oi(2), '## OI-4 — probe\n\n', '## OI-3 — probe\n\n- **Status**: OPEN\n\n']);
      expect(checkCounts(base, o, t, out), isEmpty);
    });

    test('PINNED false positive 1: both sides delete one record and each adds a record sharing a line', () {
      final o = board([oi(1), oi(3)]);
      final t = board([oi(1), oi(4)]);
      final right = board([oi(1), oi(4), oi(3)]);
      expect(checkCounts(base, o, t, right), isNotEmpty);
    });

    test('PINNED false positive 2: both sides add the SAME record and ours nets below on a shared line', () {
      final o = board([oi(1), oi(5)]);
      final t = board([oi(1), oi(2), oi(5)]);
      final right = board([oi(1), oi(5)]);
      expect(checkCounts(base, o, t, right), isNotEmpty);
    });

    test('a PARTIAL result: the interval form passes a correct conflicted result and fails a line dropped outside the hunk', () {
      final o = board([oi(1), oi(2), oi(3, title: 'ours')]);
      final t = board([oi(1), oi(2), oi(3, title: 'theirs')]);
      final r = resolveFile(_oiSpec, base: base, ours: o, theirs: t, textMerge: realMerge);
      expect(r.partial, isTrue);
      expect(checkCounts(base, o, t, r.text), isEmpty);
      expect(checkCounts(base, o, t, r.text.replaceFirst('## OI-1 — probe\n', '')), isNotEmpty);
    });

    test('the interval uses the base section of a diff3 hunk NEITHER as ours nor as theirs', () {
      final o = board([oi(1), oi(2, body: '- **Status**: ours')]);
      final t = board([oi(1), oi(2, body: '- **Status**: theirs')]);
      final c = conflictOf(oi(2, body: '- **Status**: ours'), oi(2), oi(2, body: '- **Status**: theirs'));
      final out = board([oi(1), c.text]);
      expect(checkCounts(base, o, t, out), isEmpty);
    });
  });

  group('V-b, agreement with git outside its conflict hunks (checkAgreement)', () {
    final o = board([oi(1, body: '- **Status**: OPEN\n- **Note**: ours edit'), oi(2), oi(3)]);
    final t = board([oi(1), oi(2), oi(4)]);
    final good = board([oi(1, body: '- **Status**: OPEN\n- **Note**: ours edit'), oi(2), oi(4), oi(3)]);

    test('passes the record merge', () {
      expect(checkAgreement(base, o, t, good, realMerge), isNull);
    });

    test('passes a record placed differently NEXT to a hunk', () {
      final swapped = board([oi(1, body: '- **Status**: OPEN\n- **Note**: ours edit'), oi(2), oi(3), oi(4)]);
      expect(checkAgreement(base, o, t, swapped, realMerge), isNull);
    });

    test('FAILS on a hunk-external change that was lost (ours\' edit of OI-1)', () {
      final lost = board([oi(1), oi(2), oi(4), oi(3)]);
      final msg = checkAgreement(base, o, t, lost, realMerge);
      expect(msg, isNotNull);
      expect(msg, contains('ours edit'));
    });

    test('FAILS on a line moved out of its record', () {
      final moved = good.replaceFirst('- **Status**: OPEN\n- **Note**: ours edit\n', '- **Note**: ours edit\n');
      expect(checkAgreement(base, o, t, moved, realMerge), isNotNull);
    });

    test('FAILS on a reorder of records outside the hunk', () {
      final reordered = board([oi(2), oi(1, body: '- **Status**: OPEN\n- **Note**: ours edit'), oi(4), oi(3)]);
      expect(checkAgreement(base, o, t, reordered, realMerge), isNotNull);
    });

    test('FAILS when a line git keeps is missing', () {
      expect(checkAgreement(base, o, t, good.replaceFirst('## OI-2 — probe\n', ''), realMerge), contains('OI-2'));
    });

    test('FAILS on a line git keeps AFTER a conflict hunk (the close marker ends the hunk)', () {
      final git = '$kOpen HEAD\nours\n$kMid\ntheirs\n$kClose origin/main\nkeep\n';
      ({String text, bool conflicted}) fake(String b, String x, String y) => (text: git, conflicted: true);
      expect(checkAgreement('', '', '', 'keep\n', fake), isNull);
      expect(checkAgreement('', '', '', 'other\n', fake), contains('keep'));
    });

    test('a git merge that FAILS is an Unresolvable thrown from the text merge, not a pass', () {
      expect(
        () => checkAgreement(base, o, t, good, (b, x, y) => throw Unresolvable('git merge-file failed (exit 255)')),
        throwsA(isA<Unresolvable>()),
      );
    });
  });

  group('V-c, emitter fidelity (checkStructure)', () {
    test('a clean output parses back to the decisions', () {
      final o = board([oi(1), oi(2), oi(3)]);
      final t = board([oi(1), oi(2), oi(4)]);
      final r = resolveFile(_oiSpec, base: base, ours: o, theirs: t, textMerge: noMerge());
      expect(checkStructure(_oiSpec, r.text, r.decisions), isNull);
    });

    test('FAILS on a glued record (two records on one line)', () {
      final o = board([oi(1), oi(2), oi(3)]);
      final t = board([oi(1), oi(2), oi(4)]);
      final r = resolveFile(_oiSpec, base: base, ours: o, theirs: t, textMerge: noMerge());
      final glued = r.text.replaceFirst('OPEN\n\n## OI-3', 'OPEN## OI-3');
      expect(glued, isNot(r.text));
      expect(checkStructure(_oiSpec, glued, r.decisions), isNotNull);
    });

    test('FAILS on a changed key', () {
      final r = resolveFile(_oiSpec, base: base, ours: base, theirs: base, textMerge: noMerge());
      expect(checkStructure(_oiSpec, r.text.replaceFirst('## OI-2 ', '## OI-7 '), r.decisions), isNotNull);
    });

    test('FAILS on invalid JSON (a missing comma between elements)', () {
      final b = migrations([migrationEl('001_a'), migrationEl('002_b')]);
      final r = resolveFile(_migSpec, base: b, ours: b, theirs: b, textMerge: noMerge());
      expect(checkStructure(_migSpec, r.text, r.decisions), isNull);
      final noComma = r.text.replaceFirst('  },\n  {', '  }\n  {');
      expect(noComma, isNot(r.text));
      expect(checkStructure(_migSpec, noComma, r.decisions), contains('JSON does not decode'));
    });

    test('FAILS on a JSON element that is not a map holding "migration" (a nested key still keys the record)', () {
      final x = migrations(['  {\n    "wrapper": {\n      "migration": "145"\n    }\n  }']);
      final r = resolveFile(_migSpec, base: x, ours: x, theirs: x, textMerge: noMerge());
      expect(r.text, x);
      expect(checkStructure(_migSpec, r.text, r.decisions), contains('a JSON element is not a map holding "migration"'));
    });

    test('FAILS on a registry line at column 0, and on a stray line the emitter added', () {
      final reg = 'concepts:\n${registryRec('a')}${registryRec('b')}';
      final r = resolveFile(_regSpec, base: reg, ours: reg, theirs: reg, textMerge: noMerge());
      expect(checkStructure(_regSpec, r.text, r.decisions), isNull);
      final stray = reg.replaceFirst('    writer: x\n\n  - concept: b', '    writer: x\nstray\n\n  - concept: b');
      expect(stray, isNot(reg));
      // the emitter added the line: the re-parsed record differs from the decision
      expect(checkStructure(_regSpec, stray, r.decisions), contains('re-parsed records differ'));
      // a source already held the line: the decision matches, the column-0 rule names it
      final rs = resolveFile(_regSpec, base: stray, ours: stray, theirs: stray, textMerge: noMerge());
      expect(rs.text, stray);
      expect(checkStructure(_regSpec, rs.text, rs.decisions), contains('registry record a has a line at column 0: stray'));
    });

    test('FAILS on a ledger line at column 0 that is not a record head', () {
      final x = '# header\n\n${ledgerRec('check_a')}stray: line\n';
      final r = resolveFile(specOf('docs/audit/gate_test_ledger.yaml'), base: x, ours: x, theirs: x, textMerge: noMerge());
      expect(r.text, x);
      expect(checkStructure(specOf('docs/audit/gate_test_ledger.yaml'), r.text, r.decisions), contains('ledger line at column 0 is not a record: stray: line'));
    });

    test('a changed group of a repeated key parses back to ALL its parts', () {
      final glossSpec = specOf('docs/naming_conventions.md');
      final b = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'one'), glossaryRow('gate', def: 'two'), glossaryRow('omega')]);
      final t = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'one'), glossaryRow('gate', def: 'two'), glossaryRow('gate', def: 'three'), glossaryRow('omega')]);
      final r = resolveFile(glossSpec, base: b, ours: b, theirs: t, textMerge: noMerge());
      expect(r.text, t);
      expect(checkStructure(glossSpec, r.text, r.decisions), isNull);
      final jb = migrations([migrationEl('145', extra: ',\n    "n": 1'), migrationEl('145', extra: ',\n    "n": 2'), migrationEl('146')]);
      final jt = migrations([migrationEl('145', extra: ',\n    "n": 1'), migrationEl('145', extra: ',\n    "n": 2'), migrationEl('145', extra: ',\n    "n": 3'), migrationEl('146')]);
      final jr = resolveFile(_migSpec, base: jb, ours: jb, theirs: jt, textMerge: noMerge());
      expect(jr.text, jt);
      expect(checkStructure(_migSpec, jr.text, jr.decisions), isNull);
    });

    test('is NOT applied to a partial output: verifyResolution passes a conflicted registry whose markers sit at column 0', () {
      final b = 'concepts:\n${registryRec('a')}';
      final o = 'concepts:\n${registryRec('a')}${registryRec('k', body: '    writer: ours')}';
      final t = 'concepts:\n${registryRec('a')}${registryRec('k', body: '    writer: theirs')}';
      final r = resolveFile(_regSpec, base: b, ours: o, theirs: t, textMerge: realMerge);
      expect(r.partial, isTrue);
      expect(checkStructure(_regSpec, r.text, r.decisions), isNotNull);
      expect(verifyResolution(_regSpec, r, base: b, ours: o, theirs: t, textMerge: realMerge), isNull);
    });

    test('is applied to a clean output: verifyResolution names the check', () {
      final b = 'concepts:\n${registryRec('a')}';
      final o = 'concepts:\n${registryRec('a')}${registryRec('k')}';
      final r = resolveFile(_regSpec, base: b, ours: o, theirs: b, textMerge: noMerge());
      final broken = Resolution(
        text: '${r.text}stray\n',
        conflictedKeys: r.conflictedKeys,
        mergedByLine: r.mergedByLine,
        decisions: r.decisions,
        partial: false,
      );
      // 'stray' is a new line neither side holds: V-a stops it first
      expect(verifyResolution(_regSpec, broken, base: b, ours: o, theirs: b, textMerge: realMerge), startsWith('check V-a'));
    });
  });

  group('verifyResolution names the failing check', () {
    final o = board([oi(1), oi(2), oi(3)]);
    final t = board([oi(1), oi(2), oi(4)]);

    Resolution withText(Resolution r, String text) =>
        Resolution(text: text, conflictedKeys: r.conflictedKeys, mergedByLine: r.mergedByLine, decisions: r.decisions, partial: r.partial);

    test('a correct resolution returns null', () {
      final r = resolveFile(_oiSpec, base: base, ours: o, theirs: t, textMerge: realMerge);
      expect(verifyResolution(_oiSpec, r, base: base, ours: o, theirs: t, textMerge: realMerge), isNull);
    });

    test('V-a first', () {
      final r = resolveFile(_oiSpec, base: base, ours: o, theirs: t, textMerge: realMerge);
      expect(verifyResolution(_oiSpec, withText(r, board([oi(3), oi(4)])), base: base, ours: o, theirs: t, textMerge: realMerge), startsWith('check V-a'));
    });

    test('V-b when the counts are fine and the order is not', () {
      final r = resolveFile(_oiSpec, base: base, ours: o, theirs: t, textMerge: realMerge);
      final reordered = board([oi(2), oi(1), oi(4), oi(3)]);
      expect(verifyResolution(_oiSpec, withText(r, reordered), base: base, ours: o, theirs: t, textMerge: realMerge), startsWith('check V-b'));
    });

    test('V-c when counts and order are fine and the structure is not', () {
      final b = migrations([migrationEl('001_a'), migrationEl('002_b')]);
      final oo = migrations([migrationEl('001_a'), migrationEl('002_b'), migrationEl('003_c')]);
      final r = resolveFile(_migSpec, base: b, ours: oo, theirs: b, textMerge: realMerge);
      final noComma = r.text.replaceFirst('  },\n  {', '  }\n  {');
      expect(noComma, isNot(r.text));
      expect(verifyResolution(_migSpec, withText(r, noComma), base: b, ours: oo, theirs: b, textMerge: realMerge), startsWith('check V-c'));
    });
  });

  group('B-pass: gaps the mutation run left', () {
    test('V-c rejects an output whose region is empty (every record deleted, one by each side)', () {
      final b = board([oi(1), oi(2)]);
      final o = board([oi(1)]);
      final t = board([oi(2)]);
      final r = resolveFile(_oiSpec, base: b, ours: o, theirs: t, textMerge: realMerge);
      expect(r.text, '# Board\n\n');
      final v = verifyResolution(_oiSpec, r, base: b, ours: o, theirs: t, textMerge: realMerge);
      expect(v, startsWith('check V-c'));
      expect(v, contains('does not parse again'));
    });

    test('V-c rejects a JSON document that is not an array', () {
      final x = '{\n"m": [\n${migrationEl('001_a')}\n]\n}\n';
      final r = resolveFile(_migSpec, base: x, ours: x, theirs: x, textMerge: noMerge());
      expect(checkStructure(_migSpec, r.text, r.decisions), 'the JSON is not an array');
    });

    test('V-a on a PARTIAL result fails a unique line that appears twice outside the hunk', () {
      final o = board([oi(1), oi(2), oi(3, title: 'ours')]);
      final t = board([oi(1), oi(2), oi(3, title: 'theirs')]);
      final r = resolveFile(_oiSpec, base: base, ours: o, theirs: t, textMerge: realMerge);
      expect(r.partial, isTrue);
      expect(checkCounts(base, o, t, r.text), isEmpty);
      final dup = r.text.replaceFirst('## OI-1 — probe\n', '## OI-1 — probe\n## OI-1 — probe\n');
      expect(dup, isNot(r.text));
      expect(checkCounts(base, o, t, dup), isNotEmpty);
    });
  });
}
