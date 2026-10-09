// lib/core/services/sync/sync_skip_index.dart
//
// One skip mechanism for every history push in the sync layer
// (docs/superpowers/specs/2026-09-26-day-swapper-design.md §5.9, plan D4/D13).
//
// A row is pushed only when its fingerprint differs from the fingerprint of
// the last push that was CONFIRMED. The helper owns the try/catch around the
// push, so a domain loop cannot record a row as sent after a swallowed
// failure — the gap docs/architecture/sync.md documents for the old
// count-based gate. Gate G1 (scripts/check_sync_hash_skip_atomicity.dart)
// requires every history write in the sync layer to sit inside
// pushIfChanged, and requires every `*_payload_hash_index` literal to live
// in THIS file.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:uuid/uuid.dart';

/// Where a domain's index lives: always the user-scoped box that holds the
/// domain's rows (HiveUserSession.userScopedBoxRoots), so the per-user box
/// file is the namespace and sign-out / account swap / DPDP clear it.
enum SyncSkipBox { workout, nutrition, health, custom }

/// Every history domain with a skip index. `sched`, `exlog` and `nlog` keep
/// the index keys and kill-switch names they shipped with (H1b / OI-204), so
/// their stored fingerprints stay valid after the update.
enum SyncSkipDomain {
  sched('sync_sched_payload_hash_index', 'disable_sched_hash_skip',
      'upsert_scheduled_workout', SyncSkipBox.workout),
  exlog('sync_exlog_payload_hash_index', 'disable_exlog_hash_skip',
      'upsert_exercise_log', SyncSkipBox.workout),
  nlog('sync_nlog_payload_hash_index', 'disable_nlog_hash_skip',
      'upsert_nutrition_log', SyncSkipBox.nutrition),
  wlog('sync_wlog_payload_hash_index', 'disable_wlog_hash_skip',
      'upsert_workout_log', SyncSkipBox.workout),
  completion('sync_completion_payload_hash_index',
      'disable_completion_hash_skip', 'upsert_schedule_completion',
      SyncSkipBox.workout),
  template('sync_template_payload_hash_index', 'disable_template_hash_skip',
      'upsert_workout_template', SyncSkipBox.workout),
  plan('sync_plan_payload_hash_index', 'disable_plan_hash_skip',
      'sync_workout_plan', SyncSkipBox.workout),
  streak('sync_streak_payload_hash_index', 'disable_streak_hash_skip',
      'upsert_streak', SyncSkipBox.health),
  water('sync_water_payload_hash_index', 'disable_water_hash_skip',
      'upsert_water_log', SyncSkipBox.health),
  steps('sync_steps_payload_hash_index', 'disable_steps_hash_skip',
      'upsert_daily_steps', SyncSkipBox.health),
  urine('sync_urine_payload_hash_index', 'disable_urine_hash_skip',
      'upsert_urine_color_log', SyncSkipBox.health),
  sleep('sync_sleep_payload_hash_index', 'disable_sleep_hash_skip',
      'upsert_sleep_log', SyncSkipBox.health),
  weight('sync_weight_payload_hash_index', 'disable_weight_hash_skip',
      'upsert_weight_log', SyncSkipBox.health),
  measurement('sync_measurement_payload_hash_index',
      'disable_measurement_hash_skip', 'upsert_body_measurement',
      SyncSkipBox.health),
  readiness('sync_readiness_payload_hash_index', 'disable_readiness_hash_skip',
      'upsert_readiness_daily', SyncSkipBox.health),
  savedMeal('sync_saved_meal_payload_hash_index', 'disable_saved_meal_hash_skip',
      'upsert_saved_meal', SyncSkipBox.nutrition),
  customItem('sync_custom_item_payload_hash_index',
      'disable_custom_item_hash_skip', 'sync_custom_items', SyncSkipBox.custom);

  const SyncSkipDomain(this.indexKey, this.killSwitchKey, this.opType, this.box);

  /// Hive key of the `{rowKey: fingerprint}` map, in [box].
  final String indexKey;

  /// configBox flag; `true` restores the unconditional sweep for this domain.
  final String killSwitchKey;

