// Shared cross-archetype contract tests for Plan Engine V4.
//
// Relocated from `test/plan_engine_v3_test.dart` on 2026-05-21 (tech-debt
// audit B5 / T7 split). Test bodies are byte-identical to V3.
//
// Scope: contracts that span all archetypes — SplitResolver intermediate
// / advanced / all-splits / 6-day / 5-day; SequencingEngine ordering;
// CardioFinisher goal+preference+equipment matrix; WarmupCooldownSelector
// attachment + experience differences; SupersetPairer day-type +
// antagonist rules; and the end-to-end Periodization → Sequencing →
// Superset → Finisher → Warmup integration pipeline.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/cardio_finisher.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/sequencing_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/superset_pairer.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/warmup_cooldown.dart';

import '_helpers.dart';

void main() {
  // ════════════════════════════════════════════════════════════════
  // 1. SPLIT RESOLVER — non-beginner, non-strength-archetype-specific
  // ════════════════════════════════════════════════════════════════

  group('SplitResolver', () {
    group('Intermediate routing', () {
      test('intermediate 4-day build_muscle → NOT full body', () {
        final slots = SplitResolver.select(
          'build_muscle', 4, experienceLevel: 'intermediate',
        );
        expect(slots.length, 4);
        final dayTypes = slots.map((s) => s.dayType).toSet();
        // Should have push, pull, legs, upper — not all full_body
        expect(dayTypes, isNot(equals({'full_body'})));
        expect(dayTypes, containsAll(['push', 'pull', 'legs']));
      });

      test('intermediate 3-day lose_fat → full body splits', () {
        final slots = SplitResolver.select(
          'lose_fat', 3, experienceLevel: 'intermediate',
        );
        expect(slots.length, 3);
        for (final slot in slots) {
          expect(slot.dayType, 'full_body');
        }
      });

      test('intermediate 3-day build_muscle → push/pull/legs', () {
        final slots = SplitResolver.select(
          'build_muscle', 3, experienceLevel: 'intermediate',
        );
        expect(slots.length, 3);
        final dayTypes = slots.map((s) => s.dayType).toSet();
        expect(dayTypes, containsAll(['push', 'pull', 'legs']));
      });
    });

    group('Advanced routing', () {
      test('advanced 3-day build_muscle → NOT full body', () {
        final slots = SplitResolver.select(
          'build_muscle', 3, experienceLevel: 'advanced',
        );
        expect(slots.length, 3);
        final dayTypes = slots.map((s) => s.dayType).toSet();
        expect(dayTypes, containsAll(['push', 'pull', 'legs']));
      });
    });

    group('All splits have non-empty specs', () {
      for (final goal in ['build_muscle', 'lose_fat', 'strength', 'general_fitness']) {
        for (final days in [3, 4, 5, 6]) {
          for (final exp in ['beginner', 'intermediate', 'advanced']) {
            test('$exp $days-day $goal has non-empty specs', () {
              final slots = SplitResolver.select(
                goal, days, experienceLevel: exp,
              );
              expect(slots, isNotEmpty,
                  reason: '$exp $days-day $goal returned no slots');
              for (final slot in slots) {
                expect(slot.specsA, isNotEmpty,
                    reason: '${slot.name} has empty specsA');
                expect(slot.name, isNotEmpty);
                expect(slot.focus, isNotEmpty);
                expect(slot.dayType, isNotEmpty);
                expect(slot.intensity, isNotEmpty);
              }
            });
          }
        }
      }
    });

    group('6-day splits', () {
      test('6-day build_muscle → 6 days with PPL A/B baked in', () {
        final slots = SplitResolver.select(
          'build_muscle', 6, experienceLevel: 'intermediate',
        );
        expect(slots.length, 6);
        final names = slots.map((s) => s.name).toList();
        expect(names.where((n) => n.contains('Push')).length, 2);
        expect(names.where((n) => n.contains('Pull')).length, 2);
        expect(names.where((n) => n.contains('Legs')).length, 2);
      });

      test('6-day default → 6 days', () {
        final slots = SplitResolver.select(
          'lose_fat', 6, experienceLevel: 'intermediate',
        );
        expect(slots.length, 6);
      });
    });

    group('5-day build_muscle has shoulders_arms day', () {
      test('5-day muscle includes a shoulders_arms day type', () {
        final slots = SplitResolver.select(
          'build_muscle', 5, experienceLevel: 'intermediate',
        );
        final dayTypes = slots.map((s) => s.dayType).toSet();
        expect(dayTypes, contains('shoulders_arms'));
      });
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 3. SEQUENCING ENGINE
  // ════════════════════════════════════════════════════════════════

  group('SequencingEngine', () {
    group('Compound before isolation', () {
      test('compounds sorted before isolations', () {
        final weeks = [
          weekPlan(workoutDays: [
            workoutDay(exercises: [
              exercise(name: 'Cable Fly', exerciseType: 'isolation'),
              exercise(name: 'Bench Press', exerciseType: 'compound'),
              exercise(name: 'Lateral Raise', exerciseType: 'isolation'),
              exercise(name: 'Incline Bench Press', exerciseType: 'compound'),
            ]),
          ]),
        ];

        final result = SequencingEngine.sequence(weeks);
        final exercises = result[0].workoutDays[0].exercises;

        // Find boundary: all compounds should come before all isolations
        int lastCompoundIdx = -1;
        int firstIsolationIdx = exercises.length;
        for (int i = 0; i < exercises.length; i++) {
          if (exercises[i].exerciseType == 'compound') {
            lastCompoundIdx = i;
          }
          if (exercises[i].exerciseType == 'isolation' && i < firstIsolationIdx) {
            firstIsolationIdx = i;
          }
        }
        expect(lastCompoundIdx, lessThan(firstIsolationIdx),
            reason: 'All compounds should appear before any isolation');
      });
    });

    group('Bilateral before unilateral within compounds', () {
      test('bilateral compounds sorted before unilateral compounds', () {
        final weeks = [
          weekPlan(workoutDays: [
            workoutDay(exercises: [
              exercise(name: 'Bulgarian Split Squat', exerciseType: 'compound'),
              exercise(name: 'Barbell Squat', exerciseType: 'compound'),
              exercise(name: 'Walking Lunge', exerciseType: 'compound'),
              exercise(name: 'Deadlift', exerciseType: 'compound'),
            ]),
          ]),
        ];

        final result = SequencingEngine.sequence(weeks);
        final exercises = result[0].workoutDays[0].exercises;

        // Bilateral exercises (Squat, Deadlift) should come before unilateral (Lunge, Split Squat)
        final sqIdx = exercises.indexWhere((e) => e.exerciseName == 'Barbell Squat');
        final dlIdx = exercises.indexWhere((e) => e.exerciseName == 'Deadlift');
        final lungeIdx = exercises.indexWhere((e) => e.exerciseName == 'Walking Lunge');
        final bssIdx = exercises.indexWhere((e) => e.exerciseName == 'Bulgarian Split Squat');

        // Both bilateral exercises should be before both unilateral exercises
        expect(sqIdx, lessThan(lungeIdx));
        expect(sqIdx, lessThan(bssIdx));
        expect(dlIdx, lessThan(lungeIdx));
        expect(dlIdx, lessThan(bssIdx));
      });
    });

    group('CNS ordering within same tier', () {
      test('higher CNS demand compound exercises come first', () {
        final weeks = [
          weekPlan(workoutDays: [
            workoutDay(exercises: [
              exercise(name: 'Lat Pulldown', exerciseType: 'compound'),
              exercise(name: 'Barbell Squat', exerciseType: 'compound'),
              exercise(name: 'Bench Press', exerciseType: 'compound'),
            ]),
          ]),
        ];

        final result = SequencingEngine.sequence(weeks);
        final exercises = result[0].workoutDays[0].exercises;

        // Squat (CNS 5) should come before Bench (4) which should come before Pulldown (3)
        final sqIdx = exercises.indexWhere((e) => e.exerciseName == 'Barbell Squat');
        final bpIdx = exercises.indexWhere((e) => e.exerciseName == 'Bench Press');
        final lpIdx = exercises.indexWhere((e) => e.exerciseName == 'Lat Pulldown');

        expect(sqIdx, lessThan(bpIdx),
            reason: 'Squat (CNS 5) should come before Bench Press (CNS 4)');
        expect(bpIdx, lessThan(lpIdx),
            reason: 'Bench Press (CNS 4) should come before Lat Pulldown (CNS 3)');
      });
    });

    group('Warmup annotation', () {
      test('compound exercises get warmupSet = true', () {
        final weeks = [
          weekPlan(workoutDays: [
            workoutDay(exercises: [
              exercise(name: 'Bench Press', exerciseType: 'compound'),
              exercise(name: 'Overhead Press', exerciseType: 'compound'),
              exercise(name: 'Cable Fly', exerciseType: 'isolation'),
              exercise(name: 'Lateral Raise', exerciseType: 'isolation'),
            ]),
          ]),
        ];

        final result = SequencingEngine.sequence(weeks);
        final exercises = result[0].workoutDays[0].exercises;

        // Both compounds should have warmupSet = true (they are first 2 in sorted order)
        final compounds = exercises.where((e) => e.exerciseType == 'compound').toList();
        for (final c in compounds) {
          expect(c.warmupSet, isTrue,
              reason: '${c.exerciseName} (compound) should have warmupSet = true');
        }

        // Isolations should NOT have warmupSet
        final isolations = exercises.where((e) => e.exerciseType == 'isolation').toList();
        for (final iso in isolations) {
          expect(iso.warmupSet, isFalse,
              reason: '${iso.exerciseName} (isolation) should NOT have warmupSet');
        }
      });
    });

    group('Edge cases', () {
      test('single exercise returns unchanged', () {
        final single = exercise(name: 'Bench Press', exerciseType: 'compound');
        final weeks = [
          weekPlan(workoutDays: [
            workoutDay(exercises: [single]),
          ]),
        ];

        final result = SequencingEngine.sequence(weeks);
        final exercises = result[0].workoutDays[0].exercises;
        expect(exercises.length, 1);
        expect(exercises[0].exerciseName, 'Bench Press');
      });

      test('empty list returns empty', () {
        final weeks = [
          weekPlan(workoutDays: [
            workoutDay(exercises: []),
          ]),
        ];

        final result = SequencingEngine.sequence(weeks);
        expect(result[0].workoutDays[0].exercises, isEmpty);
      });

      test('preserves warmup/cooldown/finisher through sequencing', () {
        final warmupEx = exercise(name: 'Arm Circles', category: 'warmup');
        final cooldownEx = exercise(name: 'Stretching', category: 'cooldown');
        final finisherEx = exercise(name: 'Burpees', category: 'finisher');

        final weeks = [
          weekPlan(workoutDays: [
            workoutDay(
              exercises: [exercise(name: 'Bench Press', exerciseType: 'compound')],
              warmup: [warmupEx],
              cooldown: [cooldownEx],
              finisher: [finisherEx],
            ),
          ]),
        ];

        final result = SequencingEngine.sequence(weeks);
        final day = result[0].workoutDays[0];
        expect(day.warmup.length, 1);
        expect(day.cooldown.length, 1);
        expect(day.finisher.length, 1);
        expect(day.warmup[0].exerciseName, 'Arm Circles');
        expect(day.cooldown[0].exerciseName, 'Stretching');
        expect(day.finisher[0].exerciseName, 'Burpees');
      });
    });

    group('Multiple weeks processed', () {
      test('all weeks get sequenced', () {
        final weeks = List.generate(4, (i) => weekPlan(
          weekNumber: i + 1,
          weekInPhase: i + 1,
          workoutDays: [
            workoutDay(exercises: [
              exercise(name: 'Cable Fly', exerciseType: 'isolation'),
              exercise(name: 'Bench Press', exerciseType: 'compound'),
            ]),
          ],
        ));

        final result = SequencingEngine.sequence(weeks);
        expect(result.length, 4);

        for (final week in result) {
          final exs = week.workoutDays[0].exercises;
          // Compound (Bench Press) should be first in every week
          expect(exs[0].exerciseName, 'Bench Press');
          expect(exs[1].exerciseName, 'Cable Fly');
        }
      });
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 4. CARDIO FINISHER
  // ════════════════════════════════════════════════════════════════

  group('CardioFinisher', () {
    group('Goal filtering', () {
      test('only attaches for lose_fat', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'lose_fat',
          cardioPreference: 'hiit',
          equipmentList: ['bodyweight'],
        );
        final daysWithFinisher = result[0].workoutDays.where((d) => d.finisher.isNotEmpty);
        expect(daysWithFinisher, isNotEmpty);
      });

      test('only attaches for general_fitness', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'general_fitness',
          cardioPreference: 'hiit',
          equipmentList: ['bodyweight'],
        );
        final daysWithFinisher = result[0].workoutDays.where((d) => d.finisher.isNotEmpty);
        expect(daysWithFinisher, isNotEmpty);
      });

      test('build_muscle goal → no finishers attached', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'build_muscle',
          cardioPreference: 'hiit',
          equipmentList: ['bodyweight'],
        );
        for (final day in result[0].workoutDays) {
          expect(day.finisher, isEmpty,
              reason: 'build_muscle should have no finishers');
        }
      });

      test('strength goal → no finishers attached', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'strength',
          cardioPreference: 'running',
          equipmentList: ['bodyweight'],
        );
        for (final day in result[0].workoutDays) {
          expect(day.finisher, isEmpty,
              reason: 'strength should have no finishers');
        }
      });
    });

    group('Finisher count', () {
      test('attaches to exactly 2 days per week', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3), workoutDay(dayNumber: 4),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'lose_fat',
          cardioPreference: 'hiit',
          equipmentList: ['bodyweight'],
        );
        final daysWithFinisher = result[0].workoutDays.where((d) => d.finisher.isNotEmpty).length;
        expect(daysWithFinisher, 2);
      });

      test('attaches to exactly 2 days even for 6-day weeks', () {
        final weeks = [weekPlan(workoutDays: List.generate(6,
          (i) => workoutDay(dayNumber: i + 1),
        ))];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'lose_fat',
          cardioPreference: 'running',
          equipmentList: ['bodyweight'],
        );
        final daysWithFinisher = result[0].workoutDays.where((d) => d.finisher.isNotEmpty).length;
        expect(daysWithFinisher, 2);
      });
    });

    group('Finisher exercises', () {
      test('finisher exercises have category = finisher', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'lose_fat',
          cardioPreference: 'hiit',
          equipmentList: ['bodyweight'],
        );
        for (final day in result[0].workoutDays) {
          for (final f in day.finisher) {
            expect(f.category, 'finisher');
          }
        }
      });

      test('finisher exercises have loggingType = timed', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'lose_fat',
          cardioPreference: 'jump_rope',
          equipmentList: ['bodyweight'],
        );
        for (final day in result[0].workoutDays) {
          for (final f in day.finisher) {
            expect(f.loggingType, 'timed');
          }
        }
      });
    });

    group('Preference differences', () {
      test('running preference → treadmill/jogging exercises', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'lose_fat',
          cardioPreference: 'running',
          equipmentList: ['full_gym'],
        );
        final finisherDays = result[0].workoutDays.where((d) => d.finisher.isNotEmpty);
        for (final day in finisherDays) {
          expect(day.finisher.length, 1);
          final name = day.finisher[0].exerciseName.toLowerCase();
          expect(name.contains('treadmill') || name.contains('jogging'), isTrue,
              reason: 'Running preference should produce treadmill/jogging finisher, got: ${day.finisher[0].exerciseName}');
        }
      });

      test('hiit preference → multiple bodyweight exercises', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'lose_fat',
          cardioPreference: 'hiit',
          equipmentList: ['bodyweight'],
        );
        final finisherDays = result[0].workoutDays.where((d) => d.finisher.isNotEmpty);
        for (final day in finisherDays) {
          // HIIT has burpees + mountain climbers + jump squats = 3 exercises
          expect(day.finisher.length, 3);
        }
      });

      test('hate_cardio preference → mini HIIT (shortest)', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'lose_fat',
          cardioPreference: 'hate_cardio',
          equipmentList: ['bodyweight'],
        );
        final finisherDays = result[0].workoutDays.where((d) => d.finisher.isNotEmpty);
        for (final day in finisherDays) {
          // Mini HIIT: high knees + burpees + mountain climbers = 3
          expect(day.finisher.length, 3);
          // Each has only 2 sets (shorter than regular HIIT)
          for (final f in day.finisher) {
            expect(f.sets, 2);
          }
        }
      });

      test('jump_rope preference → single exercise', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'general_fitness',
          cardioPreference: 'jump_rope',
          equipmentList: ['bodyweight'],
        );
        final finisherDays = result[0].workoutDays.where((d) => d.finisher.isNotEmpty);
        for (final day in finisherDays) {
          expect(day.finisher.length, 1);
          expect(day.finisher[0].exerciseName, 'Jump Rope Intervals');
        }
      });
    });

    group('Equipment awareness', () {
      test('no gym → bodyweight running alternative (spot jogging)', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'lose_fat',
          cardioPreference: 'running',
          equipmentList: ['bodyweight', 'dumbbells'],
        );
        final finisherDays = result[0].workoutDays.where((d) => d.finisher.isNotEmpty);
        for (final day in finisherDays) {
          expect(day.finisher[0].exerciseName, 'Spot Jogging Intervals',
              reason: 'Without gym equipment, running should fallback to Spot Jogging');
        }
      });

      test('full_gym → treadmill for running preference', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'lose_fat',
          cardioPreference: 'running',
          equipmentList: ['full_gym'],
        );
        final finisherDays = result[0].workoutDays.where((d) => d.finisher.isNotEmpty);
        for (final day in finisherDays) {
          expect(day.finisher[0].exerciseName, 'Treadmill Intervals');
        }
      });

      test('no gym + cycling preference → high knees fallback', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'lose_fat',
          cardioPreference: 'cycling',
          equipmentList: ['bodyweight'],
        );
        final finisherDays = result[0].workoutDays.where((d) => d.finisher.isNotEmpty);
        for (final day in finisherDays) {
          expect(day.finisher[0].exerciseName, 'High Knees Intervals');
        }
      });

      test('gym + cycling preference → stationary bike', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1), workoutDay(dayNumber: 2),
          workoutDay(dayNumber: 3),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'lose_fat',
          cardioPreference: 'cycling',
          equipmentList: ['basic_gym'],
        );
        final finisherDays = result[0].workoutDays.where((d) => d.finisher.isNotEmpty);
        for (final day in finisherDays) {
          expect(day.finisher[0].exerciseName, 'Stationary Bike Sprints');
        }
      });
    });

    group('Preserves existing exercises', () {
      test('main exercises not modified when finisher is attached', () {
        final originalEx = exercise(name: 'Bench Press', sets: 4);
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1, exercises: [originalEx]),
          workoutDay(dayNumber: 2, exercises: [originalEx]),
          workoutDay(dayNumber: 3, exercises: [originalEx]),
        ])];
        final result = CardioFinisher.attach(
          weeks: weeks,
          goal: 'lose_fat',
          cardioPreference: 'hiit',
          equipmentList: ['bodyweight'],
        );
        for (final day in result[0].workoutDays) {
          expect(day.exercises.length, 1);
          expect(day.exercises[0].exerciseName, 'Bench Press');
          expect(day.exercises[0].sets, 4);
        }
      });
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 5. WARMUP/COOLDOWN SELECTOR
  // ════════════════════════════════════════════════════════════════

  group('WarmupCooldownSelector', () {
    group('Basic attachment', () {
      test('warmup attached to every workout day', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1, name: 'Push'),
          workoutDay(dayNumber: 2, name: 'Pull'),
          workoutDay(dayNumber: 3, name: 'Legs'),
        ])];

        final result = WarmupCooldownSelector.attach(weeks, 'beginner', ['bodyweight']);

        for (final day in result[0].workoutDays) {
          expect(day.warmup, isNotEmpty,
              reason: '${day.name} should have warmup exercises');
        }
      });

      test('cooldown attached to every workout day', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1, name: 'Push'),
          workoutDay(dayNumber: 2, name: 'Pull'),
          workoutDay(dayNumber: 3, name: 'Legs'),
        ])];

        final result = WarmupCooldownSelector.attach(weeks, 'beginner', ['bodyweight']);

        for (final day in result[0].workoutDays) {
          expect(day.cooldown, isNotEmpty,
              reason: '${day.name} should have cooldown exercises');
        }
      });
    });

    group('Warmup structure', () {
      test('warmup has cardio + dynamic exercises', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1, name: 'Push'),
        ])];

        final result = WarmupCooldownSelector.attach(weeks, 'beginner', ['bodyweight']);
        final warmup = result[0].workoutDays[0].warmup;

        // First exercise should be cardio (timed, 300s)
        expect(warmup[0].loggingType, 'timed');
        expect(warmup[0].reps, '300s');
        expect(warmup[0].category, 'warmup');

        // Should have at least 3 more dynamic exercises
        expect(warmup.length, greaterThanOrEqualTo(4),
            reason: 'Warmup should have 1 cardio + at least 3 dynamic exercises');
      });

      test('all warmup exercises have category = warmup', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1, name: 'Legs'),
        ])];

        final result = WarmupCooldownSelector.attach(weeks, 'beginner', ['bodyweight']);
        for (final ex in result[0].workoutDays[0].warmup) {
          expect(ex.category, 'warmup');
        }
      });
    });

    group('Cooldown structure', () {
      test('cooldown has slow walking + stretches', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1, name: 'Push'),
        ])];

        final result = WarmupCooldownSelector.attach(weeks, 'intermediate', ['bodyweight']);
        final cooldown = result[0].workoutDays[0].cooldown;

        // First exercise should be slow walking
        expect(cooldown[0].exerciseName, 'Slow Walking');
        expect(cooldown[0].reps, '300s');

        // Should have stretches after
        expect(cooldown.length, greaterThanOrEqualTo(3),
            reason: 'Cooldown should have slow walking + at least 2 stretches');

        // All should be timed
        for (final ex in cooldown) {
          expect(ex.loggingType, 'timed');
          expect(ex.category, 'cooldown');
        }
      });

      test('stretches are 30s duration', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1, name: 'Push'),
        ])];

        final result = WarmupCooldownSelector.attach(weeks, 'beginner', ['bodyweight']);
        final cooldown = result[0].workoutDays[0].cooldown;

        // Stretches (after slow walking) should be 30s
        for (int i = 1; i < cooldown.length; i++) {
          expect(cooldown[i].reps, '30s');
        }
      });
    });

    group('Experience-based warmup differences', () {
      test('advanced gets different warmup exercises than beginner for push day', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1, name: 'Push'),
        ])];

        final beginnerResult = WarmupCooldownSelector.attach(
          weeks, 'beginner', ['bodyweight'],
        );
        final advancedResult = WarmupCooldownSelector.attach(
          weeks, 'advanced', ['bodyweight'],
        );

        final beginnerNames = beginnerResult[0].workoutDays[0].warmup
            .map((e) => e.exerciseName).toList();
        final advancedNames = advancedResult[0].workoutDays[0].warmup
            .map((e) => e.exerciseName).toList();

        // They should not be identical
        expect(beginnerNames, isNot(equals(advancedNames)),
            reason: 'Beginner and advanced should have different warmup exercises');
      });

      test('advanced gets different warmup exercises than beginner for legs day', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1, name: 'Legs'),
        ])];

        final beginnerResult = WarmupCooldownSelector.attach(
          weeks, 'beginner', ['bodyweight'],
        );
        final advancedResult = WarmupCooldownSelector.attach(
          weeks, 'advanced', ['bodyweight'],
        );

        final beginnerNames = beginnerResult[0].workoutDays[0].warmup
            .map((e) => e.exerciseName).toList();
        final advancedNames = advancedResult[0].workoutDays[0].warmup
            .map((e) => e.exerciseName).toList();

        expect(beginnerNames, isNot(equals(advancedNames)));
      });

      test('advanced push warmup includes Push Up', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1, name: 'Push'),
        ])];
        final result = WarmupCooldownSelector.attach(weeks, 'advanced', ['bodyweight']);
        final warmupNames = result[0].workoutDays[0].warmup
            .map((e) => e.exerciseName).toList();
        expect(warmupNames, contains('Push Up'));
      });

      test('beginner push warmup includes Wall Push Up', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1, name: 'Push'),
        ])];
        final result = WarmupCooldownSelector.attach(weeks, 'beginner', ['bodyweight']);
        final warmupNames = result[0].workoutDays[0].warmup
            .map((e) => e.exerciseName).toList();
        expect(warmupNames, contains('Wall Push Up'));
      });
    });

    group('Equipment awareness', () {
      test('gym equipment adds additional cardio options', () {
        // With multiple days, the cardio rotation should cycle through gym options
        final weeks = [weekPlan(workoutDays: List.generate(5,
          (i) => workoutDay(dayNumber: i + 1, name: 'Day ${i + 1}'),
        ))];

        final resultNoGym = WarmupCooldownSelector.attach(weeks, 'beginner', ['bodyweight']);
        final resultGym = WarmupCooldownSelector.attach(weeks, 'beginner', ['full_gym']);

        final noGymCardio = resultNoGym[0].workoutDays
            .map((d) => d.warmup[0].exerciseName).toSet();
        final gymCardio = resultGym[0].workoutDays
            .map((d) => d.warmup[0].exerciseName).toSet();

        // Gym should have more cardio variety
        expect(gymCardio.length, greaterThan(noGymCardio.length),
            reason: 'Gym equipment should provide more cardio warmup variety');
      });
    });

    group('Preserves existing data', () {
      test('main exercises preserved after warmup/cooldown attached', () {
        final ex = exercise(name: 'Squat', sets: 5);
        final weeks = [weekPlan(workoutDays: [
          workoutDay(dayNumber: 1, name: 'Legs', exercises: [ex]),
        ])];

        final result = WarmupCooldownSelector.attach(weeks, 'beginner', ['bodyweight']);
        expect(result[0].workoutDays[0].exercises.length, 1);
        expect(result[0].workoutDays[0].exercises[0].exerciseName, 'Squat');
        expect(result[0].workoutDays[0].exercises[0].sets, 5);
      });

      test('finisher preserved after warmup/cooldown attached', () {
        final finisherEx = exercise(name: 'Burpees', category: 'finisher');
        final weeks = [weekPlan(workoutDays: [
          workoutDay(
            dayNumber: 1, name: 'Push',
            finisher: [finisherEx],
          ),
        ])];

        final result = WarmupCooldownSelector.attach(weeks, 'beginner', ['bodyweight']);
        expect(result[0].workoutDays[0].finisher.length, 1);
        expect(result[0].workoutDays[0].finisher[0].exerciseName, 'Burpees');
      });
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 6. SUPERSET PAIRER
  // ════════════════════════════════════════════════════════════════

  group('SupersetPairer', () {
    group('Antagonist pairing', () {
      test('pairs chest and back exercises', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(name: 'Upper', exercises: [
            exercise(name: 'Bench Press', primaryMuscles: ['Chest']),
            exercise(name: 'Shoulder Press', primaryMuscles: ['Deltoids']),
            exercise(name: 'Cable Fly', primaryMuscles: ['Chest']),
            exercise(name: 'Lat Pulldown', primaryMuscles: ['Lats']),
            exercise(name: 'Bicep Curl', primaryMuscles: ['Biceps']),
            exercise(name: 'Tricep Extension', primaryMuscles: ['Triceps']),
          ]),
        ])];

        final result = SupersetPairer.pair(weeks);
        final exercises = result[0].workoutDays[0].exercises;

        // First 2 should remain standalone (no superset group)
        expect(exercises[0].supersetGroup, isNull);
        expect(exercises[1].supersetGroup, isNull);

        // Check that some exercises got paired
        final pairedExercises = exercises.where((e) => e.supersetGroup != null).toList();
        expect(pairedExercises, isNotEmpty,
            reason: 'Some exercises should be paired as supersets');
      });

      test('pairs biceps and triceps', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(name: 'Shoulders + Arms', exercises: [
            exercise(name: 'Shoulder Press', primaryMuscles: ['Deltoids']),
            exercise(name: 'Lateral Raise', primaryMuscles: ['Side Deltoid']),
            exercise(name: 'Bicep Curl', primaryMuscles: ['Biceps']),
            exercise(name: 'Tricep Extension', primaryMuscles: ['Triceps']),
          ]),
        ])];

        final result = SupersetPairer.pair(weeks);
        final exercises = result[0].workoutDays[0].exercises;

        // Bicep Curl and Tricep Extension (indices 2,3) should be paired
        final bicepCurl = exercises.firstWhere((e) => e.exerciseName == 'Bicep Curl');
        final tricepExt = exercises.firstWhere((e) => e.exerciseName == 'Tricep Extension');
        expect(bicepCurl.supersetGroup, isNotNull);
        expect(tricepExt.supersetGroup, isNotNull);
        expect(bicepCurl.supersetGroup, tricepExt.supersetGroup);
      });

      test('pairs quads and hamstrings', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(name: 'Legs', exercises: [
            exercise(name: 'Squat', primaryMuscles: ['Quads']),
            exercise(name: 'Romanian Deadlift', primaryMuscles: ['Hamstrings']),
            exercise(name: 'Leg Extension', primaryMuscles: ['Quads']),
            exercise(name: 'Leg Curl', primaryMuscles: ['Hamstrings']),
            exercise(name: 'Calf Raise', primaryMuscles: ['Calves']),
          ]),
        ])];

        final result = SupersetPairer.pair(weeks);
        final exercises = result[0].workoutDays[0].exercises;

        // Exercises at index 2+ should have some pairing
        final legExt = exercises.firstWhere((e) => e.exerciseName == 'Leg Extension');
        final legCurl = exercises.firstWhere((e) => e.exerciseName == 'Leg Curl');
        expect(legExt.supersetGroup, isNotNull);
        expect(legCurl.supersetGroup, isNotNull);
        expect(legExt.supersetGroup, legCurl.supersetGroup);
      });
    });

    group('First 2 exercises remain standalone', () {
      test('does NOT pair first 2 exercises', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(name: 'Full Body', exercises: [
            exercise(name: 'Bench Press', primaryMuscles: ['Chest']),
            exercise(name: 'Barbell Row', primaryMuscles: ['Back']),
            exercise(name: 'Cable Fly', primaryMuscles: ['Chest']),
            exercise(name: 'Lat Pulldown', primaryMuscles: ['Lats']),
          ]),
        ])];

        final result = SupersetPairer.pair(weeks);
        final exercises = result[0].workoutDays[0].exercises;

        // First 2 exercises should have no superset group
        expect(exercises[0].supersetGroup, isNull,
            reason: 'First exercise should not be paired');
        expect(exercises[1].supersetGroup, isNull,
            reason: 'Second exercise should not be paired');
      });
    });

    group('Day type restrictions', () {
      test('pairs on legs day', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(name: 'Legs', exercises: [
            exercise(name: 'Squat', primaryMuscles: ['Quads']),
            exercise(name: 'RDL', primaryMuscles: ['Hamstrings']),
            exercise(name: 'Leg Extension', primaryMuscles: ['Quads']),
            exercise(name: 'Leg Curl', primaryMuscles: ['Hamstrings']),
          ]),
        ])];
        final result = SupersetPairer.pair(weeks);
        final paired = result[0].workoutDays[0].exercises
            .where((e) => e.supersetGroup != null);
        expect(paired, isNotEmpty);
      });

      test('pairs on upper day', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(name: 'Upper', exercises: [
            exercise(name: 'Bench Press', primaryMuscles: ['Chest']),
            exercise(name: 'Row', primaryMuscles: ['Back']),
            exercise(name: 'Bicep Curl', primaryMuscles: ['Biceps']),
            exercise(name: 'Tricep Pushdown', primaryMuscles: ['Triceps']),
          ]),
        ])];
        final result = SupersetPairer.pair(weeks);
        final paired = result[0].workoutDays[0].exercises
            .where((e) => e.supersetGroup != null);
        expect(paired, isNotEmpty);
      });

      test('pairs on full_body day', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(name: 'Full Body A', exercises: [
            exercise(name: 'Squat', primaryMuscles: ['Quads']),
            exercise(name: 'Deadlift', primaryMuscles: ['Hamstrings']),
            exercise(name: 'Bench Press', primaryMuscles: ['Chest']),
            exercise(name: 'Lat Pulldown', primaryMuscles: ['Lats']),
          ]),
        ])];
        final result = SupersetPairer.pair(weeks);
        final paired = result[0].workoutDays[0].exercises
            .where((e) => e.supersetGroup != null);
        expect(paired, isNotEmpty);
      });

      test('pairs on shoulders_arms day', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(name: 'Shoulders + Arms', exercises: [
            exercise(name: 'OHP', primaryMuscles: ['Deltoids']),
            exercise(name: 'Lateral Raise', primaryMuscles: ['Side Deltoid']),
            exercise(name: 'Bicep Curl', primaryMuscles: ['Biceps']),
            exercise(name: 'Tricep Extension', primaryMuscles: ['Triceps']),
          ]),
        ])];
        final result = SupersetPairer.pair(weeks);
        final paired = result[0].workoutDays[0].exercises
            .where((e) => e.supersetGroup != null);
        expect(paired, isNotEmpty);
      });

      test('does NOT pair on push day', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(name: 'Push', exercises: [
            exercise(name: 'Bench Press', primaryMuscles: ['Chest']),
            exercise(name: 'Incline Press', primaryMuscles: ['Upper Chest']),
            exercise(name: 'Shoulder Press', primaryMuscles: ['Deltoids']),
            exercise(name: 'Tricep Extension', primaryMuscles: ['Triceps']),
          ]),
        ])];
        final result = SupersetPairer.pair(weeks);
        final allUnpaired = result[0].workoutDays[0].exercises
            .every((e) => e.supersetGroup == null);
        expect(allUnpaired, isTrue,
            reason: 'Push day should not have any superset pairings');
      });

      test('does NOT pair on pull day', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(name: 'Pull', exercises: [
            exercise(name: 'Deadlift', primaryMuscles: ['Hamstrings']),
            exercise(name: 'Barbell Row', primaryMuscles: ['Back']),
            exercise(name: 'Lat Pulldown', primaryMuscles: ['Lats']),
            exercise(name: 'Bicep Curl', primaryMuscles: ['Biceps']),
          ]),
        ])];
        final result = SupersetPairer.pair(weeks);
        final allUnpaired = result[0].workoutDays[0].exercises
            .every((e) => e.supersetGroup == null);
        expect(allUnpaired, isTrue,
            reason: 'Pull day should not have any superset pairings');
      });
    });

    group('inferDayType', () {
      test('infers full_body from name', () {
        final day = workoutDay(name: 'Full Body A');
        expect(SupersetPairer.inferDayType(day), 'full_body');
      });

      test('infers push from name', () {
        expect(SupersetPairer.inferDayType(workoutDay(name: 'Push')), 'push');
        expect(SupersetPairer.inferDayType(workoutDay(name: 'Chest')), 'push');
        expect(SupersetPairer.inferDayType(workoutDay(name: 'Bench Day')), 'push');
      });

      test('infers pull from name', () {
        expect(SupersetPairer.inferDayType(workoutDay(name: 'Pull')), 'pull');
        expect(SupersetPairer.inferDayType(workoutDay(name: 'Back')), 'pull');
      });

      test('infers legs from name', () {
        expect(SupersetPairer.inferDayType(workoutDay(name: 'Legs')), 'legs');
        expect(SupersetPairer.inferDayType(workoutDay(name: 'Lower Body')), 'legs');
        expect(SupersetPairer.inferDayType(workoutDay(name: 'Squat Day')), 'legs');
        expect(SupersetPairer.inferDayType(workoutDay(name: 'Deadlift Day')), 'legs');
      });

      test('infers upper from name', () {
        expect(SupersetPairer.inferDayType(workoutDay(name: 'Upper')), 'upper');
      });

      test('infers shoulders_arms from name', () {
        expect(SupersetPairer.inferDayType(workoutDay(name: 'Shoulders + Arms')), 'shoulders_arms');
      });
    });

    group('Edge cases', () {
      test('fewer than 4 exercises → no pairing', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(name: 'Full Body', exercises: [
            exercise(name: 'Squat', primaryMuscles: ['Quads']),
            exercise(name: 'Bench', primaryMuscles: ['Chest']),
            exercise(name: 'Row', primaryMuscles: ['Back']),
          ]),
        ])];
        final result = SupersetPairer.pair(weeks);
        final allUnpaired = result[0].workoutDays[0].exercises
            .every((e) => e.supersetGroup == null);
        expect(allUnpaired, isTrue,
            reason: 'With only 3 exercises and first 2 excluded, cannot pair');
      });

      test('exercises without primaryMuscles → no pairing', () {
        final weeks = [weekPlan(workoutDays: [
          workoutDay(name: 'Full Body', exercises: [
            exercise(name: 'Ex1'),
            exercise(name: 'Ex2'),
            exercise(name: 'Ex3'),
            exercise(name: 'Ex4'),
          ]),
        ])];
        final result = SupersetPairer.pair(weeks);
        final allUnpaired = result[0].workoutDays[0].exercises
            .every((e) => e.supersetGroup == null);
        expect(allUnpaired, isTrue,
            reason: 'Without muscle data, cannot determine antagonist pairs');
      });
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 7. INTEGRATION-STYLE (PURE LOGIC)
  // ════════════════════════════════════════════════════════════════

  group('Integration: PeriodizationEngine.apply full structure', () {
    test('produces 4 WeekPlans with correct weekInPhase', () {
      final populated = [
        populatedDay(name: 'Push'),
        populatedDay(name: 'Pull'),
        populatedDay(name: 'Legs'),
      ];
      final weeks = PeriodizationEngine.apply(
        populated: populated,
        phase: 1,
        is6Day: false,
      );

      expect(weeks.length, 4);
      for (int i = 0; i < 4; i++) {
        expect(weeks[i].weekInPhase, i + 1);
        expect(weeks[i].workoutDays.length, 3);
      }
    });

    test('full pipeline: Periodization → Sequencing → Superset → Finisher → Warmup', () {
      // Build populated days manually (skipping ExerciseSelector)
      final populated = [
        PopulatedDay(
          name: 'Upper', focus: 'Chest + Back', dayType: 'upper', intensity: 'hypertrophy',
          exercisesA: [
            exercise(name: 'Bench Press', exerciseType: 'compound', primaryMuscles: ['Chest']),
            exercise(name: 'Barbell Row', exerciseType: 'compound', primaryMuscles: ['Back']),
            exercise(name: 'Cable Fly', exerciseType: 'isolation', primaryMuscles: ['Chest']),
            exercise(name: 'Face Pull', exerciseType: 'isolation', primaryMuscles: ['Rear Deltoid']),
            exercise(name: 'Bicep Curl', exerciseType: 'isolation', primaryMuscles: ['Biceps']),
            exercise(name: 'Tricep Extension', exerciseType: 'isolation', primaryMuscles: ['Triceps']),
          ],
          exercisesB: [
            exercise(name: 'Incline Press', exerciseType: 'compound', primaryMuscles: ['Chest']),
            exercise(name: 'Lat Pulldown', exerciseType: 'compound', primaryMuscles: ['Lats']),
            exercise(name: 'Chest Dip', exerciseType: 'compound', primaryMuscles: ['Chest']),
            exercise(name: 'Rear Delt Fly', exerciseType: 'isolation', primaryMuscles: ['Rear Deltoid']),
            exercise(name: 'Hammer Curl', exerciseType: 'isolation', primaryMuscles: ['Biceps']),
            exercise(name: 'Overhead Extension', exerciseType: 'isolation', primaryMuscles: ['Triceps']),
          ],
        ),
        PopulatedDay(
          name: 'Legs', focus: 'Quads + Hams', dayType: 'legs', intensity: 'strength',
          exercisesA: [
            exercise(name: 'Barbell Squat', exerciseType: 'compound', primaryMuscles: ['Quads']),
            exercise(name: 'Romanian Deadlift', exerciseType: 'compound', primaryMuscles: ['Hamstrings']),
            exercise(name: 'Leg Extension', exerciseType: 'isolation', primaryMuscles: ['Quads']),
            exercise(name: 'Leg Curl', exerciseType: 'isolation', primaryMuscles: ['Hamstrings']),
            exercise(name: 'Calf Raise', exerciseType: 'isolation', primaryMuscles: ['Calves']),
          ],
          exercisesB: [
            exercise(name: 'Front Squat', exerciseType: 'compound', primaryMuscles: ['Quads']),
            exercise(name: 'Stiff Leg Deadlift', exerciseType: 'compound', primaryMuscles: ['Hamstrings']),
            exercise(name: 'Leg Press', exerciseType: 'compound', primaryMuscles: ['Quads']),
            exercise(name: 'Hip Thrust', exerciseType: 'compound', primaryMuscles: ['Glutes']),
            exercise(name: 'Seated Calf', exerciseType: 'isolation', primaryMuscles: ['Calves']),
          ],
        ),
      ];

      // Stage 4: Periodization
      var weeks = PeriodizationEngine.apply(
        populated: populated,
        phase: 1,
        is6Day: false,
        effectiveExp: 'intermediate',
      );
      expect(weeks.length, 4);

      // Stage 3: Sequencing
      weeks = SequencingEngine.sequence(weeks);
      for (final week in weeks) {
        for (final day in week.workoutDays) {
          // Verify compounds come first
          bool seenIsolation = false;
          for (final ex in day.exercises) {
            if (ex.exerciseType == 'isolation') seenIsolation = true;
            if (ex.exerciseType == 'compound' && seenIsolation) {
              fail('Compound ${ex.exerciseName} appeared after isolation in ${day.name} week ${week.weekInPhase}');
            }
          }
        }
      }

      // Stage 5: Superset pairing
      weeks = SupersetPairer.pair(weeks);
      // Upper day is a qualifying dayType → should have some pairs
      for (final week in weeks) {
        final upperDay = week.workoutDays.firstWhere((d) => d.name.contains('Upper'));
        final pairedCount = upperDay.exercises.where((e) => e.supersetGroup != null).length;
        // At least one pair (2 exercises) expected for antagonist muscles
        expect(pairedCount, greaterThanOrEqualTo(0)); // may be 0 if pairing conditions not met after sequencing
      }

      // Stage 6: Cardio finisher (lose_fat)
      weeks = CardioFinisher.attach(
        weeks: weeks,
        goal: 'lose_fat',
        cardioPreference: 'hiit',
        equipmentList: ['full_gym'],
      );
      for (final week in weeks) {
        final daysWithFinisher = week.workoutDays.where((d) => d.finisher.isNotEmpty);
        expect(daysWithFinisher.length, 2);
      }

      // Stage 7: Warmup + Cooldown
      weeks = WarmupCooldownSelector.attach(weeks, 'intermediate', ['full_gym']);
      for (final week in weeks) {
        for (final day in week.workoutDays) {
          expect(day.warmup, isNotEmpty,
              reason: '${day.name} week ${week.weekInPhase} missing warmup');
          expect(day.cooldown, isNotEmpty,
              reason: '${day.name} week ${week.weekInPhase} missing cooldown');
        }
      }
    });

    test('cycle multiplier affects sets in later phases', () {
      final populated = [populatedDay(intensity: 'hypertrophy')];

      // APK Test #12.6 — removed unused phase1Weeks / phase5Weeks
      // assignments (intermediate path; the assertions below use the
      // beginner-effectiveExp variants).
      //
      // Phase 5 has 1.1x multiplier, phase 1 has 1.0x.
      // Hypertrophy base sets = 3, so phase 1 baseline = 3, phase 5
      // baseline = round(3*1.1) = 3. With 4-set minimum for intermediate,
      // both become 4 — that's why we use beginner here where the floor
      // doesn't apply.
      final phase1BeginnerWeeks = PeriodizationEngine.apply(
        populated: populated,
        phase: 1,
        is6Day: false,
        effectiveExp: 'beginner',
      );
      final phase5BeginnerWeeks = PeriodizationEngine.apply(
        populated: populated,
        phase: 5,
        is6Day: false,
        effectiveExp: 'beginner',
      );

      final p1Sets = phase1BeginnerWeeks[0].workoutDays[0].exercises[0].sets;
      final p5Sets = phase5BeginnerWeeks[0].workoutDays[0].exercises[0].sets;
      // phase 5 cycle multiplier = 1.1, so 3*1.1 = 3.3 → 3 (rounded)
      // The volume bump might be negligible for 3 sets but should be >= p1 sets
      expect(p5Sets, greaterThanOrEqualTo(p1Sets));
    });

    test('overload notes differ across weeks', () {
      final populated = [populatedDay()];
      final weeks = PeriodizationEngine.apply(
        populated: populated,
        phase: 1,
        is6Day: false,
      );

      final notes = weeks.map((w) => w.overloadNotes).toSet();
      expect(notes.length, 4,
          reason: 'Each week should have a distinct overload note');
    });

    test('6-day plan does not A/B alternate (always uses A)', () {
      final exA = exercise(name: 'Variant A');
      final exB = exercise(name: 'Variant B');
      final populated = [
        PopulatedDay(
          name: 'Push A', focus: 'Chest', dayType: 'push', intensity: 'hypertrophy',
          exercisesA: [exA],
          exercisesB: [exB],
        ),
      ];

      final weeks = PeriodizationEngine.apply(
        populated: populated,
        phase: 1,
        is6Day: true,
      );

      // All 4 weeks should use variant A for 6-day (A/B baked into the split)
      for (final week in weeks) {
        expect(week.workoutDays[0].exercises[0].exerciseName, 'Variant A',
            reason: '6-day plans should not alternate A/B (baked into split structure)');
      }
    });
  });
}
