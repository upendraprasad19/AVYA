@Timeout(Duration(minutes: 8))
library;

// test/scripts/sync_resolver_fuzz_test.dart
//
// Row F of docs/plans/sync-resolver.md section 5: 80 seeds x three region shapes (blank-separated board,
// table rows with no separator, JSON elements with commas). A random base, two random op sequences (add
// anywhere, delete, edit a line, append, prepend; never a move, never both sides deleting the same record,
// never an identical add combined with a delete), merged with a REAL `git merge-file` as the text merge.
//
// The oracle is an independent set model of the decision table of section 4.3, computed from the
// generator's own model of each version (not from the lib's parser): per key, equal sides -> that, one
// side unchanged -> the other, both changed -> the real text merge of the three record texts. It asserts
// the key set, every clean record's text, the partial flag and the conflicted keys, the relative order of
// each side's records, V-a and V-c on every clean result (no false positive) and the interval form of V-a
// on every conflicted result. V-b rejections are COUNTED, not forbidden: a correct merge can be rejected
// (section 4.4), and the pinned bound is the first run's rate rounded up.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/sync_resolver_lib.dart';
import '../helpers/sync_resolver_fixtures.dart';

class _Rec {
  _Rec(this.key, this.lines);

  final String key;
  final List<String> lines;

  _Rec copy() => _Rec(key, List.of(lines));
}

abstract class _Shape {
  String get name;
  FileSpec get spec;

  /// The record's text without trailing blank lines.
  String render(_Rec r);

  String file(List<_Rec> recs);

  /// Fresh body lines for a new record tagged [tag].
  List<String> body(String tag, Random rnd);

  String key(int n);
}

class _BoardShape extends _Shape {
  @override
  String get name => 'board';
  @override
  FileSpec get spec => specOf('docs/audit/open_issues.md');
  @override
  String render(_Rec r) => '## ${r.key} — probe\n\n${r.lines.join('\n')}';
  @override
  String file(List<_Rec> recs) => '# Board\n\nprose\n\n${recs.map((r) => '${render(r)}\n\n').join()}';
  @override
  List<String> body(String tag, Random rnd) => ['- **Status**: OPEN', '- **Tag**: $tag', '- **Note**: n${rnd.nextInt(1000)}', '- **Last**: l$tag'];
  @override
  String key(int n) => 'OI-$n';
}

class _TableShape extends _Shape {
  @override
  String get name => 'table';
  @override
  FileSpec get spec => specOf('docs/naming_conventions.md');
  @override
  String render(_Rec r) => '| ${r.key} | ${r.lines.join(' / ')} |';
  @override
  String file(List<_Rec> recs) => glossary(recs.map((r) => '${render(r)}\n').toList());
  @override
  List<String> body(String tag, Random rnd) => ['shared definition', 'tag $tag'];
  @override
  String key(int n) => '**k$n**';
}

class _JsonShape extends _Shape {
  @override
  String get name => 'json';
  @override
  FileSpec get spec => specOf('backups/applied_migrations.json');
  @override
  String render(_Rec r) => '  {\n    "migration": "${r.key}",\n${r.lines.join(',\n')}\n  }';
  @override
  String file(List<_Rec> recs) => '[\n${recs.map(render).join(',\n')}\n]\n';
  @override
  List<String> body(String tag, Random rnd) => ['    "kind": "sql"', '    "tag": "$tag"', '    "note": "n${rnd.nextInt(1000)}"', '    "last": "l$tag"'];
  @override
  String key(int n) => 'm$n';
}

/// [line] with its value replaced by [value], keeping the markup (`- **Key**: `, `"key": "..."`).
String _edited(String line, String value) {
  final lead = RegExp(r'^(\s*(- \*\*\w+\*\*: |"\w+": ")?)').firstMatch(line)!.group(1)!;
  final tail = line.endsWith('"') ? '"' : '';
  return '$lead$value$tail';
}