  /// Telemetry op type for a failed push (the domain's existing primary one).
  final String opType;
  final SyncSkipBox box;
}

/// The plan domain has one row. Its stored fingerprint IS
/// `plan_bundle_cloud_fingerprint` (spec §5.7 L2).
const String kPlanBundleRowKey = 'bundle';

/// UUID v5 over canonical JSON — the same primitive and namespace as
/// `SyncService._deterministicId`.
class SyncFingerprint {
  SyncFingerprint._();

  static const Uuid _uuid = Uuid();
  static const String _namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

  static String ofCanonical(String canonical) => _uuid.v5(_namespace, canonical);

  /// Fingerprint of [value] with map keys sorted at every depth. A jsonb
  /// round-trip reorders keys; this makes the fingerprint survive it.
  static String of(Object? value) => ofCanonical(canonicalJson(value));

  static String canonicalJson(Object? value) => jsonEncode(_canon(value));

  static Object? _canon(Object? v) {
    if (v is Map) {
      final entries = v.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return <String, Object?>{
        for (final e in entries) e.key.toString(): _canon(e.value),
      };
    }
    if (v is Iterable) return v.map(_canon).toList();
    if (v is DateTime) return v.toUtc().toIso8601String();
    return v;
  }
}

typedef SyncSkipFailureReporter = void Function(
    String opType, Object error, StackTrace stack);

class SyncSkipIndex {
  SyncSkipIndex({
    required Box<dynamic> box,
    required this.domain,
    required this.disabled,
    required bool Function() ownerChangedNow,
    required SyncSkipFailureReporter reportFailure,
    this.forcePushKeys = const <String>{},
  })  : _box = box,
        _ownerChangedNow = ownerChangedNow,
        _reportFailure = reportFailure,
        _stored = readIndex(box, domain.indexKey);

  final SyncSkipDomain domain;

  /// The kill switch (or a domain-specific extra condition) is on.
  final bool disabled;

  /// Rows pushed even when their fingerprint matches the stored one, and
  /// recorded normally afterwards. For a self-heal that knows the cloud
  /// copy of THESE rows is gone although this phone confirmed it once (the
  /// scheduled_workouts FK recovery re-pushing one template). Deliberately
  /// NOT [disabled]: a disabled index deletes itself at [commit], which would
  /// re-push every row of the domain on the next pass. B-pass R1-F1.
  final Set<String> forcePushKeys;

  final Box<dynamic> _box;
  final bool Function() _ownerChangedNow;
  final SyncSkipFailureReporter _reportFailure;
  final Map<String, String> _stored;

  /// L1a-3 (D5a): THIS pass's own deltas against the stored index. [commit]
  /// applies only these to a fresh re-read of the box, so two overlapping
  /// passes never overwrite each other's confirmations with a stale snapshot.
  /// A key is in at most one of the two. Skipped keys are in neither.
  final Map<String, String> _confirmed = <String, String>{};
  final Set<String> _forgotten = <String>{};
  bool _aborted = false;

  /// D13 no-flood: the fingerprint catch runs per ROW, so only the FIRST
  /// fingerprint failure of this instance's pass is reported to
  /// ErrorTelemetry.
  int _fingerprintFailures = 0;

  int pushed = 0;
  int skipped = 0;
  int failed = 0;
  int unconfirmed = 0;

  /// Distinct opTypes already reported to [_reportFailure] THIS pass (mirror
  /// gap fix, F1 round 2). `failed == 1` alone is wrong for a shared index
  /// like `customItem`, which passes a different [opType] override per call:
  /// an exercise-upsert failure followed by a food-upsert failure in the
  /// SAME pass are two DISTINCT opTypes, and both must be reported once
  /// each -- but a domain with only one opType (the common case) must keep
  /// reporting exactly once per pass, exactly as before. Reset happens
  /// naturally: this field lives on the instance, and a new SyncSkipIndex is
  /// constructed per pass (same lifetime as [failed] itself).
  final Set<String> _reportedOpTypes = <String>{};

