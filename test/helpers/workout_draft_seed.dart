import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';

/// A [WorkoutDraftNotifier] that starts with [seed]. `build()` runs the real
/// one first (it watches auth and resets the private fields), and the seed is
/// returned only on the FIRST build, so an auth flip still clears the draft.
class SeededWorkoutDraftNotifier extends WorkoutDraftNotifier {
  final WorkoutDraft seed;
  bool _seeded = false;

  SeededWorkoutDraftNotifier(this.seed);

  @override
  WorkoutDraft? build() {
    super.build();
    if (_seeded) return null;
    _seeded = true;
    return seed;
  }
}
