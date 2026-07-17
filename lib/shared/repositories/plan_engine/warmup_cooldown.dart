import 'package:flutter/foundation.dart' show visibleForTesting;

import 'models.dart';
import 'plan_engine_flags.dart';
import 'superset_pairer.dart';

/// Stage 7: Attaches warm-up and cool-down to every workout day.
///
/// Extracted from V2 _WarmupCooldownSelector — logic is identical (plus the
/// U3 injury filter, a1f6c3 sibling — see [_moveInjuries]).
class WarmupCooldownSelector {
  /// U3 (warmup/cooldown injury filter): the injury tokens each FIXED warmup/
  /// cooldown/cardio move loads (canonical InjuryVocab vocabulary).
  ///
  /// - MAIN-cascade-selectable moves (Push Up, Band Pull Apart, Baithak) use
  ///   their EXACT library `injury_contraindications`, so a move is never dropped
  ///   from warmup while the main plan keeps it (Push Up stays for a shoulder
  ///   injury in both — the library tags it wrist-only).
  /// - Warmup/cooldown/cardio-ONLY moves use conservative exercise-science tags,
  ///   because the library UNDER-tags them (most are `injury_contraindications:
  ///   []` despite clearly loading an area). This map deliberately supersedes the
  ///   under-tagged library warmup rows.
  ///
  /// The main-move library under-tagging (e.g. Push Up not shoulder-tagged) is a
  /// separate, deliberate library-audit batch — NOT expanded into this warmup fix.
  static const _moveInjuries = <String, Set<String>>{
    // main-cascade-selectable → library injury_contraindications (verified)
    'Push Up': {'wrist'},
    'Band Pull Apart': <String>{},
    'Baithak (Hindu Squat)': {'hip', 'knee'},
    // warmup/cooldown/cardio-only → conservative
    'Arm Circles': <String>{}, // low-load end-range mobility / rehab, not loading
    'Torso Twists': {'lower_back'},
    'Wall Push Up': {'shoulder', 'wrist', 'elbow'},
    'Wrist Rotations': {'wrist'},
    'Neck Rotations': {'neck'},
    'Dead Hang': {'shoulder', 'wrist', 'elbow'},
    'High Knees': {'knee', 'hip', 'ankle'},
    'Leg Swings': {'hip', 'hamstring'},
    'Hip Circles': {'hip'},
    'Jumping Jacks': {'knee', 'ankle'}, // impact; overhead swing is low-load (cf Arm Circles)
    'Spot Jogging': {'knee', 'ankle'},
    'Jump Rope': {'knee', 'ankle', 'wrist'},
    'Cycling (Stationary)': <String>{}, // low-impact
    'Running (Treadmill)': {'knee', 'ankle', 'hip'},
    'Slow Walking': <String>{}, // universally-safe cooldown / floor anchor
    'Chest Doorway Stretch': {'shoulder'},
    'Cross-body Shoulder Stretch': {'shoulder'},
    'Overhead Stretch': {'shoulder'},
    'Standing Toe Touch': {'lower_back', 'hamstring'},
    'Side Bend Stretch': {'lower_back'},
    'Standing Quad Stretch': {'knee', 'ankle'},
    'Deep Breathing': <String>{}, // universally-safe anchor
    // dead durationMap entries (never emitted today) — mapped for the drift guard
    'Ankle Rotations': {'ankle'},
    'Butt Kicks': {'knee', 'hamstring'},
  };

  /// True when [name] loads any of the user's [injuries] (already lowercased).
  static bool _moveIsContra(String name, Set<String> injuries) {
    if (injuries.isEmpty) return false;
    final contra = _moveInjuries[name];
    if (contra == null || contra.isEmpty) return false;
    return contra.any(injuries.contains);
  }

  /// Every fixed move name that CAN be emitted (cardio + dynamic warmup +
  /// cooldown). Drift-guard surface: a move added to a list without a
  /// [_moveInjuries] entry would silently bypass the injury filter.
  ///
  /// ⚠ Keep this in sync with the emit sites in [attach]: if a NEW emittable
  /// move-list (a whole new source, not just a new entry in the existing
  /// `_bodyweightCardio`/`_gymCardio`/`_dynamicWarmup`/`_cooldownStretches`) is
  /// ever added, add it here too or the drift-guard test goes blind to it.
  @visibleForTesting
  static Set<String> get allFixedMoves => {
        ..._bodyweightCardio,
        ..._gymCardio,
        'Slow Walking',
        for (final tierMap in _dynamicWarmup.values)
          for (final list in tierMap.values) ...list,
        for (final list in _cooldownStretches.values) ...list,
      };

