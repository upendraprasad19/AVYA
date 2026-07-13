import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/detraining.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

import '../user_repository.dart';
import 'models.dart';
import 'plan_engine_flags.dart';

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
    Map<String, String?> repRanges = const {},
  }) {
    if (phase <= 1) return {};

    final weights = <String, double>{};

    try {
      final workoutBox = HiveService.instance.workoutBox;
      final graded = PlanEngineFlags.gradedProgressionEnabled;

      // Per exercise, the MOST RECENT logged session's top set (full history,
      // no 4-week window — an exercise reappearing after a gap still progresses
      // from where the user left off). SOLE source of base/est1rm/⑦a-decay.
      final lastSession = <String, _SessionTop>{};

      // W2.1 (graded ON-only, ADDITIVE): all sessions per exercise → the top-2
      // distinct calendar days feed the 2-consecutive back-off gate. NEVER feeds
      // base/est1rm, so flag-OFF stays byte-identical + ⑦a is untouched.
      final allByExercise = graded ? <String, List<_SessionTop>>{} : null;

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

        final row = _SessionTop(
            date: date, dateStr: dateStr, weight: top.weight, reps: top.reps);
        final existing = lastSession[name];
        if (existing == null || date.isAfter(existing.date)) {
          lastSession[name] = row; // verbatim first-seen tie-break, UNCHANGED
        }
        if (allByExercise != null) {
          (allByExercise[name] ??= <_SessionTop>[]).add(row);
        }
      }

      // W2.1 (graded ON-only): read the profile ONCE (not per-exercise) for the
      // beginner auto-linear window — RAW `fitness_experience` (NOT effectiveExp,
      // which widens at phase≥3, silently closing the window) + training-age from
      // `onboarding_completed_at`. `DateTime.tryParse` (NOT parse): a null/malformed
      // ts ⇒ not-linear (realistically null on restored phase-2+ profiles).
      bool beginnerLinear = false;
      if (graded) {
        // OWN try/catch (W2.1 F6, matching the flag getter): getProfile() reads
        // the GuardedBox-wrapped userBox, which can throw on a session-state
        // desync. Left un-guarded the throw hits the OUTER catch and empties the
        // WHOLE progression map — nuking suggested weights for users whose
        // workout logs are perfectly readable. Localize it: a profile-read
        // failure only closes the beginner window.
        try {
          final profile = UserRepository.instance.getProfile();
          final exp = (profile?['fitness_experience'] as String?) ?? '';
          final onboardedAt = DateTime.tryParse(
              (profile?['onboarding_completed_at'] as String?) ?? '');
          if (exp == 'beginner' && onboardedAt != null) {
            // nowWall() (the clock seam), NOT raw DateTime.now(): training-age is
            // a "how long since onboarding" read, so the dev-panel time-travel +
            // year-sim harness must fast-forward it in one place (ist_date.dart
            // :59-64). Release-identical to DateTime.now(); raw now() also makes
            // the beginner-window test a time-bomb (setTestClockTo can't reach it).
            beginnerLinear = nowWall().difference(onboardedAt).inDays < 120;
          }
        } catch (_) {
          beginnerLinear = false;
        }
      }

      // Match exercise names from the new plan to logged history + autoregulate.
      for (final exerciseName in exerciseNames) {
        final top = lastSession[exerciseName];
        if (top == null) continue;

        // est-1RM (Epley) — safety ceiling on the LAST-DEMONSTRATED top set,
        // computed from the ORIGINAL (pre-decay) weight: detraining decay lowers
        // the STARTING weight, never the true single-rep-max cap.
        final est1rm =
            top.reps > 0 ? top.weight * (1 + top.reps / 30.0) : top.weight;

        // ⑦(a) detraining decay (Batch 3b-i): a user resuming after a training
        // gap restarts lighter. The decayed `base` REPLACES top.weight in EVERY
        // branch below — INCLUDING the <=0 floor — so decay only ever reduces
        // (a floor reset to the ORIGINAL weight would invert "reduce-only").
        final base = PlanEngineFlags.detrainingDecayEnabled
            ? top.weight * _detrainingFactor(top.dateStr)
            : top.weight;

        // W2.1 (Batch 3b-ii): rep-range-aware graded rule when the flag is ON;
        // else the VERBATIM fixed-10/5 rule (flag-OFF is byte-identical — this
        // must never regress the shipped ⑦a decay + 10/5 for live users).
        double suggested;
        if (graded) {
          suggested = _gradedSuggestion(
            exerciseName,
            base: base,
            reps: top.reps,
            repRange: repRanges[exerciseName],
            beginnerLinear: beginnerLinear,
            sessions: allByExercise?[exerciseName] ?? const [],
          );
        } else if (top.reps >= 10) {
          // Strong session → progress.
          final increment = _isLowerBody(exerciseName) ? 5.0 : 2.5;
          suggested = base + increment;
        } else if (top.reps >= 5) {
          // Moderate → hold (consolidate before adding load).
          suggested = base;
        } else {
          // Struggled (<5 reps) → small back-off to rebuild movement quality.
          final backoff = _isLowerBody(exerciseName) ? 2.5 : 1.25;
          suggested = base - backoff;
          if (suggested <= 0) suggested = base;
        }

        // Never exceed est-1RM (the pre-decay demonstrated max).
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

  /// W2.1 rep-range-aware graded rule (ON-branch only), from the ⑦a [base]:
  /// beginner-linear → always progress; else parse the range and progress at
  /// `hi`, hold within, and back off ONLY on 2 consecutive distinct days below
  /// `lo`. No/invalid range → the verbatim fixed-10/5 semantics. The Epley clamp
  /// is applied by the caller.
  static double _gradedSuggestion(
    String exerciseName, {
    required double base,
    required int reps,
    required String? repRange,
    required bool beginnerLinear,
    required List<_SessionTop> sessions,
  }) {
    final increment = _isLowerBody(exerciseName) ? 5.0 : 2.5;
    if (beginnerLinear) return base + increment; // linear ramp for true newbies

    final parsed = parseRepRange(repRange);
    if (parsed == null) {
      // No/invalid range → verbatim fixed-10/5 semantics.
      if (reps >= 10) return base + increment;
      if (reps >= 5) return base;
      return _backOff(exerciseName, base);
    }

    final (lo, hi) = parsed;
    if (reps >= hi) return base + increment; // hit the top of the range → progress
    if (reps >= lo) return base; // within range → hold
    // Below the range → back off ONLY if the top-2 most-recent DISTINCT days are
    // BOTH below `lo` (2-consecutive) — one off day never backs off.
    final recent = _top2DistinctDays(sessions);
    final twoConsecutiveBelow =
        recent.length == 2 && recent.every((s) => s.reps < lo);
    return twoConsecutiveBelow ? _backOff(exerciseName, base) : base;
  }

  /// Back-off magnitude (same as today's fixed rule): −2.5 lower / −1.25 upper,
  /// floored to the (decayed) [base] so it never resets upward.
  static double _backOff(String exerciseName, double base) {
    final backoff = _isLowerBody(exerciseName) ? 2.5 : 1.25;
    final s = base - backoff;
    return s <= 0 ? base : s;
  }

  /// The 2 most-recent DISTINCT CALENDAR DAYS' top sets (heaviest per day),
  /// newest first — for W2.1's 2-consecutive gate. De-dupes by (y,m,d), NOT
  /// instant, so a same-day re-log (or a legacy full-timestamp row) can't fill
  /// both slots and trip the gate on ONE bad day.
  static List<_SessionTop> _top2DistinctDays(List<_SessionTop> sessions) {
    final byDay = <String, _SessionTop>{};
    for (final s in sessions) {
      final ymd = '${s.date.year}-${s.date.month}-${s.date.day}';
      final ex = byDay[ymd];
      if (ex == null || s.weight > ex.weight) byDay[ymd] = s;
    }
    final days = byDay.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return days.take(2).toList();
  }

  /// ⑦(a) detraining decay factor by the IST day-gap since [dateStr] (the raw
  /// `exlog_*` date-only string, already written via `istDateStr`). Reduce-only:
  /// ≤7d → 1.0 · 8–21d → 0.925 (−7.5%) · 22–35d → 0.825 (−17.5%) · >35d → 0.5.
  /// Returns 1.0 (no decay) when the date is missing/unparseable (safe default).
  static double _detrainingFactor(String? dateStr) {
    if (dateStr == null) return 1.0;
    final last = DateTime.tryParse(dateStr);
    // istTodayStr() is a date-only IST string; parsing both date-only makes the
    // device time-zone cancel — do NOT re-zone `dateStr` (it is ALREADY IST;
    // re-zoning double-shifts east-of-IST devices — Test #11.1 class).
    final today = DateTime.tryParse(istTodayStr());
    if (last == null || today == null) return 1.0;
    final gapDays = today.difference(last).inDays;
    // Shared band table (⑦b reuses it from an int gap) — one copy, #1 bug class.
    return detrainingFactorForGap(gapDays);
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

  /// The RAW `exlog_*` `date` string (already an IST date-only value written via
  /// `istDateStr`). Used for the ⑦(a) gap so we NEVER re-zone an already-IST
  /// date (which would double-shift east-of-IST devices — Test #11.1 class).
  final String? dateStr;
  final double weight;
  final int reps;
  const _SessionTop({
    required this.date,
    this.dateStr,
    required this.weight,
    required this.reps,
  });
}
