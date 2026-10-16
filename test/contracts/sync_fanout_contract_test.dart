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
                    '(see docs/architecture/sync.md sync fan-out contract).');
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
                    '(see docs/architecture/sync.md sync fan-out contract).');
      }
    });

    test(
        '_syncScheduledWorkouts resolves template_id by NAME lookup, never '
        '_deterministicId coercion (APK Test #14 / Bug B.1)', () {
      // day-swapper+sync-load Task 15 correction (2026-09-27): this
      // assertion previously read `isTrue` — the OLD (pre-2026-05-10)
      // contract, which was removed by APK Test #14 / Bug B.1 (the v5 hash
      // on the raw Hive tmpl_<ms> key never matched cloud's
      // gen_random_uuid() id and 23503'd every push carrying a template;
      // see docs/diagnoses/2026-05-10-fk-violation-saturday-c8e4a1.md).
      // It kept passing only because the pre-Task-15 body's own explanatory
      // comment happened to quote the literal `_deterministicId` string —
      // a coincidental pass, not a real assertion of the coercion contract.
      // Task 15's rewritten doc comment no longer quotes it, which exposed
      // the staleness. Comment-stripped (mirrors the `_syncSavedMeals`
      // check below) so a future explanatory comment can't re-trip this
      // either way. The real contract (name-based resolution) is pinned in
      // full by test/contracts/scheduled_workouts_fk_resilience_test.dart.
      final body = methodBody(syncServiceSrc, '_syncScheduledWorkouts')
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .replaceAll(RegExp(r'//[^\n]*'), '');
      expect(body.contains('_deterministicId'), isFalse,
          reason: 'APK Test #14 / Bug B.1: template_id is resolved by '
                  'lookup-by-name (resolveCloudTemplateId), never coerced '
                  'via _deterministicId(rawTemplateId).');
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
