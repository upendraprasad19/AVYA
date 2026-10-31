// test/contracts/exercise_media_resolver_test.dart
//
// Batch M2a (plan Task 4): `resolveMedia(exerciseName)` reads a library row's `media_slug` and `media_version` and returns the
// object name and the bundled still of its animation, or null. The row's fields are untrusted: the exerciseBox also holds
// community rows written from Postgres (`sync_community.dart:502`) where any field can be any JSON type, and the slug becomes a
// URL path segment, a file name and an asset path, so its SHAPE is checked here, once, before anything downstream sees it.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_media_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late List<Map<String, dynamic>> lib;
  var seq = 0;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('media_resolver');
    // REQUIRED: HiveService.init() calls Hive.initFlutter(), which resolves via path_provider and IGNORES Hive.init()'s path.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    await HiveService.instance.init();
    lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    await HiveService.instance.exerciseBox.putAll({for (final e in lib) e['id'] as String: e});
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  /// Seeds ONE row under a fresh unique name and returns that name. [fields] are the row's media keys, set exactly as given
  /// (including wrong types); a key mapped to the sentinel [_absent] is left out.
  Future<String> seed(Map<String, Object?> fields, {List<String>? aliases}) async {
    final n = ++seq;
    final name = 'Zmedia Test Row $n';
    final row = <String, dynamic>{'id': 'ZMEDIA$n', 'name': name, if (aliases != null) 'name_aliases': aliases};
    fields.forEach((k, v) {
      if (!identical(v, _absent)) row[k] = v;
    });
    await HiveService.instance.exerciseBox.put('ZMEDIA$n', row);
    return name;
  }

  test('a real library row resolves to its object name and its bundled still', () {
    final real = lib.firstWhere((e) => e['id'] == 'G0103');
    expect(real['name'], 'Barbell Standing Ab Rollout', reason: 'the fixture row moved; pick another row that has media_slug');
    final m = resolveMedia(real['name'] as String);
    expect(m, isNotNull);
    expect(m!.slug, '0103-barbell-standing-ab-rollout');
    expect(m.version, 1);
    expect(m.objectName, '0103-barbell-standing-ab-rollout_v1.webp');
    expect(m.stillAsset, 'assets/exercise_stills/0103-barbell-standing-ab-rollout.webp');
  });

  test('every library row with a media_slug resolves, and its object name matches the client pattern', () {
    final pattern = RegExp(r'^[a-z0-9][a-z0-9-]*_v[1-9][0-9]*\.webp$');
    final bad = <String>[];
    var checked = 0;
    for (final e in lib) {
      if (e['media_slug'] == null) continue;
      checked++;
      final m = resolveMedia(e['name'] as String);
      if (m == null) {
        bad.add('${e['id']}: null');
      } else if (!pattern.hasMatch(m.objectName)) {
        bad.add('${e['id']}: ${m.objectName}');
      }
    }
    expect(checked, greaterThan(0));
    expect(bad, isEmpty, reason: bad.take(5).join('\n'));
  });

  test('a version that is missing, zero, negative, a double or a string yields null', () async {
    for (final v in <Object?>[_absent, 0, -1, 1.0, '1', null]) {
      final name = await seed({'media_slug': 'abc', 'media_version': v});
      expect(resolveMedia(name), isNull, reason: 'media_version ${identical(v, _absent) ? '(absent)' : '$v (${v.runtimeType})'}');
    }
  });

  test('a slug that is empty, blank, a number or null yields null', () async {
    for (final s in <Object?>['', '  ', 7, null, _absent]) {
      final name = await seed({'media_slug': s, 'media_version': 1});
      expect(resolveMedia(name), isNull, reason: 'media_slug ${identical(s, _absent) ? '(absent)' : '$s'}');
    }
  });

  test('a slug with a separator, "..", an internal space, an uppercase letter or a leading hyphen yields null', () async {
    for (final s in <String>['a/b', r'a\b', '..', 'a..b', '../x', 'a b', 'ABC', 'abC', '-abc', 'a_b', 'a.webp', 'a%2fb']) {
      final name = await seed({'media_slug': s, 'media_version': 1});
      expect(resolveMedia(name), isNull, reason: 'slug ${jsonEncode(s)} must not resolve');
    }
  });

  test('a slug padded with spaces is trimmed first and resolves to the bare slug [c]', () async {
    final name = await seed({'media_slug': ' abc ', 'media_version': 3});
    final m = resolveMedia(name);
    expect(m, isNotNull);
    expect(m!.slug, 'abc');
    expect(m.objectName, 'abc_v3.webp');
  });

  test('an unknown name yields null and never throws', () {
    expect(resolveMedia('Totally Invented Exercise'), isNull);
    expect(resolveMedia(''), isNull);
    expect(resolveMedia('   '), isNull);
  });

  test('a name that matches only through name_aliases resolves to the surviving row', () async {
    final primary = await seed({'media_slug': 'alias-target', 'media_version': 2}, aliases: ['Zmedia Old Name']);
    expect(primary, isNot('Zmedia Old Name'));
    final m = resolveMedia('Zmedia Old Name');
    expect(m, isNotNull);
    expect(m!.objectName, 'alias-target_v2.webp');
  });

  test('a community row with a non-String media_slug does not throw', () async {
    final name = await seed({'media_slug': 42, 'media_version': 'x'});
    expect(resolveMedia(name), isNull);
  });
}

/// Marks a field as "leave this key out of the row".
const Object _absent = Object();
