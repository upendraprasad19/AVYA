// Behavioral + library contract — W3.6: per-exercise coaching content panel.
//
// The Active Workout panel resolves the curated library fields by EXACT name
// (ExerciseData carries no id) via ExerciseRepository.getByExactName. Two risks
// this pins:
//   • the lookup must be EXACT, not substring — "Push Up" must NOT resolve to
//     "Pike Push Up" (ExerciseRepository.search is pure substring);
//   • the 3 always-present coaching fields must stay populated across all 258
//     library rows, or the panel silently blanks (a library regression).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<Map<String, dynamic>> lib;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_coaching_content');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);

    lib = (jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    for (final m in lib) {
      await exBox.put(m['id'], m);
    }
    HiveService.instance.markInitializedForTests();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final repo = ExerciseRepository.instance;

  group('library coaching fields stay populated (panel non-blank)', () {
    test('all rows carry non-empty coaching_cues / common_mistakes (arrays)',
        () {
      for (final m in lib) {
        final cues = m['coaching_cues'];
        final mistakes = m['common_mistakes'];
        expect(cues is List && cues.isNotEmpty, isTrue,
            reason: '${m['name']} has empty coaching_cues');
        expect(mistakes is List && mistakes.isNotEmpty, isTrue,
            reason: '${m['name']} has empty common_mistakes');
      }
    });

    test('all rows carry a non-empty breathing_cue (string)', () {
      for (final m in lib) {
        final b = m['breathing_cue'];
        expect(b is String && b.trim().isNotEmpty, isTrue,
            reason: '${m['name']} has empty breathing_cue');
      }
    });
  });

  group('getByExactName', () {
    test('returns the full library map with coaching fields for a real name',
        () {
      final first = lib.first;
      final name = first['name'] as String;
      final got = repo.getByExactName(name);
      expect(got, isNotNull);
      expect(got!['id'], first['id']);
      expect((got['coaching_cues'] as List).isNotEmpty, isTrue);
    });

    test('is EXACT, not substring — "Push Up" never resolves to "Pike Push Up"',
        () {
      final names = lib.map((m) => (m['name'] as String)).toSet();
      // Guard on the known collision pair actually being present.
      if (names.contains('Push Up') && names.contains('Pike Push Up')) {
        final got = repo.getByExactName('Push Up');
        expect(got, isNotNull);
        expect(got!['name'], 'Push Up',
            reason: 'exact match must not grab the "Pike Push Up" superstring');
      }
      // Independent of that pair: any name that is a case-insensitive substring
      // of another name must still resolve to ITSELF.
      final lower = {for (final n in names) n.toLowerCase(): n};
      for (final n in names) {
        final nl = n.toLowerCase();
        final hasSuperstring =
            lower.keys.any((k) => k != nl && k.contains(nl));
        if (hasSuperstring) {
          final got = repo.getByExactName(n);
          expect(got?['name'], n,
              reason: '"$n" is a substring of another name but must self-resolve');
          break; // one representative is enough
        }
      }
    });

    test('is case-insensitive', () {
      final name = lib.first['name'] as String;
      expect(repo.getByExactName(name.toLowerCase())?['id'],
          repo.getByExactName(name)?['id']);
    });

    test('returns null for an unknown / custom exercise (panel hides)', () {
      expect(repo.getByExactName('Zzzz Not A Real Exercise 9999'), isNull);
      expect(repo.getByExactName(''), isNull);
      expect(repo.getByExactName('   '), isNull);
    });
  });
}
