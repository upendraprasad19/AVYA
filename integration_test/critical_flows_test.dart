// Critical-flows scaffold (APK Test #12.6).
//
// Data-layer round-trip smoke for the three highest-risk consumer paths:
//   1. log meal → read back items[]
//   2. log workout → read back via WorkoutRepository
//   3. log workout → render via WorkoutReceiptData.fromExerciseLogs
//
// These exercise the WriteService → Hive → Reader chain that has caused
// the most APK regressions (Tests #6 → #12). Per CLAUDE.md §4.4 rule 21, every
// new flow added here must FAIL on the writer-only side without the
// matching reader update — see `feedback_source_of_truth_audit.md`.
//
// Run: `flutter test integration_test/critical_flows_test.dart`
// Extending: see integration_test/README.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_card.dart';

import '../test/workout_write_service/helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('flow1_log_meal_round_trip: items[] non-empty + meal name resolvable',
      () async {
    final date = DateTime(2026, 5, 6);
    final r = await NutritionWriteService.instance.logMeal(
      date: date,
      mealType: 'lunch',
      items: const [
        FoodItem(
          name: 'Basmati Rice',
          quantityG: 150,
          calories: 195,
          protein: 4,
          carbs: 43,
          fat: 0.4,
          fiber: 0.6,
        ),
      ],
      source: NutritionWriteSource.manualSearch,
    );
    expect(r.success, isTrue, reason: r.errorMessage);

    final box = HiveService.instance.nutritionBox;
    final keys =
        box.keys.where((k) => k.toString().startsWith('nlog_')).toList();
    expect(keys.length, 1, reason: 'exactly ONE nlog_* row');

    final entry = (box.get(keys.first) as Map).cast<String, dynamic>();

    // items[] non-empty
    final items = (entry['items'] as List).cast<Map>();
    expect(items, isNotEmpty);

    // First item resolvable (name + macros)
    expect(items.first['name'], 'Basmati Rice');
    expect((items.first['quantity_g'] as num).toDouble(), 150);
    expect((items.first['calories'] as num).toDouble(), 195);

    // Top-level totals match per-item sum (no AI-response 0-totals leak)
    expect(entry['total_calories'], 195);
    expect(entry['total_protein'], 4);
    expect(entry['meal_type'], 'lunch');
  });

  test('flow2_log_workout_round_trip: 3 sets → set_number=3, sets.length=3',
      () async {
    final date = DateTime(2026, 5, 6);
    final base = date.millisecondsSinceEpoch;

    final r = await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Bench Press',
      sets: [
        ExerciseSet(weightKg: 60, reps: 10, loggedAtMs: base),
        ExerciseSet(weightKg: 70, reps: 8, loggedAtMs: base + 90_000),
        ExerciseSet(weightKg: 80, reps: 6, loggedAtMs: base + 180_000),
      ],
      source: WriteSource.activeWorkout,
    );
    expect(r.success, isTrue, reason: r.errorMessage);

    // Read via WorkoutRepository (the canonical reader, not raw box)
    final repo = WorkoutRepository.instance;
    final logs = repo.getExerciseLogsForDate(date);
    expect(logs.length, 1, reason: 'exactly ONE per-exercise summary row');

    final log = logs.first;
    expect(log['exercise_name'], 'Bench Press');
    expect(log['set_number'], 3, reason: 'aggregate set_number = 3');

    final sets = (log['sets'] as List).cast<Map>();
    expect(sets.length, 3, reason: 'sets[] preserves all 3 entries');

    // Best weight is the heaviest set
    expect((log['weight_kg'] as num).toDouble(), 80);

    // Cumulative reps
    expect(log['reps_completed'], 24);

    // Volume = 60*10 + 70*8 + 80*6 = 1640
    expect((log['volume_kg'] as num).toInt(), 60 * 10 + 70 * 8 + 80 * 6);
  });

  test(
      'flow3_receipt_renders_per_set: WorkoutReceiptData.fromExerciseLogs has 3-set breakdown',
      () async {
    final date = DateTime(2026, 5, 6);
    final base = date.millisecondsSinceEpoch;

    final r = await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Bench Press',
      sets: [
        ExerciseSet(weightKg: 60, reps: 10, loggedAtMs: base),
        ExerciseSet(weightKg: 70, reps: 8, loggedAtMs: base + 90_000),
        ExerciseSet(weightKg: 80, reps: 6, loggedAtMs: base + 180_000),
      ],
      source: WriteSource.activeWorkout,
    );
    expect(r.success, isTrue, reason: r.errorMessage);

    final receipt = WorkoutReceiptData.fromExerciseLogs(date);
    expect(receipt, isNotNull,
        reason: 'fromExerciseLogs must return data when exlog_* exists');

    expect(receipt!.exercises, isNotEmpty);
    final ex = receipt.exercises.first;
    expect(ex.name, 'Bench Press');

    // Aggregate sets count
    expect(ex.sets, 3, reason: 'aggregate set count = 3');

    // 3-set breakdown: receipt must surface per-set chip data, NOT
    // collapse to a single summary row. Pre-Test-#12 the field-rename
    // bug caused this to render as "0 sets · 24 reps".
    expect(ex.perSetBreakdown.length, 3,
        reason: 'receipt per-set breakdown preserves all 3 sets');

    // Set values mirror what WriteService persisted.
    final weights = ex.perSetBreakdown.map((s) => s.weightKg).toList();
    expect(weights, containsAll(<double?>[60.0, 70.0, 80.0]));

    // Aggregate sanity
    expect(receipt.totalSets, 3);
    expect(receipt.totalVolumeKg, (60 * 10 + 70 * 8 + 80 * 6).toDouble());
  });
}
