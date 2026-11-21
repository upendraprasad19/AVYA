// test/scripts/sync_resolver_real_files_test.dart
//
// Row L2 of docs/plans/sync-resolver.md section 5: scripts/sync_resolver_lib.dart against the 8 REAL
// tracked files at HEAD (9 regions). It fails the day a heading is renamed, a leader moves to the wrong
// record, an append loses a blank line or the tail rule becomes unconditional, i.e. the day the spec
// stops matching the file it is supposed to describe.
//
// The insertion points are found here with their OWN small regexes (not the lib's spec), so a region
// boundary bug in the lib cannot hide behind the lib's own idea of where the region is.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/sync_resolver_lib.dart';
import '../helpers/sync_resolver_fixtures.dart';

/// Where a probe record goes inside a region.
enum _At { front, middle, end }

class _Probe {
  _Probe(
    this.path,
    this.name, {
    this.anchor,
    required this.start,
    this.endRe,
    this.tableEnd = false,
    this.leader,
    required this.rec,
    this.comma = false,
    this.blank = false,
  });

  final String path;
  final String name;
  final RegExp? anchor;
  final RegExp start;

  /// The region ends at the first line after its first record that matches this (null: end of file).
  final RegExp? endRe;

  /// The region ends at the first line after its first record that does not start with `|`.
  final bool tableEnd;
  final RegExp? leader;

  /// The probe record for [id].
  final String Function(String id) rec;
  final bool comma;

  /// Records are separated by blank lines.
  final bool blank;
}

final List<_Probe> _probes = [
  _Probe('docs/audit/open_issues.md', 'open board', start: RegExp(r'^## OI-\d+ '), blank: true, rec: (id) => '## OI-9000$id — probe\n\n- **Status**: OPEN\n\n'),
  _Probe('docs/audit/closed_issues.md', 'closed board', start: RegExp(r'^## OI-\d+ '), blank: true, rec: (id) => '## OI-9000$id — probe\n\n- **Status**: CLOSED\n\n'),
  _Probe('.claude/skills/debugging/bug-classes.md', 'bug classes', start: RegExp(r'^### \d+\.\d+[ .]'), blank: true, rec: (id) => '### 99.$id probe\n\nbody\n\n'),
  _Probe('.claude/skills/debugging/SKILL.md', 'debugging index table',
      anchor: RegExp(r'^### Bug-class index'), start: RegExp(r'^\| \d+\.\d+ \|'), tableEnd: true, rec: (id) => '| 99.$id | probe | x | y |\n'),
  _Probe('.claude/skills/debugging/SKILL.md', 'debugging changelog', anchor: RegExp(r'^## Changelog'), start: RegExp(r'^- \*\*'), rec: (id) => '- **probe$id** text\n'),
  _Probe('docs/naming_conventions.md', 'glossary',
      anchor: RegExp(r'^## 8\. Reserved domain glossary'), start: RegExp(r'^\| \*\*'), tableEnd: true, rec: (id) => '| **probe$id** | a definition |\n'),
  _Probe('docs/sot_registry.yaml', 'SoT registry',
      anchor: RegExp(r'^concepts:'), start: RegExp(r'^  - concept: '), leader: RegExp(r'^  #'), blank: true, rec: (id) => '  - concept: probe$id\n    writer: x\n\n'),
  _Probe('docs/audit/gate_test_ledger.yaml', 'gate ledger',
      start: RegExp(r'^[a-z0-9_]+\.dart:\s*$'), leader: RegExp(r'^#'), blank: true, rec: (id) => 'probe${id}_gate.dart:\n  mutation_proven: true\n\n'),
  _Probe('backups/applied_migrations.json', 'migrations',
      start: RegExp(r'^  \{\s*$'), endRe: RegExp(r'^\]'), comma: true, rec: (id) => '  {\n    "migration": "9000$id"\n  }'),
];

List<String> _lines(String x) => RegExp(r'[^\n]*\n|[^\n]+').allMatches(x).map((m) => m.group(0)!).toList();

