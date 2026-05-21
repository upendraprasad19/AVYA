import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icanbefitter/core/constants/app_environment.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';

import '../../helpers/hive_test_helper.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// REGRESSION TESTS — WORKOUT SCHEDULE (markCompleted, stale guard, custom_template)
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Split from `regression_bug_fixes_test.dart` (T5, audit 2026-05-20).
///
/// R5  — [Bug 3a] markCompleted: stores durationSeconds in Hive schedule entry
/// R6  — [Bug 3a] getScheduleForDate: reads durationSeconds back correctly
/// R7  — [Bug 5]  stale guard: yesterday's completed_at → returns 'planned'
/// R8  — [Bug 5]  stale guard: today's completed_at → stays 'completed'
/// R9  — [Bug 5]  stale guard is read-only (does NOT overwrite Hive)
/// R16a — custom_template with status=completed is read back as completed
/// R16b — custom_template with status=planned is NOT treated as rest

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
  // BUG [Session 2026-04-02] #1 — Daily goals "Workout" green but train shows planned
  // ─────────────────────────────────────────────────────────────────────────────

  test('R16a: custom_template with status=completed is read back as completed', () async {
    final today = DateTime.now();
    final dateStr = formatDateKey(today);

    // Simulate a custom template workout that was completed.
    await HiveService.instance.workoutBox.put('schedule_$dateStr', {
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

    await HiveService.instance.workoutBox.put('schedule_$dateStr', {
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
}
