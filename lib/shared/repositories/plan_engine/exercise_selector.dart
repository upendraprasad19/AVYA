import 'dart:math';

import 'package:flutter/foundation.dart';

import '../exercise_repository.dart';
import 'models.dart';

/// Stage 2: Constraint-based exercise picker.
///
/// V3 additions: injury exclusion, body focus isolation, beginner non-negotiables,
/// session duration guidance.
class ExerciseSelector {
  /// Hard minimum exercises per workout day for both A and B variants.
  static const int hardFloor = 5;

  /// Categories to broaden across when [_broadenSelection] runs out.
  static const _broadenCategories = <String, List<String>>{
    'push':           ['Push'],
    'pull':           ['Pull'],
    'legs':           ['Legs'],
    'upper':          ['Push', 'Pull'],
    'shoulders_arms': ['Push', 'Pull'],
    'full_body':      ['Push', 'Pull', 'Legs', 'Core'],
  };

  /// Hardcoded universal-bodyweight pool.
  static const _universalPool = <String, List<String>>{
    'push':           ['Push-Up', 'Incline Push-Up', 'Pike Push-Up', 'Decline Push-Up', 'Wide Push-Up'],
    'pull':           ['Inverted Row', 'Doorway Row', 'Towel Row', 'Superman Hold', 'Reverse Snow Angel'],
    'legs':           ['Bodyweight Squat', 'Reverse Lunge', 'Glute Bridge', 'Single-Leg RDL', 'Calf Raise'],
    'upper':          ['Push-Up', 'Pike Push-Up', 'Inverted Row', 'Superman Hold', 'Doorway Row'],
    'shoulders_arms': ['Pike Push-Up', 'Wall Handstand Hold', 'Doorway Row', 'Superman Hold', 'Plank'],
    'full_body':      ['Push-Up', 'Inverted Row', 'Bodyweight Squat', 'Plank', 'Glute Bridge'],
  };

  /// Timed universal names.
  static const _timedUniversal = <String>{
    'Plank', 'Dead Bug', 'Bird Dog', 'Hollow Hold', 'Side Plank',
    'Superman Hold', 'Wall Handstand Hold', 'Reverse Snow Angel',
  };

  /// Session duration → exercise count guideline.
  static const _durationExerciseCounts = <int, int>{
    30: 4,
    45: 5,
    60: 6,
    90: 8,
  };

  /// Default exercise counts by daysPerWeek × experience.
  static const defaultExerciseCounts = <int, Map<String, int>>{
    3: {'beginner': 5, 'intermediate': 6, 'advanced': 6},
    4: {'beginner': 5, 'intermediate': 5, 'advanced': 6},
    5: {'beginner': 5, 'intermediate': 5, 'advanced': 5},
    6: {'beginner': 5, 'intermediate': 5, 'advanced': 5},
  };

  /// Picks exercises for A and B variants of each day.
  static List<PopulatedDay> pick({
    required List<DaySlot> splitPlan,
    required ExerciseRepository exerciseRepo,
    required List<String> equipmentList,
    required String effectiveExp,
    required int phase,
    required int maxPerDay,
    required String goal,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
  }) {
    final result = <PopulatedDay>[];

    for (final slot in splitPlan) {
      // Cap spec counts to maxPerDay
      final cappedA = _capSpecs(slot.specsA, maxPerDay);
      final bSpecs = slot.specsB ?? slot.specsA;
      final cappedB = _capSpecs(bSpecs, maxPerDay);

      // Select Variant A exercises
      var exercisesA = _selectForSpecs(
        cappedA, exerciseRepo, equipmentList, effectiveExp, phase,
        injuries: injuries,
      );

      // V3: Inject beginner non-negotiables
      exercisesA = _injectNonNegotiables(
        exercisesA, effectiveExp, slot.dayType, exerciseRepo, equipmentList,
      );

      // Enforce hard floor of 5 on Variant A
      exercisesA = _broadenSelection(
        current: exercisesA,
        slot: slot,
        equipmentList: equipmentList,
        effectiveExp: effectiveExp,
        repo: exerciseRepo,
        variant: 'A',
        excludeNamesParam: null,
      );

      // Select Variant B exercises, excluding A names
      final excludeNames = exercisesA.map((e) => e.exerciseName).toSet();

      // For strength goal, allow primary compound overlap
      final firstSpecCount = cappedA.isNotEmpty ? cappedA.first.count : 0;
      Set<String> effectiveExclude;
      if (goal == 'strength' && exercisesA.length >= firstSpecCount) {
        effectiveExclude = exercisesA
            .skip(firstSpecCount)
            .map((e) => e.exerciseName)
            .toSet();
      } else {
        effectiveExclude = excludeNames;
      }

      var exercisesB = _selectForSpecs(
        cappedB, exerciseRepo, equipmentList, effectiveExp, phase,
        excludeNames: effectiveExclude,
        injuries: injuries,
      );

      // V3: Inject beginner non-negotiables for B variant too
      exercisesB = _injectNonNegotiables(
        exercisesB, effectiveExp, slot.dayType, exerciseRepo, equipmentList,
      );

      exercisesB = _broadenSelection(
        current: exercisesB,
        slot: slot,
        equipmentList: equipmentList,
        effectiveExp: effectiveExp,
        repo: exerciseRepo,
        variant: 'B',
        excludeNamesParam: effectiveExclude,
      );

      // V3: Body focus — append extra isolation for focus muscles
      exercisesA = _appendBodyFocusIsolation(
        exercisesA, slot, exerciseRepo, equipmentList, effectiveExp, bodyFocus,
      );
      exercisesB = _appendBodyFocusIsolation(
        exercisesB, slot, exerciseRepo, equipmentList, effectiveExp, bodyFocus,
      );

      result.add(PopulatedDay(
        name: slot.name, focus: slot.focus,
        dayType: slot.dayType, intensity: slot.intensity,
        exercisesA: exercisesA,
        exercisesB: slot.specsB != null
            ? exercisesB.map((e) => e.copyWith(variant: 'B')).toList()
            : exercisesA,
      ));
    }
    return result;
  }