/// The line index where a probe record goes, and the lines of the file.
int _slot(_Probe p, List<String> ls, _At at) {
  var from = 0;
  if (p.anchor != null) {
    from = ls.indexWhere((l) => p.anchor!.hasMatch(l));
    expect(from, greaterThanOrEqualTo(0), reason: '${p.path}: anchor of ${p.name}');
  }
  final starts = <int>[];
  for (var i = from; i < ls.length; i++) {
    if (p.start.hasMatch(ls[i])) starts.add(i);
    if (starts.isNotEmpty && i > starts.first) {
      if (p.tableEnd && !ls[i].startsWith('|')) break;
      if (p.endRe != null && p.endRe!.hasMatch(ls[i])) break;
    }
  }
  expect(starts.length, greaterThanOrEqualTo(2), reason: '${p.path}: ${p.name} has records');
  int up(int i) {
    var j = i;
    while (p.leader != null && j > 0 && p.leader!.hasMatch(ls[j - 1])) {
      j--;
    }
    return j;
  }

  switch (at) {
    case _At.front:
      return up(starts.first);
    case _At.middle:
      return up(starts[2 < starts.length ? 2 : 1]);
    case _At.end:
      var end = ls.length;
      for (var i = starts.first + 1; i < ls.length; i++) {
        if (p.tableEnd && !ls[i].startsWith('|')) {
          end = i;
          break;
        }
        if (p.endRe != null && p.endRe!.hasMatch(ls[i])) {
          end = i;
          break;
        }
      }
      return end;
  }
}

