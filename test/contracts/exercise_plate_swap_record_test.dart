// Batch A Task 4 — plate frame order and two wrong drawings.
//
// On 19 pairs the upstream catalogue's frame 1 is the END of the movement and
// frame 3 the START, so the plate sheet showed them backwards (founder review,
// 2026-10-21). The build script now writes those slugs' frames swapped
// (SWAP_FRAMES); the fixture records, from the files BEFORE the swap, which
// bytes each committed file must hold, so a rebuild without the swap list -- or
// a hand-renamed file -- fails here.
//
// E207 Torso Twists drew a standing stretch and E179 Toes to Bar a hanging leg
// raise; both lose their plate keys, and E207's slug files go with it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;

const _swapped = <String>{
  'pike-push-up', 'cable-curl', 'hanging-leg-raise', 'rowing', 'band-pull-apart',
  'pull-up', 'cable-kickback', 'banded-lateral-walk', 'landmine-press',
  'meadows-row', 'spider-curl', 'v-up', 'jumping-jack', 'arm-circles',
  'frog-pump', 'machine-row', 'donkey-kick', 'feet-elevated-pike-push-up',
  'prone-y-raise',
};

void main() {
  final fixture = (jsonDecode(
    File('test/fixtures/plate_swap_hashes.json').readAsStringSync(),
  ) as Map<String, dynamic>);

  test('build_exercise_plates.py declares SWAP_FRAMES as exactly the 19 slugs', () {
    final src = File('scripts/build_exercise_plates.py').readAsStringSync();
    final decl = RegExp(r'^SWAP_FRAMES = \{([^}]*)\}', multiLine: true).firstMatch(src);
    expect(decl, isNotNull, reason: 'SWAP_FRAMES = {...} not declared');
    final slugs = RegExp(r'"([a-z0-9-]+)"')
        .allMatches(decl!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();
    expect(slugs, _swapped);
  });

  test('the fixture covers the same 19 slugs', () {
    expect(fixture.keys.toSet(), _swapped);
  });

  test('each swapped slug ships the frames in START/END order', () {
    final wrong = <String>[];
    for (final slug in _swapped) {
      for (final frame in ['1', '3']) {
        final file = File('assets/exercise_plates/$slug-$frame.svg');
        final want = (fixture[slug] as Map)[frame];
        final got = file.existsSync() ? sha256Hex(file.readAsBytesSync()) : 'missing';
        if (got != want) wrong.add('$slug-$frame.svg');
      }
    }
    expect(wrong, isEmpty, reason: 'not in START/END order: $wrong');
  });

  test('E207 and E179 carry no plate keys, and torso-twist-stretch is gone', () {
    final rows = (jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List)
        .cast<Map<String, dynamic>>();
    for (final id in ['E207', 'E179']) {
      final row = rows.singleWhere((r) => r['id'] == id);
      expect(row.containsKey('demo_slug'), isFalse, reason: '$id demo_slug');
      expect(row.containsKey('demo_pair'), isFalse, reason: '$id demo_pair');
    }
    final left = Directory('assets/exercise_plates')
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.startsWith('torso-twist-stretch-'))
        .toList();
    expect(left, isEmpty);
  });
}
