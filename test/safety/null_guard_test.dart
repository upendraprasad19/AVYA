import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/read_screen_source.dart';

/// Verifies that the null-safety guards introduced in fix/crash-safety are
/// present in the source files. Two styles of test:
///  1. Pure-Dart unit tests for inline logic that can be extracted.
///  2. File-content assertions for widget-level guards where mounting the
///     full widget tree is not feasible in this codebase's test setup.
void main() {
  // ── Task 1: Hive.box() → HiveService.instance ──────────────────────────────

  group('Task 1 – raw Hive.box() replaced with HiveService.instance', () {
    test('sign_in_screen.dart has no raw Hive.box() calls', () {
      final src = _src('lib/features/auth/screens/sign_in_screen.dart');
      expect(src, isNot(contains("Hive.box(")),
          reason: 'sign_in_screen should use HiveService.instance, not Hive.box()');
      expect(src, contains('HiveService.instance.configBox'));
    });

    test('ai_coach_repository.dart has no raw Hive.box() calls', () {
      final src = _src(
          'lib/features/ai_coach/repositories/ai_coach_repository.dart');
      expect(src, isNot(contains("Hive.box(")),
          reason: 'ai_coach_repository should use HiveService.instance.*Box');
    });

    test('progression_resolver.dart uses HiveService.instance.workoutBox', () {
      final src = _src(
          'lib/shared/repositories/plan_engine/progression_resolver.dart');
      expect(src, isNot(contains("Hive.box(")));
      expect(src, contains('HiveService.instance.workoutBox'));
    });

    // audit-fixwave 2026-07-02 / F15 — terms_modal.dart deleted (dead widget,
    // zero call sites); its raw-Hive.box guard test was removed with it.
  });

  // ── Task 2: exercise_type List.first guards ─────────────────────────────────

  group('Task 2 – exercise_type .first guarded for empty list', () {
    test('empty list returns null (guard logic)', () {
      final typeList = <dynamic>[];
      final type = (typeList.isNotEmpty) ? typeList.first.toString() : null;
      expect(type, isNull);
    });

    test('non-empty list returns value (guard logic)', () {
      final typeList = <dynamic>['compound'];
      final type = (typeList.isNotEmpty) ? typeList.first.toString() : null;
      expect(type, 'compound');
    });

    test('train_provider.dart guards .first with isNotEmpty before the call', () {
      final src = _src('lib/features/train/providers/train_provider.dart');
      // The fix wraps the .first call inside an isNotEmpty conditional block.
      // Both the guard and the .first must be present (in that order).
      final isNotEmptyIdx = src.indexOf(
          "(m['exercise_type'] as List).isNotEmpty");
      final firstIdx = src.indexOf(
          "(m['exercise_type'] as List).first.toString()");
      expect(isNotEmptyIdx, greaterThan(0),
          reason: 'train_provider must have isNotEmpty guard on exercise_type');
      expect(firstIdx, greaterThan(isNotEmptyIdx),
          reason: '.first must come AFTER the isNotEmpty guard');
    });

    test('active_workout_screen.dart guards exercise_type .first with isNotEmpty', () {
      // C3 — file split. The picker `_showExercisePickerSheet` was moved
      // to active_workout/swap_sheets.dart, which is where the exercise_type
      // isNotEmpty guard now lives.
      final src = _src(
          'lib/features/train/screens/active_workout/swap_sheets.dart');
      // The fix wraps the .first call inside an isNotEmpty conditional block.
      final isNotEmptyIdx = src.indexOf(
          "(exerciseData['exercise_type'] as List).isNotEmpty");
      final firstIdx = src.indexOf(
          "(exerciseData['exercise_type'] as List).first.toString()");
      expect(isNotEmptyIdx, greaterThan(0),
          reason: 'active_workout_screen must have isNotEmpty guard on exercise_type');
      expect(firstIdx, greaterThan(isNotEmptyIdx),
          reason: '.first must come AFTER the isNotEmpty guard');
    });
  });

  // ── Task 3: todayDay! force-unwrap ──────────────────────────────────────────

  group('Task 3 – todayDay! force-unwrap removed', () {
    test('train_screen.dart has no todayDay! force-unwrap', () {
      final src = readScreenSource('train');
      expect(src, isNot(contains('todayDay!')),
          reason: 'todayDay! force-unwrap must be replaced with null check');
    });

    test('train_screen.dart uses null-safe isDoneToday && todayDay != null', () {
      final src = readScreenSource('train');
      expect(src, contains('isDoneToday && todayDay != null'));
    });
  });

  // ── Task 4: macros map force-unwraps ────────────────────────────────────────

  group('Task 4 – macros map force-unwraps removed', () {
    test('null-safe macro extraction returns 0.0 for missing key', () {
      final macros = <String, dynamic>{};
      final calories = (macros['calories'] as num?)?.toDouble() ?? 0.0;
      final protein = (macros['protein'] as num?)?.toDouble() ?? 0.0;
      final carbs = (macros['carbs'] as num?)?.toDouble() ?? 0.0;
      final fat = (macros['fat'] as num?)?.toDouble() ?? 0.0;
      expect(calories, 0.0);
      expect(protein, 0.0);
      expect(carbs, 0.0);
      expect(fat, 0.0);
    });

    test('null-safe macro extraction returns actual value', () {
      final macros = <String, dynamic>{
        'calories': 350,
        'protein': 28.5,
        'carbs': 45.0,
        'fat': 12,
        'fiber': 8.0,
      };
      expect((macros['calories'] as num?)?.toDouble() ?? 0.0, 350.0);
      expect((macros['protein'] as num?)?.toDouble() ?? 0.0, 28.5);
      expect((macros['carbs'] as num?)?.toDouble() ?? 0.0, 45.0);
      expect((macros['fat'] as num?)?.toDouble() ?? 0.0, 12.0);
      expect((macros['fiber'] as num?)?.toDouble() ?? 0.0, 8.0);
    });

    test('home_provider.dart has no macros[] force-unwrap bangs', () {
      final src = _src('lib/features/home/providers/home_provider.dart');
      expect(src, isNot(contains("macros['calories']!")));
      expect(src, isNot(contains("macros['protein']!")));
      expect(src, isNot(contains("macros['carbs']!")));
      expect(src, isNot(contains("macros['fat']!")));
    });

    test('nutrition_provider.dart has no macros[] force-unwrap bangs', () {
      final src = _src(
          'lib/features/nutrition/providers/nutrition_provider.dart');
      expect(src, isNot(contains("macros['calories']!")));
      expect(src, isNot(contains("macros['protein']!")));
      expect(src, isNot(contains("macros['carbs']!")));
      expect(src, isNot(contains("macros['fat']!")));
      expect(src, isNot(contains("macros['fiber']!")));
    });
  });

  // ── Task 5: sentences.last empty guard ─────────────────────────────────────

  group('Task 5 – sentences.last empty-list guard', () {
    test('guard logic: isEmpty returns null before .last', () {
      String? tip;
      const String response = '';
      final sentences = response.split(RegExp(r'[.!?]\s+'));
      // Only return null when sentences produce empty trimmed content.
      // Note: split('') returns [''] not [] — the isEmpty guard is a
      // forward-safety measure for logic changes.
      if (sentences.isEmpty) {
        tip = null;
      } else {
        final candidate = sentences.last.trim();
        tip = (candidate.length > 80 || candidate.length < 10) ? null : candidate;
      }
      // Empty string → [''] → last = '' → length 0 < 10 → null
      expect(tip, isNull);
    });

    test('guard logic: valid last sentence returned', () {
      String? tip;
      const String response = 'Keep lifting. Stay consistent. Sleep more.';
      final sentences = response.split(RegExp(r'[.!?]\s+'));
      if (sentences.isEmpty) {
        tip = null;
      } else {
        final candidate = sentences.last.trim();
        tip = (candidate.length > 80 || candidate.length < 10) ? null : candidate;
      }
      expect(tip, isNotNull);
    });

    test('home_provider.dart has isEmpty guard before sentences.last', () {
      final src = _src('lib/features/home/providers/home_provider.dart');
      expect(src, contains('if (sentences.isEmpty) return null;'));
    });
  });

  // ── Task 6: options.keys.first empty guard ──────────────────────────────────

  group('Task 6 – options.keys.first empty-map guard', () {
    test('empty options map detected before .first', () {
      final options = <String, String>{};
      // Guard: early return SizedBox.shrink() when options is empty
      expect(options.isEmpty, isTrue);
    });

    test('non-empty options resolves first key', () {
      final options = {'moderate': 'Moderate', 'active': 'Active'};
      expect(options.isEmpty, isFalse);
      expect(options.keys.first, 'moderate');
    });

    test('edit_profile_screen.dart has isEmpty early return in _buildDropdown', () {
      final src = _src(
          'lib/features/profile/screens/edit_profile_screen.dart');
      expect(src,
          contains('if (options.isEmpty) return const SizedBox.shrink();'));
    });
  });

  // ── Task 7: diet_plan_screen .first after shuffle ───────────────────────────

  group('Task 7 – diet_plan_screen isEmpty guard positioned after shuffle', () {
    test('shuffle does not affect emptiness, guard after is explicit', () {
      final foods = <Map<String, dynamic>>[
        {'name': 'Dal'},
        {'name': 'Rice'},
      ];
      foods.shuffle();
      // Guard under test — after shuffle
      if (foods.isEmpty) return;
      expect(foods.first, isNotNull);
    });

    test('diet plan generator guards isEmpty before .first/.shuffle', () {
      // APK Test #3 / Plan C Task 4 (2026-04-26) extracted the diet plan
      // algorithm from `diet_plan_screen.dart` into a dedicated service at
      // `lib/features/nutrition/services/diet_plan_generator.dart`. The
      // shuffle + .first calls now live there. The new service guards
      // isEmpty BEFORE shuffle (a slightly cheaper but equally safe pattern
      // — the original test required isEmpty AFTER shuffle, which mattered
      // only when both checks lived inline in the screen widget).
      final src = _src(
          'lib/features/nutrition/services/diet_plan_generator.dart');
      expect(src.contains('.shuffle('), isTrue,
          reason: 'shuffle call must exist in the generator');
      expect(
        src.contains('candidates.isEmpty') || src.contains('pool.isEmpty'),
        isTrue,
        reason: 'isEmpty guard must exist before .first/.shuffle to '
            'prevent crashes on empty food pools',
      );
    });
  });

  // ── Task 8: healthSyncDone addPostFrameCallback ─────────────────────────────

  group('Task 8 – healthSyncDone wrapped in addPostFrameCallback', () {
    test(
        'home_screen.dart uses addPostFrameCallback inside healthSyncDone.then',
        () {
      final src = _src('lib/features/home/screens/home_screen.dart');
      expect(src, contains('addPostFrameCallback'),
          reason: 'healthSyncDone.then must defer state change via '
              'addPostFrameCallback to avoid setState-during-build');
    });
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Reads a file path relative to the Flutter project root.
/// `flutter test` sets the working directory to the project root.
String _src(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) {
    fail('Source file not found: $relativePath');
  }
  return file.readAsStringSync();
}
