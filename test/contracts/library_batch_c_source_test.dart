// Batch C1 (docs/plans/2026-10-25-library-batch-c-new-rows.md), Task 1.4: the
// source file scripts/data/library_batch_c_source.json and its scope contract.
//
// Two halves.
//   1. The scope contract C1-C6 (scripts/library_batch_c_scope.js --check) run on
//      the real files, then run again on a SANDBOX copy that each test mutates the way
//      a real regression would re-enter, with the exact set of failing contract
//      points asserted (the script prints EVERY failing point, never just the first).
//   2. Source-internal checks on the NON-HELD rows (held rows may collide in name or
//      carry raw tokens; they are checked for the `hold` shape only).
//
// Every literal about the data is computed by the test from the files, never typed.
@Timeout(Duration(minutes: 8))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';

import '../helpers/spawn.dart';

const _srcRel = 'scripts/data/library_batch_c_source.json';
const _mediaRel = 'scripts/data/library_batch_c_media_map.json';
const _libRel = 'assets/data/exercise_library.json';
const _scopeRel = 'scripts/library_batch_c_scope.js';

const _holdClasses = {'token', 'name_collision', 'low_confidence', 'picture'};
const _holdOwners = {'Batch D', 'C2', 'founder GIF review', 'founder'};

Map<String, dynamic> _readMap(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
/// The ORIGINAL library rows (E-ids): once the importer has run, the file also holds the new rows, and every check here
/// compares the SOURCE against what existed before it, so the new rows must not be counted as a collision with themselves.
List<Map<String, dynamic>> _readLib() => (jsonDecode(File(_libRel).readAsStringSync()) as List)
    .cast<Map<String, dynamic>>()
    .where((r) => RegExp(r'^E\d').hasMatch(r['id'] as String))
    .toList();
List<Map<String, dynamic>> _rows(Map<String, dynamic> src) => (src['rows'] as List).cast<Map<String, dynamic>>();
Map<String, dynamic> _row(Map<String, dynamic> src, String id) => _rows(src).firstWhere((r) => r['id'] == id);
Map<String, dynamic> _meta(Map<String, dynamic> src) => src['_meta'] as Map<String, dynamic>;
List<String> _strs(Object? v) => (v as List? ?? const []).map((e) => e.toString()).toList();

/// The failing contract points a `--check` run printed (`FAIL C3 (2)` lines).
Set<String> _failed(String out) =>
    RegExp(r'^FAIL (C\d)', multiLine: true).allMatches(out).map((m) => m.group(1)!).toSet();

/// A throw-away copy of the script, the source, the media map and the library, so a test
/// can break the data and run the REAL script against it (the script resolves its paths
/// from its own location, so the sandbox needs the same relative layout).
class _Sandbox {
  _Sandbox() : dir = Directory.systemTemp.createTempSync('lbc_scope_') {
    for (final rel in [_scopeRel, _srcRel, _mediaRel, _libRel]) {
      final dst = File('${dir.path}/$rel')..createSync(recursive: true);
      File(rel).copySync(dst.path);
    }
  }

  final Directory dir;
  Map<String, dynamic> src() => _readMap('${dir.path}/$_srcRel');
  void save(Map<String, dynamic> s) =>
      File('${dir.path}/$_srcRel').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(s)}\n');

  ProcessResult run(String mode) => runSpawn(
        'node',
        [_scopeRel, mode],
        why: 'library_batch_c_scope.js $mode on a mutated sandbox copy',
        workingDirectory: dir.path,
        report: (_) {},
      );

  /// `--check`, returns (exit code, failing points, stdout).
  ({int code, Set<String> points, String out}) check() {
    final r = run('--check');
    final out = '${r.stdout}';
    return (code: r.exitCode, points: _failed(out), out: out);
  }

  /// `--write` then `--check`: isolates a mutation from the stale derived counts it also causes.
  ({int code, Set<String> points, String out}) writeThenCheck() {
    final w = run('--write');
    expect(w.exitCode, 0, reason: '--write failed: ${w.stdout}${w.stderr}');
    return check();
  }

  void dispose() => dir.deleteSync(recursive: true);
}

/// The first row id passing [test] in source order (a fixture picker, not a literal).
String _pick(Map<String, dynamic> src, bool Function(Map<String, dynamic> r) test) =>
    _rows(src).firstWhere(test)['id'] as String;

