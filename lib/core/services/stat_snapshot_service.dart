/// Service for capturing starting-stats snapshots that fuel the
/// transformation comparison surface and promotion-day overlay.
///
/// APK Test #6 spec §9.5.2.
///
/// Three trigger points (CHECK-constrained `source` column on the
/// `user_stat_snapshots` table created by migration 044):
///   - 'onboarding' — auto, baseline row inserted by Plan F-9 hook on
///     first successful onboarding completion.
///   - 'promotion'  — auto, fired by RankService.evaluateAndPromote
///     per new rank insert (Plan F-10).
///   - 'manual'     — user-initiated from Profile → Take Snapshot Now
///     (Plan F-11). Optionally accepts measurements + photo URLs.
///
/// All methods are idempotent where it matters: snapshotOnboarding
/// skips if a row with `source='onboarding'` already exists, and
/// snapshotOnPromotion is keyed on (user_id, source='promotion',
/// rank_at_snapshot) to absorb re-fires.
///
/// Cloud sync is direct (Supabase insert) — there is no Hive mirror
/// today. The Reports list and promotion overlay both query Supabase
/// at view time. If/when offline support is needed, layer a
/// SyncQueue entry per write.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

/// Generic write result for snapshot operations.
///
/// Note: the existing `WriteResult` in `lib/core/services/write_result.dart`
/// is non-generic (single `logKey` string). Plan F's spec calls for a
/// typed return so callers (F-9, F-10, F-11) can read back the inserted
/// row. Defined locally to avoid touching shipped contracts of the
/// non-generic WriteResult.
@immutable
class SnapshotWriteResult<T> {
  final bool success;
  final T? value;
  final String? errorMessage;

  const SnapshotWriteResult._({
    required this.success,
    this.value,
    this.errorMessage,
  });

  const SnapshotWriteResult.success(T? value)
      : this._(success: true, value: value);

  const SnapshotWriteResult.failure(String message)
      : this._(success: false, errorMessage: message);

  @override
  String toString() =>
      'SnapshotWriteResult(success=$success, value=$value, error=$errorMessage)';
}

/// Single-row representation of `user_stat_snapshots`.
@immutable
class UserStatSnapshot {
  final String id;
  final String userId;
  final DateTime snapshotAt;
  final String source; // 'onboarding' | 'promotion' | 'manual'
  final String? rankAtSnapshot;
  final double? weightKg;
  final double? bodyFatPct;
  final double? heightCm;
  final int? ageYears;
  final Map<String, double> measurements;
  final List<Map<String, dynamic>> photos;
  final int? avgCalories7d;
  final int? avgProtein7d;
  final int? avgSteps7d;
  final double? avgSleepHours7d;
  final int? planPhase;
  final int? planWeek;
  final String? primaryGoal;

  const UserStatSnapshot({
    required this.id,
    required this.userId,
    required this.snapshotAt,
    required this.source,
    this.rankAtSnapshot,
    this.weightKg,
    this.bodyFatPct,
    this.heightCm,
    this.ageYears,
    this.measurements = const {},
    this.photos = const [],
    this.avgCalories7d,
    this.avgProtein7d,
    this.avgSteps7d,
    this.avgSleepHours7d,
    this.planPhase,
    this.planWeek,
    this.primaryGoal,
  });

  factory UserStatSnapshot.fromRow(Map<String, dynamic> row) {
    return UserStatSnapshot(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      snapshotAt: DateTime.parse(row['snapshot_at'] as String),
      source: row['source'] as String,
      rankAtSnapshot: row['rank_at_snapshot'] as String?,
      weightKg: (row['weight_kg'] as num?)?.toDouble(),
      bodyFatPct: (row['body_fat_pct'] as num?)?.toDouble(),
      heightCm: (row['height_cm'] as num?)?.toDouble(),
      ageYears: (row['age_years'] as num?)?.toInt(),
      measurements: (row['measurements'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())) ??
          const {},
      photos: (row['photos'] as List?)
              ?.map((p) => Map<String, dynamic>.from(p as Map))
              .toList() ??
          const [],
      avgCalories7d: (row['avg_calories_7d'] as num?)?.toInt(),
      avgProtein7d: (row['avg_protein_7d'] as num?)?.toInt(),
      avgSteps7d: (row['avg_steps_7d'] as num?)?.toInt(),
      avgSleepHours7d: (row['avg_sleep_hours_7d'] as num?)?.toDouble(),
      planPhase: (row['plan_phase'] as num?)?.toInt(),
      planWeek: (row['plan_week'] as num?)?.toInt(),
      primaryGoal: row['primary_goal'] as String?,
    );
  }
}

