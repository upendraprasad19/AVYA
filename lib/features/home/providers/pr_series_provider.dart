import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/train/services/exercise_pr_series.dart';

import 'home_provider.dart';

/// The best value per workout day for every exercise that has a PR, keyed by
/// `exercisePrNameKey`. Feeds the sparklines on the Home PR tiles and the
/// see-all list, and the trend sheet.
///
/// DERIVED from the PR list: it takes [allExercisePRsProvider]'s value as its
/// input (each series is in its PR's unit), so it recomputes exactly when the
/// PR list does and needs no invalidation of its own. A signed-out session has
/// an empty PR list and therefore an empty map; no box is read.
final exercisePrSeriesProvider =
    Provider<Map<String, ExercisePrSeries>>((ref) {
  final prs = ref.watch(allExercisePRsProvider);
  if (prs.isEmpty) return const <String, ExercisePrSeries>{};
  return WorkoutRepository.instance.loadAllExercisePrSeries(prs);
});
