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
import 'package:icanbefitter/core/services/target_history_service.dart';
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';
import 'package:icanbefitter/features/profile/services/target_impact.dart'
    show derivationInputsChangedForDialog;

/// A local profile that holds real answers (a goal or a height), the same test the bootstrapper's
/// `hiveHasRealData` makes: a map of stray keys (`id`, `email`, a view setting) is a fresh device.
bool _holdsRealProfile(Map<String, dynamic>? existing) =>
    existing != null &&
    (existing['primary_goal'] != null || existing['height_cm'] != null);

/// Cloud non-null fields win over [existing]; local values survive for fields the cloud left null.
/// Then, ONLY when [existing] holds real answers (a fresh device has nothing of its own to
/// disagree with, and with `{}` every cloud input would count as changed and the helper would
/// override the cloud calories: the "silent backfill" the restore guard exists to prevent) and the
/// merge changed a derivation input (judged like Edit Profile's dialog, so an ISO-timestamp date of
/// birth against `YYYY-MM-DD` of the same day is no change), the derived targets are recomputed.
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
  final merged = TargetHistoryService.stripFromProfile(<String, dynamic>{
    ...?existing,
    for (final e in cloud.entries)
      if (e.value != null) e.key: e.value,
  });
  if (recomputeDisabled || !_holdsRealProfile(existing)) return merged;
  try {
    if (!derivationInputsChangedForDialog(existing!, merged)) return merged;
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