/// One random side: a copy of [base] after 1-4 ops. [deleted] collects deleted base keys.
List<_Rec> _side(_Shape shape, List<_Rec> base, Random rnd, String who, int keyBase, Set<String> forbidDelete, Set<String> deleted, {required bool allowDelete}) {
  final recs = [for (final r in base) r.copy()];
  var added = 0;
  var edits = 0;
  for (var n = 1 + rnd.nextInt(4); n > 0; n--) {
    final op = rnd.nextInt(allowDelete ? 6 : 5);
    switch (op) {
      case 0: // add anywhere
      case 1:
        final key = shape.key(keyBase + added++);
        recs.insert(rnd.nextInt(recs.length + 1), _Rec(key, shape.body('$who-$key', rnd)));
      case 2: // append
        final key = shape.key(keyBase + added++);
        recs.add(_Rec(key, shape.body('$who-$key', rnd)));
      case 3: // prepend
        final key = shape.key(keyBase + added++);
        recs.insert(0, _Rec(key, shape.body('$who-$key', rnd)));
      case 4: // edit one line of a random record
        if (recs.isEmpty) break;
        // 70% of the edits hit the first record so both sides often edit the same one
        final r = recs[rnd.nextInt(10) < 7 ? 0 : rnd.nextInt(recs.length)];
        // mostly the first line (ours) or the last line (theirs): two edits of one record that git can merge by line
        var i = rnd.nextInt(3) == 0 ? rnd.nextInt(r.lines.length) : (who == 'o' ? 1 : r.lines.length - 1);
        // line 0 is the line every record shares. Changing it on one side while the other deletes the record, or while both
        // add the same record, is the documented V-a false positive of net deltas (section 4.4), so the generator never does
        if (i == 0) i = 1 + rnd.nextInt(r.lines.length - 1);
        final line = r.lines[i];
        r.lines[i] = _edited(line, 'edit-$who-${edits++}');
      default: // delete a base record the other side did not delete
        final candidates = [for (var i = 0; i < recs.length; i++) if (base.any((b) => b.key == recs[i].key) && !forbidDelete.contains(recs[i].key)) i];
        if (candidates.isEmpty) break;
        final i = candidates[rnd.nextInt(candidates.length)];
        deleted.add(recs[i].key);
        recs.removeAt(i);
    }
  }
  return recs;
}

Map<String, String> _texts(_Shape shape, List<_Rec> recs) => {for (final r in recs) r.key: trimEnd(shape.render(r))};

String _summary(List<_Rec> base, List<_Rec> ours, List<_Rec> theirs, List<String> out) {
  String edited(List<_Rec> side, _Rec? b, String key) {
    final r = side.where((e) => e.key == key).firstOrNull;
    if (r == null) return 'absent';
    return b == null ? 'new' : (r.lines.join() == b.lines.join() ? 'same' : 'edited');
  }

  final keys = {for (final r in base) r.key, for (final r in ours) r.key, for (final r in theirs) r.key};
  final lines = [
    'base   ${[for (final r in base) r.key]}',
    'ours   ${[for (final r in ours) r.key]}',
    'theirs ${[for (final r in theirs) r.key]}',
    'out    $out',
    for (final k in keys) '  $k: ours ${edited(ours, base.where((e) => e.key == k).firstOrNull, k)}, theirs ${edited(theirs, base.where((e) => e.key == k).firstOrNull, k)}',
  ];
  return lines.join('\n');
}

/// Removes every conflict block (marker lines included) from [text].
String _stripBlocks(String text) {
  final out = <String>[];
  var inBlock = false;
  for (final l in text.split('\n')) {
    if (l.startsWith('$kOpen ')) {
      inBlock = true;
      continue;
    }
    if (inBlock && l.startsWith('$kClose ')) {
      inBlock = false;
      continue;
    }
    if (!inBlock) out.add(l);
  }
  return out.join('\n');
}

class _Tally {
  int cases = 0;
  int clean = 0;
  int partial = 0;
  int byLine = 0;
  int vbRejectedPlain = 0;
  int vbRejectedSpecial = 0;
  int plain = 0;
  int identical = 0;
  int collisions = 0;
}

final _Tally _tally = _Tally();


