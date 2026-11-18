// lib/features/profile/services/profile_cloud_merge.dart
//
// goal-change-targets B2b: the first-sign-in merge of the cloud `user_profile` row over the local
// profile (the F2 branch of `AuthSessionBootstrapper.hydrateFromCloud`), with the derived targets
// recomputed when the merge changed an input of the derivation. Before this the merge took the
// cloud weight beside the phone's calorie target, and the later restore saw no input change
// (the bootstrapper had already written the merge), so the targets stayed stale until the next
// Save.
//
// Pure apart from the telemetry of a fail-open: the caller reads the two kill switches from
// `configBox` and passes them in.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';

/// Cloud non-null fields win over [existing]; local values survive for fields the cloud left null.
/// Then, ONLY when [existing] is a non-empty map (a fresh device has nothing of its own to
/// disagree with, and with `{}` every cloud input would count as changed and the helper would
/// override the cloud calories: the "silent backfill" the restore guard exists to prevent) and the
/// merge changed a derivation input, the derived targets are recomputed over the merged map.
///
/// The recompute is fail-open: a corrupt stored value (a non-numeric `height_cm` makes
/// `recomputeDerivedTargets` throw at its `as num?` cast) records a non-fatal and returns the plain
/// merge, so the caller still writes the profile.
Map<String, dynamic> mergeCloudProfileWithTargets({
  required Map<String, dynamic>? existing,
  required Map<String, dynamic> cloud,
  required DateTime now,
  required bool bodyFatCalcDisabled,
  required bool recomputeDisabled,
}) {
  final merged = <String, dynamic>{
    ...?existing,
    for (final e in cloud.entries)
      if (e.value != null) e.key: e.value,
  };
  if (recomputeDisabled || existing == null || existing.isEmpty) return merged;
  try {
    if (!derivedTargetInputsChanged(existing, merged)) return merged;
    final overlay = recomputeDerivedTargets(
      merged,
      now: now,
      bodyFatCalcDisabled: bodyFatCalcDisabled,
    );
    if (overlay != null) merged.addAll(overlay);
  } catch (e, st) {
    debugPrint('[mergeCloudProfileWithTargets] recompute failed: $e');
    unawaited(ErrorTelemetry.recordNonFatal(e, st,
        reason: 'bootstrapper_profile_merge_recompute'));
  }
  return merged;
}
