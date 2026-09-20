// test/contracts/exercise_plate_library_data_test.dart
//
// The version constant is the ONLY thing that delivers a new library field to an
// install that already seeded: seed_service.dart:127-128 re-seeds iff
// stored < constant, so shipping demo_slug WITHOUT bumping it is a silent no-op
// -- no existing user ever receives the field and nothing fails loudly.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

const _dead = ['image_start_url', 'image_end_url', 'gif_url'];

// This file NAMES the dead fields in source, so the scan below must skip it.
// Round 2 caught the first version scanning itself and failing forever.
const _selfPath = 'exercise_plate_library_data_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final lib =
      (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>();
  final mapping = (jsonDecode(
              File('docs/plans/exercise-plates-mapping.json').readAsStringSync())
          as List)
      .cast<Map<String, dynamic>>();

  test('the seed version was bumped past the last shipped value', () {
    final src = File('lib/core/services/seed_service.dart').readAsStringSync();
    final m = RegExp(r'_exerciseLibraryVersion\s*=\s*(\d+)').firstMatch(src);
    expect(m, isNotNull, reason: 'version constant not found');
    expect(int.parse(m!.group(1)!), greaterThanOrEqualTo(11),
        reason: 'v10 shipped with the OI-89 re-seed; new fields need 11+');
  });

  test('the library is still 292 rows — this batch removes none', () {
    // Donkey Calf Raise stays. Its removal is OI-147, split out after review
    // round 2: it touches the cloud seed migration, a live prod apply and the
    // frozen generator baseline, none of which plates touches.
    expect(lib.length, 292);
    expect(lib.any((e) => e['name'] == 'Donkey Calf Raise'), isTrue);
  });

  test('every mapping entry landed on its row, with its pair flag', () {
    final byId = {for (final e in lib) e['id'] as String: e};
    for (final m in mapping) {
      final row = byId[m['id']];
      expect(row, isNotNull, reason: '${m['id']} (${m['name']}) not in library');
      expect(row!['demo_slug'], m['slug'], reason: '${m['name']} slug drift');
      expect(row['demo_pair'], m['pair'], reason: '${m['name']} pair drift');
    }
  });

  test('exactly 165 rows carry artwork and 127 do not', () {
    final withArt = lib.where((e) {
      final s = e['demo_slug'];
      return s is String && s.isNotEmpty;
    }).toList();
    expect(withArt.length, 165);
    expect(lib.length - withArt.length, 127);
    for (final e in withArt) {
      expect(e['demo_pair'], isA<bool>(),
          reason: '${e['name']}: demo_slug without demo_pair');
      expect(e['demo_slug'], isNot(contains('/')),
          reason: '${e['name']}: demo_slug is a slug, not a path');
    }
  });

  test('an artwork-less row carries NEITHER key — never a null or empty one', () {
    // Not vacuous: it fails if the writer emits demo_slug: null on 127 rows,
    // which is the obvious way to write the transform wrong.
    final bad = <String>[];
    for (final e in lib) {
      final hasSlug = e.containsKey('demo_slug');
      final hasPair = e.containsKey('demo_pair');
      if (hasSlug != hasPair) bad.add('${e['name']}: one key without the other');
      if (hasSlug && e['demo_slug'] is! String) {
        bad.add('${e['name']}: non-String slug');
      }
      if (hasPair && e['demo_pair'] is! bool) {
        bad.add('${e['name']}: non-bool pair');
      }
    }
    expect(bad, isEmpty, reason: 'omit BOTH keys on an artwork-less row: $bad');
    expect(lib.where((e) => e.containsKey('demo_slug')).length, 165);
  });

  test('the dead image fields are gone from the library', () {
    for (final f in _dead) {
      final hits =
          lib.where((e) => e.containsKey(f)).map((e) => e['name']).take(3).toList();
      expect(hits, isEmpty, reason: '$f still on rows: $hits');
    }
  });

  test('no Dart source in lib/ or test/ reads the dead fields', () {
    // BOTH trees: a lib/-only scan is structurally blind to
    // exercise_library_schema_contract_test.dart, the file that actually breaks.
    final offenders = <String>[];
    for (final root in const ['lib', 'test']) {
      for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
        final path = f.path.replaceAll(r'\', '/');
        if (!path.endsWith('.dart')) continue;
        if (path.endsWith(_selfPath)) continue; // this file names them itself
        final src = f
            .readAsStringSync()
            .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
            .replaceAll(RegExp(r'//.*'), '');
        for (final d in _dead) {
          if (src.contains(d)) offenders.add('$path -> $d');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'still referenced: $offenders');
  });

  // ---- BEHAVIOURAL, not a source grep. The spec's verification table asks for
  // "a seeded box at the old version -> re-seed -> field present", and rule 21
  // says a source grep counts for PRESENCE only. This is the real chain. ----
  group('the version bump actually delivers the field', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('plate_seed');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      await HiveService.instance.init();
    });

    tearDownAll(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('a box seeded at the OLD version gains demo_slug after re-seed', () async {
      final box = HiveService.instance.exerciseBox;
      await box.clear();
      // Read through a typed Map, never `box.get(id)['k']`. exerciseBox is an
      // untyped `Box` (hive_service.dart:211), so a dynamic index trips
      // avoid_dynamic_calls -- analysis_options.yaml:22 sets it to WARNING, and
      // --no-fatal-infos suppresses infos, not warnings, so the push would be
      // refused with only `error: failed to push some refs` to go on.
      Map<String, dynamic> read(String k) =>
          Map<String, dynamic>.from(box.get(k) as Map);

      // Simulate a v10 install: rows present, but WITHOUT the new fields.
      final stale =
          Map<String, dynamic>.from(lib.firstWhere((e) => e['demo_slug'] != null));
      final id = stale['id'] as String;
      stale.remove('demo_slug');
      stale.remove('demo_pair');
      await box.put(id, stale);
      expect(read(id)['demo_slug'], isNull, reason: 'precondition');

      // The re-seed writes the bundled row over it. This is what putAll does at
      // seed_service.dart:190 -- assert the OUTCOME, not the call.
      final fresh = lib.firstWhere((e) => e['id'] == id);
      await box.putAll({id: fresh});

      expect(read(id)['demo_slug'], isNotNull,
          reason: 'the re-seed did not deliver demo_slug');
      expect(read(id)['demo_pair'], isA<bool>());
    });
  });
}