/// Diff of two snapshots — used for Reports row + promotion overlay.
@immutable
class StatSnapshotDiff {
  final UserStatSnapshot from;
  final UserStatSnapshot to;
  final double? weightDeltaKg;
  final double? bodyFatDelta;
  final int? caloriesDelta;
  final int? proteinDelta;
  final Duration? elapsed;

  const StatSnapshotDiff({
    required this.from,
    required this.to,
    this.weightDeltaKg,
    this.bodyFatDelta,
    this.caloriesDelta,
    this.proteinDelta,
    this.elapsed,
  });

  /// Short human-readable line for the Reports row subtitle.
  /// Example: "76.9 kg → 73.5 kg · 12 weeks"
  String shortDescription() {
    final parts = <String>[];
    if (from.weightKg != null && to.weightKg != null) {
      parts.add('${from.weightKg!.toStringAsFixed(1)} kg → '
          '${to.weightKg!.toStringAsFixed(1)} kg');
    }
    if (elapsed != null) {
      final weeks = (elapsed!.inDays / 7).floor();
      if (weeks > 0) parts.add('$weeks weeks');
    }
    return parts.isEmpty ? 'No comparison data' : parts.join(' · ');
  }
}

class StatSnapshotService {
  StatSnapshotService._();
  static final instance = StatSnapshotService._();

