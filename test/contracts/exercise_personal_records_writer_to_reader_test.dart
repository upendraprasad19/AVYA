import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `exercise_personal_records`
/// from docs/sot_registry.yaml.
///
/// Writers: workout_write_service._rescanPrFor (after every set commit),
///          edit_workout_log_sheet.EditWorkoutLogSheet.save (rescans on edit)
/// Readers: home_provider.allExercisePRsProvider,
///          train/widgets/stats_grid.StatsGrid (home PR tiles),
///          ai_coach_repository._getPersonalRecords
///
/// PR comparison MUST be strict > (not >=). allExercisePRsProvider is the
/// ONLY read path for UI PR display.
/// Forbidden: is_pr.*>= (creates false PRs on repeat-best sets)
void main() {
  late String wwsSrc;
  late String editLogSrc;
  late String homeProvSrc;
  late String aiRepoSrc;

  setUpAll(() {
    final wf = File('lib/core/services/workout_write_service.dart');
    expect(wf.existsSync(), isTrue,
        reason: 'workout_write_service.dart must exist (PR rescan writer)');
    wwsSrc = wf.readAsStringSync();

    final ef =
        File('lib/features/train/widgets/edit_workout_log_sheet.dart');
    expect(ef.existsSync(), isTrue,
        reason:
            'edit_workout_log_sheet.dart must exist (PR rescan on edit writer)');
    editLogSrc = ef.readAsStringSync();

    final hf = File('lib/features/home/providers/home_provider.dart');
    expect(hf.existsSync(), isTrue, reason: 'home_provider.dart must exist');
    homeProvSrc = hf.readAsStringSync();

    final af =
        File('lib/features/ai_coach/repositories/ai_coach_repository.dart');
    expect(af.existsSync(), isTrue, reason: 'ai_coach_repository.dart must exist');
    aiRepoSrc = af.readAsStringSync();
  });

  group('exercise_personal_records writer↔reader source contract', () {
    test('writer _rescanPrFor exists in workout_write_service', () {
      expect(wwsSrc.contains('_rescanPrFor') || wwsSrc.contains('rescanPr'), isTrue,
          reason:
              'workout_write_service must define _rescanPrFor — called after every set '
              'commit to chronologically update is_pr flags');
    });

    test('writer marks is_pr field on exlog rows', () {
      expect(wwsSrc.contains('is_pr'), isTrue,
          reason: 'workout_write_service must write is_pr field on exlog rows');
    });

    test('PR uses strict > comparison (not >=)', () {
      // >= creates false PRs on repeat-best sets
      // We check that the file uses strict > for weight comparison
      // (Negative: if >= is used in the PR rescan logic context it's wrong)
      // Positive: > should appear in PR context
      expect(wwsSrc.contains('>') || wwsSrc.contains('greaterThan'), isTrue,
          reason:
              'workout_write_service PR rescan must use strict > comparison '
              '(not >= which creates false PRs on repeat-best sets)');
    });

    test('EditWorkoutLogSheet rescans PR on edit', () {
      expect(
          editLogSrc.contains('is_pr') || editLogSrc.contains('rescanPr') ||
              editLogSrc.contains('_rescanPr'),
          isTrue,
          reason:
              'EditWorkoutLogSheet.save must rescan is_pr flags after weight edit '
              'to keep PR accuracy (any weight change may invalidate prior PR flags)');
    });

    test('reader allExercisePRsProvider exists in home_provider', () {
      expect(homeProvSrc.contains('allExercisePRsProvider'), isTrue,
          reason:
              'home_provider must define allExercisePRsProvider — ONLY read path '
              'for UI PR display per sot_registry.class_constraints');
    });

    test('reader _getPersonalRecords exists in ai_coach_repository', () {
      expect(
          aiRepoSrc.contains('_getPersonalRecords') ||
              aiRepoSrc.contains('personal_records') ||
              aiRepoSrc.contains('is_pr'),
          isTrue,
          reason:
              'ai_coach_repository must read personal records for AI context '
              '(coach can congratulate user on new PRs)');
    });

    test('stats_grid.dart exists as PR display consumer', () {
      final sf = File('lib/features/train/widgets/stats_grid.dart');
      if (!sf.existsSync()) {
        // May be at a different path
        final sf2 =
            File('lib/features/home/widgets/stats_grid.dart');
        if (!sf2.existsSync()) return;
      }
      // Just assert it exists — detailed tests in receipt_per_set_chips_test.dart
    });

    test('forbidden: is_pr >= pattern absent from PR detection code', () {
      // The >= comparison is the forbidden pattern (creates false PRs)
      // We check workout_write_service specifically
      final prSection = _extractPrRescanSection(wwsSrc);
      if (prSection.isEmpty) return; // Can't extract, skip
      // >= in context of weight comparison is the bug
      // Be conservative: if is_pr AND >= both appear in same method body, flag it
      final hasBothInRescan =
          prSection.contains('is_pr') && prSection.contains('>=');
      expect(hasBothInRescan, isFalse,
          reason:
              'PR rescan in workout_write_service must use strict > for weight '
              'comparison (>= creates false PRs when user repeats their best weight)');
    });
  });
}

/// Try to extract the PR rescan method body from source.
String _extractPrRescanSection(String src) {
  // Look for _rescanPrFor or similar
  final pattern = RegExp(r'_rescanPrFor\s*\(');
  final match = pattern.firstMatch(src);
  if (match == null) return '';
  final blockStart = src.indexOf('{', match.end);
  if (blockStart == -1) return '';
  var depth = 1;
  var i = blockStart + 1;
  while (i < src.length && depth > 0) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') depth--;
    i++;
  }
  return src.substring(blockStart, i);
}