bool _isLow(Map<String, dynamic> src, String id) =>
    ((_meta(src)['criterion_inputs'] as Map<String, dynamic>)[id] as Map<String, dynamic>)['confidence'] == 'low';

/// The recorded action of [id] in `_meta[file]`, or null when there is no entry.
String? _action(Map<String, dynamic> src, String file, String id) =>
    ((_meta(src)[file] as Map<String, dynamic>)[id] as Map<String, dynamic>?)?['action'] as String?;

void main() {
  group('scope contract C1-C6 on the real files', () {
    test('--check passes', () {
      final r = runSpawn('node', [_scopeRel, '--check'], why: 'library_batch_c_scope.js --check on the real files');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('check: OK (C1 to C6)'));
    });
  });

  group('scope contract: each mutation reddens exactly the points it should', () {
    late _Sandbox sb;
    setUp(() => sb = _Sandbox());
    tearDown(() => sb.dispose());

    test('control: the untouched sandbox is green (so the reds below are the mutations)', () {
      final c = sb.check();
      expect(c.code, 0, reason: c.out);
    });

    test('remove the picture_checked entry of G0845 -> C1', () {
      final s = sb.src();
      expect((_meta(s)['picture_checked'] as Map).remove('G0845'), isNotNull);
      sb.save(s);
      expect(sb.check().points, {'C1'});
    });

    test('remove the identity_checked entry of G0980 -> C1 (the identity direction)', () {
      final s = sb.src();
      expect((_meta(s)['identity_checked'] as Map).remove('G0980'), isNotNull);
      sb.save(s);
      final c = sb.check();
      expect(c.points, {'C1'});
      expect(c.out, contains('identity set id without identity_checked entry: G0980'));
    });

    test('an identity_checked entry for G0757, a row outside both sets, stays green (extra records are legal)', () {
      final s = sb.src();
      expect((_meta(s)['identity_checked'] as Map).containsKey('G0757'), isFalse);
      (_meta(s)['identity_checked'] as Map)['G0757'] = {'seen': 'x', 'action': 'unchanged'};
      sb.save(s);
      final c = sb.check();
      expect(c.code, 0, reason: c.out);
    });

    test('delete the hold of a low_confidence row that has no record -> C2 and C6', () {
      final s = sb.src();
      final id = _pick(s, (r) => (r['hold'] as Map?)?['class'] == 'low_confidence');
      _row(s, id).remove('hold');
      sb.save(s);
      expect(sb.check().points, {'C2', 'C6'});
    });

    test('release path: delete the low hold AND add the picture_checked record, then --write -> green', () {
      final s = sb.src();
      final id = _pick(s, (r) => (r['hold'] as Map?)?['class'] == 'low_confidence');
      _row(s, id).remove('hold');
      (_meta(s)['picture_checked'] as Map)[id] = {'seen': 'looked at the first frame', 'action': 'unchanged'};
      sb.save(s);
      final c = sb.writeThenCheck();
      expect(c.code, 0, reason: c.out);
    });

    test('the same release without --write -> C6 only (the held count is stale)', () {
      final s = sb.src();
      final id = _pick(s, (r) => (r['hold'] as Map?)?['class'] == 'low_confidence');
      _row(s, id).remove('hold');
      (_meta(s)['picture_checked'] as Map)[id] = {'seen': 'looked at the first frame', 'action': 'unchanged'};
      sb.save(s);
      expect(sb.check().points, {'C6'});
    });

    test('release a picture hold by deleting the hold only -> C3 (and C6 until --write)', () {
      final s = sb.src();
      final id = _pick(s, (r) => (r['hold'] as Map?)?['class'] == 'picture');
      _row(s, id).remove('hold');
      sb.save(s);
      expect(sb.check().points, {'C3', 'C6'});
      expect(sb.writeThenCheck().points, {'C3'});
    });

    test('release a row held in BOTH records by flipping only its picture entry -> C3', () {
      // Make G0472 held in both records (a consistent state), then release one side only.
      final s = sb.src();
      final r = _row(s, 'G0472');
      r['hold'] = {'class': 'picture', 'reason': 'test', 'owner': 'founder'};
      (_meta(s)['picture_checked'] as Map)['G0472'] = {'seen': 'held', 'action': 'hold'};
      (_meta(s)['identity_checked'] as Map)['G0472'] = {'seen': 'held', 'action': 'hold'};
      sb.save(s);
      final held = sb.writeThenCheck();
      expect(held.code, 0, reason: 'the consistent both-records hold must be green first: ${held.out}');
      final t = sb.src();
      _row(t, 'G0472').remove('hold');
      (_meta(t)['picture_checked'] as Map)['G0472'] = {'seen': 'released', 'action': 'unchanged'};
      sb.save(t);
      expect(sb.writeThenCheck().points, {'C3'});
    });

    test('add a picture_checked record to a low_confidence-held row and keep the hold -> C2', () {
      final s = sb.src();
      final id = _pick(s, (r) => (r['hold'] as Map?)?['class'] == 'low_confidence');
      (_meta(s)['picture_checked'] as Map)[id] = {'seen': 'looked', 'action': 'unchanged'};
      sb.save(s);
      expect(sb.check().points, {'C2'});
    });

    test('delete the low hold and add only an identity_checked record -> C2 (the low row needs a picture record)', () {
      final s = sb.src();
      final id = _pick(s, (r) => (r['hold'] as Map?)?['class'] == 'low_confidence');
      _row(s, id).remove('hold');
      (_meta(s)['identity_checked'] as Map)[id] = {'seen': 'looked', 'action': 'unchanged'};
      sb.save(s);
      expect(sb.check().points, {'C2', 'C6'});
      // --write puts the low_confidence hold back (a frozen-low row with no picture record is
      // held by construction), so the identity record alone never releases a low row.
      final c = sb.writeThenCheck();
      expect(c.code, 0, reason: c.out);
    });

    test('give a row that is not frozen-low a low_confidence hold -> C2', () {
      final s = sb.src();
      final id = _pick(s, (r) => r['hold'] == null && !_isLow(s, r['id'] as String));
      _row(s, id)['hold'] = {'class': 'low_confidence', 'reason': 'test', 'owner': 'founder GIF review'};
      sb.save(s);
      expect(sb.writeThenCheck().points, {'C2'});
    });

    test('a hold with owner nobody -> C5', () {
      final s = sb.src();
      final id = _pick(s, (r) => (r['hold'] as Map?)?['class'] == 'picture');
      (_row(s, id)['hold'] as Map)['owner'] = 'nobody';
      sb.save(s);
      expect(sb.check().points, {'C5'});
    });

    test('a hold without a reason -> C5', () {
      final s = sb.src();
      final id = _pick(s, (r) => (r['hold'] as Map?)?['class'] == 'picture');
      (_row(s, id)['hold'] as Map)['reason'] = '';
      sb.save(s);
      expect(sb.check().points, {'C5'});
    });

    test('remove hold.class from a row whose entry says hold -> C3 and C5', () {
      final s = sb.src();
      final id = _pick(s, (r) => (r['hold'] as Map?)?['class'] == 'picture');
      (_row(s, id)['hold'] as Map).remove('class');
      sb.save(s);
      expect(sb.writeThenCheck().points, {'C3', 'C5'});
    });

    test('a stray hold.class picture on a row whose entry says unchanged -> C3', () {
      final s = sb.src();
      final id = (_meta(s)['picture_checked'] as Map<String, dynamic>)
          .keys
          .firstWhere((k) => _action(s, 'picture_checked', k) == 'unchanged' && _row(s, k)['hold'] == null);
      _row(s, id)['hold'] = {'class': 'picture', 'reason': 'test', 'owner': 'founder'};
      sb.save(s);
      expect(sb.writeThenCheck().points, {'C3'});
    });

    test('a hold class spelled Picture -> C3, C5 and C6', () {
      final s = sb.src();
      final id = _pick(s, (r) => (r['hold'] as Map?)?['class'] == 'picture');
      (_row(s, id)['hold'] as Map)['class'] = 'Picture';
      sb.save(s);
      expect(sb.check().points, {'C3', 'C5', 'C6'});
    });

    test('blank one seen -> C4', () {
      final s = sb.src();
      final pic = _meta(s)['picture_checked'] as Map<String, dynamic>;
      (pic[pic.keys.first] as Map<String, dynamic>)['seen'] = '  ';
      sb.save(s);
      expect(sb.check().points, {'C4'});
    });

    test('blank one action -> C4', () {
      final s = sb.src();
      final pic = _meta(s)['picture_checked'] as Map<String, dynamic>;
      (pic[pic.keys.first] as Map<String, dynamic>)['action'] = '';
      sb.save(s);
      expect(sb.check().points, {'C4'});
    });

    test('action none on a real picture row (it has an animation) -> C4', () {
      final s = sb.src();
      final media = _readMap(_mediaRel);
      final pic = _meta(s)['picture_checked'] as Map<String, dynamic>;
      final id = pic.keys.firstWhere((k) => (media[k] as Map?)?['_gif'] != null);
      (pic[id] as Map<String, dynamic>)['action'] = 'none';
      sb.save(s);
      expect(sb.check().points, {'C4'});
    });

    test('change one per-class count in _meta.derived by one -> C6', () {
      final s = sb.src();
      final held = (_meta(s)['derived'] as Map)['held'] as Map;
      held['token'] = (held['token'] as int) + 1;
      sb.save(s);
      expect(sb.check().points, {'C6'});
    });

    test('change one per-level core count in _meta.derived by one -> C6', () {
      final s = sb.src();
      final core = (_meta(s)['derived'] as Map)['core'] as Map;
      core['beginner'] = (core['beginner'] as int) + 1;
      sb.save(s);
      expect(sb.check().points, {'C6'});
    });

    test('edit one row note (a hashed input) -> C6 only', () {
      final s = sb.src();
      final id = _pick(s, (r) => (r['hold'] as Map?)?['class'] == 'token');
      _row(s, id)['note'] = '${_row(s, id)['note']} edited';
      sb.save(s);
      expect(sb.check().points, {'C6'});
    });

    test('edit a frozen input, then --write: the snapshot must NOT move, C6 stays red', () {
      final s = sb.src();
      final id = _pick(s, (r) => (r['hold'] as Map?)?['class'] == 'token');
      ((_meta(s)['criterion_inputs'] as Map)[id] as Map)['name'] = 'Edited Name';
      sb.save(s);
      expect(sb.check().points, {'C6'});
      expect(sb.writeThenCheck().points, {'C6'});
    });

    test('a held low row\'s frozen equipment flipped to bodyweight -> C1 and C6; with the hash re-pinned only C1', () {
      final s = sb.src();
      final id = _pick(s, (r) => (r['hold'] as Map?)?['class'] == 'low_confidence');
      ((_meta(s)['criterion_inputs'] as Map)[id] as Map)['equipment_needed'] = ['bodyweight'];
      sb.save(s);
      final first = sb.check();
      expect(first.points, {'C1', 'C6'});
      final hash = RegExp(r'recomputed ([0-9a-f]{64})').firstMatch(first.out)!.group(1)!;
      final t = sb.src();
      _meta(t)['inputs_sha256'] = hash;
      sb.save(t);
      expect(sb.check().points, {'C1'});
    });
  });

  group('source rows (non-held): each check passes on the real data and goes red on its mutation', () {
    late Map<String, dynamic> src;
    late List<Map<String, dynamic>> lib;
    setUpAll(() {
      src = _readMap(_srcRel);
      lib = _readLib();
    });

    /// A deep copy the test may break freely.
    Map<String, dynamic> copy() => jsonDecode(jsonEncode(src)) as Map<String, dynamic>;

    test('ids are unique and no id collides with a library E-id', () {
      expect(_idViolations(src, lib), isEmpty);
    });
    test('MUTATION: a source id set to a library E-id is a violation', () {
      final s = copy();
      _rows(s).first['id'] = lib.first['id'];
      expect(_idViolations(s, lib), isNotEmpty);
    });
    test('MUTATION: two rows with one id is a violation', () {
      final s = copy();
      _rows(s)[1]['id'] = _rows(s)[0]['id'];
      expect(_idViolations(s, lib), isNotEmpty);
    });

    test('held rows carry a valid hold shape and _meta.derived equals a recount', () {
      expect(_holdViolations(src), isEmpty);
    });
    test('MUTATION: a stale held count, a bad class, a bad owner, an empty reason are each a violation', () {
      final a = copy();
      ((_meta(a)['derived'] as Map)['held'] as Map)['token'] = 99;
      expect(_holdViolations(a), isNotEmpty);
      for (final f in ['class', 'owner', 'reason']) {
        final s = copy();
        final id = _rows(s).firstWhere((r) => r['hold'] != null)['id'];
        (_row(s, id as String)['hold'] as Map)[f] = f == 'reason' ? ' ' : 'nobody';
        expect(_holdViolations(s), isNotEmpty, reason: f);
      }
    });

    test('the picture hold count is the number of DISTINCT row ids with action hold in either record', () {
      expect(_pictureHoldViolations(src), isEmpty);
      expect(_rows(src).where((r) => (r['hold'] as Map?)?['class'] == 'picture'), isNotEmpty,
          reason: 'the picture triage of Task 1.2 holds at least one row');
    });
    test('MUTATION: an action hold in the identity record alone for a row not held is a violation', () {
      final s = copy();
      (_meta(s)['identity_checked'] as Map)['G0472'] = {'seen': 'x', 'action': 'hold'};
      expect(_pictureHoldViolations(s), isNotEmpty);
    });

    test('equipment tokens are canonical on every shipped row', () {
      expect(_tokenViolations(src), isEmpty);
    });
    test('MUTATION: a raw token, and an empty list, on a shipped row are each a violation', () {
      final a = copy();
      _row(a, _firstShipped(a))['equipment_needed'] = ['weight plate'];
      expect(_tokenViolations(a), isNotEmpty);
      final b = copy();
      _row(b, _firstShipped(b))['equipment_needed'] = <String>[];
      expect(_tokenViolations(b), isNotEmpty);
    });

    test('the vocabulary maps each aliased raw token of a shipped, un-edited row to a token the row carries', () {
      expect(_aliasViolations(src), isEmpty);
      expect(_aliasChecked(src), greaterThan(0));
    });
    test('MUTATION: drop the mapped token from an aliased shipped row and the check reddens', () {
      final s = copy();
      final aliased = (_meta(s)['alias_applied'] as Map).keys.cast<String>();
      final id = aliased.firstWhere((i) =>
          _row(s, i)['hold'] == null &&
          _action(s, 'picture_checked', i) != 'edited' &&
          _action(s, 'identity_checked', i) != 'edited');
      _row(s, id)['equipment_needed'] = ['bodyweight'];
      expect(_aliasViolations(s), isNotEmpty);
    });

    test('names are unique case-insensitively across the library and the shipped source rows', () {
      expect(_nameViolations(src, lib), isEmpty);
    });
    test('MUTATION: a duplicated name, and releasing the hold of G1368 (same name as E084), are each a violation', () {
      final a = copy();
      _row(a, _firstShipped(a))['name'] = '${lib.first['name']}'.toUpperCase();
      expect(_nameViolations(a, lib), isNotEmpty);
      final b = copy();
      expect(_row(b, 'G1368')['hold'], isNotNull);
      _row(b, 'G1368').remove('hold');
      expect(_nameViolations(b, lib), isNotEmpty);
    });

    test('every ladder link resolves to exactly one name', () {
      expect(_linkViolations(src, lib), isEmpty);
    });
    test('MUTATION: a dangling link, and an ambiguous link (two rows, one name), are each a violation', () {
      final a = copy();
      _row(a, _firstShipped(a))['regression_to'] = 'No Such Exercise Anywhere';
      expect(_linkViolations(a, lib), isNotEmpty);
      // Ambiguous: point a link at a name that two rows share (the shared name is made on two held-off rows
      // so the name check, not the link check, is untouched by the setup).
      final b = copy();
      final shipped = _rows(b).where((r) => r['hold'] == null).toList();
      shipped[1]['name'] = shipped[0]['name'];
      shipped[2]['progression_to'] = shipped[0]['name'];
      final v = _linkViolations(b, lib);
      expect(v.where((e) => e.contains(shipped[2]['id'] as String)), isNotEmpty);
    });

    test('no semicolon inside either cue list of a shipped row', () {
      expect(_semicolonViolations(src), isEmpty);
    });
    test('MUTATION: a semicolon reintroduced in common_mistakes, and in coaching_cues, is a violation', () {
      final a = copy();
      (_row(a, _firstShipped(a))['common_mistakes'] as List)[0] = 'Too fast; too heavy';
      expect(_semicolonViolations(a), isNotEmpty);
      final b = copy();
      (_row(b, _firstShipped(b))['coaching_cues'] as List)[0] = 'Brace; breathe';
      expect(_semicolonViolations(b), isNotEmpty);
    });

    test('rows with identical coaching_cues share a first-primary muscle group, or a listed reason covers the group', () {
      expect(_cueGroupViolations(src), isEmpty);
    });
    test('MUTATION: copy G1730 (triceps) cues onto G0980 (glutes) -> red; a listed id with no reason stays red; with a reason green', () {
      final a = copy();
      _row(a, 'G0980')['coaching_cues'] = _row(a, 'G1730')['coaching_cues'];
      expect(_cueGroupViolations(a), isNotEmpty);
      (_meta(a)['identical_cues_ok'] as Map)['G0980'] = '';
      expect(_cueGroupViolations(a), isNotEmpty, reason: 'an entry without a reason does not cover the group');
      (_meta(a)['identical_cues_ok'] as Map)['G0980'] = 'a stated reason';
      expect(_cueGroupViolations(a), isEmpty);
    });

    test("each shipped row's movement_pattern overlaps its library siblings, or _meta.family_exception gives a reason", () {
      expect(_familyViolations(src, lib), isEmpty);
    });
    test('MUTATION: move a row to a family whose siblings share no pattern with it -> red', () {
      final s = copy();
      final id = _firstShipped(s);
      _row(s, id)['variant_family'] = 'stretch_quad'; // sibling pattern: cooldown
      _row(s, id)['movement_pattern'] = ['horizontal_push'];
      expect(_familyViolations(s, lib), isNotEmpty);
    });
  });
}

