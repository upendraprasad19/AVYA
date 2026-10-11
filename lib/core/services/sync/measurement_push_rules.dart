// lib/core/services/sync/measurement_push_rules.dart
//
// Pure rules for the `body_measurements` push and pull (plan
// docs/plans/coach-measurement-entry-l2a.md, unit U1; OI-297). No Hive, no
// network: `_syncMeasurements` / `_pullMeasurements` feed these the records.
//
// The defect: the push sent all four sites and `notes` from the day's Hive
// record, nulls included, so a device that held only some sites blanked the
// ones another device had entered (PostgREST assigns an explicit null and
// leaves an absent key alone). The new wire body carries only what the device
// holds; the FINGERPRINT stays the legacy-shape content so an upgrade or a
// kill-switch toggle re-pushes nothing.

import 'package:icanbefitter/core/constants/body_measurement_sites.dart';

/// A site value the push may send: a finite number (the same predicate as
/// `SyncService._hasNumber`, which is a private static and not reachable).
bool isPushableMeasurementSite(Object? v) => v is num && v.isFinite;

/// The payload every APK before this change sent: EVERY site, `notes` and
/// `created_at` (when known), nulls included. Key order equals that shape. It
/// is the fingerprint's source and, with the kill switch set, the wire body.
Map<String, dynamic> measurementLegacyPayload({
  required String userId,
  required String date,
  required Map<String, dynamic> log,
  required String? createdAt,
}) => <String, dynamic>{
  'user_id': userId,
  'date': date,
  for (final site in kBodyMeasurementSites) site: log[site],
  'notes': log['notes'],
  'created_at': ?createdAt,
};

/// [legacy] with every site that is not a finite number, and a `notes` that is
/// not a String, replaced by null. For every record the in-repo writers can
/// produce this equals [legacy], so its fingerprint equals the one stored by
/// builds that fingerprinted the legacy payload.
Map<String, dynamic> measurementFingerprintContent(
  Map<String, dynamic> legacy,
) => <String, dynamic>{
  for (final e in legacy.entries)
    e.key: kBodyMeasurementSites.contains(e.key)
        ? (isPushableMeasurementSite(e.value) ? e.value : null)
        : e.key == 'notes'
        ? (e.value is String ? e.value : null)
        : e.value,
};

/// The merge-safe wire body: `user_id`, `date`, only the sites that are finite
/// numbers, `notes` only when a String (an empty String is a value), and
/// `created_at` when present. Null when the record holds no site and no
/// `notes` String: a body of only `user_id`/`date` would create an empty row.
Map<String, dynamic>? measurementMergeSafeBody(Map<String, dynamic> legacy) {
  final body = <String, dynamic>{
    'user_id': legacy['user_id'],
    'date': legacy['date'],
  };
  var hasContent = false;
  for (final site in kBodyMeasurementSites) {
    final v = legacy[site];
    if (isPushableMeasurementSite(v)) {
      body[site] = v;
      hasContent = true;
    }
  }
  final notes = legacy['notes'];
  if (notes is String) {
    body['notes'] = notes;
    hasContent = true;
  }
  if (!hasContent) return null;
  if (legacy.containsKey('created_at')) {
    body['created_at'] = legacy['created_at'];
  }
  return body;
}

/// The cross-channel pull's merge rule: fill a site from the cloud row only
/// where the local value is null.
Map<String, dynamic> mergeCloudSitesIntoLocal(
  Map<String, dynamic> existing,
  Map<String, dynamic> cloud,
) {
  final merged = Map<String, dynamic>.from(existing);
  for (final site in kBodyMeasurementSites) {
    if (merged[site] == null && cloud[site] != null) merged[site] = cloud[site];
  }
  return merged;
}