void _runSeed(_Shape shape, int seed) {
  final rnd = Random(seed * 7919 + shape.name.length);
  final baseN = 3 + rnd.nextInt(6);
  final base = [for (var i = 0; i < baseN; i++) _Rec(shape.key((i + 1) * 10), shape.body('b${(i + 1) * 10}', rnd))];
  final identical = seed % 8 == 3;
  final collide = seed % 8 == 5;
  // a record both sides added at DIFFERENT places cannot keep both sides' order: it follows ours
  // (the same holds for a collision: the conflicted record anchors theirs-only neighbours at ours' place)
  final scattered = (identical && seed % 16 == 3) || collide;
  final oursDeleted = <String>{}, theirsDeleted = <String>{};
  final ours = _side(shape, base, rnd, 'o', 1000, const {}, oursDeleted, allowDelete: !identical);
  final theirs = _side(shape, base, rnd, 't', 2000, oursDeleted, theirsDeleted, allowDelete: !identical);
  if (seed % 8 == 1) {
    // both sides edit ONE record, ours its second line and theirs its last: git merges that by line
    final k = base[rnd.nextInt(base.length)].key;
    final oRec = ours.where((e) => e.key == k).firstOrNull, tRec = theirs.where((e) => e.key == k).firstOrNull;
    if (oRec != null && tRec != null) {
      oRec.lines[1] = _edited(oRec.lines[1], 'dual-o');
      tRec.lines[tRec.lines.length - 1] = _edited(tRec.lines.last, 'dual-t');
    }
  }
  if (identical) {
    final same = _Rec(shape.key(3000), shape.body('same', rnd));
    if (scattered) {
      ours.insert(rnd.nextInt(ours.length + 1), same.copy());
      theirs.insert(rnd.nextInt(theirs.length + 1), same.copy());
    } else {
      ours.add(same.copy());
      theirs.add(same.copy());
    }
    _tally.identical++;
  }
  if (collide) {
    ours.insert(rnd.nextInt(ours.length + 1), _Rec(shape.key(4000), shape.body('ours-collision', rnd)));
    theirs.insert(rnd.nextInt(theirs.length + 1), _Rec(shape.key(4000), shape.body('theirs-collision', rnd)));
    _tally.collisions++;
  }
  final b = shape.file(base), o = shape.file(ours), t = shape.file(theirs);
  final why = 'shape=${shape.name} seed=$seed';
  _tally.cases++;
  if (!identical && !collide) _tally.plain++;

  // ---- the oracle: an independent set model of the decision table
  final bt = _texts(shape, base), ot = _texts(shape, ours), tt = _texts(shape, theirs);
  final keys = {...bt.keys, ...ot.keys, ...tt.keys};
  final want = <String, String>{};
  final wantConflicted = <String>{};
  final wantByLine = <String>{};
  for (final k in keys) {
    final bb = bt[k], oo = ot[k], t2 = tt[k];
    if (oo == t2) {
      if (oo != null) want[k] = oo;
    } else if (oo == bb) {
      if (t2 != null) want[k] = t2;
    } else if (t2 == bb) {
      if (oo != null) want[k] = oo;
    } else {
      String raw(List<_Rec> recs, String key) {
        for (final r in recs) {
          if (r.key == key) return '${shape.render(r)}\n';
        }
        return '';
      }

      final m = realMerge(raw(base, k), raw(ours, k), raw(theirs, k));
      (m.conflicted ? wantConflicted : wantByLine).add(k);
      if (!m.conflicted) want[k] = trimEnd(m.text);
    }
  }

  final Resolution r;
  try {
    r = resolveFile(shape.spec, base: b, ours: o, theirs: t, textMerge: realMerge);
  } on Unresolvable catch (e) {
    fail('$why: unresolvable on a legal input: ${e.reason}\n--- base\n$b--- ours\n$o--- theirs\n$t');
  }

  expect(r.partial, wantConflicted.isNotEmpty, reason: why);
  expect(r.conflictedKeys.toSet(), wantConflicted, reason: why);
  expect(r.mergedByLine.toSet(), wantByLine, reason: why);

  // ---- the records: every clean record is present with the oracle's text, nothing else but conflicted keys
  final shown = r.partial ? _stripBlocks(r.text) : r.text;
  final got = <String, String>{};
  var gotKeys = <String>[];
  if (r.partial) {
    // a conflicted record may leave its heading behind when git merged part of it cleanly
    final recs = parseFile(shown, shape.spec.regions).whereType<RegionPiece>().single.records;
    for (final rec in recs) {
      got[rec.key] = trimEnd(rec.text);
    }
    gotKeys = [for (final rec in recs) rec.key];
    for (final k in want.keys) {
      expect(got[k], want[k], reason: '$why: record $k\n${r.text}');
    }
    for (final k in got.keys) {
      expect(want.containsKey(k) || wantConflicted.contains(k), isTrue, reason: '$why: unexpected record $k\n${r.text}');
    }
  } else {
    final recs = parseFile(shown, shape.spec.regions).whereType<RegionPiece>().single.records;
    for (final rec in recs) {
      expect(got.containsKey(rec.key), isFalse, reason: '$why: record ${rec.key} twice');
      got[rec.key] = trimEnd(rec.text);
    }
    gotKeys = [for (final rec in recs) rec.key];
    expect(got, want, reason: '$why\n${r.text}');
  }

  // ---- order: each side's own records keep their relative order
  List<String> restrict(List<String> order, Iterable<String> only) {
    final s = only.toSet();
    return [for (final k in order) if (s.contains(k)) k];
  }

  final survivors = gotKeys.toSet();
  expect(restrict(gotKeys, ours.map((e) => e.key).where(survivors.contains)), restrict([for (final e in ours) e.key], survivors), reason: '$why: ours order\n${_summary(base, ours, theirs, gotKeys)}');
  if (!scattered) {
    expect(restrict(gotKeys, theirs.map((e) => e.key).where(survivors.contains)), restrict([for (final e in theirs) e.key], survivors), reason: '$why: theirs order\n${_summary(base, ours, theirs, gotKeys)}');
  }

  // ---- the checks
  final comma = shape.spec.regions.any((s) => s.sep == Sep.comma);
  expect(checkCounts(b, o, t, r.text, comma: comma), isEmpty, reason: '$why: V-a\n${_summary(base, ours, theirs, gotKeys)}\n${r.text}');
  if (r.partial) {
    _tally.partial++;
  } else {
    _tally.clean++;
    if (r.mergedByLine.isNotEmpty) _tally.byLine++;
    expect(checkStructure(shape.spec, r.text, r.decisions), isNull, reason: '$why: V-c\n${r.text}');
  }
  if (checkAgreement(b, o, t, r.text, realMerge, comma: comma) != null) {
    if (identical || collide) {
      _tally.vbRejectedSpecial++;
    } else {
      _tally.vbRejectedPlain++;
    }
  }
}