  /// The move names that carry an injury-token mapping.
  @visibleForTesting
  static Set<String> get mappedMoves => _moveInjuries.keys.toSet();

  /// General cardio options (bodyweight — always available).
  static const _bodyweightCardio = ['Spot Jogging', 'Jumping Jacks'];

  /// Additional cardio options when user has gym equipment.
  static const _gymCardio = ['Jump Rope', 'Cycling (Stationary)', 'Running (Treadmill)'];

  /// Dynamic warm-up exercises per dayType, by experience tier.
  static const _dynamicWarmup = <String, Map<String, List<String>>>{
    'push': {
      'beginner': ['Arm Circles', 'Torso Twists', 'Wall Push Up'],
      'advanced': ['Arm Circles', 'Push Up', 'Band Pull Apart'],
    },
    'pull': {
      'beginner': ['Arm Circles', 'Wrist Rotations', 'Neck Rotations'],
      'advanced': ['Arm Circles', 'Dead Hang', 'Neck Rotations'],
    },
    'legs': {
      'beginner': ['High Knees', 'Leg Swings', 'Hip Circles'],
      'advanced': ['High Knees', 'Baithak (Hindu Squat)', 'Leg Swings'],
    },
    'upper': {
      'beginner': ['Arm Circles', 'Torso Twists', 'Wrist Rotations'],
      'advanced': ['Arm Circles', 'Push Up', 'Dead Hang'],
    },
    'full_body': {
      'beginner': ['Jumping Jacks', 'Arm Circles', 'Hip Circles'],
      'advanced': ['High Knees', 'Push Up', 'Baithak (Hindu Squat)'],
    },
    'shoulders_arms': {
      'beginner': ['Arm Circles', 'Wrist Rotations', 'Neck Rotations'],
      'advanced': ['Arm Circles', 'Wrist Rotations', 'Band Pull Apart'],
    },
  };

  /// Static stretch cool-down exercises per dayType.
  static const _cooldownStretches = <String, List<String>>{
    'push': ['Chest Doorway Stretch', 'Cross-body Shoulder Stretch', 'Overhead Stretch'],
    'pull': ['Standing Toe Touch', 'Cross-body Shoulder Stretch', 'Side Bend Stretch'],
    'legs': ['Standing Quad Stretch', 'Standing Toe Touch', 'Side Bend Stretch'],
    'upper': ['Chest Doorway Stretch', 'Standing Toe Touch', 'Cross-body Shoulder Stretch'],
    'full_body': ['Standing Toe Touch', 'Standing Quad Stretch', 'Chest Doorway Stretch'],
    'shoulders_arms': ['Cross-body Shoulder Stretch', 'Overhead Stretch', 'Deep Breathing'],
  };