  /// True once the live account differs from the pass's owner. The domain
  /// loop should stop; nothing more is pushed or recorded.
  bool get aborted => _aborted;

  /// Pushes [rowKey] unless its fingerprint equals the last confirmed one.
  /// Returns true when the row is confirmed in the cloud after this call.
  ///
  /// [opType] overrides [SyncSkipDomain.opType] for THIS call's failure
  /// report only (Task 17 fix round 1, F1) -- a domain that shares one
  /// index across several underlying tables (e.g. `customItem` for both
  /// `user_custom_exercises` and `user_custom_foods`) would otherwise report
  /// every push failure under the same generic string, indistinguishable
  /// from each other AND from the domain's own whole-function catch-all.
  /// Every other domain omits it and keeps reporting under `domain.opType`
  /// exactly as before.
  Future<bool> pushIfChanged(
    String rowKey,
    String Function() fingerprint,
    Future<bool> Function() push, {
    String? opType,
  }) async {
    if (_aborted) return false;
    if (_ownerChangedNow()) {
      _aborted = true;
      return false;
    }
    String? fp;
    if (!disabled) {
      try {
        fp = fingerprint();
      } catch (e, st) {
        fp = null; // fail open: push, never record
        debugPrint('[SyncSkipIndex] ${domain.name} fingerprint $rowKey: $e');
        _fingerprintFailures++;
        if (_fingerprintFailures == 1) {
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'sync_skip_fingerprint_${domain.name}'));
        }
      }
      if (fp != null &&
          !forcePushKeys.contains(rowKey) &&
          _stored[rowKey] == fp) {
        skipped++;
        return true;
      }
    }
    final bool confirmed;
    try {
      confirmed = await push();
    } catch (e, st) {
      failed++;
      _forget(rowKey);
      // Report once per DISTINCT opType per pass, not just the first
      // failure overall (mirror gap fix, F1 round 2) -- a shared index
      // (customItem) can see two different opType overrides fail in one
      // pass, and both must surface; a single-opType domain still reports
      // exactly once, since `add` returns false on the second occurrence.
      final op = opType ?? domain.opType;
      if (_reportedOpTypes.add(op)) _reportFailure(op, e, st);
      return false;
    }
    if (_ownerChangedNow()) {
      _aborted = true;
      return false;
    }
    if (!confirmed) {
      unconfirmed++;
      _forget(rowKey);
      return false;
    }
    pushed++;
    if (fp != null) {
      _stored[rowKey] = fp;
      _confirmed[rowKey] = fp;
      _forgotten.remove(rowKey);
    }
    return true;
  }

  void _forget(String rowKey) {
    _stored.remove(rowKey);
    _confirmed.remove(rowKey);
    _forgotten.add(rowKey);
  }

  /// Persists the index once per pass: prunes rows not in [liveKeys] and
  /// writes Hive only when something changed. Writes nothing after an
  /// ownership change. A disabled index is deleted.
  Future<void> commit({required Set<String> liveKeys}) async {
    if (_aborted || _ownerChangedNow()) return;
    try {
      if (disabled) {
        if (_box.containsKey(domain.indexKey)) await _box.delete(domain.indexKey);
        return;
      }
      // Merge this pass's deltas into the CURRENT stored map (re-read, with
      // no await between the read and the put), never the construction-time
      // snapshot: an overlapping pass may have confirmed other rows since.
      final fresh = readIndex(_box, domain.indexKey);
      final merged = Map<String, String>.from(fresh)
        ..addAll(_confirmed)
        ..removeWhere((k, _) => _forgotten.contains(k) || !liveKeys.contains(k));
      if (merged.length == fresh.length &&
          merged.entries.every((e) => fresh[e.key] == e.value)) {
        return;
      }
      await _box.put(domain.indexKey, merged);
    } catch (e, st) {
      // Losing the index costs one extra push next pass — never a false skip.
      debugPrint('[SyncSkipIndex] ${domain.name} commit: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_skip_commit_${domain.name}'));
    } finally {
      if (kDebugMode) {
        debugPrint('[sync-skip] ${domain.name}: pushed $pushed, skipped '
            '$skipped, failed $failed, unconfirmed $unconfirmed');
      }
    }
  }

  /// The stored `{rowKey: fingerprint}` map; empty on any unexpected shape.
  static Map<String, String> readIndex(Box<dynamic> box, String indexKey) {
    try {
      final raw = box.get(indexKey);
      if (raw is Map) {
        return <String, String>{
          for (final e in raw.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
        };
      }
    } catch (e, st) {
      debugPrint('[SyncSkipIndex] readIndex $indexKey: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_skip_read_index', extra: {'index_key': indexKey}));
    }
    return <String, String>{};
  }

  /// Records [fingerprint] for [rowKey] when the device learned the cloud's
  /// content by DOWNLOADING it (the plan merge, spec §5.7 L2).
  static Future<void> recordConfirmed(Box<dynamic> box, SyncSkipDomain domain,
      String rowKey, String fingerprint) async {
    final m = readIndex(box, domain.indexKey);
    if (m[rowKey] == fingerprint) return;
    m[rowKey] = fingerprint;
    await box.put(domain.indexKey, m);
  }

  /// Records several download-confirmed fingerprints in ONE read-merge-put
  /// (L1a-3 / M2: the exercise-log restore, so a log it just wrote is not
  /// pushed straight back). Nothing is written once the owner changed, and
  /// nothing when every entry is already recorded.
  static Future<void> recordConfirmedAll(
    Box<dynamic> box,
    SyncSkipDomain domain,
    Map<String, String> fingerprints, {
    required bool Function() ownerChangedNow,
  }) async {
    if (fingerprints.isEmpty || ownerChangedNow()) return;
    final m = readIndex(box, domain.indexKey);
    var changed = false;
    fingerprints.forEach((k, v) {
      if (m[k] != v) {
        m[k] = v;
        changed = true;
      }
    });
    if (!changed) return;
    await box.put(domain.indexKey, m);
  }

  /// Test-only seam: when non-null, forces the named domain's clear to throw
  /// during [clearAll] without needing a real Hive box failure. Mirrors the
  /// established `debugCurrentUidResolverForTests` seam (hive_user_session.dart).
  /// Production leaves this null; reset it in tearDown.
  @visibleForTesting
  static bool Function(SyncSkipDomain)? debugForceClearFailureForTests;

  /// Deletes every domain's index (the `sync_epoch` repair lever, spec
  /// §5.10 rule 3). A per-domain failure is caught here and reported (never
  /// rethrown, so one bad domain cannot abort the rest of the sweep) but is
  /// still counted in [ClearAllResult.failed] so a caller — the sync_epoch
  /// lever, specifically — can tell "every domain cleared" apart from
  /// "something was left dirty" and avoid marking the repair as done when it
  /// was not (diagnose a9d3f6).
  static Future<ClearAllResult> clearAll(
      Box<dynamic> Function(SyncSkipBox) boxFor) async {
    var cleared = 0;
    var failed = 0;
    for (final d in SyncSkipDomain.values) {
      try {
        if (debugForceClearFailureForTests?.call(d) ?? false) {
          throw StateError('debugForceClearFailureForTests: ${d.name}');
        }
        final b = boxFor(d.box);
        if (b.containsKey(d.indexKey)) {
          await b.delete(d.indexKey);
          cleared++;
        }
      } catch (e, st) {
        failed++;
        debugPrint('[SyncSkipIndex] clearAll ${d.name}: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_skip_clear_all', extra: {'domain': d.name}));
      }
    }
    return ClearAllResult(cleared: cleared, failed: failed);
  }
}

/// Outcome of [SyncSkipIndex.clearAll]: how many domain indexes were
/// actually deleted, and how many domains threw while being cleared. A
/// caller that needs a strict "did the whole sweep succeed" answer reads
/// [failed] — [cleared] alone cannot distinguish "nothing to clear" from
/// "clearing failed", since both leave a domain uncounted in [cleared].
class ClearAllResult {
  const ClearAllResult({required this.cleared, required this.failed});

  final int cleared;
  final int failed;

  bool get allSucceeded => failed == 0;
}
