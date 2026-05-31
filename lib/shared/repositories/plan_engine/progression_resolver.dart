import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

/// Stage 0: Reads exercise logs from Hive for Phase 2+ to suggest starting weights.
///
/// Called before plan generation to provide log-aware progression.
///
/// 2026-05-31 — AUTOREGULATED load (replaces the old flat "+5kg lower / +2.5kg
/// upper on the 4-week max"). For each exercise we read the MOST RECENT logged
/// session's top set (across full history, not a 4-week window — so an exercise
/// that reappears after a gap still progresses from where the user left off),
/// then decide progress / hold / back-off from how that session went:
///   - reps >= 10 (hit the hypertrophy range with room to spare) → PROGRESS
///     (+5kg lower / +2.5kg upper).
///   - 5 <= reps < 10 → HOLD (consolidate the current load before adding).
///   - reps < 5 (grinded it out) → small BACK-OFF to rebuild quality.
/// est-1RM (Epley: w·(1+reps/30)) is a safety ceiling — we never prescribe a
/// starting weight above the user's estimated single-rep max. This is what lets
/// a user keep progressing realistically across the open-ended post-phase-12
/// deployment cycles all the way to Lieutenant.
class ProgressionResolver {
  /// Lower-body muscle/category keywords for +5 kg progression.
  static const _lowerBodyKeywords = {
    'legs', 'leg', 'quad', 'hamstring', 'glute', 'calf', 'calves',
    'squat', 'deadlift', 'lunge', 'hip thrust', 'leg press',
    'romanian deadlift', 'leg curl', 'leg extension',
  };

  /// Logging types that use bodyweight (no weight suggestion).
  static const _bodyweightTypes = {
    'bodyweight_reps', 'timed', 'cardio', 'distance', 'reps_only',
  };

  /// Resolve suggested starting weights from last phase's exercise logs.
  ///
  /// Returns a map of exerciseName → suggested weight (kg).
  /// Only called for phase >= 2.
  static Map<String, double> resolve({
    required int phase,
    required List<String> exerciseNames,
  }) {
    if (phase <= 1) return {};

    final weights = <String, double>{};

    try {
      final workoutBox = HiveService.instance.workoutBox;

      // Per exercise, the MOST RECENT logged session's top set (full history,
      // no 4-week window — an exercise reappearing after a gap still progresses
      // from where the user left off).
      final lastSession = <String, _SessionTop>{};

      for (final key in workoutBox.keys) {
        final keyStr = key.toString();
        if (!keyStr.startsWith('exlog_')) continue;

        final log = workoutBox.get(key);
        if (log is! Map) continue;

        final dateStr = log['date'] as String?;
        if (dateStr == null) continue;
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;

        final name = log['exercise_name'] as String?;
        if (name == null) continue;

        final top = _topSet(log);
        if (top == null) continue;

        final existing = lastSession[name];
        if (existing == null || date.isAfter(existing.date)) {
          lastSession[name] =
              _SessionTop(date: date, weight: top.weight, reps: top.reps);
        }
      }

      // Match exercise names from the new plan to logged history + autoregulate.
      for (final exerciseName in exerciseNames) {
        final top = lastSession[exerciseName];
        if (top == null) continue;

        // est-1RM (Epley) — safety ceiling so we never prescribe above the
        // user's estimated single-rep max.
        final est1rm =
            top.reps > 0 ? top.weight * (1 + top.reps / 30.0) : top.weight;

        double suggested;
        if (top.reps >= 10) {
          // Strong session → progress.
          final increment = _isLowerBody(exerciseName) ? 5.0 : 2.5;
          suggested = top.weight + increment;
        } else if (top.reps >= 5) {
          // Moderate → hold (consolidate before adding load).
          suggested = top.weight;
        } else {
          // Struggled (<5 reps) → small back-off to rebuild movement quality.
          final backoff = _isLowerBody(exerciseName) ? 2.5 : 1.25;
          suggested = top.weight - backoff;
          if (suggested <= 0) suggested = top.weight;
        }

        // Never exceed est-1RM.
        if (est1rm > 0 && suggested > est1rm) suggested = est1rm;

        weights[exerciseName] =
            double.parse(suggested.toStringAsFixed(1));
      }
    } catch (e, st) {
      // H-42 (audit-2026-05-11) — silent failure here means the plan
      // generator silently falls back to the default starting weight
      // for every exercise. Surface the error remotely so we can spot
      // Hive corruption / schema drift before it tanks user plans.
      debugPrint('[ProgressionResolver] Error reading Hive logs: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'progression_resolver_hive_read'));
    }

    return weights;
  }

  /// The heaviest set in a logged exercise entry + the reps achieved at it.
  /// Returns null for bodyweight/timed/cardio types (no load progression) or
  /// when no positive weight is found.
  static _SessionTop? _topSet(Map log) {
    final loggingType = log['logging_type'] as String?;
    if (loggingType != null && _bodyweightTypes.contains(loggingType)) {
      return null;
    }

    double bestW = 0;
    int bestReps = 0;
    final setsRaw = log['sets'];
    if (setsRaw is List) {
      for (final s in setsRaw) {
        if (s is! Map) continue;
        final w = _toDouble(s['weight_kg']);
        if (w == null || w <= bestW) continue;
        bestW = w;
        bestReps = _toInt(s['reps_completed'] ?? s['reps']) ?? 0;
      }
    }

    if (bestW <= 0) {
      // Older rows without a `sets` array — fall back to top-level fields.
      final w = _extractWeight(log);
      if (w == null || w <= 0) return null;
      bestW = w;
      // `reps_completed` here is cumulative (Σ set reps); a rough proxy.
      bestReps = _toInt(log['reps_completed']) ?? 0;
    }

    return _SessionTop(date: DateTime(0), weight: bestW, reps: bestReps);
  }

  /// Extract weight from an exercise log entry (top-level fallback).
  static double? _extractWeight(Map log) {
    final loggingType = log['logging_type'] as String?;
    if (loggingType != null && _bodyweightTypes.contains(loggingType)) {
      return null; // No weight suggestion for bodyweight exercises
    }
    return _toDouble(log['weight_kg']);
  }

  static double? _toDouble(Object? v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _toInt(Object? v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Check if exercise targets lower body (for +5 kg vs +2.5 kg increment).
  static bool _isLowerBody(String exerciseName) {
    final lower = exerciseName.toLowerCase();
    return _lowerBodyKeywords.any((kw) => lower.contains(kw));
  }
}

/// The top (heaviest) set of an exercise's most recent logged session.
class _SessionTop {
  final DateTime date;
  final double weight;
  final int reps;
  const _SessionTop({
    required this.date,
    required this.weight,
    required this.reps,
  });
}
