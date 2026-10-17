// test/contracts/exercise_plate_assets_present_test.dart
//
// Pins the properties the runtime depends on and cannot check itself: that
// every demo_slug has the frames its shape calls for, that a pair's two frames
// share a viewBox (or the figure visibly changes size between START and END),
// and that nothing outside the mapping was invented.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lib =
      (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>();

  // slug -> isPair, DEDUPED: 165 exercises share 153 slugs.
  final slugs = <String, bool>{};
  final conflicts = <String>[];
  for (final e in lib) {
    final s = e['demo_slug'];
    if (s is! String || s.isEmpty) continue;
    final pair = e['demo_pair'] == true;
    if (slugs.containsKey(s) && slugs[s] != pair) conflicts.add(s);
    slugs[s] = pair;
  }

  test('no slug is claimed as both pair and single', () {
    // The pipeline hard-fails on this; assert it here too, because a
    // last-write-wins map would otherwise hide it on the Dart side.
    expect(conflicts, isEmpty);
  });

  test('the shipping set is 153 slugs, 139 of them pairs', () {
    expect(slugs.length, 153);
    expect(slugs.values.where((p) => p).length, 139);
    expect(slugs.values.where((p) => !p).length, 14);
  });

  test('every slug has exactly the frames its shape calls for', () {
    final wrong = <String>[];
    for (final entry in slugs.entries) {
      final one = File('assets/exercise_plates/${entry.key}-1.svg');
      final three = File('assets/exercise_plates/${entry.key}-3.svg');
      if (!one.existsSync()) wrong.add('${entry.key}-1.svg missing');
      if (entry.value && !three.existsSync()) {
        wrong.add('${entry.key}-3.svg missing (pair)');
      }
      if (!entry.value && three.existsSync()) {
        wrong.add('${entry.key}-3.svg present but the exercise is a hold');
      }
    }
    expect(wrong, isEmpty, reason: 'asset shape drift: $wrong');
  });

  test('exactly 292 SVGs ship — no orphans left by a rename', () {
    final dir = Directory('assets/exercise_plates');
    expect(dir.existsSync(), isTrue,
        reason: 'run python scripts/build_exercise_plates.py first');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.svg'))
        .toList();
    expect(files.length, 292);
  });

  test('paired frames share one viewBox', () {
    final vb = RegExp(r'viewBox="([^"]+)"');
    final drift = <String>[];
    for (final entry in slugs.entries.where((e) => e.value)) {
      final a = File('assets/exercise_plates/${entry.key}-1.svg');
      final b = File('assets/exercise_plates/${entry.key}-3.svg');
      expect(a.existsSync() && b.existsSync(), isTrue,
          reason: '${entry.key}: generate the assets first');
      final va = vb.firstMatch(a.readAsStringSync())?.group(1);
      if (va != vb.firstMatch(b.readAsStringSync())?.group(1)) {
        drift.add(entry.key);
      }
    }
    expect(drift, isEmpty, reason: 'frames would jump size: $drift');
  });

  test('every frame is tintable and unsized', () {
    for (final entry in slugs.entries) {
      final names = ['${entry.key}-1.svg', if (entry.value) '${entry.key}-3.svg'];
      for (final n in names) {
        final f = File('assets/exercise_plates/$n');
        expect(f.existsSync(), isTrue,
            reason: '$n: generate the assets first');
        final t = f.readAsStringSync();
        expect(t.contains('fill="currentColor"'), isTrue,
            reason: '$n is not tintable');
        expect(RegExp(r'<svg[^>]*\s(width|height)=').hasMatch(t), isFalse,
            reason: '$n pins a size and will not scale');
      }
    }
  });

  test('every shipped slug exists in the upstream manifest', () {
    final f = File('docs/plans/exercise-plates-manifest.json');
    expect(f.existsSync(), isTrue,
        reason: 'copy the upstream manifest in first');
    final man =
        (jsonDecode(f.readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final upstream = man.map((e) => e['slug'] as String).toSet();
    expect(slugs.keys.toSet().difference(upstream), isEmpty,
        reason: 'demo_slug values with no upstream drawing');
  });
}
