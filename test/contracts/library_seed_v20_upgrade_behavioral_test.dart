// Batch C2c (seed v20, OI-474, docs/plans/2026-11-06-library-batch-c2c-e230.md): an install at the v19 library holds E230
// Standing Single Leg Curl as the CABLE row (equipment cables, weight_reps, tier basic_gym + full_gym, cable cues, no picture).
// Its next launch puts the bodyweight row in the box (the seed's putAll rewrites by id) and changes nothing else; a fresh install
// gets the bodyweight row. Drives the REAL SeedService.seedIfNeeded.
//
// Accepted (plan "Accepted behaviour changes" c): an install at v19 keeps the cable row until its next launch after the upgrade,
// and a plan already generated keeps its old notes / equipment_needed / logging_type until regenerated.
//
// Mutations (each reddens a test below): put the version constant back to 19; delete the media keys of E230 from the library;
// leave the cable cue in the library row; drop E230 from the seed.
//
// A plain test(), not testWidgets: real file I/O inside testWidgets hangs (CLAUDE.md section 4.9).
//
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';

import '../helpers/hive_test_setup.dart';

const _mediaKeys = ['media_slug', 'media_version', 'media_source'];

List<Map<String, dynamic>> _bundled() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _record() => jsonDecode(File('scripts/data/library_e230_retag.json').readAsStringSync()) as Map<String, dynamic>;

/// E230 as a v19 install holds it: the nine retag keys at `before`, and none of the media keys.
Map<String, dynamic> _v19E230(Map<String, dynamic> bundled) {
  final before = (_record()['before'] as Map).cast<String, dynamic>();
  return {for (final e in bundled.entries) if (!_mediaKeys.contains(e.key)) e.key: before.containsKey(e.key) ? before[e.key] : e.value};
}

Future<void> _markSeeded(HiveService hive, int exerciseVersion) async {
  await hive.configBox.put('seeded', true);
  await hive.configBox.put('seeded_exercises', true);
  await hive.configBox.put('seeded_foods', true);
  await hive.configBox.put('exercise_library_version', exerciseVersion);
  await hive.configBox.put('food_library_version', 9999);
}

Map<String, dynamic> _asJson(Object? row) => jsonDecode(jsonEncode(row)) as Map<String, dynamic>;

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(tempDir));

  test('a v19 box holding the cable E230 ends at v20 with the bodyweight E230, the picture keys, and every other row unchanged', () async {
    final hive = HiveService.instance;
    final bundled = _bundled();
    final after = (_record()['after'] as Map).cast<String, dynamic>();
    final shipped = bundled.singleWhere((r) => r['id'] == 'E230');
    for (final r in bundled) {
      await hive.exerciseBox.put(r['id'], r['id'] == 'E230' ? _v19E230(shipped) : r);
    }
    await _markSeeded(hive, 19);
    final old = _asJson(hive.exerciseBox.get('E230'));
    expect(old['equipment_needed'], ['cables'], reason: 'precondition: the v19 install holds the cable row');
    expect(old['logging_type'], 'weight_reps');
    expect(_mediaKeys.any(old.containsKey), isFalse, reason: 'precondition: no picture yet');
    final others = {for (final id in hive.exerciseBox.keys.where((k) => k != 'E230')) id as String: jsonEncode(_asJson(hive.exerciseBox.get(id)))};

    await SeedService.instance.seedIfNeeded();

    final now = _asJson(hive.exerciseBox.get('E230'));
    for (final k in after.keys) {
      expect(jsonEncode(now[k]), jsonEncode(after[k]), reason: 'E230.$k must be the record after');
    }
    expect(now['equipment_needed'], ['bodyweight']);
    expect(now['logging_type'], 'bodyweight_reps');
    expect((now['coaching_cues'] as List).first, (after['coaching_cues'] as List).first, reason: 'the cable cue must be gone');
    expect(now['media_slug'], '0795-standing-single-leg-curl');
    expect(now['media_version'], isA<int>());
    expect(now['media_source'], 'wardroom');
    expect(jsonEncode(now), jsonEncode(_asJson(shipped)), reason: 'the whole row is the bundled one');
    for (final e in others.entries) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(e.key))), e.value, reason: '${e.key} must be unchanged');
    }
    expect(hive.exerciseBox.length, bundled.length);
    expect(hive.configBox.get('exercise_library_version') as int, 23);
  });

  test('a fresh install gets the bodyweight E230 with its picture', () async {
    final hive = HiveService.instance;
    await SeedService.instance.seedIfNeeded();
    final e230 = _asJson(hive.exerciseBox.get('E230'));
    expect(e230['equipment_needed'], ['bodyweight']);
    expect(e230['logging_type'], 'bodyweight_reps');
    expect(e230['equipment_tier'], ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym']);
    expect(e230['media_slug'], '0795-standing-single-leg-curl');
    expect(hive.exerciseBox.length, _bundled().length);
    expect(hive.configBox.get('exercise_library_version') as int, 23);
  });

  test('MIRROR: a box already at the current version (v23, Library Batch S1b-2) is not rewritten (the upgrade fires only when the stored version is older)', () async {
    final hive = HiveService.instance;
    final shipped = _bundled().singleWhere((r) => r['id'] == 'E230');
    final marker = {..._v19E230(shipped), 'name': 'Left alone'};
    for (final r in _bundled()) {
      await hive.exerciseBox.put(r['id'], r['id'] == 'E230' ? marker : r);
    }
    await _markSeeded(hive, 23);
    await SeedService.instance.seedIfNeeded();
    expect(_asJson(hive.exerciseBox.get('E230'))['name'], 'Left alone');
    expect(hive.configBox.get('exercise_library_version') as int, 23);
  });
}
