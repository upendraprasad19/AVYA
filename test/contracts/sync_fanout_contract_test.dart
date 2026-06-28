import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

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
    syncServiceSrc = loadSyncServiceSource().readAsStringSync();
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
    test('syncWorkoutDataNow() fans out to all 6 workout-domain helpers', () {
      // Unit H / H1a — the fan-out body moved to the non-coalesced
      // syncWorkoutDataNow(); syncWorkoutData() is the coalesced entry that
      // delegates to it.
      final body = methodBody(syncServiceSrc, 'syncWorkoutDataNow');

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
            reason: 'syncWorkoutDataNow() must fan out to $helper '
                    '(see CLAUDE.md §15 sync fan-out contract).');
      }
    });

    test('syncNutritionDataNow() fans out to all 3 nutrition-domain helpers', () {
      // Unit H / H1a — fan-out body moved to syncNutritionDataNow().
      final body = methodBody(syncServiceSrc, 'syncNutritionDataNow');

      const expectedHelpers = {
        '_syncNutritionLogs',
        '_syncWaterLogs',
        '_syncSavedMeals',
      };

      for (final helper in expectedHelpers) {
        expect(body.contains(helper), isTrue,
            reason: 'syncNutritionDataNow() must fan out to $helper '
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

    test('_syncSavedMeals omits id + upserts onConflict (user_id,name) — f7e3a1', () {
      // f7e3a1 reversed the old "coerce id via _deterministicId" contract: a
      // name-only deterministic id collided cross-user. Comment-stripped so the
      // explanatory comment (naming the OLD shape) can't false-pass this.
      final body = methodBody(syncServiceSrc, '_syncSavedMeals')
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .replaceAll(RegExp(r'//[^\n]*'), '');
      expect(body.contains("onConflict: 'user_id,name'"), isTrue,
          reason: 'f7e3a1: user-scoped natural key (user_id,name), not a '
                  'name-only deterministic id.');
      expect(body.contains('_deterministicId'), isFalse,
          reason: 'f7e3a1: id is OMITTED (gen_random_uuid). Diagnose f7e3a1.');
    });
  });
}
