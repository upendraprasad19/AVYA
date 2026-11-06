// test/features/ai_coach/coach_single_confirm_per_log_intent_test.dart
//
// audit-fixwave 2026-07-02 / F1 (+ B-pass fix) — coach dual-path double-log.
//
// One AI response that carries BOTH a legacy `confirm_workout_log` draft AND its
// typed `log_set` intent must render exactly ONE confirm affordance — but the
// draft carries an exercises[] ARRAY while log_set covers ONE exercise, so the
// draft is suppressed ONLY when EVERY draft exercise is covered by a log_set
// intent (resolved exerciseId→name via exerciseBox). A partially-covered
// multi-exercise draft is KEPT so its uncovered exercises are never lost (the
// B-pass P2 the adversarial review caught). Food (log_meal_by_text) is covered
// by a boolean.
//
// These tests FAIL on the pre-fix tree AND on the naive kind-based dedup (which
// dropped the whole multi-exercise draft).
//
// closes-diagnose: a1d7c3

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';

import '../../helpers/hive_test_setup.dart';

ToolIntent _logSet(String exerciseId) => ToolIntent(
      id: 'id_$exerciseId',
      type: 'log_set',
      payload: {'exerciseId': exerciseId},
      confirmationClass: ConfirmationClass.reviewable,
      previewSummary: '',
      createdAt: DateTime.now(),
    );

ToolIntent _foodIntent() => ToolIntent(
      id: 'id_food',
      type: 'log_meal_by_text',
      payload: const {},
      confirmationClass: ConfirmationClass.reviewable,
      previewSummary: '',
      createdAt: DateTime.now(),
    );

Map<String, dynamic> _workoutAction(List<String> exerciseNames) => {
      'action': 'confirm_workout_log',
      'data': {
        'exercises': [
          for (final n in exerciseNames)
            {
              'name': n,
              'logging_type': 'weight_reps',
              'sets': [
                {'weight_kg': 60, 'reps': 10},
              ],
            },
        ],
      },
    };

const _foodAction = {
  'action': 'log_food',
  'data': {'food_name': 'Roti', 'meal_type': 'lunch'},
};

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  late dynamic tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    // Seed the exercise library so log_set exerciseId → name resolves.
    await HiveService.instance.exerciseBox.put('ex_bench', {'name': 'Bench Press'});
    await HiveService.instance.exerciseBox.put('ex_squat', {'name': 'Squat'});
  });
  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  void run(ProviderContainer c, List<Map<String, dynamic>> actions,
      List<ToolIntent> intents) {
    final ref = c.read(_refProvider);
    c.read(pendingLogActionsProvider.notifier).addActions(
          actions,
          ref,
          coverage: typedLogCoverage(intents),
        );
  }

  group('typedLogCoverage', () {
    test('resolves log_set exerciseId → exercise name; flags food', () {
      final cov = typedLogCoverage([_logSet('ex_bench'), _foodIntent()]);
      expect(cov.workoutExerciseNames, {'bench press'});
      expect(cov.foodCovered, isTrue);
    });
    test('unresolvable exerciseId contributes no coverage', () {
      final cov = typedLogCoverage([_logSet('ex_unknown')]);
      expect(cov.workoutExerciseNames, isEmpty);
    });
  });

  group('addActions — F1 exercise-aware dedup', () {
    test('suppresses a single-exercise draft fully covered by a log_set', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      run(c, [_workoutAction(['Bench Press'])], [_logSet('ex_bench')]);
      expect(c.read(workoutDraftProvider), isNull,
          reason: 'draft fully covered by the typed log_set → one card, not two');
    });

    test('KEEPS a multi-exercise draft only PARTIALLY covered (no exercise lost)',
        () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // Draft = Bench + Squat; log_set covers only Bench.
      run(c, [_workoutAction(['Bench Press', 'Squat'])], [_logSet('ex_bench')]);
      final draft = c.read(workoutDraftProvider);
      expect(draft, isNotNull,
          reason: 'a partially-covered multi-exercise draft must NOT be dropped '
              '— Squat would be silently lost (B-pass P2)');
    });

    test('suppresses a multi-exercise draft FULLY covered by matching log_sets',
        () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      run(c, [_workoutAction(['Bench Press', 'Squat'])],
          [_logSet('ex_bench'), _logSet('ex_squat')]);
      expect(c.read(workoutDraftProvider), isNull,
          reason: 'all draft exercises covered → suppress the redundant draft');
    });

    test('KEEPS a solo draft with no log_set intent', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      run(c, [_workoutAction(['Bench Press'])], const []);
      expect(c.read(workoutDraftProvider), isNotNull);
    });

    test('suppresses a log_food action when a log_meal_by_text intent covers it',
        () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      run(c, [Map<String, dynamic>.from(_foodAction)], [_foodIntent()]);
      expect(c.read(pendingLogActionsProvider), isEmpty);
    });

    test('never suppresses a non-overlapping legacy action (water)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      run(c, [
        {
          'action': 'log_water',
          'data': {'ml': 250},
        },
      ], [
        _logSet('ex_bench'),
        _foodIntent(),
      ]);
      expect(c.read(pendingLogActionsProvider).length, 1,
          reason: 'water has no typed twin — always enqueues');
    });
  });
}
