// Batch A Task 2 — a retired exercise's old name still resolves to its kept
// twin, and the kept twin fills the slot the retired row used to fill.
//
// A plan built before v12 can hold a retired name (the frozen baseline picks
// "Hip Abductor Machine"). The coaching panel, the plate sheet, the compound
// check and the "is it library?" predicate all look up by exact name, so each
// must fall back to `name_aliases` or that planned day loses its cues and
// pictures. An exact name always wins over an alias.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/muscle_groups.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final repo = ExerciseRepository.instance;
  final bundled = (jsonDecode(
    File('assets/data/exercise_library.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, dynamic>>();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('alias_lookup');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> loadBox(Map<String, Map<String, dynamic>> rows) async {
    if (Hive.isBoxOpen(HiveService.exerciseBoxName)) {
      await Hive.box(HiveService.exerciseBoxName).close();
    }
    try {
      await Hive.deleteBoxFromDisk(HiveService.exerciseBoxName);
    } catch (_) {}
    final box = await Hive.openBox(HiveService.exerciseBoxName);
    await box.putAll(rows);
  }

  group('exact-name lookups fall back to name_aliases', () {
    setUp(() => loadBox({for (final r in bundled) r['id'] as String: r}));

    test('a retired name resolves to its kept twin', () {
      expect(repo.getByExactName('Hip Abductor Machine')?['id'], 'E107');
      expect(repo.getByExactName(' hip abductor machine ')?['id'], 'E107');
      expect(repo.getByExactName('Hip Abduction Machine')?['id'], 'E107');
    });

    test('the compound check follows the alias', () {
      // E016 is compound; without the alias the lookup is null -> false.
      expect(repo.isCompoundByExactName('Close-Grip Bench Press'), isTrue);
    });

    test('hasExactNameWhere follows the alias', () {
      expect(repo.hasExactNameWhere('V-Ups', (_) => true), isTrue);
    });

    test('an unknown name stays unresolved', () {
      expect(repo.getByExactName('Nonexistent Exercise'), isNull);
      expect(repo.hasExactNameWhere('Nonexistent Exercise', (_) => true), isFalse);
    });
  });

  group('an exact name wins over an alias (mirror)', () {
    // The alias row sorts FIRST (Hive orders string keys), so a single loop
    // that matched name-or-alias would return it; only exact-then-alias passes.
    setUp(() => loadBox({
          'A': {'id': 'A', 'name': 'Other', 'name_aliases': ['X']},
          'B': {'id': 'B', 'name': 'X'},
        }));

    test('getByExactName returns the row NAMED X, not the one aliased X', () {
      expect(repo.getByExactName('X')?['id'], 'B');
    });

    test('hasExactNameWhere still reaches the alias row when the named row fails the test',
        () {
      expect(repo.hasExactNameWhere('X', (r) => r['id'] == 'A'), isTrue);
    });
  });

  group('the kept twin fills the retired twin\'s slot', () {
    setUp(() => loadBox({for (final r in bundled) r['id'] as String: r}));

    List<String> phase1HipGlutes(Set<String>? capability) => repo
        .queryV4(
          movementPattern: 'hip_isolation',
          targetMuscle: 'Glutes',
          equipmentTier: 'full_gym',
          exerciseType: 'isolation',
          foundationalOnly: true,
          exclusions: const {},
          capability: capability,
        )
        .map((r) => r['id'] as String)
        .toList();

    test('Phase-1 Glutes/hip_isolation at full_gym returns E107 (was E225)', () {
      expect(phase1HipGlutes(null), contains('E107'));
      expect(phase1HipGlutes(EquipmentVocab.effectiveItems('full_gym', [], [])),
          contains('E107'));
    });

    test("E107's muscles credit the Glutes group, as E225's did", () {
      final e107 = bundled.singleWhere((r) => r['id'] == 'E107');
      final groups = (e107['primary_muscles'] as List)
          .map((m) => muscleGroupOf(m.toString()))
          .toSet();
      expect(groups, contains(muscleGroupOf('Glutes')));
    });
  });
}
