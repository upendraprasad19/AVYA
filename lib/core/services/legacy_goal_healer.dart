import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/constants/fitness_goals.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';

/// Unit 3B (OI-487, founder d4 / d71 / d72): moves a stored legacy goal to the goal that replaced it.
///
/// `strength` becomes `build_muscle` and, when the stored physique focus is null, empty or `balanced`, the focus
/// becomes `strength` (d71: a focus the user chose is kept). `recompose` becomes `lose_fat` (focus untouched).
/// Anything else returns null. The targets map is [FitnessGoals.legacyTargets].
Map<String, dynamic>? legacyGoalPatch(Map<dynamic, dynamic> profile) {
  final goal = profile['primary_goal'];
  if (goal is! String) return null;
  final target = FitnessGoals.legacyTargets[goal];
  if (target == null) return null;
  final patch = <String, dynamic>{'primary_goal': target};
  if (goal == 'strength') {
    final focus = profile['physique_focus'];
    final unset = focus == null || (focus is String && (focus.trim().isEmpty || focus.trim() == 'balanced'));
    if (unset) patch['physique_focus'] = 'strength';
  }
  return patch;
}

/// [legacyGoalPatch] plus the derived targets recomputed for the healed profile (d71 / d72 accept the calorie
/// change), so one write carries the new goal and its targets and no push ever sends the new goal beside the old
/// targets. [recomputeTargets] false (the `disable_profile_target_recompute` switch) leaves the targets out; an
/// incomplete profile (`recomputeDerivedTargets` returns null) heals the goal alone. The overlay holds `carb_grams`, a
/// Hive-only key: the profile push sends its own key list, so it never reaches the cloud.
Map<String, dynamic>? legacyGoalHealPatch(
  Map<dynamic, dynamic> profile, {
  required DateTime now,
  required bool recomputeTargets,
  required bool bodyFatCalcDisabled,
}) {
  final patch = legacyGoalPatch(profile);
  if (patch == null) return null;
  if (!recomputeTargets) return patch;
  final healed = <String, dynamic>{
    for (final e in profile.entries) e.key.toString(): e.value,
    ...patch,
  };
  final overlay = recomputeDerivedTargets(healed, now: now, bodyFatCalcDisabled: bodyFatCalcDisabled);
  return overlay == null ? patch : <String, dynamic>{...overlay, ...patch};
}

/// The stored-value heal of [legacyGoalPatch] (plan `docs/plans/2026-11-16-generator-step3b-goal-list.md` §2.2).
///
/// Called by `SyncService.restoreFromCloudForUser` after every SUCCEEDED restore, with the uid the wrapper captured
/// before awaiting and its live-uid resolver (the one `shouldSettleRestoreMarker` is given, which honours the test
/// resolver). It decides and writes under `ProfileWriteService`'s lock in one step
/// (`ProfileWriteService.patchProfileWith`), re-checking the owner there before the box is read. It awaits no
/// network: the write fires the normal profile push, which is what carries the heal to the cloud; a failed push leaves
/// the cloud on the legacy value, the next restore merges it back and this heal moves it again.
class LegacyGoalHealer {
  LegacyGoalHealer._();

  /// Kill switch (device-level `configBox` flag; default off, heal active).
  static const String killSwitch = 'disable_legacy_goal_heal';

  /// The restore recompute's kill switch (`SyncService.kDisableProfileTargetRecomputeKey`, which is
  /// `@visibleForTesting`; equality pinned by `legacy_goal_heal_behavioral_test.dart`): when set, the heal moves the
  /// goal without the targets, as the restore merge does.
  static const String recomputeKillSwitch = 'disable_profile_target_recompute';

  /// Telemetry event for a heal that wrote.
  static const String healedEvent = 'legacy_goal_healed';

  /// Heals the open profile of [uid]. Returns true when it wrote. Never throws.
  static Future<bool> run(String? uid, {required String? Function() liveUid, DateTime Function()? now}) async {
    try {
      final config = HiveService.instance.configBox;
      if (config.get(killSwitch) == true) return false;
      if (uid == null || uid.isEmpty) return false;
      bool owned() => liveUid() == uid && HiveUserSession.currentOwnerFullId == uid;
      if (!owned()) return false;
      final recompute = config.get(recomputeKillSwitch) != true;
      final bodyFatOff = config.get('disable_bodyfat_calc') == true;
      String? from;
      Map<String, dynamic>? applied;
      final wrote = await ProfileWriteService.instance.patchProfileWith(
        (current) {
          final p = legacyGoalHealPatch(current,
              now: (now ?? DateTime.now)(), recomputeTargets: recompute, bodyFatCalcDisabled: bodyFatOff);
          if (p != null) {
            from = current['primary_goal']?.toString();
            applied = p;
          }
          return p;
        },
        stillOwner: owned,
      );
      if (wrote) {
        final to = applied?['primary_goal'];
        final focus = applied?.containsKey('physique_focus') == true ? 'focus_set' : 'focus_kept';
        unawaited(ErrorTelemetry.logEvent(healedEvent, message: '$from->$to $focus'));
      }
      return wrote;
    } catch (e, st) {
      debugPrint('[LegacyGoalHealer] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: 'legacy_goal_heal'));
      return false;
    }
  }
}
