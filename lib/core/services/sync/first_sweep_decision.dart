// sync-storm-first-sweep W3 — pure decisions for postponing the first full sweep
// on a device that was EMPTY at its first launch. No Hive, no network, no clock
// read: every input is a parameter so the truth tables are testable in a pure VM.
// Plan docs/plans/2026-10-25-sync-storm-first-sweep.md section 5 (W3).
//
// Why: on a fresh device `last_full_sync` is null, so `checkAndSync` ran the
// daily sweep at once, at the same time as the migrator-triggered
// `syncWorkoutData()`, re-uploading what the restore had just downloaded. The
// sweep is POSTPONED, not dropped: it runs at the first launch at least 24 h
// after the marker time, as one single pass.
library;

/// How long after the first launch of an empty device its marker is honoured.
/// Short on purpose: the only hazard is the launch RIGHT after the restore,
/// where two pushers overlap; an hour later the sweep runs alone.
const Duration kFreshDeviceWindow = Duration(hours: 1);

/// `syncBox` key prefix of the per-user marker (`fresh_device_<userId>`). The
/// box is shared across accounts, hence the user id in the key.
const String kFreshDeviceMarkerPrefix = 'fresh_device_';

String freshDeviceMarkerKey(String userId) => '$kFreshDeviceMarkerPrefix$userId';

enum SweepAction {
  /// Not due: nothing to decide.
  none,

  /// Run the sweep exactly as before.
  run,

  /// Skip the sweep this launch and stamp `last_full_sync` with the marker time.
  postponeAndStamp,
}

/// [owed] is the durable "an outage-shaped push failure is waiting for a resend"
/// flag: a sweep that is owed always runs. [enabled] is the kill switch (not
/// engaged).
SweepAction decideSweep({
  required bool due,
  required bool owed,
  required bool freshWithinWindow,
  required bool enabled,
}) {
  if (!due) return SweepAction.none;
  if (!owed && freshWithinWindow && enabled) return SweepAction.postponeAndStamp;
  return SweepAction.run;
}

/// Whether this launch should write the marker: the device holds no workout
/// history, no sweep was ever stamped, and no marker exists yet (first-wins).
bool shouldMarkFreshDevice({
  required bool hasLocalHistory,
  required DateTime? lastFullSync,
  required bool markerExists,
  required bool enabled,
}) =>
    enabled && !hasLocalHistory && lastFullSync == null && !markerExists;

/// A marker is honoured only while it is younger than [kFreshDeviceWindow]. One
/// from the future (a changed device clock) is stale.
bool isFreshWithinWindow({required DateTime? marker, required DateTime now}) {
  if (marker == null) return false;
  if (marker.isAfter(now)) return false;
  return now.difference(marker) < kFreshDeviceWindow;
}
