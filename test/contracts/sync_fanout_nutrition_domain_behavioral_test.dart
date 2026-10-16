// Tech-debt audit 2026-05-20 finding T3.2 — BEHAVIORAL contract for the
// `sync_fanout_nutrition_domain` SoT registry concept.
//
// Concept: every NutritionWriteService write produces the canonical
// `nlog_<date>_<meal>_<hash>` Hive entry so the downstream
// `SyncService.syncNutritionData()` fan-out can push BOTH parent
// `nutrition_logs` row AND the N child `nutrition_log_items` rows from
// the same Hive map. Failure mode this test prevents: a writer that
// silently no-ops the Hive write (returns `WriteResult.ok` without a
// `put`), leaving the cloud fan-out with nothing to fanout. This is
// the exact silent-restore-failure class that #12.6 closed for
// `client_errors` telemetry but the writer side was previously only
// covered by source-grep.
//
// Bug class prevented (cites
// `feedback_source_grep_false_confidence.md`): a source-grep that
// merely asserts "nlog_" appears in nutrition_write_service.dart
// passes the test even if the actual `await box.put(key, payload)`
// call has been removed or guarded behind a `kDebugMode` branch. Only
// a behavioral test that runs `logMeal` against real Hive catches it.
//
// Run: flutter test test/contracts/sync_fanout_nutrition_domain_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir =
        Directory.systemTemp.createTempSync('sync_fanout_nutrition_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.closeAll();
    const fakeUserId = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff';
    await HiveUserSession.openForUser(fakeUserId);
    await HiveService.instance.nutritionBox.clear();
  });

  group('sync_fanout_nutrition_domain — behavioral contract', () {
    test(
        'logMeal writes nlog_<date>_<meal>_<hash> with parent totals AND '
        'per-item rows in the same Hive map', () async {
      final today = DateTime.utc(2026, 5, 20, 6, 0);

      final result = await NutritionWriteService.instance.logMeal(
        date: today,
        mealType: 'lunch',
        items: const [
          FoodItem(
            name: 'Chicken Breast',
            quantityG: 200,
            calories: 330,
            protein: 60,
            carbs: 0,
            fat: 8,
            fiber: 0,
          ),
          FoodItem(
            name: 'Brown Rice',
            quantityG: 150,
            calories: 165,
            protein: 4,
            carbs: 35,
            fat: 1.5,
            fiber: 3,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );

      expect(result.success, isTrue,
          reason: 'logMeal must succeed: ${result.errorMessage}');
      expect(result.logKey, startsWith('nlog_'),
          reason: 'logKey must follow nlog_<date>_<meal>_<hash> shape so '
              'the cloud fan-out (_syncNutritionLogs) can locate parent + '
              'item rows by prefix.');

      // Parent row — Hive map carrying total_calories / total_protein /
      // total_carbs / total_fat / total_fiber. Cloud fan-out projects
      // these into `nutrition_logs` columns.
      final stored = HiveService.instance.nutritionBox.get(result.logKey!);
      expect(stored, isA<Map>(),
          reason: 'nlog_* Hive entry must exist after logMeal; failure '
              'here is the silent-write regression that #12.6 closed for '
              'telemetry but the writer side had only source-grep '
              'coverage.');
      final m = stored as Map;
      expect(m['meal_type'], 'lunch');
      expect(m['total_calories'], 330 + 165);
      expect(m['total_protein'], 60 + 4);

      // Per-item rows — Hive stores them inline as a List under `items`.
      // Cloud fan-out (_syncNutritionLogs) iterates this list and
      // projects each into a `nutrition_log_items` row.
      final items = m['items'];
      expect(items, isA<List>(),
          reason: 'items[] list MUST be present so cloud fan-out has '
              'per-item rows to project — failure mode: writer collapses '
              'items into the parent payload and cloud loses macro detail.');
      expect((items as List).length, 2);
      final names = items.map((e) => (e as Map)['name']).toList();
      expect(names, containsAll(['Chicken Breast', 'Brown Rice']));
    });

    test(
        'logMeal stamps both `id` AND `log_key` on the parent map — '
        'reader/writer field contract', () async {
      // Closes the specific writer/reader drift fixed in APK Test #12.6
      // / Obs 7: dismissible + _showEditMacrosSheet read `meal['id']`,
      // editLog scans by `log_key`. Both must be present and equal.
      final today = DateTime.utc(2026, 5, 20, 6, 0);
      final result = await NutritionWriteService.instance.logMeal(
        date: today,
        mealType: 'breakfast',
        items: const [
          FoodItem(
            name: 'Eggs',
            quantityG: 100,
            calories: 155,
            protein: 13,
            carbs: 1,
            fat: 11,
            fiber: 0,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
      expect(result.success, isTrue);

      final stored = HiveService.instance.nutritionBox.get(result.logKey!)
          as Map;
      expect(stored['id'], result.logKey,
          reason: 'id field MUST equal log_key — reader/writer drift '
              'class previously dropped dismissible swipe + edit macros.');
      expect(stored['log_key'], result.logKey);
    });

    test('logMeal rejects empty items[] without writing a ghost row',
        () async {
      // Validation contract — empty meals must never reach Hive,
      // otherwise the cloud fan-out projects an empty nutrition_logs
      // row that the AI coach + receipts treat as a real meal.
      final today = DateTime.utc(2026, 5, 20, 6, 0);
      final before = HiveService.instance.nutritionBox.keys.length;

      final result = await NutritionWriteService.instance.logMeal(
        date: today,
        mealType: 'snacks',
        items: const [],
        source: NutritionWriteSource.manualSearch,
      );

      expect(result.success, isFalse);
      expect(
        HiveService.instance.nutritionBox.keys.length,
        before,
        reason: 'empty items[] must NOT produce a Hive entry; cloud '
            'fan-out would otherwise push a ghost row.',
      );
    });

    test('logMeal rejects unknown mealType', () async {
      final today = DateTime.utc(2026, 5, 20, 6, 0);
      final result = await NutritionWriteService.instance.logMeal(
        date: today,
        mealType: 'brunch', // not in {breakfast,lunch,dinner,snacks}
        items: const [
          FoodItem(
            name: 'Coffee',
            quantityG: 250,
            calories: 5,
            protein: 0,
            carbs: 1,
            fat: 0,
            fiber: 0,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
      expect(result.success, isFalse,
          reason: 'mealType outside the canonical set must be rejected '
              'so cloud fan-out never sees a row with a meal_type the '
              'AI coach / day_detail_sheet readers cannot bucket.');
    });
  });
}
