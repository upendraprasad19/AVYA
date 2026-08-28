import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';

import '../exercise_repository.dart';
import 'plan_engine_flags.dart';

/// Stage 0 (companion to [ProgressionResolver]) — reads Hive to produce
/// PHASE 2+ personalization signals for the plan engine.
///
/// 2026-05-31 personalization levers L5/L6/L7. Pure static methods, mirrors
/// `ProgressionResolver`'s structure: each public method wraps its Hive read
/// in try/catch + `ErrorTelemetry.recordNonFatal` and degrades to a safe empty
/// / neutral value when history is sparse or unreadable. Offline-first — never
/// touches the network and never throws into the generator.
///
/// All three levers no-op for Phase 1 (callers gate on `phase >= 2`) and for
/// users with < ~2 weeks of logged data.
class TrainingHistoryAnalyzer {
  /// Minimum distinct logged days before any signal is trusted (~2 weeks).
  static const int _minLoggedDaysForSignal = 14;

  /// LEVER 5 (weak-point → bodyFocus): the 1-2 muscle-group tokens with the
  /// LOWEST relative training-volume share over the recent window. These become
  /// `bodyFocus` tokens that [PeriodizationEngine] turns into +1 set on matching
  /// exercises (and [ExerciseSelector] uses for the isolation top-up).
  ///
  /// Volume per muscle = Σ (set volume) attributed to each `primary_muscles`
  /// token of the logged exercise (looked up in the exercise taxonomy). Tokens
  /// are returned lowercased to match how `PeriodizationEngine.apply` compares
  /// bodyFocus against `primaryMuscles` (`muscles.any((m) => m.contains(focus))`).
  ///
  /// Returns an empty list (safe no-op) if there are fewer than ~2 weeks of
  /// logged days or if no muscle volume could be attributed.
  static List<String> weakMuscles({int recentDays = 84}) {
    try {
      final workoutBox = HiveService.instance.workoutBox;
      final cutoff = DateTime.now().subtract(Duration(days: recentDays));

      // exercise_name (lowercased) → its primary-muscle tokens, from taxonomy.
      final taxonomy = _muscleTaxonomy();
      if (taxonomy.isEmpty) return const [];

      final volumePerMuscle = <String, double>{};
      final loggedDays = <String>{};

      for (final key in workoutBox.keys) {
        final keyStr = key.toString();
        if (!keyStr.startsWith('exlog_')) continue;

        final log = workoutBox.get(key);
        if (log is! Map) continue;

        final dateStr = log['date'] as String?;
        if (dateStr == null) continue;
        final date = DateTime.tryParse(dateStr);
        if (date == null || date.isBefore(cutoff)) continue;
        loggedDays.add(dateStr);

        final name = (log['exercise_name'] as String?)?.toLowerCase().trim();
        if (name == null || name.isEmpty) continue;

        final muscles = taxonomy[name];
        if (muscles == null || muscles.isEmpty) continue;

        final vol = _sessionVolume(log);
        if (vol <= 0) continue;

        // Attribute the session's volume to each primary muscle it trains.
        for (final m in muscles) {
          volumePerMuscle[m] = (volumePerMuscle[m] ?? 0) + vol;
        }
      }

      // Need at least ~2 weeks of distinct logged days to trust the signal.
      if (loggedDays.length < _minLoggedDaysForSignal) return const [];
      if (volumePerMuscle.length < 2) return const [];

      // Lagging groups = lowest relative share. Sort ascending by volume.
      final sorted = volumePerMuscle.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      // Return the 1-2 lowest-volume groups (the laggards) as bodyFocus tokens.
      final take = sorted.length >= 4 ? 2 : 1;
      return sorted.take(take).map((e) => e.key).toList();
    } catch (e, st) {
      debugPrint('[TrainingHistoryAnalyzer.weakMuscles] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'training_history_analyzer_weak_muscles'));
      return const [];
    }
  }

  /// LEVER 8 (⑤ Batch 4, explicit body-focus bring-up): translates the user's
  /// self-selected `physique_focus` profile token into the lowercased muscle-
  /// substring tokens that [PeriodizationEngine] turns into +1 set on matching
  /// exercises — the SAME downstream path as [weakMuscles]. Returns `[]` for
  /// `balanced` / `strength` / absent (no explicit bring-up → the caller falls
  /// back to [weakMuscles]). try/catch → `[]` like [weakMuscles] so a null /
  /// corrupt / unopened `userBox['profile']` never throws into the generator.
  /// The caller gates on `PlanEngineFlags.physiqueFocusBringupEnabled` (ship-dark).
  static List<String> physiqueFocusMuscles() {
    try {
      final profile = HiveService.instance.userBox.get('profile');
      if (profile is! Map) return const [];
      final token = (profile['physique_focus'] as String?)?.trim();
      return physiqueFocusToBodyFocus(token);
    } catch (e, st) {
      debugPrint('[TrainingHistoryAnalyzer.physiqueFocusMuscles] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'training_history_analyzer_physique_focus'));
      return const [];
    }
  }

  /// Pure translation (Hive-free, testable in isolation): a `physique_focus`
  /// token → the lowercased muscle-substring tokens PeriodizationEngine matches
  /// via `primaryMuscles.any((m) => m.contains(token))`. Verified against the
  /// library `primary_muscles`: `delt` catches Deltoid + Delts, `shoulder`
  /// catches Shoulders + Shoulder Stabilisers (which `delt` misses). `balanced`
  /// / `strength` / null → `[]` (no bring-up). See docs/plans/body-focus-batch.md.
  @visibleForTesting
  static List<String> physiqueFocusToBodyFocus(String? token) {
    switch (token) {
      case 'glutes_legs':
        return const ['glutes', 'quads', 'hamstrings', 'calves'];
      case 'chest_shoulders_arms':
        return const ['chest', 'delt', 'shoulder', 'triceps', 'biceps'];
      default:
        return const []; // balanced / strength / null → fall back to weakMuscles
    }
  }

  /// ⑤ (Batch 4) — resolves the effective bodyFocus for the periodization +1-set
  /// nudge, in PRECEDENCE order: an explicit [explicitBodyFocus] (rarely passed) >
  /// the user's `physique_focus` bring-up ([physiqueFocusMuscles], ship-dark
  /// behind `enable_physique_focus_bringup`, applies at ALL phases) > the auto
  /// laggard signal ([weakMuscles], phase≥2 only). When the flag is OFF this is
  /// BYTE-IDENTICAL to the pre-⑤ seam (`explicitBodyFocus.isEmpty && phase>=2 ?
  /// weakMuscles() : explicitBodyFocus`). Extracted from `plan_generator`'s inline
  /// seam so the flag-gate + precedence glue is DIRECTLY behavior-tested (B-pass P2).
  static List<String> resolveBodyFocus({
    required List<String> explicitBodyFocus,
    required int phase,
  }) {
    if (explicitBodyFocus.isNotEmpty) return explicitBodyFocus;
    final focus = PlanEngineFlags.physiqueFocusBringupEnabled
        ? physiqueFocusMuscles()
        : const <String>[];
    if (focus.isNotEmpty) return focus;
    if (phase >= 2) return weakMuscles();
    return const [];
  }

  /// ⑥ slice C1 — resolves the effective equipment-EXCLUSION set for generateV4,
  /// flag-gated. **LIVE since 2026-08-05** (diagnose e2d6b8): the gate is now the
  /// `disable_equipment_exclusions` kill-switch, default ON — it was ship-dark
  /// behind `enable_equipment_exclusions` (default OFF) until then, which is why
  /// the Customize UI's saved exclusions were silently ignored. Mirrors
  /// [resolveBodyFocus]/[physiqueFocusMuscles]: flag OFF → `const {}` WITHOUT
  /// reading Hive (byte-identical to B1's inert seam). Flag ON: an explicit [param]
  /// (tests / direct callers) takes precedence; else the user's `equipment_exclusions`
  /// profile field is read (crash-safe) and floor-sanitized
  /// ([EquipmentVocab.floorSanitizedExclusions] strips none/bodyweight so the
  /// bodyweight floor is never excludable). try/catch → `{}` so a null / corrupt /
  /// unopened `userBox['profile']` never throws into the generator.
  static Set<String> resolveEquipmentExclusions(
    List<String> param, {
    required bool flagEnabled,
  }) {
    if (!flagEnabled) return const <String>{};
    if (param.isNotEmpty) {
      return EquipmentVocab.floorSanitizedExclusions(param);
    }
    try {
      final profile = HiveService.instance.userBox.get('profile');
      if (profile is! Map) return const <String>{};
      return EquipmentVocab.floorSanitizedExclusions(
          EquipmentVocab.fromProfile(profile['equipment_exclusions']));
    } catch (e, st) {
      debugPrint('[TrainingHistoryAnalyzer.resolveEquipmentExclusions] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'training_history_analyzer_equipment_exclusions'));
      return const <String>{};
    }
  }

  /// ⑦ OI-89: the user's real equipment capability, or NULL for "do not
  /// enforce". Mirrors [resolveEquipmentExclusions].
  ///
  /// Returns null in three cases, each deliberate:
  ///   - flag OFF — a genuine SKIP. A "universal set" would NOT be inert:
  ///     `canPerform` fails CLOSED on an unreadable requirement regardless of
  ///     what the set contains, so it would still drop community/custom rows.
  ///   - tier is not `bodyweight` — founder decision 1 scopes the HARD floor to
  ///     that tier only; the other three keep queryV4's soft tier curation.
  ///     Scoping HERE rather than inside the cascade keeps tier logic in one
  ///     place; every drop site downstream is just `capability != null`.
  ///   - Hive is unreachable — fail OPEN. We cannot know the user's kit, and
  ///     enforcing an unknown set would drop every exercise. Availability wins
  ///     over a guess.
  static Set<String>? resolveCapability({
    required String tier,
    required Set<String> exclusions,
    required bool flagEnabled,
  }) {
    if (!flagEnabled) return null;
    if (tier != 'bodyweight') return null;
    try {
      final profile = HiveService.instance.userBox.get('profile');
      final owned = profile is Map
          ? EquipmentVocab.fromProfile(profile['equipment_owned'])
          : const <String>[];
      return EquipmentVocab.effectiveItems(tier, owned, exclusions.toList());
    } catch (e, st) {
      debugPrint('[TrainingHistoryAnalyzer.resolveCapability] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'training_history_analyzer_capability'));
      return null; // fail OPEN — see doc above
    }
  }

  /// LEVER 6 (demote swapped-out exercises): the set of ORIGINAL exercise names
  /// the user swapped AWAY from. Selection deprioritizes these (treats them as
  /// disliked) when an equivalent alternative exists.
  ///
  /// Scans `schedule_*` rows for entries flagged `is_swapped == true` and
  /// collects the names the user moved off. Two swap shapes are honored:
  ///   - exercise-level swap (`swap_service.swapExerciseInDay`) stamps the
  ///     replacement exercise map with `swapped_via` / `swapped_from` — the
  ///     ORIGINAL name is what we want to demote;
  ///   - day-level swap stamps the schedule row `is_swapped == true`.
  ///
  /// Returns an empty set (safe no-op) if there is no swap history.
  static Set<String> demotedExercises({int recentDays = 84}) {
    final demoted = <String>{};
    try {
      final workoutBox = HiveService.instance.workoutBox;
      final cutoff = DateTime.now().subtract(Duration(days: recentDays));

      for (final key in workoutBox.keys) {
        final keyStr = key.toString();
        if (!keyStr.startsWith('schedule_')) continue;

        final raw = workoutBox.get(key);
        if (raw is! Map) continue;

        // Window the scan by the schedule row's date when present.
        final dateStr = raw['date'] as String?;
        if (dateStr != null) {
          final date = DateTime.tryParse(dateStr);
          if (date != null && date.isBefore(cutoff)) continue;
        }

        final exercisesRaw = raw['exercises'];

        if (exercisesRaw is List) {
          for (final ex in exercisesRaw) {
            if (ex is! Map) continue;
            // Exercise-level swap: `SwapService.swapExercise` stamps the
            // replacement with `swapped_via` and `swapped_from` (the name it
            // replaced). Collect the ORIGINAL so selection deprioritizes it.
            final swappedFrom = (ex['swapped_from'] as String?)?.trim();
            if (swappedFrom != null && swappedFrom.isNotEmpty) {
              demoted.add(swappedFrom);
            }
          }
        }
        // NOTE: day-level swap (`SwapService.swapDays`) stamps the row
        // `is_swapped` + `original_date` but records no single original
        // exercise name — there is nothing reliable to demote there.
      }
    } catch (e, st) {
      debugPrint('[TrainingHistoryAnalyzer.demotedExercises] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'training_history_analyzer_demoted_exercises'));
    }
    return demoted;
  }

  /// LEVER 7 (bodyweight trend): a simple slope of recent bodyweight.
  ///
  /// Reads `weight_*` rows (healthBox), compares the mean of the last ~4 weeks
  /// against the mean of the prior ~4 weeks. Returns the delta in kg:
  ///   - negative  → losing weight,
  ///   - ~0        → stalled,
  ///   - positive  → gaining.
  ///
  /// Returns 0.0 (neutral) when there is not enough data to compare two windows.
  static double bodyweightTrendSignal() {
    try {
      final healthBox = HiveService.instance.healthBox;
      final now = DateTime.now();
      final recentCutoff = now.subtract(const Duration(days: 28));
      final priorCutoff = now.subtract(const Duration(days: 56));

      final recent = <double>[];
      final prior = <double>[];

      for (final key in healthBox.keys) {
        final keyStr = key.toString();
        if (!keyStr.startsWith('weight_')) continue;

        final raw = healthBox.get(key);
        if (raw is! Map) continue;

        final dateStr = raw['date'] as String?;
        if (dateStr == null) continue;
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;

        final w = _toDouble(raw['weight_kg']);
        if (w == null || w <= 0) continue;

        if (!date.isBefore(recentCutoff)) {
          recent.add(w);
        } else if (!date.isBefore(priorCutoff)) {
          prior.add(w);
        }
      }

      if (recent.isEmpty || prior.isEmpty) return 0.0;

      final recentMean = recent.reduce((a, b) => a + b) / recent.length;
      final priorMean = prior.reduce((a, b) => a + b) / prior.length;
      return double.parse((recentMean - priorMean).toStringAsFixed(2));
    } catch (e, st) {
      debugPrint('[TrainingHistoryAnalyzer.bodyweightTrendSignal] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'training_history_analyzer_bodyweight_trend'));
      return 0.0;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────

  /// exercise_name (lowercased) → lowercased `primary_muscles` tokens, built
  /// once per call from the exercise taxonomy (library + customs). Empty if the
  /// exercise box is unreadable.
  static Map<String, List<String>> _muscleTaxonomy() {
    final map = <String, List<String>>{};
    try {
      final repo = ExerciseRepository.instance;
      for (final e in repo.getAll()) {
        final name = (e['name'] as String?)?.toLowerCase().trim();
        if (name == null || name.isEmpty) continue;
        final muscles = _muscleTokens(e['primary_muscles']);
        if (muscles.isNotEmpty) map[name] = muscles;
      }
      // Custom exercises also carry primary_muscles.
      for (final e in repo.getCustomExercises()) {
        final name = (e['name'] as String?)?.toLowerCase().trim();
        if (name == null || name.isEmpty) continue;
        final muscles = _muscleTokens(e['primary_muscles']);
        if (muscles.isNotEmpty) map[name] = muscles;
      }
    } catch (e, st) {
      debugPrint('[TrainingHistoryAnalyzer._muscleTaxonomy] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'training_history_analyzer_muscle_taxonomy'));
    }
    return map;
  }

  static List<String> _muscleTokens(Object? raw) {
    if (raw is List) {
      return raw
          .map((m) => m.toString().toLowerCase().trim())
          .where((m) => m.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return [raw.toLowerCase().trim()];
    }
    return const [];
  }

  /// Total training volume of a logged exercise session. Prefers `volume_kg`
  /// (weight × reps), falls back to total reps for bodyweight/timed work so a
  /// muscle trained only with bodyweight still registers a share.
  static double _sessionVolume(Map log) {
    final vol = _toDouble(log['volume_kg']);
    if (vol != null && vol > 0) return vol;

    // Bodyweight / timed work: count reps so the muscle isn't invisible.
    final reps = _toDouble(log['reps_completed']);
    if (reps != null && reps > 0) return reps;

    // Older rows: sum the sets array.
    final setsRaw = log['sets'];
    if (setsRaw is List) {
      double sum = 0;
      for (final s in setsRaw) {
        if (s is! Map) continue;
        final w = _toDouble(s['weight_kg']) ?? 0;
        final r = _toDouble(s['reps_completed'] ?? s['reps']) ?? 0;
        sum += w > 0 ? w * r : r;
      }
      if (sum > 0) return sum;
    }
    return 0;
  }

  static double? _toDouble(Object? v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
