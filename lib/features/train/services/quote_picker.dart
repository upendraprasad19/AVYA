import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';

import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

class WorkoutQuote {
  final String text;
  final List<String> tags;
  const WorkoutQuote({required this.text, required this.tags});
}

/// Deterministic category-tagged quote picker backed by
/// [assets/data/workout_quotes.json].
///
/// Same (category, seed) always returns the same quote so "View Card" and
/// the post-completion card render identically.
class QuotePicker {
  static List<WorkoutQuote>? _cache;

  static Future<List<WorkoutQuote>> _loadAll() async {
    if (_cache != null) return _cache!;
    final raw =
        await rootBundle.loadString('assets/data/workout_quotes.json');
    final list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
    _cache = list
        .map((m) => WorkoutQuote(
              text: m['text'] as String,
              tags: (m['tags'] as List).cast<String>(),
            ))
        .toList();
    return _cache!;
  }

  /// Pick a quote tagged with [category]. Falls back to 'general' if no
  /// tagged match. Selection is deterministic per [seed].
  static Future<String> pickForCategory({
    required String category,
    required int seed,
  }) async {
    final all = await _loadAll();
    final byCategory =
        all.where((q) => q.tags.contains(category)).toList();
    final pool = byCategory.isNotEmpty
        ? byCategory
        : all.where((q) => q.tags.contains('general')).toList();
    if (pool.isEmpty) {
      return 'Discipline hit. Brain still buffering.';
    }
    final rng = Random(seed);
    return pool[rng.nextInt(pool.length)].text;
  }

  /// Word-boundary keyword match (case-insensitive input is pre-uppercased).
  /// SHORT keywords MUST be word-bounded — bare `.contains('LAT')` matched
  /// mid-word ("test temp**lat**e" → pull → the founder's stray "lat" quote,
  /// Unit 3 obs 2; also "warm-up"→ARM, "leverage"→LEG, "grow"→ROW,
  /// "absolute"→ABS, "grunt"→RUN; "**back**" inside "Kick**back**"→pull,
  /// this batch — "Cable Tricep Kickback" / "Dumbbell Kickback" / "Glute
  /// Kickback" all matched a mid-word `.contains('BACK')`). Long unambiguous
  /// keywords (PULL, PRESS, SQUAT, …) stay substrings so compounds like
  /// "Pulldown" still match.
  ///
  /// The word-boundary fix stops all three Kickback names from wrongly
  /// landing on 'pull', but only "Cable Tricep Kickback" (TRICEP) and "Glute
  /// Kickback" (GLUTE) land on their TRUE category after it — "Dumbbell
  /// Kickback" has no other keyword in this list and falls to 'general'
  /// (accepted residual gap, see the diagnose-doc's `impact_analysis`; a
  /// strict improvement over the pre-fix 'pull', not a full fix).
  static bool _hasWord(String upperName, String pattern) =>
      RegExp(pattern).hasMatch(upperName);

  /// Derive a quote category from a workout name. Falls back to 'general'.
  ///
  /// LEGS is checked FIRST, ahead of PULL/PUSH — deliberately, not
  /// alphabetically. A whole-word-boundary fix on BACK/CURL alone does NOT
  /// fix names like "Barbell Back Squat" or "Leg Curl (Lying)": "Back" and
  /// "Curl" are genuine, correctly-spelled whole words there, so `\bBACK\b`
  /// / `\bCURLS?\b` still match — this is a real cross-category keyword
  /// COLLISION, not a substring bug, and no amount of word-boundary
  /// tightening resolves a collision between two equally-valid whole-word
  /// matches. Verified against the full `assets/data/exercise_library.json`
  /// (this batch, diagnose — see docs/diagnoses/): every name matching BOTH
  /// a pull keyword and a legs keyword resolves correctly once legs wins the
  /// tie — including a PRE-EXISTING, previously-unreported miscategorization
  /// this same audit surfaced: "Leg Press" matched PUSH's `PRESS` keyword
  /// and was never reaching the legs check at all under the old pull→push→
  /// legs order.
  static String categoryForWorkout(String workoutName) {
    final name = workoutName.toUpperCase();
    if (name.contains('SQUAT') || name.contains('LUNGE') ||
        name.contains('GLUTE') || name.contains('QUAD') ||
        name.contains('HAMSTRING') || name.contains('CALF') ||
        _hasWord(name, r'\bLEGS?\b')) {
      return 'legs';
    }
    if (name.contains('PULL') || _hasWord(name, r'\bBACK\b') ||
        name.contains('DEADLIFT') || name.contains('BICEP') ||
        name.contains('CURL') ||
        _hasWord(name, r'\bLATS?\b') || _hasWord(name, r'\bROWS?\b')) {
      return 'pull';
    }
    if (name.contains('PUSH') || name.contains('CHEST') ||
        name.contains('PRESS') || name.contains('SHOULDER') ||
        name.contains('TRICEP')) {
      return 'push';
    }
    if (name.contains('CORE') || name.contains('PLANK') ||
        name.contains('CRUNCH') || _hasWord(name, r'\bABS?\b')) {
      return 'core';
    }
    if (name.contains('CARDIO') || name.contains('HIIT') ||
        name.contains('JUMP') || _hasWord(name, r'\bRUN')) {
      return 'cardio';
    }
    if (name.contains('FULL BODY') || name.contains('FULL-BODY')) {
      return 'full_body';
    }
    if (_hasWord(name, r'\bARMS?\b')) {
      return 'arms';
    }
    return 'general';
  }