  /// V3: Resolve maxPerDay considering session duration.
  static int resolveMaxPerDay({
    required int daysPerWeek,
    required String effectiveExp,
    int? sessionDuration,
  }) {
    if (sessionDuration != null) {
      return _durationExerciseCounts[sessionDuration] ??
          defaultExerciseCounts[daysPerWeek]?[effectiveExp] ?? 5;
    }
    return defaultExerciseCounts[daysPerWeek]?[effectiveExp] ?? 5;
  }

  // ── V3: Beginner non-negotiables ─────────────────────────────

  /// Inject squats + push-ups into beginner full-body days if not already present.
  static List<PlannedExercise> _injectNonNegotiables(
    List<PlannedExercise> exercises,
    String effectiveExp,
    String dayType,
    ExerciseRepository repo,
    List<String> equipmentList,
  ) {
    if (effectiveExp != 'beginner') return exercises;
    if (dayType != 'full_body') return exercises;

    final names = exercises.map((e) => e.exerciseName.toLowerCase()).toSet();
    final result = List<PlannedExercise>.from(exercises);

    // Inject Bodyweight Squat if no squat variant present
    if (!names.any((n) => n.contains('squat'))) {
      final squat = repo.search('Bodyweight Squat');
      if (squat.isNotEmpty) {
        result.insert(0, _buildExercise(squat.first));
      } else {
        result.insert(0, PlannedExercise(
          exerciseId: 'bodyweight_squat',
          exerciseName: 'Bodyweight Squat',
          loggingType: 'bodyweight_reps',
          sets: 3, reps: '10', restSeconds: 60,
          category: 'Legs',
          equipmentNeeded: const ['bodyweight'],
        ));
      }
    }

    // Inject Push-Up if no push-up variant present
    if (!names.any((n) => n.contains('push-up') || n.contains('push up') || n.contains('pushup'))) {
      final pushup = repo.search('Push-Up');
      if (pushup.isNotEmpty) {
        result.insert(1, _buildExercise(pushup.first));
      } else {
        result.insert(1, PlannedExercise(
          exerciseId: 'push_up',
          exerciseName: 'Push-Up',
          loggingType: 'bodyweight_reps',
          sets: 3, reps: '10', restSeconds: 60,
          category: 'Push',
          equipmentNeeded: const ['bodyweight'],
        ));
      }
    }

    return result;
  }

  // ── V3: Body focus isolation ──────────────────────────────────

