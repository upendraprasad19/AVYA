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

  /// Derive a quote category from a workout name. Falls back to 'general'.
  static String categoryForWorkout(String workoutName) {
    final name = workoutName.toUpperCase();
    if (name.contains('PULL') || name.contains('BACK') ||
        name.contains('ROW') || name.contains('DEADLIFT') ||
        name.contains('BICEP') || name.contains('CURL') ||
        name.contains('LAT')) {
      return 'pull';
    }
    if (name.contains('PUSH') || name.contains('CHEST') ||
        name.contains('PRESS') || name.contains('SHOULDER') ||
        name.contains('TRICEP')) {
      return 'push';
    }
    if (name.contains('LEG') || name.contains('SQUAT') ||
        name.contains('LUNGE') || name.contains('GLUTE') ||
        name.contains('QUAD') || name.contains('HAMSTRING') ||
        name.contains('CALF')) {
      return 'legs';
    }
    if (name.contains('CORE') || name.contains('ABS') ||
        name.contains('PLANK') || name.contains('CRUNCH')) {
      return 'core';
    }
    if (name.contains('CARDIO') || name.contains('RUN') ||
        name.contains('HIIT') || name.contains('JUMP')) {
      return 'cardio';
    }
    if (name.contains('FULL BODY') || name.contains('FULL-BODY')) {
      return 'full_body';
    }
    if (name.contains('ARM') || name.contains('BICEP') ||
        name.contains('TRICEP')) {
      return 'arms';
    }
    return 'general';
  }
}
