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
  })  : _box = box,
        _ownerChangedNow = ownerChangedNow,
        _reportFailure = reportFailure,
        _stored = readIndex(box, domain.indexKey);

  final SyncSkipDomain domain;

  /// The kill switch (or a domain-specific extra condition) is on.
  final bool disabled;

  final Box<dynamic> _box;
  final bool Function() _ownerChangedNow;
  final SyncSkipFailureReporter _reportFailure;
  final Map<String, String> _stored;
  bool _dirty = false;
  bool _aborted = false;

  /// D13 no-flood: the fingerprint catch runs per ROW, so only the FIRST
  /// fingerprint failure of this instance's pass is reported to
  /// ErrorTelemetry.
  int _fingerprintFailures = 0;

  int pushed = 0;
  int skipped = 0;
  int failed = 0;
  int unconfirmed = 0;

  /// True once the live account differs from the pass's owner. The domain
  /// loop should stop; nothing more is pushed or recorded.
  bool get aborted => _aborted;

  /// Pushes [rowKey] unless its fingerprint equals the last confirmed one.
  /// Returns true when the row is confirmed in the cloud after this call.
  Future<bool> pushIfChanged(
    String rowKey,
    String Function() fingerprint,
    Future<bool> Function() push,
  ) async {
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
      if (fp != null && _stored[rowKey] == fp) {
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
      if (failed == 1) _reportFailure(domain.opType, e, st);
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
    if (fp != null && _stored[rowKey] != fp) {
      _stored[rowKey] = fp;
      _dirty = true;
    }
    return true;
  }

  void _forget(String rowKey) {
    if (_stored.remove(rowKey) != null) _dirty = true;
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
      final before = _stored.length;
      _stored.removeWhere((k, _) => !liveKeys.contains(k));
      if (_stored.length != before) _dirty = true;
      if (!_dirty) return;
      await _box.put(domain.indexKey, Map<String, String>.from(_stored));
      _dirty = false;
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

  /// Deletes every domain's index (the `sync_epoch` repair lever, spec
  /// §5.10 rule 3). Returns how many indexes existed.
  static Future<int> clearAll(Box<dynamic> Function(SyncSkipBox) boxFor) async {
    var cleared = 0;
    for (final d in SyncSkipDomain.values) {
      try {
        final b = boxFor(d.box);
        if (b.containsKey(d.indexKey)) {
          await b.delete(d.indexKey);
          cleared++;
        }
      } catch (e, st) {
        debugPrint('[SyncSkipIndex] clearAll ${d.name}: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_skip_clear_all', extra: {'domain': d.name}));
      }
    }
    return cleared;
  }
}
