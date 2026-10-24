// Superset groups written back to the stored `schedule_<date>` row by
// exercise IDENTITY, not by position (docs/plans/active-workout-swap-move.md
// Task 2). The session order can differ from the stored order after an
// in-workout move, so an index write would stamp a group onto the wrong row.
// Pure: no provider or Hive import, so `train_provider.dart` can use it.

/// One session exercise as the superset write sees it.
typedef SessionExerciseIdentity = ({
  String? exerciseId,
  String name,
  int? supersetGroup,
});

/// A copy of [stored] with each session exercise's `superset_group` written
/// onto its own row. Each session entry claims one not-yet-claimed Map row
/// with the same identity, in two passes: first id-to-id (both ids present
/// and equal), then by name for the rest (the row's `exercise_name ?? name`
/// equals the session name; two present ids that differ never match). So a
/// name-only entry cannot take the row a later entry owns by id. The group is
/// written even when null (ungrouping). A session group of two or more that
/// would land on ONE stored row only (its partner is session-only, e.g.
/// swapped in) is written as null instead: storing half a pair is worse than
/// not storing the pairing. A group that is already single in the session
/// is written as it is.
/// Unclaimed rows and non-Map entries pass through untouched; [stored]
/// itself is never mutated.
List<dynamic> applySupersetGroupsByIdentity({
  required List<dynamic> stored,
  required List<SessionExerciseIdentity> session,
}) {
  final out = List<dynamic>.from(stored);
  final claimed = List<bool>.filled(out.length, false);
  final rowOf = List<int?>.filled(session.length, null);

  String? idOf(Map<dynamic, dynamic> row) => row['exercise_id'] as String?;

  void claim(bool Function(Map<dynamic, dynamic> row, SessionExerciseIdentity s) m) {
    for (var j = 0; j < session.length; j++) {
      if (rowOf[j] != null) continue;
      for (var i = 0; i < out.length; i++) {
        final row = out[i];
        if (claimed[i] || row is! Map || !m(row, session[j])) continue;
        claimed[i] = true;
        rowOf[j] = i;
        break;
      }
    }
  }

  claim((row, s) =>
      s.exerciseId != null && idOf(row) != null && idOf(row) == s.exerciseId);
  claim((row, s) {
    final rowId = idOf(row);
    if (rowId != null && s.exerciseId != null) return false;
    return (row['exercise_name'] ?? row['name']) == s.name;
  });

  for (var j = 0; j < session.length; j++) {
    final i = rowOf[j];
    if (i == null) continue;
    out[i] = Map<String, dynamic>.from(out[i] as Map)
      ..['superset_group'] = session[j].supersetGroup;
  }

  // Members per group: stored across the whole result (untouched rows count
  // too) vs the session. Clear only a pair the write itself would split.
  final storedMembers = <Object?, int>{};
  for (final row in out) {
    if (row is Map && row['superset_group'] != null) {
      storedMembers.update(row['superset_group'], (n) => n + 1,
          ifAbsent: () => 1);
    }
  }
  final sessionMembers = <Object?, int>{};
  for (final s in session) {
    if (s.supersetGroup != null) {
      sessionMembers.update(s.supersetGroup, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  for (final i in rowOf) {
    if (i == null) continue;
    final row = out[i] as Map<String, dynamic>;
    final g = row['superset_group'];
    if (g != null &&
        storedMembers[g] == 1 &&
        (sessionMembers[g] ?? 0) >= 2) {
      row['superset_group'] = null;
    }
  }
  return out;
}