  /// Auto-snapshot fired immediately after onboarding completion.
  /// Pulls weight/height/age/goal/etc. from the user_profile that
  /// onboarding just saved. 7-day averages are 0 (no history yet).
  Future<SnapshotWriteResult<UserStatSnapshot?>> snapshotOnboarding() async {
    try {
      final supa = SupabaseService.instance.client;
      final user = supa.auth.currentUser;
      if (user == null) {
        return const SnapshotWriteResult.failure('not_authenticated');
      }

      final profile = HiveService.instance.userBox.get('profile') as Map?;
      if (profile == null) {
        return const SnapshotWriteResult.failure('no_profile');
      }

      // Idempotency guard: skip if an onboarding row already exists.
      final existing = await supa
          .from('user_stat_snapshots')
          .select('id')
          .eq('user_id', user.id)
          .eq('source', 'onboarding')
          .maybeSingle();
      if (existing != null) {
        return const SnapshotWriteResult.success(null); // no-op
      }

      final row = {
        'user_id': user.id,
        'source': 'onboarding',
        'rank_at_snapshot': null,
        'weight_kg': profile['current_weight_kg'],
        'body_fat_pct': profile['body_fat_percent'],
        'height_cm': profile['height_cm'],
        'age_years': _ageFromDob(profile['date_of_birth'] as String?),
        'measurements': null,
        'photos': null,
        'avg_calories_7d': 0,
        'avg_protein_7d': 0,
        'avg_steps_7d': 0,
        'avg_sleep_hours_7d': 0,
        'plan_phase': 1,
        'plan_week': 1,
        'primary_goal': profile['primary_goal'],
      };

      final inserted = await supa
          .from('user_stat_snapshots')
          .insert(row)
          .select()
          .single();

      return SnapshotWriteResult.success(UserStatSnapshot.fromRow(inserted));
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[StatSnapshotService.snapshotOnboarding] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'stat_snapshot_onboarding'));
      return SnapshotWriteResult.failure(e.toString());
    }
  }

  /// Auto-snapshot fired by RankService.evaluateAndPromote per new rank.
  Future<SnapshotWriteResult<UserStatSnapshot?>> snapshotOnPromotion(
      String newRankCode) async {
    try {
      final supa = SupabaseService.instance.client;
      final user = supa.auth.currentUser;
      if (user == null) {
        return const SnapshotWriteResult.failure('not_authenticated');
      }

      // Idempotency: skip if a promotion snapshot already exists for
      // this rank (rank_promotions UNIQUE prevents repeat fires, but
      // belt-and-suspenders).
      final existing = await supa
          .from('user_stat_snapshots')
          .select('id')
          .eq('user_id', user.id)
          .eq('source', 'promotion')
          .eq('rank_at_snapshot', newRankCode)
          .maybeSingle();
      if (existing != null) {
        return const SnapshotWriteResult.success(null);
      }

      final profile = HiveService.instance.userBox.get('profile') as Map?;
      final averages = await _compute7dAverages(supa, user.id);

      final row = {
        'user_id': user.id,
        'source': 'promotion',
        'rank_at_snapshot': newRankCode,
        'weight_kg': _latestWeight(),
        'body_fat_pct': profile?['body_fat_percent'],
        'height_cm': profile?['height_cm'],
        'age_years': _ageFromDob(profile?['date_of_birth'] as String?),
        'avg_calories_7d': averages['calories'],
        'avg_protein_7d': averages['protein'],
        'avg_steps_7d': averages['steps'],
        'avg_sleep_hours_7d': averages['sleep'],
        'plan_phase': profile?['plan_phase'] ?? 1,
        'plan_week': profile?['plan_week'] ?? 1,
        'primary_goal': profile?['primary_goal'],
      };

      final inserted = await supa
          .from('user_stat_snapshots')
          .insert(row)
          .select()
          .single();

      return SnapshotWriteResult.success(UserStatSnapshot.fromRow(inserted));
    } catch (e, st) {
      debugPrint('[StatSnapshotService.snapshotOnPromotion] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'stat_snapshot_on_promotion'));
      return SnapshotWriteResult.failure(e.toString());
    }
  }

  /// Manual snapshot. Optionally accepts measurements + photo URLs
  /// captured by the take-snapshot sheet (F-11).
  Future<SnapshotWriteResult<UserStatSnapshot?>> snapshotManual({
    Map<String, double>? measurements,
    List<String>? photoUrls,
  }) async {
    try {
      final supa = SupabaseService.instance.client;
      final user = supa.auth.currentUser;
      if (user == null) {
        return const SnapshotWriteResult.failure('not_authenticated');
      }

      final profile = HiveService.instance.userBox.get('profile') as Map?;
      final averages = await _compute7dAverages(supa, user.id);
      final photos = (photoUrls ?? [])
          .map((u) => {
                'url': u,
                'taken_at': istNow().toIso8601String(),
                'angle': 'front',
              })
          .toList();

      final row = {
        'user_id': user.id,
        'source': 'manual',
        'rank_at_snapshot': profile?['current_rank_code'],
        'weight_kg': _latestWeight(),
        'body_fat_pct': profile?['body_fat_percent'],
        'height_cm': profile?['height_cm'],
        'age_years': _ageFromDob(profile?['date_of_birth'] as String?),
        'measurements': measurements,
        'photos': photos.isEmpty ? null : photos,
        'avg_calories_7d': averages['calories'],
        'avg_protein_7d': averages['protein'],
        'avg_steps_7d': averages['steps'],
        'avg_sleep_hours_7d': averages['sleep'],
        'plan_phase': profile?['plan_phase'] ?? 1,
        'plan_week': profile?['plan_week'] ?? 1,
        'primary_goal': profile?['primary_goal'],
      };

      final inserted = await supa
          .from('user_stat_snapshots')
          .insert(row)
          .select()
          .single();

      return SnapshotWriteResult.success(UserStatSnapshot.fromRow(inserted));
    } catch (e, st) {
      debugPrint('[StatSnapshotService.snapshotManual] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'stat_snapshot_manual'));
      return SnapshotWriteResult.failure(e.toString());
    }
  }

  /// All snapshots for the current user, ordered by snapshot_at DESC.
  Future<List<UserStatSnapshot>> listAll() async {
    try {
      final supa = SupabaseService.instance.client;
      final user = supa.auth.currentUser;
      if (user == null) return const [];

      final rows = await supa
          .from('user_stat_snapshots')
          .select()
          .eq('user_id', user.id)
          .order('snapshot_at', ascending: false);

      return (rows as List)
          .map((r) => UserStatSnapshot.fromRow(Map<String, dynamic>.from(r)))
          .toList();
    } catch (e, st) {
      debugPrint('[StatSnapshotService.listAll] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'stat_snapshot_list_all'));
      return const [];
    }
  }

  /// The earliest (`source='onboarding'`) snapshot.
  Future<UserStatSnapshot?> baseline() async {
    final all = await listAll();
    if (all.isEmpty) return null;
    final onboarding = all.where((s) => s.source == 'onboarding').toList()
      ..sort((a, b) => a.snapshotAt.compareTo(b.snapshotAt));
    return onboarding.isNotEmpty ? onboarding.first : all.last;
  }

  /// Compute deltas between two snapshots.
  StatSnapshotDiff diff(UserStatSnapshot a, UserStatSnapshot b) {
    return StatSnapshotDiff(
      from: a,
      to: b,
      weightDeltaKg: (a.weightKg != null && b.weightKg != null)
          ? b.weightKg! - a.weightKg!
          : null,
      bodyFatDelta: (a.bodyFatPct != null && b.bodyFatPct != null)
          ? b.bodyFatPct! - a.bodyFatPct!
          : null,
      caloriesDelta: (a.avgCalories7d != null && b.avgCalories7d != null)
          ? b.avgCalories7d! - a.avgCalories7d!
          : null,
      proteinDelta: (a.avgProtein7d != null && b.avgProtein7d != null)
          ? b.avgProtein7d! - a.avgProtein7d!
          : null,
      elapsed: b.snapshotAt.difference(a.snapshotAt),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────

  int? _ageFromDob(String? dobIso) {
    if (dobIso == null || dobIso.isEmpty) return null;
    final dob = DateTime.tryParse(dobIso);
    if (dob == null) return null;
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  double? _latestWeight() {
    final hive = HiveService.instance;
    DateTime? latestTs;
    double? latestKg;
    for (final raw in hive.healthBox.values) {
      if (raw is! Map) continue;
      if (raw['type'] != 'weight_log') continue;
      final ts = DateTime.tryParse(raw['created_at'] as String? ?? '');
      final kg = (raw['weight_kg'] as num?)?.toDouble();
      if (ts == null || kg == null) continue;
      if (latestTs == null || ts.isAfter(latestTs)) {
        latestTs = ts;
        latestKg = kg;
      }
    }
    return latestKg;
  }

  /// 7-day rolling averages from `nutrition_logs`, `daily_steps`,
  /// `sleep_logs` for the snapshot user. Defensive on errors —
  /// returns 0s rather than nulls so the row inserts cleanly.
  Future<Map<String, num>> _compute7dAverages(
      SupabaseClient supa, String userId) async {
    try {
      final since = istDateStr(
        DateTime.now().subtract(const Duration(days: 7)),
      );

      final nutrRows = await supa
          .from('nutrition_logs')
          .select('total_calories, total_protein')
          .eq('user_id', userId)
          .gte('date', since);
      // Schema-ref fix (diagnose a7c3e1, 2026-05-30): daily_steps has column
      // `steps` (NOT `total_steps`) and sleep_logs has `duration_hrs` (NOT
      // `hours`). The prior column names threw 42703 → the whole try block
      // jumped to catch → every 7d average returned 0 for promotion + manual
      // snapshots. Verified against live information_schema 2026-05-30.
      final stepRows = await supa
          .from('daily_steps')
          .select('steps')
          .eq('user_id', userId)
          .gte('date', since);
      final sleepRows = await supa
          .from('sleep_logs')
          .select('duration_hrs')
          .eq('user_id', userId)
          .gte('date', since);

      double avg(List rows, String key) {
        if (rows.isEmpty) return 0;
        final sum = rows.fold<double>(
            0, (s, r) => s + (((r as Map)[key] as num?)?.toDouble() ?? 0));
        return sum / rows.length;
      }

      return {
        'calories': avg(nutrRows as List, 'total_calories').round(),
        'protein': avg(nutrRows, 'total_protein').round(),
        'steps': avg(stepRows as List, 'steps').round(),
        'sleep': double.parse(
            avg(sleepRows as List, 'duration_hrs').toStringAsFixed(1)),
      };
    } catch (e, st) {
      debugPrint('[StatSnapshotService._compute7dAverages] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'stat_snapshot_compute_7d_averages'));
      return {'calories': 0, 'protein': 0, 'steps': 0, 'sleep': 0};
    }
  }
}
