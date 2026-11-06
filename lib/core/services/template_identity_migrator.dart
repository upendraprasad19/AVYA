import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'error_telemetry.dart';
import 'hive_service.dart';
import 'supabase_service.dart';
import 'template_identity.dart';

/// OI-252 (stable ID rework) — one-time-per-legacy-row migration from the
/// old ambiguous template identities (`tmpl_<ms>` from create,
/// `tmpl_<hash(lower(name))>` from restore) to the single `tmpl_<uuid>`
/// identity every other piece of this rework assumes.
///
/// Called from `_syncWorkoutTemplates` / `_restoreWorkoutTemplates`
/// themselves (never from `_restoreIfNeeded` as a whole — round-2 plan
/// review found that gating the whole restore entry point would starve
/// unrelated domains, like nutrition or weight, for an offline user; only
/// the template-specific functions wait on this).
///
/// Re-runs every launch (a cheap `workoutBox.keys` scan) rather than being
/// strictly one-shot — once no legacy key remains, every call is a no-op
/// that returns `true` immediately. This closes the gap a one-shot flag
/// would leave if a legacy-shaped key ever appeared again after the flag
/// was set (round-1 plan review, finding 7).
class TemplateIdentityMigrator {
  TemplateIdentityMigrator._();

  /// Telemetry-only — the migration does not gate correctness on this flag
  /// (see class doc); it is set purely so an audit can see a device has
  /// completed at least one full pass.
  static const _flagKey = 'tmpl_identity_v1_done';

  /// Test-only invocation counter, incremented as the FIRST statement of
  /// [runIfNeeded] — before the Hive scan or any network call. No Supabase
  /// mocking seam exists anywhere in this repo (`SupabaseService.client`
  /// hardcodes `Supabase.instance.client`, uninitialized in unit tests), so
  /// this is how a caller-wiring test proves the gate was REACHED without
  /// needing to exercise its live-network legacy-key-resolve branch.
  /// OI-252 B-pass finding 2 (2026-09-27).
  @visibleForTesting
  static int invocationCountForTest = 0;

  /// Runs the migration pass if any non-uuid `tmpl_*` template row
  /// remains. Returns `true` when it is safe to push/restore templates
  /// this launch — either nothing needed migrating, or every legacy row
  /// was resolved just now — and `false` when at least one legacy row
  /// remains because resolving it failed (offline, or a network error).
  /// Callers MUST skip template push/restore for this pass when this
  /// returns `false`; every OTHER restore domain proceeds regardless.
  static Future<bool> runIfNeeded(String userId) async {
    invocationCountForTest++;
    final box = HiveService.instance.workoutBox;
    final legacyKeys = box.keys
        .whereType<String>()
        .where((k) => k.startsWith('tmpl_') && cloudIdFromKey(k) == null)
        .where((k) {
          final v = box.get(k);
          return v is Map && v['type'] == 'template';
        })
        .toList();

    if (legacyKeys.isEmpty) return true;

    final client = SupabaseService.instance.client;

    // Group by (trimmed) name -- the create-key-vs-restore-key duplicate
    // class this whole rework exists to fix. Two-or-more legacy rows
    // sharing a name keep only the newest by content.
    final byName = <String, List<String>>{};
    for (final k in legacyKeys) {
      final v = box.get(k);
      if (v is! Map) continue;
      final name = (v['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      byName.putIfAbsent(name, () => []).add(k);
    }

    var allResolved = true;
    final oldKeyToNewKey = <String, String>{};
    final rawUuidToNewKey = <String, String>{};

    for (final entry in byName.entries) {
      final name = entry.key;
      final keys = entry.value;
      try {
        final keeperKey = _pickNewest(box, keys);

        String cloudId;
        final rows = await client
            .from('workout_templates')
            .select('id')
            .eq('user_id', userId)
            .eq('name', name)
            .isFilter('deleted_at', null)
            .limit(1);
        if (rows.isNotEmpty && rows.first['id'] is String) {
          cloudId = rows.first['id'] as String;
        } else {
          cloudId = const Uuid().v4();
        }

        final newKey = templateKeyFor(cloudId);
        rawUuidToNewKey[cloudId] = newKey;

        final keeperValue = box.get(keeperKey);
        if (keeperValue is Map) {
          final rekeyed = Map<String, dynamic>.from(keeperValue)
            ..['id'] = newKey;
          await box.put(newKey, rekeyed);
        }
        for (final k in keys) {
          oldKeyToNewKey[k] = newKey;
          if (k != newKey) await box.delete(k);
        }
      } catch (e, st) {
        allResolved = false;
        debugPrint('[TemplateIdentityMigrator] "$name": $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'template_identity_migrator_resolve'));
      }
    }

    // Rewrite every schedule_*/displaced_* reference to a migrated key --
    // covers both the legacy Hive-key shape AND a bare cloud UUID with no
    // `tmpl_` prefix (the pre-fix `_restoreScheduledWorkouts` shape).
    if (oldKeyToNewKey.isNotEmpty || rawUuidToNewKey.isNotEmpty) {
      for (final k in box.keys.whereType<String>().toList()) {
        if (!k.startsWith('schedule_') && !k.startsWith('displaced_')) {
          continue;
        }
        final v = box.get(k);
        if (v is! Map) continue;
        final tid = v['template_id'];
        if (tid is! String) continue;
        final newTid = oldKeyToNewKey[tid] ?? rawUuidToNewKey[tid];
        if (newTid == null || newTid == tid) continue;
        final updated = Map<String, dynamic>.from(v)..['template_id'] = newTid;
        await box.put(k, updated);
      }
    }

    if (allResolved) {
      await HiveService.instance.userBox.put(_flagKey, true);
    }
    return allResolved;
  }

  /// The key whose row is "newest by content" — `updated_at`, else
  /// `created_at`, else the first key encountered (stable, arbitrary).
  static String _pickNewest(Box box, List<String> keys) {
    String best = keys.first;
    DateTime? bestTime;
    for (final k in keys) {
      final v = box.get(k);
      if (v is! Map) continue;
      final raw = (v['updated_at'] ?? v['created_at']) as String?;
      if (raw == null) continue;
      final t = DateTime.tryParse(raw);
      if (t == null) continue;
      if (bestTime == null || t.isAfter(bestTime)) {
        bestTime = t;
        best = k;
      }
    }
    return best;
  }
}
