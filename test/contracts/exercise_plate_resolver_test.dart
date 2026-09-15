// test/contracts/exercise_plate_resolver_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late List<Map<String, dynamic>> lib;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('plate_resolver');
    // REQUIRED: HiveService.init() calls Hive.initFlutter(), which resolves via
    // path_provider and IGNORES Hive.init()'s path. Without this the file
    // throws MissingPluginException in setUpAll — an error, not a failure.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    await HiveService.instance.init();
    lib =
        (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
                as List)
            .cast<Map<String, dynamic>>();
    await HiveService.instance.exerciseBox
        .putAll({for (final e in lib) e['id'] as String: e});
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  // ---- ENUMERATED, not sampled. ----
  test('every row with artwork resolves to the frames demo_pair declares', () {
    final bad = <String>[];
    for (final e in lib) {
      final slug = e['demo_slug'];
      if (slug is! String || slug.isEmpty) continue;
      final p = resolvePlate(e['name'] as String);
      if (!p.hasArtwork) {
        bad.add('${e['name']}: no artwork');
        continue;
      }
      if (p.slug != slug) bad.add('${e['name']}: slug ${p.slug} != $slug');
      if (p.isPair != (e['demo_pair'] == true)) {
        bad.add('${e['name']}: pair drift');
      }
      if (p.assetPaths.length != (e['demo_pair'] == true ? 2 : 1)) {
        bad.add('${e['name']}: ${p.assetPaths.length} paths');
      }
      if (p.assetPaths.first != 'assets/exercise_plates/$slug-1.svg') {
        bad.add('${e['name']}: bad path ${p.assetPaths.first}');
      }
    }
    expect(bad, isEmpty,
        reason: 'shape drift on ${bad.length} rows: ${bad.take(5)}');
  });

  test('every row WITHOUT artwork resolves to a monogram and no paths', () {
    var checked = 0;
    for (final e in lib) {
      if (e.containsKey('demo_slug')) continue;
      checked++;
      final p = resolvePlate(e['name'] as String);
      expect(p.hasArtwork, isFalse, reason: '${e['name']} claims artwork');
      expect(p.assetPaths, isEmpty);
      expect(p.monogram, isNotEmpty);
    }
    expect(checked, 127, reason: 'the artwork-less set is 127 rows');
  });

  test('an unknown name never throws and never claims artwork', () {
    final p = resolvePlate('Totally Invented Exercise');
    expect(p.hasArtwork, isFalse);
    expect(p.monogram, 'TIE');
  });

  test('lookup is EXACT, never substring', () {
    // Both rows must exist or this passes vacuously on null == null.
    expect(lib.map((e) => e['name']).toSet(),
        containsAll(<String>['Push Up', 'Pike Push Up']));
    expect(resolvePlate('Push Up').slug,
        isNot(equals(resolvePlate('Pike Push Up').slug)));
  });

  test('a non-String demo_slug is ignored, not cast', () {
    // Community rows are written from Postgres
    // (lib/core/services/sync/sync_community.dart:502) and carry any JSON type.
    HiveService.instance.exerciseBox.put('ZTEST', {
      'id': 'ZTEST',
      'name': 'Ztest Bogus Row',
      'demo_slug': 42,
      'demo_pair': 'yes',
    });
    expect(resolvePlate('Ztest Bogus Row').hasArtwork, isFalse);
  });

  group('monogramFor', () {
    test('takes the initial of up to three significant words', () {
      expect(monogramFor('Barbell Bench Press'), 'BBP');
      expect(monogramFor('Push Up'), 'PU');
    });

    test('strips the POSSESSIVE, and nothing else', () {
      // The bug was "Captain's" -> [Captain, s] contributing a bare S.
      expect(monogramFor("Captain's Chair Leg Raise"), 'CCL');
      expect(monogramFor("Child's Pose"), 'CP');
      expect(monogramFor("World's Greatest Stretch"), 'WGS');
    });

    test('KEEPS genuine one-letter words', () {
      // A length filter "fixed" the 3 possessives and broke 9 real names --
      // V-Up -> U, Z Press -> P, T-Bar Row -> BR, and Prone Y/T/W Raise all
      // collapsing to PR. The possessive is the signal, not the length.
      expect(monogramFor('V-Up'), 'VU');
      expect(monogramFor('V-Ups'), 'VU');
      expect(monogramFor('Z Press'), 'ZP');
      expect(monogramFor('T-Bar Row'), 'TBR');
      expect(monogramFor('L-Sit Hold'), 'LSH');
      expect(monogramFor('B-Stance RDL'), 'BSR');
      expect(monogramFor('Prone Y Raise'), 'PYR');
      expect(monogramFor('Prone T Raise'), 'PTR');
      expect(monogramFor('Prone W Raise'), 'PWR');
    });

    test('drops punctuation and stop words', () {
      expect(monogramFor('Dip (Parallel Bars)'), 'DPB');
      // The stop list is not dead code: 4 library names carry one.
      expect(monogramFor('Chest to Bar Pull Up'), 'CBP');
    });

    test('never returns empty for any library name', () {
      for (final e in lib) {
        expect(monogramFor(e['name'] as String), isNotEmpty,
            reason: '${e['name']}');
      }
      expect(monogramFor('   '), isNotEmpty);
      expect(monogramFor('123'), isNotEmpty);
    });
  });
}