/// [x] with a probe record inserted at [at]; JSON gets its commas, blank-separated regions a blank
/// line where the previous line is text.
String _with(_Probe p, String x, String id, _At at) {
  final ls = _lines(x);
  final slot = _slot(p, ls, at);
  var rec = p.rec(id);
  if (p.comma) {
    if (at == _At.end) {
      // the previous element loses its "no comma" and the probe is the new last element
      final prev = ls[slot - 1];
      ls[slot - 1] = prev.replaceFirst(RegExp(r'\n$'), ',\n');
      rec = '$rec\n';
    } else {
      rec = '$rec,\n';
    }
  } else if (p.blank && at == _At.end && slot > 0 && ls[slot - 1].trim().isNotEmpty) {
    rec = '\n$rec';
  }
  return [...ls.sublist(0, slot), rec, ...ls.sublist(slot)].join();
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  final files = _probes.map((p) => p.path).toSet();

  group('the 8 real files round-trip losslessly', () {
    for (final path in files) {
      test(path, () {
        final x = _read(path);
        final spec = specOf(path);
        final r = resolveFile(spec, base: x, ours: x, theirs: x, textMerge: noMerge());
        expect(r.text, x);
        expect(r.partial, isFalse);
        expect(verifyResolution(spec, r, base: x, ours: x, theirs: x, textMerge: realMerge), isNull);
      });
    }
  });

  group('every region is found, has records, and every record has a key', () {
    for (final path in files) {
      test(path, () {
        final spec = specOf(path);
        final pieces = parseFile(_read(path), spec.regions);
        final regions = pieces.whereType<RegionPiece>().toList();
        expect(regions.length, spec.regions.length);
        for (final r in regions) {
          expect(r.records, isNotEmpty);
          for (final rec in r.records) {
            expect(rec.key, isNotEmpty);
          }
        }
        // the pieces concatenate back to the file: nothing is dropped between regions
        if (!spec.regions.any((s) => s.sep == Sep.comma)) {
          final back = StringBuffer();
          for (final p in pieces) {
            if (p is GapPiece) {
              back.write(p.text);
            } else if (p is RegionPiece) {
              for (final rec in p.records) {
                back.write(rec.text);
              }
            }
          }
          expect(back.toString(), _read(path));
        }
      });
    }

    test('every row of the two TABLE regions matches the record pattern (no absorbed prose)', () {
      for (final path in ['.claude/skills/debugging/SKILL.md', 'docs/naming_conventions.md']) {
        final spec = specOf(path);
        final table = spec.regions.firstWhere((r) => r.table);
        final region = parseFile(_read(path), spec.regions).whereType<RegionPiece>().firstWhere((p) => p.spec == table);
        for (final rec in region.records) {
          for (final l in splitLines(rec.text)) {
            expect(table.start.hasMatch(l), isTrue, reason: '$path: "${l.trim()}"');
          }
        }
      }
    });

    test('the registry owns its comment blocks: every comment directly above a concept is part of that concept\'s record', () {
      final x = _read('docs/sot_registry.yaml');
      final ls = _lines(x);
      var withLeader = 0;
      for (var i = 1; i < ls.length; i++) {
        if (ls[i].startsWith('  - concept: ') && ls[i - 1].startsWith('  #')) withLeader++;
      }
      expect(withLeader, greaterThan(0), reason: 'the real registry carries commented concepts; if it stops, this test needs a new anchor');
      final region = parseFile(x, specOf('docs/sot_registry.yaml').regions).whereType<RegionPiece>().single;
      var owned = 0;
      for (final rec in region.records) {
        final rl = splitLines(rec.text);
        final at = rl.indexWhere((l) => l.startsWith('  - concept: '));
        expect(rl.take(at).every((l) => l.startsWith('  #')), isTrue, reason: rec.key);
        if (at > 0) owned++;
      }
      expect(owned, withLeader);
    });

    test('duplicate keys exist only in the two files that legitimately repeat a key (ledger and glossary)', () {
      for (final path in files) {
        final region = parseFile(_read(path), specOf(path).regions).whereType<RegionPiece>();
        for (final r in region) {
          final seen = <String>{};
          final dup = <String>{};
          for (final rec in r.records) {
            if (!seen.add(rec.key)) dup.add(rec.key);
          }
          if (dup.isNotEmpty) {
            expect(path, anyOf('backups/applied_migrations.json', 'docs/naming_conventions.md'), reason: '$path repeats ${dup.join(', ')}');
          }
        }
      }
    });
  });

  group('one-sided changes reproduce the changed side byte for byte (resolve(x,x,y)==y and resolve(x,y,x)==y)', () {
    for (final p in _probes) {
      for (final at in _At.values) {
        test('${p.name}: a record at the ${at.name}', () {
          final x = _read(p.path);
          final y = _with(p, x, '1', at);
          expect(y, isNot(x));
          final spec = specOf(p.path);
          final m = FakeMerge();
          final a = resolveFile(spec, base: x, ours: x, theirs: y, textMerge: m.fn);
          final b = resolveFile(spec, base: x, ours: y, theirs: x, textMerge: m.fn);
          expect(a.text, y);
          expect(b.text, y);
          expect(m.calls, isEmpty);
          expect(verifyResolution(spec, a, base: x, ours: x, theirs: y, textMerge: realMerge), isNull);
          expect(verifyResolution(spec, b, base: x, ours: y, theirs: x, textMerge: realMerge), isNull);
        });
      }
    }
  });

  group('two sides append DIFFERENT records at the same spot: both survive, main (theirs) first', () {
    for (final p in _probes) {
      test(p.name, () {
        final x = _read(p.path);
        final ours = _with(p, x, '1', _At.end);
        final theirs = _with(p, x, '2', _At.end);
        final spec = specOf(p.path);
        final r = resolveFile(spec, base: x, ours: ours, theirs: theirs, textMerge: noMerge());
        expect(r.partial, isFalse);
        expect(r.mergedByLine, isEmpty);
        final baseKeys = keysOf(spec, x);
        final regionEnd = keysOf(spec, _with(p, x, '3', _At.end)).indexOf(_keyOf(spec, p, '3').single);
        expect(regionEnd, greaterThan(0));
        final want = [...baseKeys.sublist(0, regionEnd), ..._keyOf(spec, p, '2'), ..._keyOf(spec, p, '1'), ...baseKeys.sublist(regionEnd)];
        expect(keysOf(spec, r.text), want);
        expect(verifyResolution(spec, r, base: x, ours: ours, theirs: theirs, textMerge: realMerge), isNull);
      });
    }
  });
}

/// The key the lib derives for the probe record [id] (parsed from the record text itself).
List<String> _keyOf(FileSpec spec, _Probe p, String id) {
  final region = spec.regions.firstWhere((r) => r.start.hasMatch('${p.rec(id).split('\n').firstWhere((l) => l.trim().isNotEmpty)}\n'));
  final m = region.key.firstMatch(p.rec(id));
  expect(m, isNotNull);
  return [m!.group(1)!];
}