void main() {
  final shapes = <_Shape>[_BoardShape(), _TableShape(), _JsonShape()];
  for (final shape in shapes) {
    for (var chunk = 0; chunk < 4; chunk++) {
      test('${shape.name}: seeds ${chunk * 20}..${chunk * 20 + 19}', () {
        final failures = <String>[];
        for (var s = chunk * 20; s < chunk * 20 + 20; s++) {
          try {
            _runSeed(shape, s);
          } on TestFailure catch (e) {
            failures.add('seed $s: ${'$e'.split('\n').take(80).join('\n')}');
          }
        }
        expect(failures, isEmpty);
      });
    }
  }

  tearDownAll(() {
    // ignore: avoid_print
    print('sync_resolver fuzz: ${_tally.cases} cases, ${_tally.clean} clean (${_tally.byLine} merged by line), '
        '${_tally.partial} partial, ${_tally.identical} identical adds, ${_tally.collisions} collisions, '
        'V-b rejections: ${_tally.vbRejectedPlain} of ${_tally.plain} plain, ${_tally.vbRejectedSpecial} of ${_tally.identical + _tally.collisions} identical/collision');
  });

  test('coverage and the pinned V-b rejection rate over all seeds', () {
    // The tests above run in this order inside one isolate, so the tally is complete here.
    expect(_tally.cases, 240);
    expect(_tally.collisions, greaterThan(0));
    expect(_tally.identical, greaterThan(0));
    expect(_tally.partial, greaterThan(0));
    expect(_tally.byLine, greaterThan(5), reason: 'the generator must reach clean line merges of one record');
    // A correct merge CAN be rejected by V-b (section 4.4); the measured rejections are all in the seeds where both
    // sides add the same key at scattered places (26 of 60); one plain seed (json 20: adjacent deletions plus an edit
    // in a comma region, the documented shape) is rejected (1 of 180). Each bound is the measured rate rounded up.
    expect(_tally.vbRejectedPlain / _tally.plain, lessThanOrEqualTo(0.01));
    expect(_tally.vbRejectedSpecial / (_tally.identical + _tally.collisions), lessThanOrEqualTo(0.44));
  });
}