  /// Attach warm-up and cool-down to every WorkoutDay in every WeekPlan.
  static List<WeekPlan> attach(
    List<WeekPlan> weeks,
    String effectiveExp,
    List<String> equipmentList, {
    List<String> injuries = const [],
    bool? hasGymEquipmentOverride, // ⑥ C2 (WU-2) — generateV4 passes the flag-gated signal; null → old predicate
  }) {
    final isAdvanced = effectiveExp != 'beginner';
    // ⑥ C2 — on the GENERATED path `equipmentList` is item tokens (never 'gym'/'full')
    // so the old predicate is always-false; generateV4 passes the resolved override.
    // A null override (template_service + tier-string test callers) keeps the old
    // predicate → byte-identical.
    final hasGymEquipment = hasGymEquipmentOverride ??
        equipmentList.any(
            (e) => e.toLowerCase().contains('gym') || e.toLowerCase().contains('full'));

    // U3: DROP warmup/cooldown/cardio moves that load a user's injury (canonical
    // InjuryVocab tokens; drop-not-substitute). injuries arrive already normalized
    // from the caller. Default-empty injuries OR the kill-switch → verbatim
    // pre-U3 behavior.
    final injSet = injuries.map((e) => e.toLowerCase()).toSet();
    final filterOn =
        injSet.isNotEmpty && PlanEngineFlags.warmupInjuryFilterEnabled;

    final cardioPool = [..._bodyweightCardio];
    if (hasGymEquipment) cardioPool.addAll(_gymCardio);
    // FLOOR: keep a universally-safe cardio lead-in (Slow Walking) so the warmup
    // is never emptied even when every listed cardio option loads the injury
    // (e.g. a knee-injured bodyweight user — Spot Jogging + Jumping Jacks both drop).
    final safeCardio = filterOn
        ? cardioPool.where((c) => !_moveIsContra(c, injSet)).toList()
        : cardioPool;
    final cardioLead =
        safeCardio.isNotEmpty ? safeCardio : const ['Slow Walking'];

    return weeks.map((week) {
      final days = week.workoutDays.asMap().entries.map((entry) {
        final dayIndex = entry.key;
        final day = entry.value;
        final dayType = SupersetPairer.inferDayType(day);

        // --- WARM-UP ---
        final warmup = <PlannedExercise>[];

        final cardioName = cardioLead[dayIndex % cardioLead.length];
        warmup.add(_timedExercise(cardioName, '300', 'warmup'));

        final tier = isAdvanced ? 'advanced' : 'beginner';
        final dynamicMap = _dynamicWarmup[dayType] ?? _dynamicWarmup['upper']!;
        final dynamicList = dynamicMap[tier] ?? dynamicMap['beginner']!;
        final safeDynamic = filterOn
            ? dynamicList.where((n) => !_moveIsContra(n, injSet)).toList()
            : dynamicList;
        for (final name in safeDynamic) {
          warmup.add(_warmupExercise(name));
        }
        // FLOOR: if filtering emptied the dynamic warmup (multi-injury), keep a
        // universally-safe mobility anchor so it is never just cardio-then-nothing.
        if (filterOn && safeDynamic.isEmpty) {
          warmup.add(_timedExercise('Deep Breathing', '60', 'warmup'));
        }

        // --- COOL-DOWN ---
        final cooldown = <PlannedExercise>[];

        // Slow Walking is unconditionally prepended → the cooldown floor always
        // holds (it is universally-safe, never dropped).
        cooldown.add(_timedExercise('Slow Walking', '300', 'cooldown'));

        final stretches = _cooldownStretches[dayType] ?? _cooldownStretches['upper']!;
        final safeStretches = filterOn
            ? stretches.where((n) => !_moveIsContra(n, injSet)).toList()
            : stretches;
        for (final name in safeStretches) {
          cooldown.add(_timedExercise(name, '30', 'cooldown'));
        }

        return WorkoutDay(
          dayNumber: day.dayNumber,
          name: day.name,
          focus: day.focus,
          exercises: day.exercises,
          warmup: warmup,
          cooldown: cooldown,
          finisher: day.finisher,
        );
      }).toList();

      return WeekPlan(
        weekNumber: week.weekNumber,
        weekInPhase: week.weekInPhase,
        overloadNotes: week.overloadNotes,
        weekCharacter: week.weekCharacter,
        workoutDays: days,
      );
    }).toList();
  }

  static PlannedExercise _timedExercise(String name, String duration, String category) {
    return PlannedExercise(
      exerciseId: name,
      exerciseName: name,
      loggingType: 'timed',
      sets: 1,
      reps: '${duration}s',
      restSeconds: 0,
      category: category,
    );
  }

  static PlannedExercise _warmupExercise(String name) {
    const activationExercises = {
      'Push Up', 'Wall Push Up', 'Baithak (Hindu Squat)', 'Band Pull Apart',
    };
    if (activationExercises.contains(name)) {
      return PlannedExercise(
        exerciseId: name,
        exerciseName: name,
        loggingType: 'bodyweight_reps',
        sets: 1,
        reps: '10',
        restSeconds: 0,
        category: 'warmup',
      );
    }

    if (name == 'Dead Hang') {
      return _timedExercise(name, '30', 'warmup');
    }

    const durationMap = <String, String>{
      'Arm Circles': '60',
      'Neck Rotations': '30',
      'Torso Twists': '60',
      'Hip Circles': '60',
      'Leg Swings': '60',
      'Wrist Rotations': '30',
      'Ankle Rotations': '30',
      'Jumping Jacks': '60',
      'High Knees': '60',
      'Butt Kicks': '60',
      'Spot Jogging': '60',
    };
    final dur = durationMap[name] ?? '60';
    return _timedExercise(name, dur, 'warmup');
  }
}
