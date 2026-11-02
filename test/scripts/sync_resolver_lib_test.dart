// test/scripts/sync_resolver_lib_test.dart
//
// scripts/sync_resolver_lib.dart (landing C2, docs/plans/sync-resolver.md section 5, rows L1, L2, the
// merge matrix and the allow-list). The text merge is a scripted fake that records its calls, so a
// case that must be decided WITHOUT it fails on an unexpected call and a case that must call it names
// the three texts it passes. The checks (V-a, V-b, V-c) are in sync_resolver_checks_test.dart, the
// seeded fuzz in sync_resolver_fuzz_test.dart, the CLI in sync_with_main_e2e_test.dart.
//
// Rule 21: every expectation is a whole output string composed from the record builders, never a
// `contains` on a fragment, so a mutant that moves, drops or duplicates a record reddens a test.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/bug_class_ids_lib.dart';
import '../../scripts/sync_resolver_lib.dart';
import '../helpers/sync_resolver_fixtures.dart';

final FileSpec _oiSpec = specOf('docs/audit/open_issues.md');
final FileSpec _bugSpec = specOf('.claude/skills/debugging/bug-classes.md');
final FileSpec _skillSpec = specOf('.claude/skills/debugging/SKILL.md');
final FileSpec _glossSpec = specOf('docs/naming_conventions.md');
final FileSpec _regSpec = specOf('docs/sot_registry.yaml');
final FileSpec _ledgerSpec = specOf('docs/audit/gate_test_ledger.yaml');
final FileSpec _migSpec = specOf('backups/applied_migrations.json');

Resolution _res(FileSpec spec, String base, String ours, String theirs, [FakeMerge? m]) =>
    resolveFile(spec, base: base, ours: ours, theirs: theirs, textMerge: (m ?? FakeMerge()).fn);

String _oiNoTail(int n) => '## OI-$n — probe\n\n- **Status**: OPEN\n';

Matcher _unresolvable(String part) => throwsA(isA<Unresolvable>().having((e) => e.reason, 'reason', contains(part)));

final FileSpec _migSpecB = specOf('backups/applied_migrations.json');

