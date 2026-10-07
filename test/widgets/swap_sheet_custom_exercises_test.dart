import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

/// APK Test #15.4 / A5 — closes the swap-picker custom-exercise miss.
///
/// closes-diagnose: 2026-05-15-swap-picker-custom-miss-a5d29c
///
/// Bug: Founder's "Single Leg Front Lever" (custom exercise created
/// 2026-05-02, present in cloud `user_custom_exercises`) returned
/// "No matching exercises found" in the active-workout SWAP EXERCISE
/// picker after fresh install. Restore wrote raw cloud rows into
/// `customBox` keyed `custom_exercise_<id>` but the cloud row has no
/// `type` column, so the reader's `if (ex['type'] == 'exercise')`
/// filter silently dropped every restored entry.
///
/// Two-layer defense pinned here:
///   1. Reader fallback — `getCustomExercises()` accepts entries by
///      either `type == 'exercise'` (legacy create path) OR Hive key
///      prefix `custom_exercise_*` (restore path).
///   2. Restore stamp — `_restoreCustomExercises` writes
///      `item['type'] = 'exercise'` before `customBox.put` so legacy
///      readers that haven't grown key-prefix fallback also see them.
///
/// Plus the UX bug: empty-state "No matching exercises found" now
/// only fires when BOTH library and custom result lists are empty.
/// Pre-fix it rendered above the custom section if the library half
/// was empty, hiding the matching custom result visually.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Source-grep: swap sheet custom-exercise wiring', () {
    test('exercise_swap_sheet loads + filters custom exercises', () {
      final source = File(
        'lib/features/train/widgets/exercise_swap_sheet.dart',
      ).readAsStringSync();

      expect(
        source.contains('getCustomExercises()'),
        isTrue,
        reason: 'Sheet must load custom exercises via '
            'ExerciseRepository.getCustomExercises() so users see their '
            'own exercises (including restored ones).',
      );
      expect(
        source.contains('_filteredCustom'),
        isTrue,
        reason: 'Sheet must expose a separately-filtered custom list so '
            'the search box applies to user exercises too.',
      );
      expect(
        source.contains('YOUR CUSTOM EXERCISES'),
        isTrue,
        reason: 'Custom section header must be present so users can '
            'visually distinguish their own exercises from the library.',
      );
      expect(
        source.contains('isCustom: true'),
        isTrue,
        reason: 'Custom entries must pass isCustom=true so the CUSTOM '
            'badge renders on the row.',
      );
      expect(
        source.contains("'CUSTOM'"),
        isTrue,
        reason: 'CUSTOM badge text must render on each custom entry.',
      );
    });

    test(
        'empty-state fires only when BOTH library AND custom are empty',
        () {
      final source = File(
        'lib/features/train/widgets/exercise_swap_sheet.dart',
      ).readAsStringSync();

      // The empty-state condition must check BOTH lists. Pre-fix this
      // was `if (filtered.isEmpty)` only → misleading message rendered
      // above non-empty custom results.
      expect(
        source.contains('filtered.isEmpty && filteredCustom.isEmpty'),
        isTrue,
        reason: 'Empty-state guard must require both library AND custom '
            'lists to be empty before showing "No matching exercises '
            'found". Pre-fix this rendered when library was empty even '
            'if custom had a match (the founder bug).',
      );
    });

    test('restore stamps type:exercise on restored custom items', () {
      final source = File(
        'lib/core/services/sync/sync_community.dart',
      ).readAsStringSync();

      expect(
        source.contains("item['type'] = 'exercise'"),
        isTrue,
        reason: '_restoreCustomExercises must stamp type:exercise on '
            'every restored row so legacy readers that filter by '
            "ex['type'] == 'exercise' see them. Cloud "
            'user_custom_exercises has no type column.',
      );
    });

    test('reader accepts either type field OR key prefix', () {
      final source = File(
        'lib/shared/repositories/exercise_repository.dart',
      ).readAsStringSync();

      expect(
        source.contains("key.startsWith('custom_exercise_')"),
        isTrue,
        reason: 'getCustomExercises() must accept entries by Hive key '
            'prefix as well as the legacy type field — restore writes '
            "raw cloud rows that don't carry type. Pre-fix the type-only "
            'filter dropped every restored custom exercise.',
      );
    });
  });

  group('Behavioral: getCustomExercises restored entries', () {
    Directory? tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('swap_test_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir!.path,
      );
      Hive.init(tempDir!.path);
      GuardedBox.testBypassOwnership = true;
      await HiveService.instance.init();
      await HiveUserSession.openForUser(
        'swap-test-id-12345678-aaaa-bbbb-cccc-dddddddddddd',
      );
    });

    tearDownAll(() async {
      GuardedBox.testBypassOwnership = false;
      await HiveUserSession.closeAll();
      await Hive.deleteFromDisk();
      await Hive.close();
      if (tempDir != null && await tempDir!.exists()) {
        await tempDir!.delete(recursive: true);
      }
    });

    test(
        'restored cloud row WITHOUT type field is visible via '
        'getCustomExercises (key-prefix fallback)',
        () async {
      final customBox = HiveService.instance.customBox;
      await customBox.clear();

      // Simulate a raw cloud row written by _restoreCustomExercises
      // BEFORE the type-stamp fix landed (e.g. devices that already
      // restored). No `type` field.
      await customBox.put('custom_exercise_29aeaa20-7c10-5012-b89a-209a3692f150', {
        'id': '29aeaa20-7c10-5012-b89a-209a3692f150',
        'name': 'Single Leg Front Lever',
        'category': 'Pull',
        'logging_type': 'timed',
        // NOTE: no 'type' field — this is the bug shape.
      });

      final results = ExerciseRepository.instance.getCustomExercises();
      expect(results.length, 1,
          reason: 'Reader must surface the restored entry via key-prefix '
              'fallback even when the cloud row carries no type field.');
      expect(results.first['name'], 'Single Leg Front Lever');
    });

    test(
        'legacy entry WITH type:exercise (and any key) is still visible',
        () async {
      final customBox = HiveService.instance.customBox;
      await customBox.clear();

      // Locally-created entry via CreateCustomExerciseSheet — carries
      // type:exercise and may use a timestamp-based key like
      // 'cx_<timestamp>' (legacy WorkoutRepository.createCustomExercise
      // historically used different key shapes).
      await customBox.put('cx_1714600000', {
        'id': 'cx_1714600000',
        'name': 'Tornado Kick',
        'category': 'Cardio',
        'logging_type': 'timed',
        'type': 'exercise',
      });

      final results = ExerciseRepository.instance.getCustomExercises();
      expect(results.length, 1,
          reason: 'Reader must continue to accept legacy entries '
              'identified by type:exercise regardless of key shape.');
      expect(results.first['name'], 'Tornado Kick');
    });

    test('non-exercise custom items (foods) are NOT returned', () async {
      final customBox = HiveService.instance.customBox;
      await customBox.clear();

      await customBox.put('custom_food_abc123', {
        'id': 'abc123',
        'name': 'Homemade Idli',
        'type': 'food',
      });
      await customBox.put(
          'custom_exercise_29aeaa20-7c10-5012-b89a-209a3692f150', {
        'id': '29aeaa20-7c10-5012-b89a-209a3692f150',
        'name': 'Single Leg Front Lever',
        'category': 'Pull',
        // no type stamp — restore shape
      });

      final results = ExerciseRepository.instance.getCustomExercises();
      expect(results.length, 1,
          reason: 'Custom foods must NOT leak into the exercise list. '
              'Key-prefix discriminates exercises from foods.');
      expect(results.first['name'], 'Single Leg Front Lever');
    });

    test('search query finds restored custom exercise by name substring',
        () async {
      final customBox = HiveService.instance.customBox;
      await customBox.clear();

      await customBox.put(
          'custom_exercise_29aeaa20-7c10-5012-b89a-209a3692f150', {
        'id': '29aeaa20-7c10-5012-b89a-209a3692f150',
        'name': 'Single Leg Front Lever',
        'category': 'Pull',
        'logging_type': 'timed',
      });

      // Mirror the swap-sheet _filteredCustom logic.
      final all = ExerciseRepository.instance.getCustomExercises();
      final q = 'Single Leg Front'.toLowerCase();
      final matching = all.where((e) {
        final name = (e['name'] as String?)?.toLowerCase() ?? '';
        return name.contains(q);
      }).toList();

      expect(matching.length, 1,
          reason: 'Founder\'s exact search query "Single Leg Front" must '
              'surface the restored custom exercise.');
      expect(matching.first['name'], 'Single Leg Front Lever');
    });
  });
}
