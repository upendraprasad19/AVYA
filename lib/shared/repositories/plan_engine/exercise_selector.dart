import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';

import '../exercise_repository.dart';
import 'models.dart';
import 'training_history_analyzer.dart';

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
    'push':           ['Push Up', 'Incline Push Up', 'Pike Push Up', 'Decline Push Up', 'Wall Push Up'],
    'pull':           ['Inverted Row', 'TRX Row', 'Inverted Row', 'Plank', 'Dead Bug'],
    'legs':           ['Baithak (Hindu Squat)', 'Reverse Lunge', 'Glute Bridge', 'Single Leg Romanian Deadlift', 'Standing Calf Raise'],
    'upper':          ['Push Up', 'Pike Push Up', 'Inverted Row', 'Plank', 'Inverted Row'],
    'shoulders_arms': ['Pike Push Up', 'Handstand Hold', 'Inverted Row', 'Plank', 'Plank'],
    'full_body':      ['Push Up', 'Inverted Row', 'Baithak (Hindu Squat)', 'Plank', 'Glute Bridge'],
  };

  /// Timed universal names.
  static const _timedUniversal = <String>{
    'Plank', 'Dead Bug', 'Hollow Body Hold', 'Side Plank',
    'Handstand Hold', 'Copenhagen Plank',
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

    // Inject Baithak (Hindu Squat) if no squat variant present
    if (!names.any((n) => n.contains('squat'))) {
      final squat = repo.search('Baithak (Hindu Squat)');
      if (squat.isNotEmpty) {
        result.insert(0, _buildExercise(squat.first));
      } else {
        result.insert(0, PlannedExercise(
          exerciseId: 'baithak_hindu_squat',
          exerciseName: 'Baithak (Hindu Squat)',
          loggingType: 'bodyweight_reps',
          sets: 3, reps: '10', restSeconds: 60,
          category: 'Legs',
          equipmentNeeded: const ['bodyweight'],
        ));
      }
    }

    // Inject Push Up if no push-up variant present
    if (!names.any((n) => n.contains('push-up') || n.contains('push up') || n.contains('pushup'))) {
      final pushup = repo.search('Push Up');
      if (pushup.isNotEmpty) {
        result.insert(1, _buildExercise(pushup.first));
      } else {
        result.insert(1, PlannedExercise(
          exerciseId: 'push_up',
          exerciseName: 'Push Up',
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
        final rawType = c['exercise_type'];
        final type = rawType is List ? (rawType.isNotEmpty ? rawType.first.toString() : '') : (rawType as String? ?? '');
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

  // ── V4: Muscle-slot architecture ─────────────────────────────────

  /// V4 universal bodyweight pool — keyed by movement pattern.
  /// Used as Attempt 5 (last resort) in the cascade.
  static const universalPoolV4 = <String, List<String>>{
    'horizontal_push':    ['Push Up', 'Incline Push Up', 'Wall Push Up', 'Decline Push Up', 'Diamond Push Up'],
    'vertical_push':      ['Pike Push Up', 'Handstand Hold', 'Dand (Hindu Pushup)'],
    'horizontal_pull':    ['Inverted Row', 'TRX Row', 'Inverted Row', 'Dead Bug'],
    'vertical_pull':      ['Pull Up', 'Chin Up', 'Inverted Row'],
    'knee_dominant':      ['Baithak (Hindu Squat)', 'Reverse Lunge', 'Bulgarian Split Squat', 'Jump Squat'],
    'hip_dominant':       ['Glute Bridge', 'Single Leg Romanian Deadlift', 'Good Morning'],
    'core':               ['Plank', 'Dead Bug', 'Hollow Body Hold', 'Bicycle Crunch', 'Mountain Climber'],
    'elbow_flexion':      ['Chin Up', 'Inverted Row'],
    'elbow_extension':    ['Diamond Push Up', 'Bench Dips', 'Dip (Parallel Bars)'],
    'shoulder_isolation': ['Pike Push Up', 'Arm Circles', 'Band Pull Apart'],
    'hip_isolation':      ['Glute Bridge', 'Side Plank', 'Glute Bridge'],
  };

  /// V4: Pick exercises for MuscleSlotDays using 5-attempt cascading fallback.
  /// movement_pattern is NEVER dropped across all 5 attempts.
  static List<PopulatedDay> pickV4({
    required List<MuscleSlotDay> slotDays,
    required ExerciseRepository exerciseRepo,
    required String equipmentTier,
    required String effectiveExp,
    required int phase,
    required String goal,
    List<String> injuries = const [],
    // U2 kill-switch (§4.6, platform tier): when true (default), attempt-5
    // universal-pool picks are injury-filtered like attempts 1-4. false =
    // verbatim pre-U2 behavior (pool bypasses the injury filter). Default ON is
    // fail-safe — a caller that forgets the flag still gets the safe path.
    bool applyInjuryUniversalFilter = true,
    // ⑥ slice B1: user-excluded equipment (canonical, floor-sanitized). Default
    // `const {}` (unset caller / flag OFF) → every downstream drop inert →
    // byte-identical. A HARD constraint threaded to every pick path.
    Set<String> exclusions = const {},
  }) {
    final result = <PopulatedDay>[];

    // 2026-05-31 personalization levers L2 + L6 — read history ONCE per
    // generation (Phase 2+ only; empty/no-op for Phase 1 or no data). These
    // feed a SUPPLEMENTARY post-selection adjustment pass (see
    // `_applyHistoryAdjustments`), deliberately kept OUT of the 5-attempt
    // cascade so the 0-fallback (attempt3/universalPool/none) target is
    // preserved — the cascade still picks library exercises first; we only
    // reshuffle/append afterward.
    final demoted = phase >= 2
        ? TrainingHistoryAnalyzer.demotedExercises()
        : const <String>{};
    final customs = phase >= 2
        ? _eligibleCustomExercises(exerciseRepo)
        : const <Map<String, dynamic>>[];

    for (final day in slotDays) {
      // Fill variant A
      var exercisesA = _fillSlots(
        day.slotsA, exerciseRepo, equipmentTier, effectiveExp, phase,
        injuries: injuries, excludeNames: {},
        applyInjuryUniversalFilter: applyInjuryUniversalFilter,
        exclusions: exclusions,
      );

      // Fill variant B: use slotsB if defined, exclude A names for variety
      List<PlannedExercise> exercisesB;
      if (day.slotsB != null) {
        final aNames = exercisesA.map((e) => e.exerciseName).toSet();
        exercisesB = _fillSlots(
          day.slotsB!, exerciseRepo, equipmentTier, effectiveExp, phase,
          injuries: injuries, excludeNames: goal == 'strength' ? {} : aNames,
          applyInjuryUniversalFilter: applyInjuryUniversalFilter,
          exclusions: exclusions,
        );
      } else {
        exercisesB = exercisesA;
      }

      // 2026-05-31 personalization L2/L6 — supplementary post-pass.
      if (phase >= 2 && (demoted.isNotEmpty || customs.isNotEmpty)) {
        exercisesA = _applyHistoryAdjustments(
          exercisesA, day.slotsA, exerciseRepo, equipmentTier, effectiveExp,
          phase, injuries, demoted, customs,
          exclusions: exclusions,
        );
        if (!identical(exercisesB, exercisesA) && day.slotsB != null) {
          exercisesB = _applyHistoryAdjustments(
            exercisesB, day.slotsB!, exerciseRepo, equipmentTier, effectiveExp,
            phase, injuries, demoted, customs,
            exclusions: exclusions,
          );
        } else {
          exercisesB = exercisesA;
        }
      }

      result.add(PopulatedDay(
        name: day.name, focus: day.focus,
        dayType: day.dayType, intensity: day.intensity,
        exercisesA: exercisesA, exercisesB: exercisesB,
      ));
    }
    return result;
  }

  /// ⑧ 8-A / UNIT 2-cap (W2.5 repeat-content) — build [PopulatedDay]s from a
  /// PINNED exercise SELECTION instead of the [pickV4] cascade.
  ///
  /// "Repeat the last phase" is implemented as: reuse the prior phase's exercise
  /// NAMES, slotted into the CURRENT-profile split [frames], then let the normal
  /// generateV4 tail run — so stage-0 [ProgressionResolver.resolve] re-decays the
  /// ACTUAL last-logged weight BY NAME and periodization re-applies the wave. A
  /// raw plan-blob copy would instead re-decay an already-cooked `suggested_weight`
  /// (double-decay) AND bypass the injury/equipment filters that live INSIDE the
  /// cascade. Pinning only the SELECTION avoids both.
  ///
  /// Each day carries BOTH variant-A names (weeks 1 & 3) AND variant-B names
  /// (weeks 2 & 4): the split alternates anterior/posterior emphasis across weeks
  /// and [PeriodizationEngine] reads `exercisesB` for the B-weeks
  /// (`useB = !is6Day && weekIdx∈{1,3}`), so a naive single-list `B == A` would make
  /// a repeat's weeks 2/4 DUPLICATE weeks 1/3. When a day supplies no B names, B is
  /// derived the way [pickV4] does — a fresh B-variant fill when `slotsB != null`,
  /// else `B == A` (:557-566) — never a collapse.
  ///
  /// Because this bypasses [pickV4], it re-applies the two HARD constraints
  /// (safety + explicit-lack) queryV4 attempts 1-4 enforce — but NOT the soft
  /// equipment-TIER match:
  ///  - equipment-exclusion    (exercise_repository.dart:282-285) — the user's
  ///    explicit `equipment_exclusions` (items they lack); a HARD constraint the
  ///    cascade keeps even at att4.
  ///  - injury contraindication (exercise_repository.dart:324-334) — applied
  ///    UNGATED. att1-4 always drops a contraindicated pick when injuries are
  ///    present; the `applyInjuryUniversalFilter` kill-switch governs ONLY the
  ///    att-5 universal pool, not this primary-path filter. A user who added an
  ///    injury since the prior phase must never get the old contraindicated lift
  ///    repeated. (This deviates from the pre-implementation plan note, which
  ///    mirrored att-5's gated skip — the wrong reference for a pin.)
  ///  - equipment-TIER is deliberately NOT re-applied: it is a SOFT selection
  ///    heuristic the cascade itself RELAXES at attempt-4 (a shallow slot can be
  ///    filled by an off-tier move), so re-filtering would silently DROP a
  ///    same-tier att4 pick from a faithful repeat. Cross-tier faithfulness is the
  ///    CALLER's contract: UNIT 2-int gates the repeat on the prior phase's
  ///    equipment-tier being UNCHANGED (alongside goal + daysPerWeek), so a
  ///    tier-inappropriate pin never reaches here. Mirrors ⑥ B1's "equipment_tier
  ///    filter UNTOUCHED" exclusion contract.
  ///
  /// A pinned name is resolved to its EXACT library row
  /// ([ExerciseRepository.getByExactName]) or, failing that, the user's matching
  /// custom exercise; a name absent from BOTH is DROPPED. If a variant ends up
  /// empty (every pin dropped), it FRESH-FILLS via the normal [pickV4] cascade for
  /// that single frame — so a repeat day degrades to at worst the SAME safe
  /// slot-omission a fresh generation would produce, never a bespoke `(none)`.
  ///
  /// Day-cardinality: [frames] come from the CURRENT profile's daysPerWeek; pinned
  /// entries map BY INDEX. A frame with no pinned entry (days↑) fresh-fills; pinned
  /// entries beyond `frames.length` (days↓) are dropped.
  ///
  /// SHIP-DARK: reached only when a caller passes `pinnedExercisesByDay` to
  /// generateV4 (none does in 8-A — inert; the `null` branch is byte-identical).
  /// The repeat is faithful only when the prior phase's goal + daysPerWeek + tier
  /// match the current profile (`intensity`/`dayType` come from the current frame)
  /// — the caller (UNIT 2-int) gates on that.
  static List<PopulatedDay> buildPinnedDays({
    required List<MuscleSlotDay> frames,
    required Map<int, ({List<String> a, List<String> b})> pinnedByDay,
    required ExerciseRepository exerciseRepo,
    required String equipmentTier,
    required String effectiveExp,
    required int phase,
    required String goal,
    List<String> injuries = const [],
    bool applyInjuryUniversalFilter = true,
    Set<String> exclusions = const {},
  }) {
    final result = <PopulatedDay>[];
    // Custom exercises are scanned at most ONCE (lazily, on the first library miss).
    List<Map<String, dynamic>>? customsCache;
    List<Map<String, dynamic>> customs() =>
        customsCache ??= exerciseRepo.getCustomExercises();

    // Resolve a pinned NAME list → built exercises, re-applying the HARD filters the
    // cascade (queryV4 att1-4) enforces: equipment-EXCLUSION + UNGATED injury. Tier
    // is NOT re-applied (soft/att4-relaxed; the caller guarantees same-tier). A name
    // absent from BOTH the library and the user's customs is dropped.
    List<PlannedExercise> resolve(List<String> names) {
      final picked = <PlannedExercise>[];
      final seen = <String>{}; // per-variant dedupe
      for (final name in names) {
        final lower = name.trim().toLowerCase();
        if (lower.isEmpty || !seen.add(lower)) continue;
        Map<String, dynamic>? row = exerciseRepo.getByExactName(name);
        var isCustom = false;
        if (row == null) {
          for (final c in customs()) {
            if ((c['name'] as String?)?.trim().toLowerCase() == lower) {
              row = c;
              isCustom = true;
              break;
            }
          }
        }
        if (row == null) continue; // absent library + custom → drop the pin.
        // 1. equipment-exclusion (exercise_repository.dart:282-285).
        if (exclusions.isNotEmpty &&
            EquipmentVocab.fromProfile(row['equipment_needed'])
                .any(exclusions.contains)) {
          continue;
        }
        // 2. injury (exercise_repository.dart:324-334) — UNGATED (see docstring).
        if (_isContraindicated(row, injuries)) continue;
        picked.add(
          isCustom ? _buildCustomExercise(row, 'A') : _buildExercise(row),
        );
      }
      return picked;
    }

    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      final pins = pinnedByDay[i];

      // A fresh single-frame cascade, computed at most once per frame — for the MF-1
      // empty-variant fill AND the B-variant fallback (so weeks 2/4 never collapse
      // onto weeks 1/3). pickV4 emits exactly one PopulatedDay per slotDay.
      PopulatedDay? freshCache;
      PopulatedDay fresh() => freshCache ??= pickV4(
            slotDays: [frame],
            exerciseRepo: exerciseRepo,
            equipmentTier: equipmentTier,
            effectiveExp: effectiveExp,
            phase: phase,
            goal: goal,
            injuries: injuries,
            applyInjuryUniversalFilter: applyInjuryUniversalFilter,
            exclusions: exclusions,
          ).first;

      // Variant A (weeks 1 & 3). Empty (all pins dropped) → fresh-fill (MF-1).
      var exercisesA = resolve(pins?.a ?? const []);
      if (exercisesA.isEmpty) exercisesA = fresh().exercisesA;

      // Variant B (weeks 2 & 4). Prefer the pinned B; else derive it the way pickV4
      // does — a fresh B-variant when slotsB≠null (NEVER `B = A`, which would
      // duplicate weeks 1/3), or B==A when the split has no B-slots (:557-566).
      final bNames = pins?.b ?? const <String>[];
      List<PlannedExercise> exercisesB;
      if (bNames.isNotEmpty) {
        exercisesB = resolve(bNames);
        if (exercisesB.isEmpty) {
          exercisesB = frame.slotsB != null ? fresh().exercisesB : exercisesA;
        }
      } else if (frame.slotsB == null) {
        exercisesB = exercisesA;
      } else {
        exercisesB = fresh().exercisesB;
      }

      result.add(PopulatedDay(
        name: frame.name,
        focus: frame.focus,
        dayType: frame.dayType,
        intensity: frame.intensity,
        exercisesA: exercisesA,
        exercisesB: exercisesB,
      ));
    }

    return result;
  }

  // ── 2026-05-31 personalization levers L2 + L6 ─────────────────────

  /// Supplementary post-selection adjustment (runs AFTER the cascade has fully
  /// populated a day). Two effects, both ADDITIVE / reshuffling — never starves
  /// the cascade:
  ///
  ///   L6 (demote swapped-out): if a cascade-picked exercise is in [demoted]
  ///   (the user previously swapped away from it) AND a non-demoted alternative
  ///   in the SAME movement pattern exists in the library pool (and isn't
  ///   already picked), swap to the alternative. If no clean alternative exists
  ///   we keep the original — we never drop a slot.
  ///
  ///   L2 (custom exercises in pool): append the user's matching
  ///   `custom_exercise_*` entries as SUPPLEMENTARY options for the day when
  ///   their muscle intent matches a slot on the day. Never replaces a library
  ///   pick — purely additive at the tail.
  ///
  /// Implemented as a post-pass (not inside `_cascadeFill`) on purpose: keeping
  /// L2/L6 out of the cascade guarantees the `sample_plans_report.dart`
  /// 0-fallback target is unaffected (custom data is empty in that harness, and
  /// the demote-swap only ever exchanges one library pick for another).
  static List<PlannedExercise> _applyHistoryAdjustments(
    List<PlannedExercise> picked,
    List<MuscleSlot> slots,
    ExerciseRepository repo,
    String equipmentTier,
    String effectiveExp,
    int phase,
    List<String> injuries,
    Set<String> demoted,
    List<Map<String, dynamic>> customs, {
    required Set<String> exclusions, // ⑥ B1 (compile-enforced thread)
  }) {
    final result = List<PlannedExercise>.from(picked);
    final pickedNames = result.map((e) => e.exerciseName).toSet();

    // L6: try to replace each demoted pick with a same-movement-pattern
    // non-demoted library alternative.
    if (demoted.isNotEmpty) {
      for (var i = 0; i < result.length; i++) {
        final ex = result[i];
        if (!demoted.contains(ex.exerciseName)) continue;

        // Find the slot whose movement pattern this pick most likely served.
        final pattern = _patternForPick(ex, slots);
        if (pattern == null) continue;

        final alternatives = repo.queryV4(
          movementPattern: pattern,
          equipmentTier: equipmentTier,
          suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
          excludeNames: pickedNames,
          injuryExclusions: injuries.isEmpty ? null : injuries,
          exclusions: exclusions,
        );
        for (final c in alternatives) {
          final name = c['name'] as String? ?? '';
          if (name.isEmpty || demoted.contains(name)) continue;
          // Swap to the non-demoted alternative.
          final replacement = _buildExercise(c).copyWith(variant: ex.variant);
          result[i] = replacement;
          pickedNames.remove(ex.exerciseName);
          pickedNames.add(name);
          break;
        }
      }
    }

    // L2: append eligible customs that match a slot on this day.
    if (customs.isNotEmpty) {
      final dayMuscles = <String>{};
      for (final s in slots) {
        dayMuscles.add(s.targetMuscle.toLowerCase());
        if (s.subFocus != null) dayMuscles.add(s.subFocus!.toLowerCase());
      }
      for (final custom in customs) {
        final name = custom['name'] as String? ?? '';
        if (name.isEmpty || pickedNames.contains(name)) continue;
        final cm = _muscleTokens(custom['primary_muscles']);
        final matches = cm.any(
          (m) => dayMuscles.any((d) => d.contains(m) || m.contains(d)),
        );
        if (!matches) continue;
        // ⑥ B1: don't auto-append a custom exercise requiring excluded equipment
        // — a user who excluded 'barbell' shouldn't get their barbell custom
        // appended (consistency with "I don't have this now"). Empty set → inert.
        if (exclusions.isNotEmpty &&
            EquipmentVocab.fromProfile(custom['equipment_needed'])
                .any(exclusions.contains)) {
          continue;
        }
        result.add(_buildCustomExercise(custom, result.first.variant));
        pickedNames.add(name);
      }
    }

    return result;
  }

  /// The movement pattern a cascade-picked exercise most likely served, found
  /// by matching the pick's category/muscles back to a slot on the day. Returns
  /// null when no confident match exists (then L6 leaves the pick untouched).
  static String? _patternForPick(PlannedExercise ex, List<MuscleSlot> slots) {
    final muscles = (ex.primaryMuscles ?? const [])
        .map((m) => m.toLowerCase())
        .toList();
    for (final s in slots) {
      final target = s.targetMuscle.toLowerCase();
      if (muscles.any((m) => m.contains(target) || target.contains(m))) {
        return s.movementPattern;
      }
    }
    // Fallback: a single-slot day, or no muscle metadata — use first slot.
    return slots.isNotEmpty ? slots.first.movementPattern : null;
  }

  /// User custom exercises eligible to supplement a plan (have a name + at
  /// least one primary muscle). Empty when there are no customs.
  static List<Map<String, dynamic>> _eligibleCustomExercises(
    ExerciseRepository repo,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final c in repo.getCustomExercises()) {
      final name = c['name'] as String? ?? '';
      if (name.isEmpty) continue;
      if (_muscleTokens(c['primary_muscles']).isEmpty) continue;
      out.add(c);
    }
    return out;
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

  /// Build a PlannedExercise from a user `custom_exercise_*` map (L2). Custom
  /// maps use `default_logging_type` (sheet field) or `logging_type`.
  static PlannedExercise _buildCustomExercise(
    Map<String, dynamic> c,
    String variant,
  ) {
    final equipRaw = c['equipment_needed'];
    final equipList = equipRaw is List
        ? equipRaw.map((e) => e.toString()).toList()
        : <String>[];
    final muscles = _muscleTokens(c['primary_muscles']);
    return PlannedExercise(
      exerciseId: c['id'] as String? ?? '',
      exerciseName: c['name'] as String? ?? 'Custom',
      loggingType: c['default_logging_type'] as String? ??
          c['logging_type'] as String? ??
          'weight_reps',
      sets: c['default_sets'] as int? ?? 3,
      reps: (c['default_reps'] ?? '10').toString(),
      restSeconds: c['default_rest_secs'] as int? ?? 60,
      durationSeconds: c['default_duration_seconds'] as int?,
      category: c['category'] as String?,
      equipmentNeeded: equipList,
      primaryMuscles: muscles.isEmpty ? null : muscles,
      variant: variant,
    );
  }

  /// Fill a list of MuscleSlots with exercises via 5-attempt cascade.
  static List<PlannedExercise> _fillSlots(
    List<MuscleSlot> slots,
    ExerciseRepository repo,
    String equipmentTier,
    String effectiveExp,
    int phase, {
    required List<String> injuries,
    required Set<String> excludeNames,
    bool applyInjuryUniversalFilter = true,
    required Set<String> exclusions, // ⑥ B1 (required — compile-enforced thread)
  }) {
    final exercises = <PlannedExercise>[];
    final pickedNames = Set<String>.from(excludeNames);

    for (final slot in slots) {
      for (var i = 0; i < slot.count; i++) {
        final exercise = _cascadeFill(
          slot, repo, equipmentTier, effectiveExp, phase,
          injuries: injuries, pickedNames: pickedNames,
          applyInjuryUniversalFilter: applyInjuryUniversalFilter,
          exclusions: exclusions,
        );
        if (exercise != null) {
          exercises.add(exercise);
          pickedNames.add(exercise.exerciseName);
        }
      }
    }
    return exercises;
  }

  /// 5-attempt cascade for a single MuscleSlot.
  /// movement_pattern is NEVER dropped.
  static PlannedExercise? _cascadeFill(
    MuscleSlot slot,
    ExerciseRepository repo,
    String equipmentTier,
    String effectiveExp,
    int phase, {
    required List<String> injuries,
    required Set<String> pickedNames,
    bool applyInjuryUniversalFilter = true,
    required Set<String> exclusions, // ⑥ B1 (required — compile-enforced thread)
  }) {
    // Attempt 1: Exact target + subFocus + equipment + type + experience
    var candidates = repo.queryV4(
      movementPattern: slot.movementPattern,
      targetFocus: slot.subFocus != null
          ? '${slot.targetMuscle} (${slot.subFocus})'
          : null,
      targetMuscle: slot.targetMuscle,
      equipmentTier: equipmentTier,
      exerciseType: slot.exerciseType,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      foundationalOnly: phase == 1,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
      exclusions: exclusions,
    );
    if (candidates.isNotEmpty) return _buildExercise(candidates.first);

    // Attempt 2: Drop subFocus (broader target within same muscle)
    candidates = repo.queryV4(
      movementPattern: slot.movementPattern,
      targetMuscle: slot.targetMuscle,
      equipmentTier: equipmentTier,
      exerciseType: slot.exerciseType,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
      exclusions: exclusions,
    );
    if (candidates.isNotEmpty) return _buildExercise(candidates.first);

    // Attempt 3: Drop target + exercise type (any exercise in movement pattern with equipment)
    candidates = repo.queryV4(
      movementPattern: slot.movementPattern,
      equipmentTier: equipmentTier,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
      exclusions: exclusions,
    );
    if (candidates.isNotEmpty) return _buildExercise(candidates.first);

    // Attempt 4: Drop equipment TIER (allow any tier in the movement pattern).
    // ⑥ B1: the exclusion filter is KEPT here — a dropped TIER is a soft
    // curation heuristic, but an EXCLUDED item is a hard "user lacks it"
    // constraint. att5's floor-sanitized bodyweight pool is the safe catch.
    candidates = repo.queryV4(
      movementPattern: slot.movementPattern,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
      exclusions: exclusions,
    );
    if (candidates.isNotEmpty) return _buildExercise(candidates.first);

    // Attempt 5: Universal bodyweight pool.
    // U2 (injury safety): the pool bypasses queryV4, so — unlike attempts 1-4 —
    // it must apply the injury-contraindication exclusion itself, or a
    // contraindicated bodyweight move (e.g. Pike Push Up for a shoulder injury)
    // can still be handed to an injured user here. If EVERY pool move for this
    // pattern is contraindicated, the slot is SAFELY OMITTED (return null) —
    // fewer-but-safe beats injuring the user. The Batch-0 measurement harness
    // (cascade_tracer + scorecard) mirrors this filter and distinguishes a safe
    // omission from a bug-`(none)`.
    final pool = universalPoolV4[slot.movementPattern] ?? [];
    for (final name in pool) {
      if (pickedNames.contains(name)) continue;
      final matches = repo.search(name);
      if (matches.isNotEmpty) {
        // repo.search is a SUBSTRING match, so a pool name like "Push Up" also
        // matches "Pike Push Up" / "Incline Push Up". Resolve to the EXACT-name
        // record so the injury check AND the built exercise are the intended
        // pool move — not an accidental superstring (which could otherwise flip
        // the safety verdict or build the wrong exercise). Falls back to the
        // first substring match when the pool name has no exact library row.
        final resolved = matches.firstWhere(
          (m) => (m['name'] as String?)?.toLowerCase() == name.toLowerCase(),
          orElse: () => matches.first,
        );
        // ⑥ B1 (mirror the U2 injury skip): the att5 pool bypasses queryV4, so
        // it must apply the equipment-exclusion drop itself — else a pool move
        // requiring excluded equipment (e.g. Pull Up ['pull-up bar'] for a
        // pull-up-bar-excluding user) leaks. Floor-sanitize guarantees ≥1
        // pure-bodyweight move per movement_pattern, so a skip NEVER empties the
        // slot — it just prefers the bodyweight fallback (Inverted Row over Pull
        // Up). Empty set → inert.
        if (exclusions.isNotEmpty &&
            EquipmentVocab.fromProfile(resolved['equipment_needed'])
                .any(exclusions.contains)) {
          continue; // skip an excluded-equipment pool pick, try the next
        }
        if (applyInjuryUniversalFilter &&
            _isContraindicated(resolved, injuries)) {
          continue; // skip contraindicated pool pick, try the next
        }
        return _buildExercise(resolved);
      }
      // Not in the library: a hardcoded placeholder move whose contraindications
      // we cannot inspect. When the user has injuries and the filter is on, skip
      // the un-vettable placeholder rather than risk an unsafe move.
      if (applyInjuryUniversalFilter && injuries.isNotEmpty) continue;
      return _buildUniversalFallback(name, 'A');
    }

    // No on-target OR injury-safe universal pick — slot safely omitted (a null
    // cascade result is skipped by the caller, shortening that day). Reachable
    // ONLY when applyInjuryUniversalFilter is on AND the whole pool is
    // contraindicated; with an empty injury list this stays "should never happen".
    return null;
  }

  /// True when [ex]'s `injury_contraindications` intersects [injuries].
  /// Mirrors the queryV4 injury match (exercise_repository.dart:288-294): exact
  /// lowercase equality on canonical tokens. Callers pass an already-canonical
  /// injury list (InjuryVocab.normalize upstream).
  static bool _isContraindicated(
    Map<String, dynamic> ex,
    List<String> injuries,
  ) {
    if (injuries.isEmpty) return false;
    final contra = ex['injury_contraindications'];
    if (contra is! List || contra.isEmpty) return false;
    for (final injury in injuries) {
      final inj = injury.toLowerCase();
      if (contra.any((c) => c.toString().toLowerCase() == inj)) return true;
    }
    return false;
  }

  /// Build a PlannedExercise from an exercise map.
  static String? _extractFirst(dynamic field) {
    if (field is List) return field.isNotEmpty ? field.first.toString() : null;
    return field as String?;
  }

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

    // V4: carry exercise-specific rep range through the pipeline
    final repRange = ex['rep_range'] as String?;

    return PlannedExercise(
      exerciseId: ex['id'] as String? ?? '',
      exerciseName: ex['name'] as String? ?? 'Unknown',
      loggingType: ex['logging_type'] as String? ?? 'weight_reps',
      sets: ex['default_sets'] as int? ?? 3,
      reps: ex['default_reps'] as String? ?? '10',
      restSeconds: ex['default_rest_secs'] as int? ?? 60,
      durationSeconds: ex['default_duration_secs'] as int?,
      notes: notes,
      exerciseType: _extractFirst(ex['exercise_type']),
      category: ex['category'] as String?,
      equipmentNeeded: equipList,
      primaryMuscles: muscles,
      variant: 'A',
      repRange: repRange,
    );
  }
}