String _firstShipped(Map<String, dynamic> src) => _rows(src).firstWhere((r) => r['hold'] == null)['id'] as String;

List<Map<String, dynamic>> _shipped(Map<String, dynamic> src) => _rows(src).where((r) => r['hold'] == null).toList();

List<String> _idViolations(Map<String, dynamic> src, List<Map<String, dynamic>> lib) {
  final ids = _rows(src).map((r) => r['id'] as String).toList();
  final libIds = lib.map((r) => r['id'] as String).toSet();
  return [
    if (ids.toSet().length != ids.length) 'duplicate ids',
    ...ids.where(libIds.contains).map((i) => 'collides with a library id: $i'),
  ];
}

List<String> _holdViolations(Map<String, dynamic> src) {
  final out = <String>[];
  final rows = _rows(src);
  final held = rows.where((r) => r['hold'] != null).toList();
  for (final r in held) {
    final h = r['hold'] as Map<String, dynamic>;
    if (!_holdClasses.contains(h['class'])) out.add('${r['id']} class ${h['class']}');
    if (!_holdOwners.contains(h['owner'])) out.add('${r['id']} owner ${h['owner']}');
    if ('${h['reason']}'.trim().isEmpty) out.add('${r['id']} empty reason');
  }
  final count = <String, int>{for (final c in _holdClasses) c: 0};
  for (final r in held) {
    final c = (r['hold'] as Map)['class'];
    if (count.containsKey(c)) count[c as String] = count[c]! + 1;
  }
  final d = _meta(src)['derived'] as Map<String, dynamic>;
  if (jsonEncode((d['held'] as Map).cast<String, int>()) != jsonEncode(count)) out.add('held counts are stale');
  if (d['shipped'] != rows.length - held.length) out.add('shipped count is stale');
  if (d['rows'] != rows.length) out.add('rows count is stale');
  return out;
}

