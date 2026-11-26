import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ai_coach_provider.dart';
import 'workout_log_confirm_card.dart';

/// True while the chat list has a slot for the workout card. The draft stays
/// non-null through its saved hold, so the saved state is visible.
bool hasWorkoutDraftSlot(WorkoutDraft? d) => d != null;

/// The chat scrolls to the bottom only when a NEW card appears, not on every
/// change of the current one (an edit, a failure, the saved state).
bool workoutDraftChangeScrolls(WorkoutDraft? prev, WorkoutDraft? next) =>
    next != null && prev?.id != next.id;

/// The chat list's workout card slot: one card per draft, keyed by its id so
/// a held card that replaces it gets a fresh State.
class WorkoutDraftSlot extends ConsumerWidget {
  const WorkoutDraftSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(workoutDraftProvider);
    if (draft == null) return const SizedBox.shrink();
    return WorkoutLogConfirmCard(key: ValueKey(draft.id));
  }
}
