import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/plan_generator.dart';

/// Identifies a specific phase/week/day combination to preview.
class PreviewKey {
  final String phaseNumber; // Roman numeral string, e.g. 'II'
  final int week;           // week within the overall plan (1-12)
  final int day;            // day within the week (1-indexed)

  const PreviewKey(this.phaseNumber, this.week, this.day);

  @override
  bool operator ==(Object other) =>
      other is PreviewKey &&
      other.phaseNumber == phaseNumber &&
      other.week == week &&
      other.day == day;

  @override
  int get hashCode => Object.hash(phaseNumber, week, day);
}

/// Generates a phase preview using the user's actual profile values.
///
/// The PlanGenerator.generateV4 API accepts a [phase] int but always
/// generates 4 weeks of output starting from week 1 of that phase (it
/// doesn't support generating an arbitrary global week in isolation).
/// We call it with the correct phase number derived from [key.phaseNumber],
/// then index into the appropriate week-within-phase and the requested day.
///
/// Phase ↔ week mapping (4 weeks per phase):
///   Phase 1 → weeks 1-4   (week-in-phase = week)
///   Phase 2 → weeks 5-8   (week-in-phase = week - 4)
///   Phase 3 → weeks 9-12  (week-in-phase = week - 8)
///
/// Returns a Map representing the requested WorkoutDay so the screen can
/// render it without importing PlanGenerator types directly.
final previewPlanProvider =
    FutureProvider.family<Map<String, dynamic>, PreviewKey>((ref, key) async {
  final profileBox = HiveService.instance.userBox;
  final profile = profileBox.get('profile') as Map?;
  if (profile == null) {
    throw StateError('User profile not loaded — cannot generate preview.');
  }

  final phaseInt = _romanToInt(key.phaseNumber);

  // Derive week-within-phase (1-4) from the global week number.
  final weekInPhase = key.week - ((phaseInt - 1) * 4);
  // Clamp to a valid 1-4 range if called with unexpected values.
  final safeWeekInPhase = weekInPhase.clamp(1, 4);

  // Day is 1-indexed; clamp to available days.
  final safeDay = key.day.clamp(1, 7);

  final goal = (profile['primary_goal'] as String?) ?? 'general_fitness';
  final equipment = (profile['equipment_access'] as String?) ?? 'full_gym';
  final daysPerWeek = (profile['days_per_week'] as int?) ?? 4;
  // APK Test #3 / Phase exercise count fix: fallback must match
  // onboarding's pre-selected default. APK Test #2 / F6 lesson: a
  // 'beginner' fallback drives VolumeFilter.targetCount(beginner, 5) = 4
  // exercises, but the user's actual plan was built with their
  // 'intermediate' default → 6 exercises. The mismatch is the 6/7/8 vs
  // 8 confusion in roadmap previews. NEVER reset to 'beginner' here.
  final experienceLevel =
      (profile['fitness_experience'] as String?) ?? 'intermediate';

  // Debug-mode loud signal when key fields are missing — prevents the
  // silent default from hiding a profile-shape regression.
  assert(() {
    if (profile['fitness_experience'] == null) {
      // ignore: avoid_print
      print('[previewPlanProvider] WARN — fitness_experience missing on '
          'profile, falling back to "intermediate". If this fires for a '
          'real user post-onboarding, the profile shape has regressed.');
    }
    if (profile['days_per_week'] == null) {
      // ignore: avoid_print
      print('[previewPlanProvider] WARN — days_per_week missing on '
          'profile, falling back to 4.');
    }
    return true;
  }());
  final injuries = (profile['injuries'] as List?)
          ?.whereType<String>()
          .where((s) => s != 'none')
          .toList() ??
      const <String>[];

  // generateV4 runs fully on-device — zero network cost.
  final phase = PlanGenerator.instance.generateV4(
    goal: goal,
    equipment: equipment,
    daysPerWeek: daysPerWeek,
    phase: phaseInt,
    experienceLevel: experienceLevel,
    injuries: injuries,
  );

  // Select the correct week's workout days.
  // phase.weekPlans is a list of 4 WeekPlan objects (one per week in the phase).
  final weekPlanIndex = (safeWeekInPhase - 1).clamp(0, phase.weekPlans.length - 1);
  final weekPlan = phase.weekPlans.isNotEmpty
      ? phase.weekPlans[weekPlanIndex]
      : null;

  final workoutDays = weekPlan?.workoutDays ?? phase.workouts;

  // Resolve the day — day numbers are 1-indexed and may not be contiguous
  // if some are rest days; find by dayNumber first, fall back to index.
  WorkoutDay? workoutDay;
  for (final d in workoutDays) {
    if (d.dayNumber == safeDay) {
      workoutDay = d;
      break;
    }
  }
  // Fallback: use positional index (0-based) when dayNumber doesn't match.
  if (workoutDay == null && workoutDays.isNotEmpty) {
    final idx = (safeDay - 1).clamp(0, workoutDays.length - 1);
    workoutDay = workoutDays[idx];
  }

  if (workoutDay == null) {
    return <String, dynamic>{
      'phase_number': key.phaseNumber,
      'week': key.week,
      'day': key.day,
      'name': 'Rest Day',
      'focus_text': 'Active recovery',
      'exercises': <Map<String, dynamic>>[],
    };
  }

  // Serialize main exercises (exclude warmup / cooldown / finisher — shown
  // separately in the preview so the list isn't cluttered).
  final exercises = workoutDay.exercises.map((e) {
    return <String, dynamic>{
      'name': e.exerciseName,
      'sets': e.sets,
      'reps': e.reps,
      'restSeconds': e.restSeconds,
      'loggingType': e.loggingType,
      'intensityProfile': e.intensityProfile,
      if (e.suggestedWeight != null) 'weightKg': e.suggestedWeight,
      if (e.notes != null) 'notes': e.notes,
    };
  }).toList();

  final totalExercises = exercises.length;
  final totalSets = workoutDay.exercises.fold<int>(0, (sum, e) => sum + e.sets);
  final focusText =
      '${workoutDay.focus} · $totalExercises exercises · $totalSets sets';

  return <String, dynamic>{
    'phase_number': key.phaseNumber,
    'week': key.week,
    'day': key.day,
    'name': workoutDay.name,
    'focus_text': focusText,
    'exercises': exercises,
    'warmup_count': workoutDay.warmup.length,
    'cooldown_count': workoutDay.cooldown.length,
  };
});

int _romanToInt(String roman) {
  const map = <String, int>{
    'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6,
    'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10, 'XI': 11, 'XII': 12,
  };
  return map[roman] ?? 1;
}