List<String> _pictureHoldViolations(Map<String, dynamic> src) {
  final ids = <String>{};
  for (final f in ['picture_checked', 'identity_checked']) {
    (_meta(src)[f] as Map).forEach((id, e) {
      if ((e as Map)['action'] == 'hold') ids.add(id as String);
    });
  }
  final picHeld = _rows(src).where((r) => (r['hold'] as Map?)?['class'] == 'picture').map((r) => r['id'] as String).toSet();
  return [
    ...ids.difference(picHeld).map((i) => '$i has an entry saying hold but is not picture-held'),
    ...picHeld.difference(ids).map((i) => '$i is picture-held but no entry says hold'),
  ];
}

List<String> _tokenViolations(Map<String, dynamic> src) {
  final out = <String>[];
  for (final r in _shipped(src)) {
    final eq = _strs(r['equipment_needed']);
    if (eq.isEmpty) out.add('${r['id']} has no equipment');
    for (final t in eq) {
      if (!EquipmentVocab.canonicalTokens.contains(t)) out.add('${r['id']} ${r['name']}: $t');
    }
  }
  return out;
}

Set<String> _editedIds(Map<String, dynamic> src) {
  final edited = <String>{};
  for (final f in ['picture_checked', 'identity_checked']) {
    (_meta(src)[f] as Map).forEach((id, e) {
      if ((e as Map)['action'] == 'edited') edited.add(id as String);
    });
  }
  return edited;
}

