import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// F5 · Test #9 — fan-out coverage contract.
///
/// Asserts that every workoutBox / nutritionBox key prefix written
/// anywhere in the codebase has a matching `_sync*()` call inside the
/// per-mutation entry point (`syncWorkoutData()` / `syncNutritionData()`).
///
/// The 2026-05-03 sync gap (templates / scheduled_workouts / streaks /
/// saved_meals invisible to cloud for >24h) was the canonical failure
/// mode this contract prevents.
///
/// Source-grep style following test/contracts/hive_key_contracts_test.dart.
void main() {
  late String syncServiceSrc;

  setUpAll(() {
    final root = File('lib/core/services/sync_service.dart');
    expect(root.existsSync(), isTrue,
        reason: 'Run from project root');
    final partsDir = Directory('lib/core/services/sync');
    final parts = partsDir.existsSync()
        ? partsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
        : <File>[];
    syncServiceSrc = [
      root.readAsStringSync(),
      ...parts.map((f) => f.readAsStringSync()),
    ].join('\n\n');
  });

  /// Extracts the body of a named `Future<void>` method as a string.
  String methodBody(String src, String methodName) {
    final pattern =
        RegExp(r'Future<void>\s+' + methodName + r'\s*\([^)]*\)\s*async\s*\{');
    final match = pattern.firstMatch(src);
    expect(match, isNotNull,
        reason: 'method $methodName not found in sync_service.dart');
    final start = match!.end - 1;
    int depth = 1;
    int i = start + 1;
    while (i < src.length && depth > 0) {
      final ch = src[i];
      if (ch == '{') depth++;
      if (ch == '}') depth--;
      i++;
    }
    return src.substring(start, i);
  }

  group('F5 · sync fan-out contract', () {
    test('syncWorkoutData() fans out to all 6 workout-domain helpers', () {
      final body = methodBody(syncServiceSrc, 'syncWorkoutData');

      const expectedHelpers = {
        '_syncWorkoutLogs',
        '_syncExerciseLogs',
        '_syncScheduleCompletions',
        '_syncWorkoutTemplates',
        '_syncScheduledWorkouts',
        '_syncStreaks',
      };

      for (final helper in expectedHelpers) {
        expect(body.contains(helper), isTrue,
            reason: 'syncWorkoutData() must fan out to $helper '
                    '(see CLAUDE.md §15 sync fan-out contract).');
      }
    });

    test('syncNutritionData() fans out to all 3 nutrition-domain helpers', () {
      final body = methodBody(syncServiceSrc, 'syncNutritionData');

      const expectedHelpers = {
        '_syncNutritionLogs',
        '_syncWaterLogs',
        '_syncSavedMeals',
      };

      for (final helper in expectedHelpers) {
        expect(body.contains(helper), isTrue,
            reason: 'syncNutritionData() must fan out to $helper '
                    '(see CLAUDE.md §15 sync fan-out contract).');
      }
    });

    test('_syncScheduledWorkouts coerces template_id via _deterministicId', () {
      final body = methodBody(syncServiceSrc, '_syncScheduledWorkouts');
      expect(body.contains('_deterministicId'), isTrue,
          reason: '_syncScheduledWorkouts must coerce template_id to '
                  'deterministic UUID (F3). Raw Hive tmpl_<ms> strings '
                  'silently uuid-reject on the server.');
    });

    test('_syncSavedMeals coerces id via _deterministicId', () {
      final body = methodBody(syncServiceSrc, '_syncSavedMeals');
      expect(body.contains('_deterministicId'), isTrue,
          reason: '_syncSavedMeals must coerce id to deterministic UUID (F4). '
                  'Raw Hive saved_meal_<hash> keys silently uuid-reject.');
    });
  });
}
