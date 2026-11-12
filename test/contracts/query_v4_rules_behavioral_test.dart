// Unit 1B-F, Task 3 (docs/plans/2026-11-10-generator-1bf-flip.md, Ruling 7): the rules the deleted `QueryV4Mirror`
// checked, each pinned on the REAL `ExerciseRepository.queryV4`, for the rules no other real-queryV4 test covered.
// queryV4 now serves the thin-day top-up (injured users) only; the picker reads `CoreListSelector.rankedPool`.
//
// Already covered elsewhere on the real queryV4: capability (`equipment_owned_widens_test.dart`), injury exclusions
// (`injury_recheck_v14_contract_test.dart`, `injury_safety_tags_v13_behavioral_test.dart`), the same-movement
// `excludeNames` partner (`same_movement_behavioral_test.dart` test 1). Here: the tier rule when capability is null,
// `suitableFor`, `foundationalOnly`, equipment `exclusions` with capability null, and the sort (compound first, then
// `priority_tier`, then foundational). Each test is non-vacuous: the row the rule removes is returned without it.
//
// Mutations (diagnose doc): each filter switched off, and each sort key removed, reddens its test.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

Map<String, dynamic> _row(
  String id, {
  List<String> tiers = const ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'],
  List<String> suitable = const ['Beginner', 'Intermediate', 'Advanced'],
  bool foundational = true,
  List<String> needed = const ['bodyweight'],
  String type = 'compound',
  int priority = 1,
}) =>
    {
      'id': id,
      'name': 'Row $id',
      'movement_pattern': ['horizontal_push'],
      'target_focus': ['Chest'],
      'primary_muscles': ['Chest'],
      'exercise_type': [type],
      'equipment_tier': tiers,
      'equipment_needed': needed,
      'suitable_for': suitable,
      'is_foundational': foundational,
      'priority_tier': priority,
      'injury_contraindications': <String>[],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('query_v4_rules');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    await Hive.openBox(HiveService.exerciseBoxName);
    HiveService.instance.markInitializedForTests();
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> seed(List<Map<String, dynamic>> rows) async {
    final box = Hive.box(HiveService.exerciseBoxName);
    await box.clear();
    for (final r in rows) {
      await box.put(r['id'] as String, r);
    }
  }

  List<String> q({
    String? tier,
    String? suitableFor,
    bool foundationalOnly = false,
    Set<String> exclusions = const {},
  }) =>
      [
        for (final r in ExerciseRepository.instance.queryV4(
          movementPattern: 'horizontal_push',
          equipmentTier: tier,
          suitableFor: suitableFor,
          foundationalOnly: foundationalOnly,
          exclusions: exclusions,
          capability: null,
        ))
          r['id'] as String
      ];

  test('tier rule (capability null): an off-tier row leaves, a row with no tier list stays', () async {
    await seed([_row('A'), _row('GYM', tiers: ['full_gym']), _row('NOTIER', tiers: const [])]);
    expect(q(), containsAll(['A', 'GYM', 'NOTIER']), reason: 'non-vacuity: no tier asked, every row');
    expect(q(tier: 'bodyweight'), unorderedEquals(['A', 'NOTIER']));
  });

  test('suitableFor: a row not suitable for the level leaves', () async {
    await seed([_row('A'), _row('ADV', suitable: ['Advanced'])]);
    expect(q(), containsAll(['A', 'ADV']));
    expect(q(suitableFor: 'beginner'), ['A']);
  });

  test('foundationalOnly: a non-foundational row leaves', () async {
    await seed([_row('A'), _row('NF', foundational: false)]);
    expect(q(), containsAll(['A', 'NF']));
    expect(q(foundationalOnly: true), ['A']);
  });

  test('exclusions (capability null): a row needing an excluded item leaves', () async {
    await seed([_row('A'), _row('BAR', needed: ['barbell'])]);
    expect(q(), containsAll(['A', 'BAR']));
    expect(q(exclusions: const {'barbell'}), ['A']);
  });

  test('sort: compound first, then priority_tier, then foundational', () async {
    // A Hive box iterates its keys in sorted order, whatever the insertion order, so the ids are prefixed to make key
    // order the exact reverse of the expected order: box order alone cannot pass it, and each sort key separates one
    // adjacent pair (compound: ISO last; priority_tier: P1 before P2; foundational: P2F before P2NF). With unprefixed
    // ids, key order already put P2F before P2NF and removing the foundational key went unseen (Task 3 mutant).
    await seed([
      _row('A_ISO', type: 'isolation', priority: 1),
      _row('B_P2NF', priority: 2, foundational: false),
      _row('C_P2F', priority: 2),
      _row('D_P1NF', priority: 1, foundational: false),
    ]);
    expect(Hive.box(HiveService.exerciseBoxName).keys.toList(), ['A_ISO', 'B_P2NF', 'C_P2F', 'D_P1NF'],
        reason: 'precondition: key order is the reverse of the expected order');
    expect(q(), ['D_P1NF', 'C_P2F', 'B_P2NF', 'A_ISO']);
  });
}