  /// Derive a quote category for a SINGLE EXERCISE — library ground truth
  /// first, keyword classifier as the floor.
  ///
  /// The name-keyword classifier alone misclassifies names whose words
  /// disagree with the exercise's real target: "Hanging Leg Raise" is a
  /// CORE exercise (library `category: "core"`, primary muscles Core/
  /// Obliques) but `\bLEGS?\b` matches the "LEG" in its name; "Dumbbell
  /// Fly" is a PUSH exercise (library `category: "push"`,
  /// `horizontal_push`) but matches no PUSH keyword and fell to 'general'.
  /// On a Push + Core day that pair produced a legs=1 vs push=1 tie which
  /// resolved to legs via map insertion order — the founder's "Glute work"
  /// quote on a push day (2026-09-17, diagnose
  /// docs/diagnoses/2026-09-17-quote-library-category-lookup-b7e1f4.md).
  ///
  /// Library categories are already lowercase and 1:1 with the quote tags
  /// (push/pull/legs/core/cardio/full_body; 'flexibility' has no quote pool
  /// and falls through to 'general' quotes in [pickForCategory] — accepted).
  /// Custom exercises stored in the same box carry a CAPITALIZED category
  /// ('Push'), hence the lowercase normalization. Exercises absent from the
  /// box (or a box that is not open — e.g. a widget test without Hive seeded)
  /// fall back to [categoryForWorkout], which is the pre-lookup behavior;
  /// the try/catch is best-effort by design and the library-lookup path
  /// itself is pinned by the Hive-backed sweep test
  /// (`test/contracts/quote_picker_category_from_exercises_test.dart`).
  static String categoryForExercise(String exerciseName) {
    try {
      final raw = ExerciseRepository.instance.getByExactName(exerciseName);
      final cat = (raw?['category'] as String?)?.trim().toLowerCase();
      if (cat != null && cat.isNotEmpty) return cat;
    } catch (_) {
      // Hive unavailable (not initialized / box closed) — keyword floor.
    }
    return categoryForWorkout(exerciseName);
  }

  /// Derive a quote category from the workout's actual EXERCISES, falling back
  /// to the workout name, then 'general'. Exercise names carry the muscle
  /// signal even when the workout has a generic custom name (Unit 3 obs 2 — a
  /// "test template" of pull exercises should get a pull quote, not a
  /// name-derived mismatch). Per-exercise resolution goes through
  /// [categoryForExercise] (library ground truth first — 2026-09-17); the
  /// workout NAME stays keyword-classified, because workout names ("Push +
  /// Core", custom template names) are not exercise-library rows.
  /// Deterministic for a given exercise list (stable insertion order →
  /// stable tie-break), so the post-completion card and the "View Card"
  /// sheet never drift.
  static String categoryForExercises(
    List<String> exerciseNames,
    String workoutName,
  ) {
    final counts = <String, int>{};
    for (final n in exerciseNames) {
      final c = categoryForExercise(n);
      if (c != 'general') counts[c] = (counts[c] ?? 0) + 1;
    }
    if (counts.isNotEmpty) {
      var bestKey = counts.keys.first;
      var bestCount = counts[bestKey]!;
      for (final entry in counts.entries) {
        if (entry.value > bestCount) {
          bestKey = entry.key;
          bestCount = entry.value;
        }
      }
      return bestKey;
    }
    // No specific exercise signal — fall back to the workout name, then general.
    return categoryForWorkout(workoutName);
  }
}