  /// Append 1 extra isolation exercise for each focus muscle on relevant days.
  static List<PlannedExercise> _appendBodyFocusIsolation(
    List<PlannedExercise> exercises,
    DaySlot slot,
    ExerciseRepository repo,
    List<String> equipmentList,
    String effectiveExp,
    List<String> bodyFocus,
  ) {
    if (bodyFocus.isEmpty) return exercises;

    final result = List<PlannedExercise>.from(exercises);
    final pickedNames = result.map((e) => e.exerciseName).toSet();

    for (final focus in bodyFocus) {
      // Check if this day's specs target this focus muscle
      final dayTargetsFocus = slot.specsA.any((s) {
        final cat = s.category.toLowerCase();
        final focusLower = focus.toLowerCase();
        // Map body focus to relevant categories
        if (focusLower == 'chest' || focusLower == 'shoulders' || focusLower == 'triceps') {
          return cat == 'push';
        }
        if (focusLower == 'back' || focusLower == 'biceps') {
          return cat == 'pull';
        }
        if (focusLower == 'legs' || focusLower == 'glutes') {
          return cat == 'legs';
        }
        if (focusLower == 'core' || focusLower == 'abs') {
          return cat == 'core';
        }
        return false;
      });

      if (!dayTargetsFocus) continue;

      // Find an isolation exercise for this focus muscle not already picked
      final category = _focusToCategory(focus);
      final candidates = repo.query(
        category: category,
        equipment: equipmentList,
        suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
        targetMuscles: [focus],
        limit: 10,
      );

      // Filter for isolation exercises not already in the list
      for (final c in candidates) {
        final name = c['name'] as String? ?? '';
        final type = c['exercise_type'] as String? ?? '';
        if (name.isEmpty || pickedNames.contains(name)) continue;
        if (type != 'isolation') continue;

        result.add(_buildExercise(c));
        pickedNames.add(name);
        break; // Only +1 per focus muscle per day
      }
    }

    return result;
  }

  /// Map body focus muscle name to exercise library category.
  static String _focusToCategory(String focus) {
    final f = focus.toLowerCase();
    if (f == 'chest' || f == 'shoulders' || f == 'triceps') return 'Push';
    if (f == 'back' || f == 'biceps') return 'Pull';
    if (f == 'legs' || f == 'glutes') return 'Legs';
    if (f == 'core' || f == 'abs') return 'Core';
    return 'Push'; // fallback
  }

  // ── Existing logic (broadening, spec selection, etc.) ─────────

  /// Top up [current] until it has at least [hardFloor] exercises.
  static List<PlannedExercise> _broadenSelection({
    required List<PlannedExercise> current,
    required DaySlot slot,
    required List<String> equipmentList,
    required String effectiveExp,
    required ExerciseRepository repo,
    required String variant,
    required Set<String>? excludeNamesParam,
  }) {
    if (current.length >= hardFloor) return current;

    final result = List<PlannedExercise>.from(current);
    final pickedNames = result.map((e) => e.exerciseName).toSet();
    final dayName = slot.name;

    final specCategories = slot.specsA.map((s) => s.category).toSet().toList();
    final categories = specCategories.isNotEmpty
        ? specCategories
        : (_broadenCategories[slot.dayType] ?? const ['Push', 'Pull', 'Legs', 'Core']);

    final allTargets = <String>[
      for (final s in slot.specsA) ...?s.targetMuscles,
    ];
    final allExcludes = <String>[
      for (final s in slot.specsA) ...?s.excludeMuscles,
    ];

    for (var retry = 1; retry <= 4 && result.length < hardFloor; retry++) {
      if (retry >= 2) {
        debugPrint(
          '[plan_generator] broadening retry=$retry day=$dayName variant=$variant exp=$effectiveExp eq=${equipmentList.length} have=${result.length}',
        );
      }

      final dropTarget    = retry >= 1;
      final dropExclude   = retry >= 2;
      final dropExp       = retry >= 3;
      final dropEquipment = retry >= 4;

      for (final cat in categories) {
        if (result.length >= hardFloor) break;

        final candidates = repo.query(
          category: cat,
          equipment: dropEquipment ? null : equipmentList,
          suitableFor: dropExp ? null : effectiveExp,
          targetMuscles:
              dropTarget ? null : (allTargets.isEmpty ? null : allTargets),
          excludeMuscles:
              dropExclude ? null : (allExcludes.isEmpty ? null : allExcludes),
          limit: 50,
        );

        for (final c in candidates) {
          if (result.length >= hardFloor) break;
          final name = c['name'] as String? ?? '';
          if (name.isEmpty || pickedNames.contains(name)) continue;
          if (!dropExclude && (excludeNamesParam?.contains(name) ?? false)) {
            continue;
          }
          result.add(_buildExercise(c).copyWith(variant: variant));
          pickedNames.add(name);
        }
      }
    }

    // Final safety net: hardcoded universal-bodyweight pool.
    if (result.length < hardFloor) {
      debugPrint(
        '[plan_generator] universal pool fired day=$dayName variant=$variant short=${hardFloor - result.length} exp=$effectiveExp eq=${equipmentList.join(",")}',
      );
      final pool = _universalPool[slot.dayType] ?? _universalPool['upper']!;
      for (final exName in pool) {
        if (result.length >= hardFloor) break;
        if (pickedNames.contains(exName)) continue;
        final repoMatch = repo.search(exName);
        if (repoMatch.isNotEmpty) {
          result.add(_buildExercise(repoMatch.first).copyWith(variant: variant));
        } else {
          result.add(_buildUniversalFallback(exName, variant));
        }
        pickedNames.add(exName);
      }
    }

    return result;
  }

