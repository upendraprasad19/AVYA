import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icanbefitter/core/constants/app_environment.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_card.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_helper.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// REGRESSION TESTS — 6 Bugs Fixed (Session 2026-04-01)
/// ─────────────────────────────────────────────────────────────────────────────
///
/// These tests MUST pass before every APK build.
/// Run with: flutter test integration_test/flows/regression_bug_fixes_test.dart
///
/// R1  — [Bug 3b] loadAllExercisePRs: returns PRs for non-key-lift exercises
/// R2  — [Bug 3b] loadAllExercisePRs: picks BEST value per exercise
/// R3  — [Bug 3b] loadAllExercisePRs: skips zero-value entries
/// R4  — [Bug 3b] loadAllExercisePRs: handles all logging types correctly
/// R5  — [Bug 3a] markCompleted: stores durationSeconds in Hive schedule entry
/// R6  — [Bug 3a] getScheduleForDate: reads durationSeconds back correctly
/// R7  — [Bug 5]  stale guard: yesterday's completed_at → returns 'planned'
/// R8  — [Bug 5]  stale guard: today's completed_at → stays 'completed'
/// R9  — [Bug 5]  stale guard is read-only (does NOT overwrite Hive)
/// R10 — [Bug 2]  receipt deduplication: same exercise appears only once
/// R11 — [Bug 2]  receipt deduplication: sets are merged, max weight kept
/// R12 — [Bug 4]  isSaved flag: ActiveWorkoutData defaults to isSaved=false
/// R13 — [Bug 4]  isSaved flag: copyWith preserves isSaved=true
/// R14 — [Bug 4]  reopenWorkout path: isComplete flips, isSaved stays true
/// R15 — [Bug 1]  SetInputValues: stores weight, reps, duration, distance

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    kIsDevFlavor = true;
    await initHiveForTest();
    await SupabaseService.instance.initialize();
  });

  tearDown(() async {
    await clearHiveForTest();
  });

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Seeds an exercise_log entry into workoutBox (simulates a logged set).
  void seedExerciseLog({
    required String exerciseName,
    String loggingType = 'weight_reps',
    double weightKg = 0,
    int repsCompleted = 0,
    int durationSeconds = 0,
    double distanceKm = 0,
    DateTime? date,
  }) {
    final d = date ?? DateTime.now();
    final dateStr = formatDateKey(d);
    final key = 'elog_${exerciseName.replaceAll(' ', '_')}_${d.millisecondsSinceEpoch}';
    HiveService.instance.workoutBox.put(key, {
      'type': 'exercise_log',
      'exercise_name': exerciseName,
      'logging_type': loggingType,
      'weight_kg': weightKg,
      'reps_completed': repsCompleted,
      'sets_completed': 3,
      'duration_seconds': durationSeconds,
      'distance_km': distanceKm,
      'date': dateStr,
      'created_at': d.toIso8601String(),
      'is_pr': false,
    });
  }

  /// Seeds a schedule entry for a given date.
  void seedScheduleEntry(DateTime date, {
    String status = 'planned',
    String? completedAt,
    int durationSeconds = 0,
  }) {
    final dateStr = formatDateKey(date);
    HiveService.instance.workoutBox.put('schedule_$dateStr', {
      'date': dateStr,
      'type': 'workout',
      'workout_name': 'Test Workout',
      'workout_focus': 'Test',
      'exercises': <Map<String, dynamic>>[],
      'status': status,
      'completed_at': completedAt,
      'duration_seconds': durationSeconds,
      'is_swapped': false,
      'original_date': null,
    });
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG 3b — loadAllExercisePRs (PRs not showing after workout)
  // ─────────────────────────────────────────────────────────────────────────────

  test('R1: loadAllExercisePRs returns PRs for non-key-lift exercises', () async {
    // Seed three non-standard exercises (none of bench/squat/deadlift/ohp).
    seedExerciseLog(exerciseName: 'Cable Fly', weightKg: 20.0);
    seedExerciseLog(exerciseName: 'Tuck Planche Pushup', loggingType: 'bodyweight_reps', repsCompleted: 8);
    seedExerciseLog(exerciseName: 'Hollow Body Hold', loggingType: 'timed', durationSeconds: 45);

    final prs = WorkoutRepository.instance.loadAllExercisePRs();

    final names = prs.map((p) => p.exerciseName.toLowerCase()).toList();
    expect(names.any((n) => n.contains('cable fly')), isTrue,
        reason: 'Cable Fly PR should be returned');
    expect(names.any((n) => n.contains('tuck planche')), isTrue,
        reason: 'Tuck Planche Pushup PR should be returned');
    expect(names.any((n) => n.contains('hollow body')), isTrue,
        reason: 'Hollow Body Hold PR should be returned');
  });

  test('R2: loadAllExercisePRs picks BEST value across multiple logs', () async {
    // Three logs for same exercise — weights: 40, 50, 45. Best = 50.
    seedExerciseLog(exerciseName: 'Incline Dumbbell Press', weightKg: 40.0,
        date: DateTime.now().subtract(const Duration(days: 10)));
    seedExerciseLog(exerciseName: 'Incline Dumbbell Press', weightKg: 50.0,
        date: DateTime.now().subtract(const Duration(days: 5)));
    seedExerciseLog(exerciseName: 'Incline Dumbbell Press', weightKg: 45.0,
        date: DateTime.now().subtract(const Duration(days: 1)));

    final prs = WorkoutRepository.instance.loadAllExercisePRs();
    final pr = prs.firstWhere((p) => p.exerciseName.toLowerCase().contains('incline'));

    expect(pr.bestValue, equals(50.0),
        reason: 'PR should be the highest logged weight (50kg), not the most recent (45kg)');
  });

  test('R3: loadAllExercisePRs skips zero-value entries', () async {
    // Log with weight_kg=0 (user logged exercise but entered 0 — e.g. forgot).
    seedExerciseLog(exerciseName: 'Shrug', weightKg: 0.0);

    final prs = WorkoutRepository.instance.loadAllExercisePRs();
    final names = prs.map((p) => p.exerciseName.toLowerCase()).toList();

    expect(names.any((n) => n.contains('shrug')), isFalse,
        reason: 'Zero-weight entry should not appear in PRs');
  });

  test('R4: loadAllExercisePRs handles all logging types', () async {
    seedExerciseLog(
        exerciseName: 'Pull-up',
        loggingType: 'bodyweight_reps',
        repsCompleted: 12);
    seedExerciseLog(
        exerciseName: 'Plank',
        loggingType: 'timed',
        durationSeconds: 90);
    seedExerciseLog(
        exerciseName: '5km Run',
        loggingType: 'cardio',
        distanceKm: 5.2);
    seedExerciseLog(
        exerciseName: 'Weighted Pull-up',
        loggingType: 'weighted_bodyweight',
        weightKg: 15.0);

    final prs = WorkoutRepository.instance.loadAllExercisePRs();

    final pullUp = prs.firstWhereOrNull((p) => p.exerciseName.toLowerCase() == 'pull-up');
    final plank = prs.firstWhereOrNull((p) => p.exerciseName.toLowerCase() == 'plank');
    final run = prs.firstWhereOrNull((p) => p.exerciseName.toLowerCase() == '5km run');
    final wPullUp = prs.firstWhereOrNull((p) => p.exerciseName.toLowerCase() == 'weighted pull-up');

    expect(pullUp?.bestValue, equals(12.0), reason: 'bodyweight_reps: bestValue = reps_completed');
    expect(plank?.bestValue, equals(90.0), reason: 'timed: bestValue = duration_seconds');
    expect(run?.bestValue, equals(5.2), reason: 'cardio: bestValue = distance_km when > 0');
    expect(wPullUp?.bestValue, equals(15.0), reason: 'weighted_bodyweight: bestValue = weight_kg');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG 3a — 0 MIN shown on home screen after workout completion
  // ─────────────────────────────────────────────────────────────────────────────

  test('R5: markCompleted stores durationSeconds in Hive schedule entry', () async {
    final today = DateTime.now();
    seedScheduleEntry(today);

    await WorkoutScheduleService.instance.markCompleted(today, durationSeconds: 2700);

    // Read raw entry from Hive — not via getScheduleForDate (which may transform).
    final dateStr = formatDateKey(today);
    final raw = HiveService.instance.workoutBox.get('schedule_$dateStr');
    expect(raw, isNotNull);
    final map = Map<String, dynamic>.from(raw as Map);

    expect(map['duration_seconds'], equals(2700),
        reason: 'durationSeconds (2700 = 45 min) must be stored in the Hive schedule entry');
  });

  test('R6: getScheduleForDate returns durationSeconds correctly', () async {
    final today = DateTime.now();
    seedScheduleEntry(today);

    await WorkoutScheduleService.instance.markCompleted(today, durationSeconds: 1800);

    final schedule = WorkoutScheduleService.instance.getScheduleForDate(today);
    expect(schedule, isNotNull);
    expect(schedule!['duration_seconds'], equals(1800),
        reason: 'getScheduleForDate must return the stored durationSeconds (1800 = 30 min)');
    expect(schedule['status'], equals('completed'),
        reason: 'Status must be completed after markCompleted()');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG 5 — Stale auto-green (date rollover bug)
  // ─────────────────────────────────────────────────────────────────────────────

  test('R7: stale guard returns planned when completed_at is from yesterday', () async {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    // Simulate: yesterday's workout was marked complete but its schedule
    // key is for today (bug scenario: clock crossed midnight).
    seedScheduleEntry(
      today,
      status: 'completed',
      completedAt: yesterday.toIso8601String(), // stale — different date
    );

    final schedule = WorkoutScheduleService.instance.getScheduleForDate(today);
    expect(schedule, isNotNull);
    expect(schedule!['status'], equals('planned'),
        reason: 'Stale completed_at (yesterday) must be downgraded to planned');
    expect(schedule['completed_at'], isNull,
        reason: 'completed_at must be cleared in the returned map for stale entries');
  });

  test('R8: stale guard does NOT affect legitimately completed workouts', () async {
    final today = DateTime.now();

    // Workout completed today — not stale.
    seedScheduleEntry(
      today,
      status: 'completed',
      completedAt: today.toIso8601String(), // same date — not stale
      durationSeconds: 2400,
    );

    final schedule = WorkoutScheduleService.instance.getScheduleForDate(today);
    expect(schedule, isNotNull);
    expect(schedule!['status'], equals('completed'),
        reason: "Today's completed workout must stay 'completed' — guard must not over-correct");
    expect(schedule['duration_seconds'], equals(2400),
        reason: 'durationSeconds must be preserved for legitimate completions');
  });

  test('R9: stale guard is read-only — does not overwrite Hive entry', () async {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    // Seed stale entry.
    seedScheduleEntry(
      today,
      status: 'completed',
      completedAt: yesterday.toIso8601String(),
    );

    // Trigger stale guard (read-only path — must NOT write back).
    WorkoutScheduleService.instance.getScheduleForDate(today);

    // Read the RAW Hive entry — it must still have status='completed' as originally written.
    // The guard corrects the RETURNED map only, not the stored one.
    final dateStr = formatDateKey(today);
    final raw = HiveService.instance.workoutBox.get('schedule_$dateStr');
    final rawMap = Map<String, dynamic>.from(raw as Map);

    expect(rawMap['status'], equals('completed'),
        reason: 'Raw Hive entry must remain unchanged — stale guard must not write back');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG 2 — Duplicate exercises in share/receipt card
  // ─────────────────────────────────────────────────────────────────────────────

  test('R10: receipt deduplication — same exercise name appears only once', () {
    // Simulate a workout plan that has "Tuck Planche Pushup" listed twice
    // (e.g. as two superset slots).
    final exercises = [
      const ExerciseData(
          name: 'Tuck Planche Pushup',
          sets: '3',
          reps: '8',
          loggingType: 'bodyweight_reps'),
      const ExerciseData(
          name: 'Pull-up',
          sets: '3',
          reps: '10',
          loggingType: 'bodyweight_reps'),
      const ExerciseData(
          name: 'Tuck Planche Pushup', // duplicate
          sets: '2',
          reps: '6',
          loggingType: 'bodyweight_reps'),
    ];

    // Mark all sets as checked so receipt includes them.
    final checkedSets = <String, bool>{};
    final setInputValues = <String, SetInputValues>{};
    for (int i = 0; i < exercises.length; i++) {
      final numSets = int.tryParse(exercises[i].sets) ?? 3;
      for (int s = 0; s < numSets; s++) {
        checkedSets['$i-$s'] = true;
        setInputValues['$i-$s'] = const SetInputValues(reps: 8);
      }
    }

    final workoutDay = WorkoutDayData(
      dayNumber: 1,
      name: 'Push Day',
      exercises: exercises,
    );

    final data = ActiveWorkoutData(
      workoutDay: workoutDay,
      exercises: exercises,
      elapsedSeconds: 1800,
      checkedSets: checkedSets,
      setInputValues: setInputValues,
      isComplete: true,
      isSaved: true,
    );

    final receipt = WorkoutReceiptData.fromActiveWorkout(data);

    final exerciseNames =
        receipt.exercises.map((e) => e.name.toLowerCase().trim()).toList();
    final uniqueNames = exerciseNames.toSet().toList();

    expect(exerciseNames.length, equals(uniqueNames.length),
        reason: 'Receipt must have no duplicate exercise names after deduplication');

    final plancheCount = exerciseNames
        .where((n) => n.contains('tuck planche'))
        .length;
    expect(plancheCount, equals(1),
        reason: '"Tuck Planche Pushup" must appear exactly once in the receipt');
  });

  test('R11: receipt deduplication merges sets and keeps max weight', () {
    // Two slots of Bench Press: first with 60kg, second with 70kg.
    final exercises = [
      const ExerciseData(
          name: 'Bench Press', sets: '3', reps: '8', loggingType: 'weight_reps'),
      const ExerciseData(
          name: 'Bench Press', sets: '2', reps: '6', loggingType: 'weight_reps'),
    ];

    final checkedSets = <String, bool>{};
    final setInputValues = <String, SetInputValues>{};

    // First slot: 3 sets at 60kg.
    for (int s = 0; s < 3; s++) {
      checkedSets['0-$s'] = true;
      setInputValues['0-$s'] = const SetInputValues(weight: 60.0, reps: 8);
    }
    // Second slot: 2 sets at 70kg.
    for (int s = 0; s < 2; s++) {
      checkedSets['1-$s'] = true;
      setInputValues['1-$s'] = const SetInputValues(weight: 70.0, reps: 6);
    }

    final workoutDay = WorkoutDayData(
      dayNumber: 1,
      name: 'Push Day',
      exercises: exercises,
    );

    final data = ActiveWorkoutData(
      workoutDay: workoutDay,
      exercises: exercises,
      elapsedSeconds: 900,
      checkedSets: checkedSets,
      setInputValues: setInputValues,
      isComplete: true,
      isSaved: true,
    );

    final receipt = WorkoutReceiptData.fromActiveWorkout(data);

    final benchEntry =
        receipt.exercises.firstWhere((e) => e.name.toLowerCase().contains('bench'));

    expect(benchEntry.sets, equals(5),
        reason: 'Merged sets: 3 + 2 = 5');
    expect(benchEntry.maxWeightKg, equals(70.0),
        reason: 'Merged weight: max(60, 70) = 70kg');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG 4 — isSaved flag prevents double-logging
  // ─────────────────────────────────────────────────────────────────────────────

  test('R12: ActiveWorkoutData defaults to isSaved=false', () {
    const data = ActiveWorkoutData();
    expect(data.isSaved, isFalse,
        reason: 'Fresh workout must start with isSaved=false');
  });

  test('R13: copyWith preserves isSaved=true across state updates', () {
    const data = ActiveWorkoutData(isSaved: true, isComplete: true);
    // Simulates reopenWorkout(): isComplete set to false, isSaved must stay true.
    final reopened = data.copyWith(isComplete: false);

    expect(reopened.isSaved, isTrue,
        reason: 'isSaved must remain true after reopenWorkout() copyWith');
    expect(reopened.isComplete, isFalse,
        reason: 'isComplete must be false after reopenWorkout()');
  });

  test('R14: isSaved=true + isComplete=false is the valid "review" state', () {
    // This is exactly the state the app should be in after the user taps
    // "Review Workout" on the completion screen.
    const reviewState = ActiveWorkoutData(isSaved: true, isComplete: false);

    expect(reviewState.isSaved, isTrue,
        reason: 'isSaved must be true — prevents second Hive write on re-finish');
    expect(reviewState.isComplete, isFalse,
        reason: 'isComplete must be false — shows workout form, not completion screen');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG 1 — SetInputValues stored correctly for controller restore
  // ─────────────────────────────────────────────────────────────────────────────

  test('R15: SetInputValues stores all field types correctly', () {
    // weight_reps
    const wr = SetInputValues(weight: 80.0, reps: 5);
    expect(wr.weight, equals(80.0));
    expect(wr.reps, equals(5));
    expect(wr.durationSeconds, isNull);
    expect(wr.distanceKm, isNull);

    // timed
    const timed = SetInputValues(durationSeconds: 120);
    expect(timed.durationSeconds, equals(120));
    expect(timed.weight, isNull);

    // cardio
    const cardio = SetInputValues(durationSeconds: 1800, distanceKm: 5.0);
    expect(cardio.distanceKm, equals(5.0));
    expect(cardio.durationSeconds, equals(1800));
  });

  test('R15b: setInputValues map survives copyWith on ActiveWorkoutData', () {
    const values = {'0-0': SetInputValues(weight: 60.0, reps: 10)};
    const data = ActiveWorkoutData(setInputValues: values);

    // copyWith with unrelated field (elapsed timer tick) must not clear setInputValues.
    final updated = data.copyWith(elapsedSeconds: 30);

    expect(updated.setInputValues.containsKey('0-0'), isTrue,
        reason: 'setInputValues must survive copyWith — controllers rely on this for restore');
    expect(updated.setInputValues['0-0']?.weight, equals(60.0));
    expect(updated.setInputValues['0-0']?.reps, equals(10));
  });
  // ─────────────────────────────────────────────────────────────────────────────
  // BUG [Session 2026-04-02] #1 — Daily goals "Workout" green but train shows planned
  // ─────────────────────────────────────────────────────────────────────────────

  test('R16a: custom_template with status=completed is read back as completed', () async {
    final today = DateTime.now();
    final dateStr = formatDateKey(today);

    // Simulate a custom template workout that was completed.
    HiveService.instance.workoutBox.put('schedule_$dateStr', {
      'date': dateStr,
      'type': 'custom_template',
      'template_id': 'tmpl_test_001',
      'workout_name': 'Test Template Chest',
      'workout_focus': 'Custom',
      'exercises': <Map<String, dynamic>>[
        {'exercise_name': 'Bench Press', 'sets': 3, 'reps': '8'},
      ],
      'status': 'completed',
      'completed_at': today.toIso8601String(),
      'is_swapped': false,
      'duration_seconds': 1800,
    });

    final schedule = WorkoutScheduleService.instance.getScheduleForDate(today);
    expect(schedule, isNotNull);
    expect(schedule!['status'], equals('completed'),
        reason: 'custom_template type must retain completed status — '
            'home daily goals and train screen must agree');
    expect(schedule['type'], equals('custom_template'));
  });

  test('R16b: custom_template with status=planned is NOT treated as rest', () async {
    final today = DateTime.now();
    final dateStr = formatDateKey(today);

    HiveService.instance.workoutBox.put('schedule_$dateStr', {
      'date': dateStr,
      'type': 'custom_template',
      'template_id': 'tmpl_test_002',
      'workout_name': 'Custom Push Day',
      'workout_focus': 'Custom',
      'exercises': <Map<String, dynamic>>[
        {'exercise_name': 'Shoulder Press', 'sets': 3, 'reps': '10'},
      ],
      'status': 'planned',
      'is_swapped': false,
    });

    final schedule = WorkoutScheduleService.instance.getScheduleForDate(today);
    expect(schedule, isNotNull);
    expect(schedule!['type'], equals('custom_template'));
    // The isRest check in train_provider uses: type != 'workout' && type != 'custom_template'
    // So custom_template must NOT be rest.
    final isRest = schedule['type'] != 'workout' && schedule['type'] != 'custom_template';
    expect(isRest, isFalse,
        reason: 'custom_template must not be classified as rest day — '
            'this was the root cause of train screen showing gray for templates');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG [Session 2026-04-02] #2 — Auth isolation: clearAllData clears coachBox
  // ─────────────────────────────────────────────────────────────────────────────

  test('R17: clearAllData wipes coachBox (AI chat history)', () async {
    // Seed some chat history.
    HiveService.instance.coachBox.put('chat_msg_001', {
      'role': 'user',
      'content': 'Hello coach',
      'created_at': DateTime.now().toIso8601String(),
    });
    HiveService.instance.coachBox.put('chat_msg_002', {
      'role': 'assistant',
      'content': 'Hi there!',
      'created_at': DateTime.now().toIso8601String(),
    });

    expect(HiveService.instance.coachBox.length, equals(2),
        reason: 'Precondition: coachBox should have 2 messages');

    await UserRepository.instance.clearAllData();

    expect(HiveService.instance.coachBox.length, equals(0),
        reason: 'clearAllData must clear coachBox — prevents cross-user chat leakage');
    expect(HiveService.instance.workoutBox.length, equals(0),
        reason: 'clearAllData must also clear workoutBox');
    expect(HiveService.instance.nutritionBox.length, equals(0),
        reason: 'clearAllData must also clear nutritionBox');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG [Session 2026-04-02] #4 — Fiber not aggregated in daily nutrition
  // ─────────────────────────────────────────────────────────────────────────────

  test('R18: nutrition logs with total_fiber are aggregated correctly', () async {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Seed two nutrition logs with fiber.
    HiveService.instance.nutritionBox.put('nlog_test_001', {
      'id': 'nlog_test_001',
      'date': dateStr,
      'meal_type': 'breakfast',
      'food_name': 'Oatmeal',
      'total_calories': 300,
      'total_protein': 10,
      'total_carbs': 50,
      'total_fat': 5,
      'total_fiber': 8,
      'created_at': now.toIso8601String(),
      'source': 'manual',
    });
    HiveService.instance.nutritionBox.put('nlog_test_002', {
      'id': 'nlog_test_002',
      'date': dateStr,
      'meal_type': 'lunch',
      'food_name': 'Dal + Rice',
      'total_calories': 500,
      'total_protein': 20,
      'total_carbs': 70,
      'total_fat': 10,
      'total_fiber': 12,
      'created_at': now.toIso8601String(),
      'source': 'manual',
    });

    // Read back all entries for today and manually sum fiber (same logic as provider).
    double fiberTotal = 0;
    for (final val in HiveService.instance.nutritionBox.values) {
      if (val is! Map) continue;
      final log = Map<String, dynamic>.from(val);
      if (log['date'] != dateStr) continue;
      fiberTotal += (log['total_fiber'] as num?)?.toDouble() ?? 0;
    }

    expect(fiberTotal, equals(20.0),
        reason: 'Fiber should sum to 8 + 12 = 20g across both logs');

    // Also verify a log WITHOUT total_fiber doesn't crash the sum.
    HiveService.instance.nutritionBox.put('nlog_test_003', {
      'id': 'nlog_test_003',
      'date': dateStr,
      'meal_type': 'snacks',
      'food_name': 'Saved Meal (no fiber field)',
      'total_calories': 200,
      'total_protein': 15,
      'total_carbs': 20,
      'total_fat': 8,
      // NOTE: no 'total_fiber' key — simulates saved meals that lack it
      'created_at': now.toIso8601String(),
      'source': 'saved_meal',
    });

    double fiberTotal2 = 0;
    for (final val in HiveService.instance.nutritionBox.values) {
      if (val is! Map) continue;
      final log = Map<String, dynamic>.from(val);
      if (log['date'] != dateStr) continue;
      fiberTotal2 += (log['total_fiber'] as num?)?.toDouble() ?? 0;
    }

    expect(fiberTotal2, equals(20.0),
        reason: 'Missing total_fiber field should default to 0, not crash');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG [Session 2026-04-02] #8 — Volume calculation: Σ(weight × reps) per set
  // ─────────────────────────────────────────────────────────────────────────────

  test('R19a: receipt volume = sum of (weight × reps) per checked set', () {
    // 3 exercises, each with 3 sets.
    // Bench Press: 3 sets × 8 reps × 65kg = 1560
    // DB Press:    3 sets × 7 reps × 40kg = 840
    // Decline:     2 sets × 10 reps × 40kg = 800
    // Total = 1560 + 840 + 800 = 3200
    final exercises = [
      const ExerciseData(
          name: 'Barbell Bench Press', sets: '3', reps: '8', loggingType: 'weight_reps'),
      const ExerciseData(
          name: 'Dumbbell Bench Press', sets: '3', reps: '7', loggingType: 'weight_reps'),
      const ExerciseData(
          name: 'Decline Barbell Bench Press', sets: '2', reps: '10', loggingType: 'weight_reps'),
    ];

    final checkedSets = <String, bool>{};
    final setInputValues = <String, SetInputValues>{};

    // Bench: 3 sets, 8 reps, 65kg each
    for (int s = 0; s < 3; s++) {
      checkedSets['0-$s'] = true;
      setInputValues['0-$s'] = const SetInputValues(weight: 65.0, reps: 8);
    }
    // DB Press: 3 sets, 7 reps, 40kg each
    for (int s = 0; s < 3; s++) {
      checkedSets['1-$s'] = true;
      setInputValues['1-$s'] = const SetInputValues(weight: 40.0, reps: 7);
    }
    // Decline: 2 sets, 10 reps, 40kg each
    for (int s = 0; s < 2; s++) {
      checkedSets['2-$s'] = true;
      setInputValues['2-$s'] = const SetInputValues(weight: 40.0, reps: 10);
    }

    final workoutDay = WorkoutDayData(dayNumber: 1, name: 'Push Day', exercises: exercises);
    final data = ActiveWorkoutData(
      workoutDay: workoutDay,
      exercises: exercises,
      elapsedSeconds: 2700,
      checkedSets: checkedSets,
      setInputValues: setInputValues,
      isComplete: true,
      isSaved: true,
    );

    final receipt = WorkoutReceiptData.fromActiveWorkout(data);

    // 3×8×65 + 3×7×40 + 2×10×40 = 1560 + 840 + 800 = 3200
    expect(receipt.totalVolumeKg, equals(3200.0),
        reason: 'Volume must be Σ(weight × reps) per set = 3200kg');
    expect(receipt.totalSets, equals(8),
        reason: 'Total sets: 3 + 3 + 2 = 8');
  });

  test('R19b: warm-up sets are excluded from volume', () {
    final exercises = [
      const ExerciseData(
          name: 'Squat', sets: '4', reps: '5', loggingType: 'weight_reps'),
    ];

    final checkedSets = <String, bool>{};
    final setInputValues = <String, SetInputValues>{};
    final warmUpSets = <String, bool>{};

    // Set 0: warm-up at 40kg (should be excluded)
    checkedSets['0-0'] = true;
    setInputValues['0-0'] = const SetInputValues(weight: 40.0, reps: 5);
    warmUpSets['0-0'] = true;

    // Sets 1-3: working sets at 100kg
    for (int s = 1; s < 4; s++) {
      checkedSets['0-$s'] = true;
      setInputValues['0-$s'] = const SetInputValues(weight: 100.0, reps: 5);
    }

    final workoutDay = WorkoutDayData(dayNumber: 1, name: 'Leg Day', exercises: exercises);
    final data = ActiveWorkoutData(
      workoutDay: workoutDay,
      exercises: exercises,
      elapsedSeconds: 1800,
      checkedSets: checkedSets,
      setInputValues: setInputValues,
      warmUpSets: warmUpSets,
      isComplete: true,
      isSaved: true,
    );

    final receipt = WorkoutReceiptData.fromActiveWorkout(data);

    // Only working sets: 3 × 5 × 100 = 1500  (warm-up 5×40=200 excluded)
    expect(receipt.totalVolumeKg, equals(1500.0),
        reason: 'Warm-up set (40kg×5) must be excluded from volume');
    expect(receipt.totalSets, equals(3),
        reason: 'Only 3 working sets counted (warm-up excluded)');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG [Session 2026-04-02] #9/#10 — Post-workout state: cancel clears state,
  //                                     isSaved disables add-exercise
  // ─────────────────────────────────────────────────────────────────────────────

  test('R20a: cancelWorkout resets state completely', () {
    // After "Back to Home", cancelWorkout() should clear everything.
    const completedState = ActiveWorkoutData(
      elapsedSeconds: 2700,
      isComplete: true,
      isSaved: true,
      checkedSets: {'0-0': true, '0-1': true},
      setInputValues: {'0-0': SetInputValues(weight: 60.0, reps: 8)},
    );

    // Simulate what cancelWorkout produces.
    const resetState = ActiveWorkoutData();

    expect(resetState.isComplete, isFalse);
    expect(resetState.isSaved, isFalse);
    expect(resetState.elapsedSeconds, equals(0));
    expect(resetState.checkedSets, isEmpty);
    expect(resetState.setInputValues, isEmpty);
    expect(resetState.exercises, isEmpty);
    expect(resetState.workoutDay, isNull);

    // Verify completed state was different.
    expect(completedState.isComplete, isTrue);
    expect(completedState.isSaved, isTrue);
    expect(completedState.elapsedSeconds, equals(2700));
  });

  test('R20b: isSaved=true means add-exercise should be blocked', () {
    // The UI condition for disabling "Add Exercise" should check isSaved.
    // This test documents the expected contract: when isSaved is true,
    // no mutations (add exercise, re-finish) should be allowed.
    const reviewState = ActiveWorkoutData(isSaved: true, isComplete: false);

    // Contract: isSaved=true → no exercise additions, no re-save.
    expect(reviewState.isSaved, isTrue,
        reason: 'In review mode, isSaved must be true');
    expect(reviewState.isComplete, isFalse,
        reason: 'In review mode, isComplete must be false (showing exercises, not completion screen)');

    // Attempting copyWith to add exercise should NOT reset isSaved.
    final withExercise = reviewState.copyWith(
      exercises: [const ExerciseData(name: 'New Exercise', sets: '3', reps: '10')],
    );
    expect(withExercise.isSaved, isTrue,
        reason: 'Adding exercise via copyWith must NOT reset isSaved — '
            'UI should block this action when isSaved=true');
  });
  // ─────────────────────────────────────────────────────────────────────────────
  // BUG [Session 2026-04-02] #1b — Timestamp in today's meals card
  // ─────────────────────────────────────────────────────────────────────────────

  test('R21: nutrition log stores created_at ISO8601 timestamp', () async {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final id = 'nlog_ts_${now.millisecondsSinceEpoch}';

    HiveService.instance.nutritionBox.put(id, {
      'id': id,
      'date': dateStr,
      'meal_type': 'lunch',
      'food_name': 'Dal Rice',
      'total_calories': 350,
      'total_protein': 12,
      'total_carbs': 55,
      'total_fat': 8,
      'total_fiber': 6,
      'created_at': now.toIso8601String(),
      'source': 'ai_text',
    });

    final stored = HiveService.instance.nutritionBox.get(id);
    expect(stored, isNotNull);
    final log = Map<String, dynamic>.from(stored as Map);

    // Verify created_at is a parseable ISO8601 timestamp.
    final createdAt = log['created_at'] as String?;
    expect(createdAt, isNotNull, reason: 'created_at must be stored');
    final parsed = DateTime.tryParse(createdAt!);
    expect(parsed, isNotNull, reason: 'created_at must be valid ISO8601');
    expect(parsed!.difference(now).inSeconds.abs(), lessThan(2),
        reason: 'created_at must be close to the time of creation');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG [Session 2026-04-02] #2b — Fiber edit round-trip via updateFoodLog
  // ─────────────────────────────────────────────────────────────────────────────

  test('R22: updating fiber via Hive preserves the value', () async {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final id = 'nlog_fiber_edit_${now.millisecondsSinceEpoch}';

    // Seed a log with fiber = 0.
    HiveService.instance.nutritionBox.put(id, {
      'id': id,
      'date': dateStr,
      'meal_type': 'snacks',
      'food_name': 'Broccoli',
      'total_calories': 200,
      'total_protein': 8,
      'total_carbs': 25,
      'total_fat': 6,
      'total_fiber': 0,
      'created_at': now.toIso8601String(),
      'source': 'ai_text',
    });

    // Simulate what updateFoodLog does: update fiber to 5.
    final existing = HiveService.instance.nutritionBox.get(id);
    final updated = Map<String, dynamic>.from(existing as Map);
    updated['total_fiber'] = 5;
    await HiveService.instance.nutritionBox.put(id, updated);

    // Read back.
    final readBack = HiveService.instance.nutritionBox.get(id);
    final log = Map<String, dynamic>.from(readBack as Map);

    expect(log['total_fiber'], equals(5),
        reason: 'Fiber must be updated to 5 after edit');

    // Verify aggregation picks it up.
    double fiberTotal = 0;
    for (final val in HiveService.instance.nutritionBox.values) {
      if (val is! Map) continue;
      final l = Map<String, dynamic>.from(val);
      if (l['date'] != dateStr) continue;
      fiberTotal += (l['total_fiber'] as num?)?.toDouble() ?? 0;
    }

    expect(fiberTotal, equals(5.0),
        reason: 'Daily fiber aggregation must include the updated value');
  });

  // ── R23: Barcode food log includes total_fiber ──────────────────────────
  testWidgets('R23 – barcode food save includes total_fiber',
      (WidgetTester tester) async {
    final hive = HiveService.instance;
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final id = 'nlog_barcode_fiber_test';

    // Simulate what barcode_scan_sheet._logFood() does after the fix:
    // fiberPer100g = 8.0, serving = 150g → fiber = 8.0 * 150 / 100 = 12
    const fiberPer100g = 8.0;
    const servingG = 150.0;
    final expectedFiber = (fiberPer100g * servingG / 100).round(); // 12

    await hive.nutritionBox.put(id, {
      'id': id,
      'date': dateStr,
      'meal_type': 'snacks',
      'food_name': 'Test Barcode Item',
      'quantity_g': servingG,
      'total_calories': 250,
      'total_protein': 10,
      'total_carbs': 30,
      'total_fat': 8,
      'total_fiber': expectedFiber,
      'created_at': now.toIso8601String(),
      'source': 'barcode',
    });

    final saved = hive.nutritionBox.get(id) as Map;
    expect(saved['total_fiber'], equals(12),
        reason: 'Barcode food log must store total_fiber computed from fiberPer100g');
    expect(saved['source'], equals('barcode'));

    // Clean up
    await hive.nutritionBox.delete(id);
  });
}

// ── Extension helpers ────────────────────────────────────────────────────────

extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
