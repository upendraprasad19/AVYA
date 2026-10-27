// OI-389 Batch 1a T16b: StatsGrid's all-exercise fallback renders a
// duration-only cardio PR in its own unit ("30 min"), never "1800 km" (the
// old per-type unit table printed every cardio value as km).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/train/widgets/stats_grid.dart';

class _FixedPRs extends AllExercisePRsNotifier {
  @override
  List<ExercisePR> build() => [
        ExercisePR(
            exerciseName: 'Running (Treadmill)',
            loggingType: 'cardio',
            bestValue: 1800,
            date: DateTime(2026, 10, 20),
            unit: 'sec'),
        ExercisePR(
            exerciseName: 'Farmers Carry',
            loggingType: 'distance',
            bestValue: 0.04,
            date: DateTime(2026, 10, 19),
            unit: 'km'),
      ];
}

void main() {
  testWidgets('T16b: a cardio PR of 1800 s reads 30 min', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workoutStatsProvider.overrideWithValue(const {
          'bench': {'current': 0, 'previous': 0},
        }),
        allExercisePRsProvider.overrideWith(_FixedPRs.new),
      ],
      child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: StatsGrid()))),
    ));
    await tester.pump();
    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('40 m'), findsOneWidget);
    expect(find.textContaining('1800'), findsNothing);
  });
}
