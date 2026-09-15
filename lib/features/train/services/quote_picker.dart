import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';

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
  /// "absolute"→ABS, "grunt"→RUN). Long unambiguous keywords (PULL, PRESS,
  /// SQUAT, …) stay substrings so compounds like "Pulldown" still match.
  static bool _hasWord(String upperName, String pattern) =>
      RegExp(pattern).hasMatch(upperName);

  /// Derive a quote category from a workout name. Falls back to 'general'.
  static String categoryForWorkout(String workoutName) {
    final name = workoutName.toUpperCase();
    if (name.contains('PULL') || name.contains('BACK') ||
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
    if (name.contains('SQUAT') || name.contains('LUNGE') ||
        name.contains('GLUTE') || name.contains('QUAD') ||
        name.contains('HAMSTRING') || name.contains('CALF') ||
        _hasWord(name, r'\bLEGS?\b')) {
      return 'legs';
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

  /// Derive a quote category from the workout's actual EXERCISES, falling back
  /// to the workout name, then 'general'. Exercise names carry the muscle
  /// signal even when the workout has a generic custom name (Unit 3 obs 2 — a
  /// "test template" of pull exercises should get a pull quote, not a
  /// name-derived mismatch). Deterministic for a given exercise list (stable
  /// insertion order → stable tie-break), so the post-completion card and the
  /// "View Card" sheet never drift.
  static String categoryForExercises(
    List<String> exerciseNames,
    String workoutName,
  ) {
    final counts = <String, int>{};
    for (final n in exerciseNames) {
      final c = categoryForWorkout(n);
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