void main() {
  group('L1 lossless round trip, one synthetic file per region shape', () {
    void roundTrip(String name, FileSpec spec, String x) {
      test(name, () {
        final r = _res(spec, x, x, x);
        expect(r.text, x);
        expect(r.partial, isFalse);
        expect(r.conflictedKeys, isEmpty);
        expect(r.mergedByLine, isEmpty);
      });
    }

    roundTrip('OI board', _oiSpec, board([oi(1), oi(2), oi(3)]));
    roundTrip('OI board, last record without a blank line', _oiSpec, board([oi(1), _oiNoTail(2)]));
    roundTrip('bug classes', _bugSpec, '# Bug classes\n\nprose\n\n${bugClass('2.1')}${bugClass('2.2')}');
    roundTrip('debugging SKILL.md, two regions', _skillSpec, skillMd(rows: [skillRow('1.1'), skillRow('1.2')], changelog: [bullet('a'), bullet('b')]));
    roundTrip('glossary table', _glossSpec, glossary([glossaryRow('alpha'), glossaryRow('beta')]));
    roundTrip('SoT registry', _regSpec, 'version: 1\nconcepts:\n${registryRec('a')}${registryRec('b', comment: '  # about b\n')}');
    roundTrip('gate ledger', _ledgerSpec, '# header\n\n${ledgerRec('check_a')}# about b\n${ledgerRec('check_b')}');
    roundTrip('migrations JSON', _migSpec, migrations([migrationEl('001_a'), migrationEl('002_b')]));
    roundTrip('migrations JSON with one element', _migSpec, migrations([migrationEl('001_a')]));
  });

  group('the merge matrix (decision table of section 4.3)', () {
    final base = board([oi(1), oi(2)]);

    test('theirs adds a record: the output is theirs, no text merge', () {
      final y = board([oi(1), oi(2), oi(5)]);
      final m = FakeMerge();
      expect(_res(_oiSpec, base, base, y, m).text, y);
      expect(m.calls, isEmpty);
    });

    test('ours adds a record: the output is ours', () {
      final y = board([oi(1), oi(2), oi(5)]);
      expect(_res(_oiSpec, base, y, base).text, y);
    });

    test('both append: main (theirs) first, then the branch (ours)', () {
      final r = _res(_oiSpec, base, board([oi(1), oi(2), oi(3)]), board([oi(1), oi(2), oi(4)]));
      expect(r.text, board([oi(1), oi(2), oi(4), oi(3)]));
      expect(r.partial, isFalse);
      expect(r.mergedByLine, isEmpty);
    });

    test('both append, the last records have no trailing blank line: one blank is added where a record stops being last', () {
      final b = board([oi(1), _oiNoTail(2)]);
      final o = board([oi(1), oi(2), _oiNoTail(3)]);
      final t = board([oi(1), oi(2), _oiNoTail(4)]);
      expect(_res(_oiSpec, b, o, t).text, board([oi(1), oi(2), oi(4), _oiNoTail(3)]));
    });

    test('both prepend: main (theirs) first', () {
      final b = board([oi(2), oi(3)]);
      expect(_res(_oiSpec, b, board([oi(1), oi(2), oi(3)]), board([oi(0), oi(2), oi(3)])).text, board([oi(0), oi(1), oi(2), oi(3)]));
    });

    test('theirs deletes a record ours kept and inserts after a later one: the anchor is found in the RESULT order', () {
      final b = board([oi(1), oi(2), oi(3), oi(4)]);
      final t = board([oi(1), oi(3), oi(9), oi(4)]);
      expect(_res(_oiSpec, b, b, t).text, t);
    });

    test('the same record added on both sides appears once', () {
      final y = board([oi(1), oi(2), oi(7)]);
      final m = FakeMerge();
      expect(_res(_oiSpec, base, y, y, m).text, y);
      expect(m.calls, isEmpty);
    });

    test('the same key with different text is a collision: markers around THAT record only, neighbours resolved', () {
      final m = FakeMerge([conflictOf(oi(3, title: 'ours'), '', oi(3, title: 'theirs'))]);
      final r = _res(_oiSpec, base, board([oi(1), oi(2), oi(3, title: 'ours'), oi(8)]), board([oi(1), oi(2), oi(3, title: 'theirs'), oi(9)]), m);
      expect(m.calls, [(base: '', ours: oi(3, title: 'ours'), theirs: oi(3, title: 'theirs'))]);
      expect(r.partial, isTrue);
      expect(r.conflictedKeys, ['OI-3']);
      expect(r.text, board([oi(1), oi(2), conflictOf(oi(3, title: 'ours'), '', oi(3, title: 'theirs')).text, oi(9), oi(8)]));
    });

    test('one-sided edit: the edited record wins, no text merge', () {
      final y = board([oi(1), oi(2, body: '- **Status**: CLOSED')]);
      final m = FakeMerge();
      expect(_res(_oiSpec, base, base, y, m).text, y);
      expect(_res(_oiSpec, base, y, base, m).text, y);
      expect(m.calls, isEmpty);
    });

    test('both edit the same record: the text merge gets the three record texts; a clean answer is reported as merged by line', () {
      final o = board([oi(1), oi(2, body: '- **Status**: OPEN\n- **Owner**: ours')]);
      final t = board([oi(1), oi(2, body: '- **Status**: OPEN\n- **Note**: theirs')]);
      final both = oi(2, body: '- **Status**: OPEN\n- **Owner**: ours\n- **Note**: theirs');
      final m = FakeMerge([(text: both, conflicted: false)]);
      final r = _res(_oiSpec, base, o, t, m);
      expect(m.calls, [(base: oi(2), ours: oi(2, body: '- **Status**: OPEN\n- **Owner**: ours'), theirs: oi(2, body: '- **Status**: OPEN\n- **Note**: theirs'))]);
      expect(r.text, board([oi(1), both]));
      expect(r.mergedByLine, ['OI-2']);
      expect(r.partial, isFalse);
    });

    test('both edit the same line: a conflicted answer keeps its markers for that record', () {
      final o = oi(2, body: '- **Status**: ours');
      final t = oi(2, body: '- **Status**: theirs');
      final c = conflictOf(o, oi(2), t);
      final r = _res(_oiSpec, base, board([oi(1), o]), board([oi(1), t]), FakeMerge([c]));
      expect(r.partial, isTrue);
      expect(r.conflictedKeys, ['OI-2']);
      expect(r.text, board([oi(1), c.text]));
    });

    test('theirs deletes a record ours did not touch: it is dropped', () {
      expect(_res(_oiSpec, base, base, board([oi(2)])).text, board([oi(2)]));
    });

    test('ours deletes a record theirs did not touch: it is dropped', () {
      expect(_res(_oiSpec, base, board([oi(1)]), base).text, board([oi(1)]));
    });

    test('delete against edit: the text merge sees an empty side, in each direction', () {
      final edited = oi(2, body: '- **Status**: CLOSED');
      final m1 = FakeMerge([conflictOf('', oi(2), edited)]);
      final r1 = _res(_oiSpec, base, board([oi(1)]), board([oi(1), edited]), m1);
      expect(m1.calls, [(base: oi(2), ours: '', theirs: edited)]);
      expect(r1.partial, isTrue);
      final m2 = FakeMerge([conflictOf(edited, oi(2), '')]);
      final r2 = _res(_oiSpec, base, board([oi(1), edited]), board([oi(1)]), m2);
      expect(m2.calls, [(base: oi(2), ours: edited, theirs: '')]);
      expect(r2.partial, isTrue);
    });

    test('both sides delete the same record: it is dropped without a text merge', () {
      final m = FakeMerge();
      expect(_res(_oiSpec, base, board([oi(1)]), board([oi(1)]), m).text, board([oi(1)]));
      expect(m.calls, isEmpty);
    });

    test('a difference in trailing blank lines only is no change', () {
      final noBlank = board([oi(1), _oiNoTail(2)]);
      final m = FakeMerge();
      // ours edits OI-1; theirs only changes the blank lines after OI-2: no text merge, both survive
      final r = _res(_oiSpec, board([oi(1), oi(2)]), board([oi(1, body: '- **Status**: CLOSED'), oi(2)]), noBlank, m);
      expect(m.calls, isEmpty);
      expect(keysOf(_oiSpec, r.text), ['OI-1', 'OI-2']);
      expect(r.text, board([oi(1, body: '- **Status**: CLOSED'), _oiNoTail(2)]));
    });

    test('equal after trimming: theirs wins only when ours still holds the base bytes', () {
      final spaced = '## OI-2 — probe\n\n- **Status**: OPEN\n\n\n\n';
      final b = board([oi(1), oi(2)]);
      // ours untouched, theirs differs in blank lines only -> theirs' bytes
      expect(_res(_oiSpec, b, b, board([oi(1), spaced])).text, board([oi(1), spaced]));
      // ours changed the blank lines too (and theirs a different way) -> ours' bytes
      final ours = '## OI-2 — probe\n\n- **Status**: OPEN\n\n\n';
      expect(_res(_oiSpec, b, board([oi(1), ours]), board([oi(1), spaced])).text, board([oi(1), ours]));
    });

    test('insertions at different anchors keep their places', () {
      final b = board([oi(1), oi(2), oi(3)]);
      final r = _res(_oiSpec, b, board([oi(1), oi(8), oi(2), oi(3)]), board([oi(1), oi(2), oi(9), oi(3)]));
      expect(r.text, board([oi(1), oi(8), oi(2), oi(9), oi(3)]));
    });

    test('a side that reordered shared records is unresolvable, naming the side', () {
      final b = board([oi(1), oi(2), oi(3)]);
      final swapped = board([oi(2), oi(1), oi(3)]);
      expect(() => _res(_oiSpec, b, swapped, b), _unresolvable('reordered records (ours)'));
      expect(() => _res(_oiSpec, b, b, swapped), _unresolvable('reordered records (theirs)'));
    });

    test('a deleted key is not an anchor: the inserted record follows the nearest PLACED predecessor', () {
      final b = board([oi(1), oi(2), oi(3)]);
      final r = _res(_oiSpec, b, board([oi(1), oi(3)]), board([oi(1), oi(2), oi(9), oi(3)]));
      expect(r.text, board([oi(1), oi(9), oi(3)]));
    });

    test('a record only theirs holds, with no placed predecessor, goes to the front', () {
      final b = board([oi(2)]);
      final r = _res(_oiSpec, b, board([oi(2)]), board([oi(1), oi(2)]));
      expect(r.text, board([oi(1), oi(2)]));
    });

    test('prefix: equal, one side, both sides (text merge, gap conflict named)', () {
      final b = board([oi(1)], head: '# Board\n\nold prose\n\n');
      final o = board([oi(1)], head: '# Board\n\nours prose\n\n');
      final t = board([oi(1)], head: '# Board\n\nold prose\n\n');
      expect(_res(_oiSpec, b, o, t).text, o);
      expect(_res(_oiSpec, b, t, o).text, o);
      expect(_res(_oiSpec, b, o, o).text, o);
      final t2 = board([oi(1)], head: '# Board\n\ntheirs prose\n\n');
      final c = conflictOf('# Board\n\nours prose\n\n', '# Board\n\nold prose\n\n', '# Board\n\ntheirs prose\n\n');
      final m = FakeMerge([c]);
      final r = _res(_oiSpec, b, o, t2, m);
      expect(m.calls, [(base: '# Board\n\nold prose\n\n', ours: '# Board\n\nours prose\n\n', theirs: '# Board\n\ntheirs prose\n\n')]);
      expect(r.conflictedKeys, ['<gap>']);
      expect(r.partial, isTrue);
      expect(r.text, '${c.text}${oi(1)}');
    });

    test('suffix text after a region (JSON closing bracket and trailer) follows the same rule', () {
      final b = '${migrations([migrationEl('001_a')])}trailer old\n';
      final t = '${migrations([migrationEl('001_a')])}trailer new\n';
      expect(_res(_migSpec, b, b, t).text, t);
      expect(_res(_migSpec, b, t, b).text, t);
    });
  });

  group('groups of a repeated key', () {
    final b = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'one'), glossaryRow('gate', def: 'two'), glossaryRow('omega')]);

    test('a group identical in all versions is carried through in place', () {
      final o = glossary([glossaryRow('alpha'), glossaryRow('aaa'), glossaryRow('gate', def: 'one'), glossaryRow('gate', def: 'two'), glossaryRow('omega')]);
      final t = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'one'), glossaryRow('gate', def: 'two'), glossaryRow('omega'), glossaryRow('zzz')]);
      final m = FakeMerge();
      expect(_res(_glossSpec, b, o, t, m).text,
          glossary([glossaryRow('alpha'), glossaryRow('aaa'), glossaryRow('gate', def: 'one'), glossaryRow('gate', def: 'two'), glossaryRow('omega'), glossaryRow('zzz')]));
      expect(m.calls, isEmpty);
    });

    test('one side extends the group: that side\'s list wins, at the first position', () {
      final t = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'one'), glossaryRow('gate', def: 'two'), glossaryRow('gate', def: 'three'), glossaryRow('omega')]);
      expect(_res(_glossSpec, b, b, t).text, t);
      final o = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'one'), glossaryRow('gate', def: 'two'), glossaryRow('gate', def: 'three'), glossaryRow('omega'), glossaryRow('late')]);
      expect(_res(_glossSpec, b, o, b).text, o);
    });

    test('a group one side extended stays together at its first position when the other side inserted a record between its rows', () {
      final o = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'one'), glossaryRow('mid'), glossaryRow('gate', def: 'two'), glossaryRow('omega')]);
      final t = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'one'), glossaryRow('gate', def: 'two'), glossaryRow('gate', def: 'three'), glossaryRow('omega')]);
      expect(_res(_glossSpec, b, o, t).text,
          glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'one'), glossaryRow('gate', def: 'two'), glossaryRow('gate', def: 'three'), glossaryRow('mid'), glossaryRow('omega')]));
    });

    test('a group whose first row one side deleted moves behind a shared record without counting as a reorder', () {
      final gb = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'one'), glossaryRow('mid'), glossaryRow('gate', def: 'two'), glossaryRow('omega')]);
      final go = glossary([glossaryRow('alpha'), glossaryRow('mid'), glossaryRow('gate', def: 'two'), glossaryRow('omega')]);
      final gt = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'one'), glossaryRow('mid'), glossaryRow('gate', def: 'two'), glossaryRow('omega'), glossaryRow('zzz')]);
      expect(_res(_glossSpec, gb, go, gt).text, glossary([glossaryRow('alpha'), glossaryRow('mid'), glossaryRow('gate', def: 'two'), glossaryRow('omega'), glossaryRow('zzz')]));
    });

    test('one side consolidates the group to a single row', () {
      final t = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'merged'), glossaryRow('omega')]);
      final o = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'one'), glossaryRow('gate', def: 'two'), glossaryRow('omega'), glossaryRow('late')]);
      expect(_res(_glossSpec, b, o, t).text, glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'merged'), glossaryRow('omega'), glossaryRow('late')]));
    });

    test('both sides change the group differently: unresolvable', () {
      final o = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'ours'), glossaryRow('gate', def: 'two'), glossaryRow('omega')]);
      final t = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'one'), glossaryRow('gate', def: 'theirs'), glossaryRow('omega')]);
      expect(() => _res(_glossSpec, b, o, t), _unresolvable('repeated key **gate** was changed on both sides'));
    });

    test('both sides make the same change to the group: taken once', () {
      final y = glossary([glossaryRow('alpha'), glossaryRow('gate', def: 'merged'), glossaryRow('omega')]);
      expect(_res(_glossSpec, b, y, y).text, y);
    });

    test('a repeated JSON key (the migration ledger repeats 145) is a group in the comma region', () {
      final jb = migrations([migrationEl('145', extra: ',\n    "n": 1'), migrationEl('145', extra: ',\n    "n": 2'), migrationEl('146')]);
      final jo = migrations([migrationEl('145', extra: ',\n    "n": 1'), migrationEl('145', extra: ',\n    "n": 2'), migrationEl('146'), migrationEl('147')]);
      final jt = migrations([migrationEl('145', extra: ',\n    "n": 1'), migrationEl('145', extra: ',\n    "n": 2'), migrationEl('146'), migrationEl('148')]);
      final r = _res(_migSpec, jb, jo, jt);
      expect(r.text, migrations([migrationEl('145', extra: ',\n    "n": 1'), migrationEl('145', extra: ',\n    "n": 2'), migrationEl('146'), migrationEl('148'), migrationEl('147')]));
    });
  });

  group('the migration key', () {
    test('is the migration field, not an earlier field that ends in "migration"', () {
      final el = '  {\n    "prior_migration": "100",\n    "migration": "101"\n  }';
      expect(keysOf(_migSpec, migrations([el])), ['101']);
    });
  });

  group('a changed group in the comma region', () {
    test('theirs extends the repeated 145: the group is emitted as separate comma-joined elements at its first position', () {
      final n1 = migrationEl('145', extra: ',\n    "n": 1'), n2 = migrationEl('145', extra: ',\n    "n": 2'), n3 = migrationEl('145', extra: ',\n    "n": 3');
      final jb = migrations([n1, n2, migrationEl('146')]);
      final jo = migrations([n1, n2, migrationEl('146'), migrationEl('147')]);
      final jt = migrations([n1, n2, n3, migrationEl('146')]);
      expect(_res(_migSpec, jb, jo, jt).text, migrations([n1, n2, n3, migrationEl('146'), migrationEl('147')]));
    });
  });

  group('what the parser refuses', () {
    final b = board([oi(1)]);

    test('an anchor missing from ONE version names that version', () {
      final sb = skillMd(rows: [skillRow('1.1')], changelog: [bullet('a')]);
      final broken = sb.replaceFirst('### Bug-class index', '### Renamed index');
      expect(() => _res(_skillSpec, sb, broken, sb), _unresolvable('ours: region 1: the anchor'));
      expect(() => _res(_skillSpec, sb, sb, broken), _unresolvable('theirs: region 1: the anchor'));
      expect(() => _res(_skillSpec, broken, sb, sb), _unresolvable('base: region 1: the anchor'));
    });

    test('an anchor with no record after it', () {
      final none = glossary([]);
      expect(() => _res(_glossSpec, none, none, none), _unresolvable('no record'));
    });

    test('a record start with no key', () {
      final bad = 'concepts:\n  - concept: \n    writer: x\n';
      expect(() => _res(_regSpec, bad, bad, bad), _unresolvable('has no key'));
    });

    test('a table row that does not match the record pattern', () {
      final bad = glossary([glossaryRow('alpha'), '| plain row |\n', glossaryRow('beta')]);
      expect(() => _res(_glossSpec, bad, bad, bad), _unresolvable('is not a table row'));
    });

    test('CRLF line endings', () {
      final crlf = board([oi(1)]).replaceAll('\n', '\r\n');
      expect(() => _res(_oiSpec, crlf, crlf, crlf), _unresolvable('CRLF'));
    });

    test('a NUL byte', () {
      final nul = '${board([oi(1)])}${String.fromCharCode(0)}\n';
      expect(() => _res(_oiSpec, nul, nul, nul), _unresolvable('NUL'));
    });

    test('a lone CR is not a line break', () {
      final x = '# Board\rstill the title\n\n${oi(1)}';
      expect(_res(_oiSpec, x, x, x).text, x);
    });

    test('an unclosed code fence', () {
      final bad = '${board([oi(1)])}```\ncode that never closes\n';
      expect(() => _res(_oiSpec, bad, bad, bad), _unresolvable('unclosed code fence'));
    });

    test('a record start inside a fenced block is not a record', () {
      final x = board([oi(1), '## OI-2 — probe\n\n```\n## OI-99 — not a record\n```\n\n']);
      expect(keysOf(_oiSpec, x), ['OI-1', 'OI-2']);
      expect(_res(_oiSpec, x, x, x).text, x);
    });

    test('a version with no record in a region is refused, naming that version', () {
      expect(() => _res(_oiSpec, '', b, b), _unresolvable('base: region 1: no record'));
    });
  });

  group('the YAML shapes', () {
    String reg(List<String> recs) => 'version: 1\nconcepts:\n${recs.join()}';

    test('a commented FIRST concept keeps its comment', () {
      final x = reg([registryRec('a', comment: '  # about a\n'), registryRec('b')]);
      expect(keysOf(_regSpec, x), ['a', 'b']);
      expect(_res(_regSpec, x, x, x).text, x);
    });

    test('a commented concept inserted at the front by theirs keeps its comment', () {
      final b = reg([registryRec('a'), registryRec('b')]);
      final t = reg([registryRec('z', comment: '  # about z\n'), registryRec('a'), registryRec('b')]);
      expect(_res(_regSpec, b, b, t).text, t);
      expect(_res(_regSpec, b, t, b).text, t);
    });

    test('a commented FIRST concept deleted takes its comment with it', () {
      final b = reg([registryRec('a', comment: '  # about a\n'), registryRec('b')]);
      final t = reg([registryRec('b')]);
      expect(_res(_regSpec, b, b, t).text, t);
      expect(_res(_regSpec, b, t, b).text, t);
    });

    test('the comment of the FIRST concept belongs to its record: ours edits it, theirs deletes the concept -> one conflict on that record, none on the gap', () {
      final ra = registryRec('a', comment: '  # about a\n'), ro = registryRec('a', comment: '  # ours\n');
      final m = FakeMerge([conflictOf(ro, ra, '')]);
      final r = _res(_regSpec, reg([ra, registryRec('b')]), reg([ro, registryRec('b')]), reg([registryRec('b')]), m);
      expect(m.calls, [(base: ra, ours: ro, theirs: '')]);
      expect(r.conflictedKeys, ['a']);
    });

    test('a commented concept deleted takes its comment with it', () {
      final b = reg([registryRec('a'), registryRec('b', comment: '  # about b\n'), registryRec('c')]);
      final t = reg([registryRec('a'), registryRec('c')]);
      expect(_res(_regSpec, b, b, t).text, t);
    });

    test('both sides append a commented concept: each comment stays with its concept', () {
      final b = reg([registryRec('a')]);
      final o = reg([registryRec('a'), registryRec('o', comment: '  # ours\n')]);
      final t = reg([registryRec('a'), registryRec('t', comment: '  # theirs\n')]);
      expect(_res(_regSpec, b, o, t).text, reg([registryRec('a'), registryRec('t', comment: '  # theirs\n'), registryRec('o', comment: '  # ours\n')]));
    });

    test('one side\'s comment and the other\'s none: the concept is one change, the comment travels with it', () {
      final b = reg([registryRec('a'), registryRec('b')]);
      final o = reg([registryRec('a'), registryRec('b', comment: '  # new note\n')]);
      expect(_res(_regSpec, b, o, b).text, o);
      expect(_res(_regSpec, b, b, o).text, o);
    });

    test('the ledger\'s column-0 comment leader; a header comment separated by a blank line stays in the prefix', () {
      final b = '# header\n\n${ledgerRec('check_a')}';
      final o = '# header\n\n${ledgerRec('check_a')}# about o\n${ledgerRec('check_o')}';
      final t = '# header\n\n${ledgerRec('check_a')}# about t\n${ledgerRec('check_t')}';
      expect(_res(_ledgerSpec, b, o, t).text, '# header\n\n${ledgerRec('check_a')}# about t\n${ledgerRec('check_t')}# about o\n${ledgerRec('check_o')}');
      expect(keysOf(_ledgerSpec, o), ['check_a.dart', 'check_o.dart']);
    });
  });

  group('JSON commas', () {
    final a = migrationEl('001_a'), b = migrationEl('002_b'), c = migrationEl('003_c');

    test('both append at the end: commas are re-added, the result decodes', () {
      final r = _res(_migSpec, migrations([a]), migrations([a, b]), migrations([a, c]));
      expect(r.text, migrations([a, c, b]));
    });

    test('an insert in the middle', () {
      final r = _res(_migSpec, migrations([a, c]), migrations([a, b, c]), migrations([a, c]));
      expect(r.text, migrations([a, b, c]));
    });

    test('theirs edits the old last element while ours appends', () {
      final a2 = migrationEl('001_a', extra: ',\n    "note": "edited"');
      final r = _res(_migSpec, migrations([a]), migrations([a, b]), migrations([a2]));
      expect(r.text, migrations([a2, b]));
    });

    test('theirs deletes the old last element while ours appends', () {
      final r = _res(_migSpec, migrations([a, b]), migrations([a, b, c]), migrations([a]));
      expect(r.text, migrations([a, c]));
    });

    test('a trailing comma on the last element is not a difference', () {
      final withComma = '[\n$a,\n$b,\n]\n';
      final without = migrations([a, b]);
      final m = FakeMerge();
      expect(_res(_migSpec, without, withComma, without, m).text, withComma.replaceAll('$b,\n]', '$b\n]'));
      expect(m.calls, isEmpty);
    });
  });

  group('table regions and the rest', () {
    test('the glossary table region ends at the first non-table line after its first row', () {
      final x = glossary([glossaryRow('a'), glossaryRow('b')], after: '\nprose with | pipes\n| not a record start |\n');
      expect(keysOf(_glossSpec, x), ['**a**', '**b**']);
    });

    test('a two-region file merges each region', () {
      final b = skillMd(rows: [skillRow('1.1')], changelog: [bullet('a')]);
      final o = skillMd(rows: [skillRow('1.1'), skillRow('1.2')], changelog: [bullet('a')]);
      final t = skillMd(rows: [skillRow('1.1')], changelog: [bullet('t'), bullet('a')]);
      expect(_res(_skillSpec, b, o, t).text, skillMd(rows: [skillRow('1.1'), skillRow('1.2')], changelog: [bullet('t'), bullet('a')]));
    });

    test('changelog prepends: main (theirs) first', () {
      final rows = [skillRow('1.1')];
      final b = skillMd(rows: rows, changelog: [bullet('a')]);
      expect(_res(_skillSpec, b, skillMd(rows: rows, changelog: [bullet('o'), bullet('a')]), skillMd(rows: rows, changelog: [bullet('t'), bullet('a')])).text,
          skillMd(rows: rows, changelog: [bullet('t'), bullet('o'), bullet('a')]));
    });

    test('both sides edit one changelog bullet: it is ONE record keyed by its bold lead, so the text merge sees the three texts', () {
      final rows = [skillRow('1.1')];
      final b = skillMd(rows: rows, changelog: [bullet('a', text: 'old'), bullet('z')]);
      final o = skillMd(rows: rows, changelog: [bullet('a', text: 'ours'), bullet('z')]);
      final t = skillMd(rows: rows, changelog: [bullet('a', text: 'theirs'), bullet('z')]);
      final c = conflictOf(bullet('a', text: 'ours'), bullet('a', text: 'old'), bullet('a', text: 'theirs'));
      final m = FakeMerge([c]);
      final r = _res(_skillSpec, b, o, t, m);
      expect(m.calls, [(base: bullet('a', text: 'old'), ours: bullet('a', text: 'ours'), theirs: bullet('a', text: 'theirs'))]);
      expect(r.conflictedKeys, ['a']);
      expect(r.text, skillMd(rows: rows, changelog: [c.text, bullet('z')]));
    });

    test('the archived heading and a bare N.M are both keys', () {
      final x = '${bugClass('2.1')}### 2.2.archived-2026-01-02 old\n\nbody\n\n### 2.3\n\nbody\n\n';
      expect(keysOf(_bugSpec, x), ['2.1', '2.2.archived-2026-01-02', '2.3']);
    });

    test('the tail rule: a deleted last record hands its trailing blank lines to the new last record', () {
      final endsBlank = board([oi(1), oi(2), oi(3)]);
      expect(_res(_oiSpec, endsBlank, endsBlank, board([oi(1), oi(2)])).text, board([oi(1), oi(2)]));
      final endsSingle = board([oi(1), oi(2), _oiNoTail(3)]);
      expect(_res(_oiSpec, endsSingle, endsSingle, board([oi(1), oi(2)])).text, board([oi(1), _oiNoTail(2)]));
    });
  });

  group('the tail rule reads ours\' last record', () {
    test('a record that stops being last takes the trailing blank lines of ours\' last record, not the base\'s', () {
      final b = board([oi(1), oi(2), oi(3)]);
      final o = board([oi(1), oi(2), _oiNoTail(3)]);
      expect(_res(_oiSpec, b, o, board([oi(1), oi(2)])).text, board([oi(1), _oiNoTail(2)]));
    });

    test('the new last record always ends with a newline, even when ours ends without one', () {
      final noEof = '## OI-3 — probe\n\n- **Status**: OPEN';
      final b = board([oi(1), oi(2), noEof]);
      expect(_res(_oiSpec, b, b, board([oi(1), oi(2)])).text, board([oi(1), _oiNoTail(2)]));
    });

    test('a changelog bullet that ended the file without a newline gets one when it stops being last', () {
      final rows = [skillRow('1.1')];
      final b = skillMd(rows: rows, changelog: ['- **a** text']);
      final o = skillMd(rows: rows, changelog: [bullet('a'), '- **o** text']);
      final t = skillMd(rows: rows, changelog: [bullet('a'), '- **t** text']);
      expect(_res(_skillSpec, b, o, t).text, skillMd(rows: rows, changelog: [bullet('a'), bullet('t'), '- **o** text']));
    });
  });

  group('the fence scanner mirrors scripts/bug_class_ids_lib.dart', () {
    final cases = <String, String>{
      'plain fence': '### 1.1 a\n\n```\n### 9.9 inside\n```\n\n### 1.2 b\n\n',
      'tilde fence': '### 1.1 a\n\n~~~\n### 9.9 inside\n~~~\n\n### 1.2 b\n\n',
      'four-backtick fence closed by three does not close': '### 1.1 a\n\n````\n### 9.9 inside\n```\n### 9.8 still inside\n````\n\n### 1.2 b\n\n',
      'closer with trailing text does not close': '### 1.1 a\n\n```\n### 9.9 inside\n``` text\n### 9.8 still inside\n```\n\n### 1.2 b\n\n',
      'backtick info string with a backtick is not an opener': '### 1.1 a\n\n``` `x`\n### 1.2 b\n\n',
      'four spaces of indent is not a fence': '### 1.1 a\n\n    ```\n### 1.2 b\n\n',
      'three spaces of indent is a fence': '### 1.1 a\n\n   ```\n### 9.9 inside\n   ```\n\n### 1.2 b\n\n',
      'tilde closer of a backtick fence does not close': '### 1.1 a\n\n```\n### 9.9 inside\n~~~\n### 9.8 still inside\n```\n\n### 1.2 b\n\n',
    };
    cases.forEach((name, text) {
      test(name, () {
        final theirs = scanHeadings(text).headings.map((h) => h.id.toString()).toList();
        expect(keysOf(_bugSpec, text), theirs);
      });
    });

    test('an unclosed fence is refused here exactly when bug_class_ids_lib reports an unclosed opener', () {
      for (final text in ['### 1.1 a\n\n```\nnever closes\n', '### 1.1 a\n\n~~~~\nnever closes\n~~~\n']) {
        expect(scanHeadings(text).unclosedFenceLine, isNotNull);
        expect(() => keysOf(_bugSpec, text), _unresolvable('unclosed code fence'));
      }
    });
  });

  group('the allow-list', () {
    test('holds none of the frozen archive, the two local indexes or the code-review skill', () {
      final paths = kResolvableFiles.map((f) => f.path).toSet();
      for (final no in const [
        '.claude/skills/code-review/tuning-history.md',
        '.claude/skills/code-review/SKILL.md',
        'docs/audit/OPEN_INDEX.md',
        'docs/diagnoses/INDEX.md',
        'docs/audit/GATE_INDEX.md',
        'CLAUDE.md',
        'docs/ship_dark_pending_review.yaml',
        'backups/live_schema_columns.json',
        'backups/context_artifact_sizes.json',
      ]) {
        expect(paths, isNot(contains(no)), reason: no);
        expect(specFor(no), isNull, reason: no);
      }
    });

    test('no two entries share a path and every entry has a region and a key pattern that matches its own start', () {
      final paths = kResolvableFiles.map((f) => f.path).toList();
      expect(paths.toSet().length, paths.length);
      expect(paths.toSet(), {
        'docs/audit/open_issues.md',
        'docs/audit/closed_issues.md',
        '.claude/skills/debugging/bug-classes.md',
        '.claude/skills/debugging/SKILL.md',
        'docs/naming_conventions.md',
        'docs/sot_registry.yaml',
        'docs/audit/gate_test_ledger.yaml',
        'backups/applied_migrations.json',
      });
      for (final f in kResolvableFiles) {
        expect(f.regions, isNotEmpty, reason: f.path);
      }
    });
  });

  group('B-pass: a conflicted JSON element keeps the separator comma inside each side', () {
    // Keeps the ours (or theirs) side of every conflict block and drops the marker lines, as a human does.
    String keep(String text, {required bool ours}) {
      final out = <String>[];
      var section = 0; // 0 outside, 1 ours, 2 base, 3 theirs
      for (final l in text.split('\n')) {
        if (l.startsWith('<<<<<<<')) {
          section = 1;
        } else if (l.startsWith('|||||||')) {
          section = 2;
        } else if (l == '=======') {
          section = 3;
        } else if (l.startsWith('>>>>>>>')) {
          section = 0;
        } else if (section == 0 || (section == 1 && ours) || (section == 3 && !ours)) {
          out.add(l);
        }
      }
      return out.join('\n');
    }

    final b = migrations([migrationEl('001_a')]);
    final o = migrations([migrationEl('001_a'), migrationEl('002_b', extra: ', "n": "ours"')]);
    final t = migrations([migrationEl('001_a'), migrationEl('002_b', extra: ', "n": "theirs"'), migrationEl('003_c')]);

    test('either side kept, the file still decodes to every element', () {
      final r = resolveFile(_migSpecB, base: b, ours: o, theirs: t, textMerge: realMerge);
      expect(r.partial, isTrue);
      expect(r.text, contains('<<<<<<<'));
      expect(r.text, isNot(contains('>>>>>>> origin/main,')));
      for (final ours in [true, false]) {
        final v = jsonDecode(keep(r.text, ours: ours)) as List;
        expect([for (final e in v) (e as Map)['migration']], ['001_a', '002_b', '003_c']);
        expect((v[1] as Map)['n'], ours ? 'ours' : 'theirs');
      }
    });

    test('a hunk in the MIDDLE of an element (a field edited on both sides) keeps the comma after the closing brace', () {
      final bb = migrations([migrationEl('001_a', extra: ', "n": "base"'), migrationEl('002_b')]);
      final oo = migrations([migrationEl('001_a', extra: ', "n": "ours"'), migrationEl('002_b')]);
      final tt = migrations([migrationEl('001_a', extra: ', "n": "theirs"'), migrationEl('002_b'), migrationEl('003_c')]);
      final r = resolveFile(_migSpecB, base: bb, ours: oo, theirs: tt, textMerge: realMerge);
      expect(r.partial, isTrue);
      for (final ours in [true, false]) {
        final v = jsonDecode(keep(r.text, ours: ours)) as List;
        expect([for (final e in v) (e as Map)['migration']], ['001_a', '002_b', '003_c']);
        expect((v[0] as Map)['n'], ours ? 'ours' : 'theirs');
      }
    });

    test('a conflicted LAST element gets no comma at all', () {
      final o2 = migrations([migrationEl('001_a'), migrationEl('002_b', extra: ', "n": "ours"')]);
      final t2 = migrations([migrationEl('001_a'), migrationEl('002_b', extra: ', "n": "theirs"')]);
      final r = resolveFile(_migSpecB, base: b, ours: o2, theirs: t2, textMerge: realMerge);
      expect(r.partial, isTrue);
      for (final ours in [true, false]) {
        expect(((jsonDecode(keep(r.text, ours: ours)) as List).last as Map)['migration'], '002_b');
      }
    });
  });

  group('B-pass: prose between regions', () {
    test('a gap that git merges cleanly by line is reported as merged by line', () {
      final b = board([oi(1)], head: '# Board\n\nline a\n\nline b\n\n');
      final o = board([oi(1)], head: '# Board\n\nline A ours\n\nline b\n\n');
      final t = board([oi(1)], head: '# Board\n\nline a\n\nline B theirs\n\n');
      final r = resolveFile(specOf('docs/audit/open_issues.md'), base: b, ours: o, theirs: t, textMerge: realMerge);
      expect(r.partial, isFalse);
      expect(r.mergedByLine, ['<gap>']);
      expect(r.text, contains('line A ours'));
      expect(r.text, contains('line B theirs'));
    });
  });
}
