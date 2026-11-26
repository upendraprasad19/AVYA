import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/train/services/exercise_pr_series.dart';

import 'home_provider.dart';

/// The best value per workout day for every exercise that has a PR, keyed by
/// `exercisePrNameKey`. Feeds the sparklines on the Home PR tiles and the
/// see-all list, and the trend sheet.
///
/// DERIVED from the PR list: it takes [allExercisePRsProvider]'s value as its
/// input (each series is in its PR's unit), so it recomputes exactly when the
/// PR list does and needs no invalidation of its own. A signed-out session
/// (the `'<anon>'` token) reads no box.
final exercisePrSeriesProvider =
    Provider<Map<String, ExercisePrSeries>>((ref) {
  final token = ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
  if (token == '<anon>') return const <String, ExercisePrSeries>{};
  final prs = ref.watch(allExercisePRsProvider);
  if (prs.isEmpty) return const <String, ExercisePrSeries>{};
  return WorkoutRepository.instance.loadAllExercisePrSeries(prs);
});
