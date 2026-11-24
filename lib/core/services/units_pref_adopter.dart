import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/unit_prefs_rule.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';

/// What one [UnitsPrefAdopter.runIfNeeded] call did. Returned for tests and
/// telemetry; callers ignore it.
enum UnitsAdoptOutcome {
  /// The flag was already set: nothing ran.
  alreadyDone,

  /// The restore for this account has not settled, or no account is open:
  /// nothing written, no flag (the next settled restore's heal retries).
  notReady,

  /// The device key was never written (the default is metric): flag only.
  noDeviceKey,

  /// No profile yet (empty account, failed restore): nothing, no flag.
  noProfile,

  /// The profile already carries `units_system` (this device or another one
  /// set it): the profile wins; the device key is dropped, flag set.
  profileAlreadySet,

  /// The device value was copied into the profile; key dropped, flag set.
  copied,
}

/// OI-348 B9 (e9a6c1): one-time per DEVICE move of the legacy device-wide
/// `configBox['units_metric']` into the signed-in user's profile
/// (`units_system`, synced by the profile push).
///
/// Called from BOTH post-restore heal sequences (`_healAfterRestoreInBackground`
/// before `reckonAndNotifyAfterRestore`, and `_ensureOwnershipBeforeHome`),
/// never from `_ensureLocalUser` (it does not run at a launch with a persisted
/// session). It runs AFTER the restore merge, so a value another device
/// already pushed is in the profile and wins ("only if absent").
///
/// The flag lives in `migrationBox` (one per device), like
/// `UserConfigMigrator`'s purge flag: the source key is device-wide, so once
/// it is moved and deleted there is nothing left for a second account.
class UnitsPrefAdopter {
  UnitsPrefAdopter._();

  static const String flagKey = 'units_metric_to_profile_v1_done';
  static const String legacyDeviceKey = 'units_metric';

  /// Test seam for the restore-settled gate (the real getter needs a live
  /// auth user). Null in production.
  @visibleForTesting
  static bool Function()? debugRestoreSettledOverride;

  static bool _restoreSettled() =>
      debugRestoreSettledOverride?.call() ??
      SyncService.instance.restoreSettledForCurrentUser;

  /// May throw (a box or profile-write failure); each caller wraps it in a try
  /// with its own `recordNonFatal` reason, so a failure names the heal path
  /// that ran it. A throw sets no flag, so the next settled restore retries.
  static Future<UnitsAdoptOutcome> runIfNeeded() async {
    final hive = HiveService.instance;
    final migBox = hive.migrationBox;
    if (migBox.get(flagKey) == true) return UnitsAdoptOutcome.alreadyDone;

    // Deliberately over-strict: a failed or unsettled restore leaves the
    // profile without the cloud's value, and copying the device value then
    // would push it over another device's.
    final owner = HiveUserSession.currentOwnerFullId;
    if (owner == null || !_restoreSettled()) return UnitsAdoptOutcome.notReady;

    final config = hive.configBox;
    if (!config.containsKey(legacyDeviceKey)) {
      await migBox.put(flagKey, true);
      return UnitsAdoptOutcome.noDeviceKey;
    }
    // Same reading as `getUnitsMetric`'s fallback: only a stored `false` is
    // imperial.
    final metric = config.get(legacyDeviceKey) != false;

    var outcome = UnitsAdoptOutcome.noProfile;
    await ProfileWriteService.instance.patchProfileWith(
      (current) {
        if (current.isEmpty) {
          outcome = UnitsAdoptOutcome.noProfile;
          return null;
        }
        if (current[kUnitsSystemKey] != null) {
          outcome = UnitsAdoptOutcome.profileAlreadySet;
          return null;
        }
        outcome = UnitsAdoptOutcome.copied;
        return {kUnitsSystemKey: unitsSystemValue(metric: metric)};
      },
      stillOwner: () => HiveUserSession.currentOwnerFullId == owner,
    );

    // An owner change inside the lock leaves `outcome` at noProfile: no flag,
    // the next settled restore retries.
    if (outcome == UnitsAdoptOutcome.noProfile) return outcome;
    await config.delete(legacyDeviceKey);
    await migBox.put(flagKey, true);
    unawaited(ErrorTelemetry.logEvent('units_pref_adopted',
        message: 'outcome=${outcome.name}'));
    return outcome;
  }
}