  static PlannedExercise _buildUniversalFallback(String name, String variant) {
    final isTimed = _timedUniversal.contains(name);
    return PlannedExercise(
      exerciseId: name.toLowerCase().replaceAll(' ', '_'),
      exerciseName: name,
      loggingType: isTimed ? 'timed' : 'bodyweight_reps',
      sets: 3,
      reps: isTimed ? '30s' : '10',
      restSeconds: 60,
      durationSeconds: isTimed ? 30 : null,
      category: _categoryForUniversalName(name),
      equipmentNeeded: const ['bodyweight'],
      variant: variant,
    );
  }

  static String _categoryForUniversalName(String name) {
    if (_universalPool['push']!.contains(name)) return 'Push';
    if (_universalPool['pull']!.contains(name)) return 'Pull';
    if (_universalPool['legs']!.contains(name)) return 'Legs';
    return 'Core';
  }

  static List<CSpec> _capSpecs(List<CSpec> specs, int maxPerDay) {
    final total = specs.fold<int>(0, (sum, s) => sum + s.count);
    if (total <= maxPerDay) return specs;

    final capped = specs.map((s) => CSpec(s.category, s.count,
        target: s.targetMuscles, exclude: s.excludeMuscles)).toList();
    var excess = total - maxPerDay;
    for (var i = capped.length - 1; i >= 0 && excess > 0; i--) {
      final trim = min(excess, capped[i].count - 1);
      capped[i] = CSpec(capped[i].category, capped[i].count - trim,
          target: capped[i].targetMuscles, exclude: capped[i].excludeMuscles);
      excess -= trim;
    }
    return capped;
  }

  static List<PlannedExercise> _selectForSpecs(
    List<CSpec> specs,
    ExerciseRepository repo,
    List<String> equipment,
    String effectiveExp,
    int phase, {
    Set<String>? excludeNames,
    List<String> injuries = const [],
  }) {
    final exercises = <PlannedExercise>[];

    for (final spec in specs) {
      var candidates = repo.query(
        category: spec.category,
        equipment: equipment,
        suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
        foundationalOnly: phase == 1,
        targetMuscles: spec.targetMuscles,
        excludeMuscles: spec.excludeMuscles,
        limit: spec.count + 4,
      );

      // Exclude already-selected exercise names
      if (excludeNames != null && excludeNames.isNotEmpty) {
        candidates = candidates
            .where((c) => !excludeNames.contains(c['name'] as String? ?? ''))
            .toList();
      }

      // Also exclude exercises already picked in this variant
      final pickedNames = exercises.map((e) => e.exerciseName).toSet();
      candidates = candidates
          .where((c) => !pickedNames.contains(c['name'] as String? ?? ''))
          .toList();

      // V3: Injury exclusion filter
      if (injuries.isNotEmpty) {
        candidates = candidates.where((c) {
          final contraindications = c['injury_contraindications'];
          if (contraindications is! List || contraindications.isEmpty) return true;
          // Exclude if any user injury matches any contraindication
          for (final injury in injuries) {
            if (contraindications.any((ci) =>
                ci.toString().toLowerCase() == injury.toLowerCase())) {
              return false;
            }
          }
          return true;
        }).toList();
      }

      final selected = candidates.length <= spec.count
          ? candidates
          : candidates.sublist(0, spec.count);

      for (final ex in selected) {
        exercises.add(_buildExercise(ex));
      }
    }
    return exercises;
  }

  /// Build a PlannedExercise from an exercise map.
  static PlannedExercise _buildExercise(Map<String, dynamic> ex) {
    final equipRaw = ex['equipment_needed'];
    final equipList = equipRaw is List
        ? equipRaw.map((e) => e.toString()).toList()
        : <String>[];

    final musclesRaw = ex['primary_muscles'];
    final muscles = musclesRaw is List
        ? musclesRaw.map((m) => m.toString()).toList()
        : <String>[];

    final cues = ex['coaching_cues'];
    final notes = (cues is List && cues.isNotEmpty) ? cues.first.toString() : null;

    return PlannedExercise(
      exerciseId: ex['id'] as String? ?? '',
      exerciseName: ex['name'] as String? ?? 'Unknown',
      loggingType: ex['logging_type'] as String? ?? 'weight_reps',
      sets: ex['default_sets'] as int? ?? 3,
      reps: ex['default_reps'] as String? ?? '10',
      restSeconds: ex['default_rest_secs'] as int? ?? 60,
      durationSeconds: ex['default_duration_secs'] as int?,
      notes: notes,
      exerciseType: ex['exercise_type'] as String?,
      category: ex['category'] as String?,
      equipmentNeeded: equipList,
      primaryMuscles: muscles,
      variant: 'A',
    );
  }
}