int _aliasChecked(Map<String, dynamic> src) {
  var n = 0;
  final edited = _editedIds(src);
  for (final e in (_meta(src)['alias_applied'] as Map<String, dynamic>).entries) {
    final r = _row(src, e.key);
    if (r['hold'] != null || edited.contains(e.key)) continue;
    n += _strs(e.value).length;
  }
  return n;
}

List<String> _aliasViolations(Map<String, dynamic> src) {
  final out = <String>[];
  final edited = _editedIds(src);
  for (final e in (_meta(src)['alias_applied'] as Map<String, dynamic>).entries) {
    final r = _row(src, e.key);
    if (r['hold'] != null || edited.contains(e.key)) continue;
    for (final raw in _strs(e.value)) {
      final mapped = EquipmentVocab.normalizeToken(raw);
      if (mapped == null || !_strs(r['equipment_needed']).contains(mapped)) out.add('${e.key} $raw -> $mapped');
    }
  }
  return out;
}

List<String> _nameViolations(Map<String, dynamic> src, List<Map<String, dynamic>> lib) {
  final seen = <String, String>{};
  final out = <String>[];
  for (final r in [...lib, ..._shipped(src)]) {
    final k = '${r['name']}'.toLowerCase();
    if (seen.containsKey(k)) out.add('"${r['name']}" ${r['id']} collides with ${seen[k]}');
    seen[k] = r['id'] as String;
  }
  return out;
}

