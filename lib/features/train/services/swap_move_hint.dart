// First-use hint for the active-workout ⇄ swap / ⇅ move icons
// (docs/plans/active-workout-swap-move.md Task 3). Shown once per ACCOUNT,
// device-local: the flag lives in the user's box through MigratedKey and is
// listed in UserConfigMigrator.userScopedKeys, so a sign-out clears it.
// Widgets never touch Hive: they go through this file.
import 'package:icanbefitter/core/services/migrated_key.dart';

import '../providers/train_provider.dart';
import 'exercise_move_logic.dart';

const String kSwapMoveHintSeenKey = 'has_seen_swap_move_hint';

/// The hint was seen (or retired) on this account. The literal key, not the
/// constant, so `migrated_key_contracts_test.dart`'s literal scan covers it.
bool swapMoveHintSeen() =>
    MigratedKey.readWithDefault<bool>('has_seen_swap_move_hint', false);

/// Retire the hint for this account.
Future<void> markSwapMoveHintSeen() =>
    MigratedKey.write('has_seen_swap_move_hint', true);

/// Show the hint: not seen, not dismissed this session, the session has
/// somewhere to move to, nothing is checked yet (warm-ups count), and ⇅ is
/// not hidden (superset-grouping mode, review mode).
bool shouldShowSwapMoveHint({
  required bool seen,
  required bool dismissedThisSession,
  required ActiveWorkoutData data,
}) =>
    !seen &&
    !dismissedThisSession &&
    hasMoveCandidates(data) &&
    data.checkedSets.isEmpty &&
    !data.isSupersetGroupMode &&
    !data.isSaved;
