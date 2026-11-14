import 'package:flutter/widgets.dart';

import '../../providers/train_provider.dart';
import '../../services/log_exercise_logic.dart';

/// Looks up the [FocusNode] of one input box. The card passes its own nodes;
/// the logging viewer passes its own, because one node cannot sit under two
/// fields.
typedef EntryFocusNodeFor = FocusNode? Function(int setIdx, SetField field);

/// What the card lends to the logging viewer (Batch M2b Part B): the card's
/// table header + set rows and its stepper + LOG row, built over the card's OWN
/// controllers. The viewer is a second host of the same input surface, never a
/// second owner of it: the controllers, the mirror state and the LOG path stay
/// in `_ExerciseCardState`.
///
/// No change notifier: a viewer rebuilds from its own `ref.watch` of the
/// provider, and the builders take their set count from
/// `min(data count, controller count)` so the frame between a `+` and the
/// card's controller resize shows the right number of rows.
class ExerciseEntryHandle {
  const ExerciseEntryHandle({
    required this.buildRows,
    required this.buildLogRow,
  });

  /// The table header and one row per set.
  final Widget Function(
    BuildContext context,
    ActiveWorkoutData data,
    EntryFocusNodeFor nodeFor,
  ) buildRows;

  /// The sets stepper and the LOG button. [afterLogged] runs only when the LOG
  /// tap really logged (not for a blocked, ignored, no-op or re-open outcome).
  final Widget Function(
    BuildContext context,
    ActiveWorkoutData data,
    EntryFocusNodeFor nodeFor,
    VoidCallback afterLogged,
  ) buildLogRow;
}