List<String> _linkViolations(Map<String, dynamic> src, List<Map<String, dynamic>> lib) {
  final count = <String, int>{};
  for (final r in [...lib, ..._shipped(src)]) {
    count.update('${r['name']}'.toLowerCase(), (v) => v + 1, ifAbsent: () => 1);
  }
  final out = <String>[];
  for (final r in _shipped(src)) {
    for (final k in ['regression_to', 'progression_to']) {
      final v = r[k];
      if (v == null) continue;
      if (count['$v'.toLowerCase()] != 1) out.add('${r['id']}.$k -> "$v" resolves to ${count['$v'.toLowerCase()] ?? 0} rows');
    }
  }
  return out;
}

List<String> _semicolonViolations(Map<String, dynamic> src) {
  final out = <String>[];
  for (final r in _shipped(src)) {
    for (final k in ['coaching_cues', 'common_mistakes']) {
      for (final it in _strs(r[k])) {
        if (it.contains(';')) out.add('${r['id']} $k: $it');
      }
    }
  }
  return out;
}

List<String> _cueGroupViolations(Map<String, dynamic> src) {
  final ok = (_meta(src)['identical_cues_ok'] as Map).cast<String, dynamic>();
  final byCues = <String, List<Map<String, dynamic>>>{};
  for (final r in _shipped(src)) {
    byCues.putIfAbsent(jsonEncode(r['coaching_cues']), () => []).add(r);
  }
  final out = <String>[];
  for (final grp in byCues.values) {
    if (grp.length < 2) continue;
    final groups = grp
        .map((r) => BudgetMuscleGroups.of(_strs(r['primary_muscles']).take(1).toList()).toList()..sort())
        .map((g) => g.join('+'))
        .toSet();
    if (groups.length < 2) continue;
    final covered = grp.any((r) => '${ok[r['id']] ?? ''}'.trim().isNotEmpty);
    if (!covered) out.add('$groups: ${grp.map((r) => r['id']).join(' ')}');
  }
  return out;
}

List<String> _familyViolations(Map<String, dynamic> src, List<Map<String, dynamic>> lib) {
  final exc = (_meta(src)['family_exception'] as Map).cast<String, dynamic>();
  final out = <String>[];
  for (final r in _shipped(src)) {
    final fam = r['variant_family'];
    if (fam == null) continue;
    final sibs = lib.where((l) => l['variant_family'] == fam).toList();
    if (sibs.isEmpty) continue;
    final pats = {for (final s in sibs) ..._strs(s['movement_pattern'])};
    final mine = _strs(r['movement_pattern']);
    if (!mine.any(pats.contains) && '${exc[r['id']] ?? ''}'.trim().isEmpty) {
      out.add('${r['id']} ${r['name']} family $fam pattern $mine vs siblings $pats');
    }
  }
  return out;
}
