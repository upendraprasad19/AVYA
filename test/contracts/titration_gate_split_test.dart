// The titration / plateau gate was ONE test file over three goals until 2026-11-24, and is now three per-goal files
// on test/helpers/titration_plateau_gate_lib.dart (plan docs/plans/2026-11-24-ci-sweep-split.md section 6d). The gate
// itself is a sweep (minutes per goal; on a pull request it runs only when its inputs changed). This file is the
// cheap, always-run half of the split's contract:
//   - the per-goal pins sum to the totals the single file pinned, so the three files check what the one file did;
//   - every pinned goal has its file, calling the lib for THAT goal, and no gate file exists for an unpinned goal
//     (a deleted or mis-pointed file would otherwise silently drop a third of the grid).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/titration_plateau_gate_lib.dart';

const _dir = 'test/plan_generator';
const _prefix = 'titration_plateau_gate_';
const _suffix = '_test.dart';

/// `null` when the three goals' pins are whole and sum to [totals]; else what is wrong.
String? pinsProblem(Map<String, Map<String, int>> pins, Map<String, int> totals, List<String> keys) {
  if (keys.toSet().length != keys.length) return 'a pin key is listed twice';
  if (!(totals.keys.toSet().containsAll(keys) && totals.length == keys.length)) return 'totals and keys differ';
  for (final e in pins.entries) {
    if (!(e.value.keys.toSet().containsAll(keys) && e.value.length == keys.length)) {
      return '${e.key}: pinned keys differ from the key list';
    }
  }
  for (final k in keys) {
    final sum = pins.values.fold<int>(0, (s, m) => s + m[k]!);
    if (sum != totals[k]) return '$k: the goals sum to $sum, the single file pinned ${totals[k]}';
  }
  return null;
}

/// `null` when [files] (name -> source) are exactly one gate file per goal, each calling the lib for its own goal.
String? filesProblem(Map<String, String> files, Iterable<String> goals) {
  final want = {for (final g in goals) '$_prefix$g$_suffix': g};
  for (final name in files.keys) {
    if (!want.containsKey(name)) return '$name: a gate file for a goal with no pins';
  }
  for (final e in want.entries) {
    final src = files[e.key];
    if (src == null) return '${e.key}: missing';
    final calls = RegExp(r"defineTitrationPlateauGate\('([^']*)'\)").allMatches(src).map((m) => m.group(1)).toList();
    if (calls.length != 1 || calls.single != e.value) return '${e.key}: calls the gate for $calls';
  }
  return null;
}

void main() {
  test('the per-goal pins are whole and sum to what the single 3-goal file pinned', () {
    expect(titrationGatePins.keys, ['build_muscle', 'lose_fat', 'general_fitness']);
    expect(pinsProblem(titrationGatePins, titrationGateTotals, titrationGatePinKeys), isNull);
  });

  test('every pinned goal has its own gate file, and only those exist', () {
    final files = {
      for (final f in Directory(_dir).listSync().whereType<File>())
        if (f.uri.pathSegments.last.startsWith(_prefix) && f.path.endsWith(_suffix))
          f.uri.pathSegments.last: f.readAsStringSync(),
    };
    expect(filesProblem(files, titrationGatePins.keys), isNull);
  });

  group('the two checks reject what they exist for', () {
    const keys = ['a', 'b'];
    const totals = {'a': 3, 'b': 5};
    const good = {
      'x': {'a': 1, 'b': 5},
      'y': {'a': 2, 'b': 0},
    };
    String src(String g) => "void main() => defineTitrationPlateauGate('$g');";

    test('pins', () {
      expect(pinsProblem(good, totals, keys), isNull);
      expect(pinsProblem({...good, 'y': {'a': 2, 'b': 1}}, totals, keys), contains('b: the goals sum to 6'));
      expect(pinsProblem({...good, 'y': {'a': 2}}, totals, keys), contains('y: pinned keys differ'));
      expect(pinsProblem({...good, 'y': {'a': 2, 'b': 0, 'c': 0}}, totals, keys), contains('y: pinned keys differ'));
      expect(pinsProblem(good, {...totals, 'c': 1}, keys), 'totals and keys differ');
      expect(pinsProblem(good, totals, ['a', 'a']), 'a pin key is listed twice');
    });

    test('files', () {
      final ok = {'${_prefix}x$_suffix': src('x'), '${_prefix}y$_suffix': src('y')};
      expect(filesProblem(ok, ['x', 'y']), isNull);
      expect(filesProblem({...ok}..remove('${_prefix}y$_suffix'), ['x', 'y']), contains('y_test.dart: missing'));
      expect(filesProblem({...ok, '${_prefix}y$_suffix': src('x')}, ['x', 'y']), contains('calls the gate for [x]'));
      expect(filesProblem({...ok, '${_prefix}y$_suffix': src('y') + src('x')}, ['x', 'y']), contains('calls the gate'));
      expect(filesProblem({...ok, '${_prefix}z$_suffix': src('z')}, ['x', 'y']), contains('no pins'));
    });
  });
}
