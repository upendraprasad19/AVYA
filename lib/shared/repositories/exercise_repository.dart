import 'package:icanbefitter/core/services/hive_service.dart';

/// Queries the exerciseBox (seeded from bundled JSON).
///
/// All reads are local Hive lookups — zero network latency.
class ExerciseRepository {
  ExerciseRepository._();
  static final ExerciseRepository _instance = ExerciseRepository._();
  static ExerciseRepository get instance => _instance;

  final HiveService _hive = HiveService.instance;

  /// Returns all exercises as a list of maps.
  List<Map<String, dynamic>> getAll() {
    final box = _hive.exerciseBox;
    return box.values
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Returns a single exercise by its [id], or null.
  Map<String, dynamic>? getById(String id) {
    final raw = _hive.exerciseBox.get(id);
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Returns exercises filtered by [category].
  ///
  /// Categories: Push, Pull, Legs, Core, Cardio, Flexibility,
  /// Calisthenics, Indian Traditional.
  List<Map<String, dynamic>> getByCategory(String category) {
    return getAll()
        .where((e) =>
            (e['category'] as String?)?.toLowerCase() ==
            category.toLowerCase())
        .toList();
  }

  /// Full-text search across exercise name and name_aliases.
  ///
  /// Case-insensitive substring match.
  List<Map<String, dynamic>> search(String query) {
    if (query.isEmpty) return getAll();

    final q = query.toLowerCase();
    return getAll().where((e) {
      final name = (e['name'] as String?)?.toLowerCase() ?? '';
      if (name.contains(q)) return true;

      final aliases = e['name_aliases'];
      if (aliases is List) {
        for (final alias in aliases) {
          if (alias.toString().toLowerCase().contains(q)) return true;
        }
      }
      return false;
    }).toList();
  }

  /// Returns exercises matching the given filters.
  ///
  /// Used by [PlanGenerator] to select exercises for workout plans.
  ///
  /// - [category] — exercise category (Push, Pull, Legs, etc.)
  /// - [equipment] — user's available equipment
  /// - [difficulty] — max difficulty level
  /// - [suitableFor] — experience level the exercise is suitable for
  /// - [limit] — max results to return
  List<Map<String, dynamic>> query({
    String? category,
    List<String>? equipment,
    String? difficulty,
    String? suitableFor,
    int? limit,
    bool foundationalOnly = false,
    List<String>? targetMuscles,
    List<String>? excludeMuscles,
  }) {
    var results = getAll();

    if (category != null) {
      results = results
          .where((e) =>
              (e['category'] as String?)?.toLowerCase() ==
              category.toLowerCase())
          .toList();
    }

    if (equipment != null && equipment.isNotEmpty) {
      final equipLower = equipment.map((e) => e.toLowerCase()).toSet();
      results = results.where((e) {
        final needed = e['equipment_needed'];
        if (needed == null) return true; // bodyweight
        if (needed is List) {
          // Exercise is usable if ALL its required equipment is in user's set.
          return needed.every((item) {
            final lower = item.toString().toLowerCase();
            return equipLower.contains(lower) ||
                lower == 'none' ||
                lower == 'bodyweight';
          });
        }
        return true;
      }).toList();
    }

    if (suitableFor != null) {
      results = results.where((e) {
        final suitable = e['suitable_for'];
        if (suitable == null) return true;
        if (suitable is List) {
          return suitable.any(
            (s) => s.toString().toLowerCase() == suitableFor.toLowerCase(),
          );
        }
        return true;
      }).toList();
    }

    if (foundationalOnly) {
      results = results
          .where((e) => e['is_foundational'] == true)
          .toList();
    }

    // Filter by target muscles: exercise must have at least one primary_muscle
    // that contains any of the target muscle strings (case-insensitive).
    if (targetMuscles != null && targetMuscles.isNotEmpty) {
      final targets =
          targetMuscles.map((m) => m.toLowerCase()).toList();
      results = results.where((e) {
        final muscles = e['primary_muscles'];
        if (muscles is! List || muscles.isEmpty) return false;
        return muscles.any((m) {
          final ml = m.toString().toLowerCase();
          return targets.any((t) => ml.contains(t));
        });
      }).toList();
    }

    // Exclude exercises whose primary_muscles match any excluded muscle string.
    if (excludeMuscles != null && excludeMuscles.isNotEmpty) {
      final excludes =
          excludeMuscles.map((m) => m.toLowerCase()).toList();
      results = results.where((e) {
        final muscles = e['primary_muscles'];
        if (muscles is! List || muscles.isEmpty) return true;
        return !muscles.any((m) {
          final ml = m.toString().toLowerCase();
          return excludes.any((ex) => ml.contains(ex));
        });
      }).toList();
    }

    // Sort compounds first.
    results.sort((a, b) {
      final aType = a['exercise_type']?.toString().toLowerCase() ?? '';
      final bType = b['exercise_type']?.toString().toLowerCase() ?? '';
      if (aType == 'compound' && bType != 'compound') return -1;
      if (aType != 'compound' && bType == 'compound') return 1;
      return 0;
    });

    if (limit != null && results.length > limit) {
      results = results.sublist(0, limit);
    }

    return results;
  }

  /// V4: Query exercises by movement pattern, target focus, and equipment tier.
  ///
  /// Used by the cascading exercise selector. Filters are applied in order:
  /// movement_pattern (required) → target_focus (optional) → equipment_tier
  /// (optional) → exercise_type (optional) → suitable_for (optional).
  List<Map<String, dynamic>> queryV4({
    required String movementPattern,
    String? targetFocus,
    String? targetMuscle,
    String? equipmentTier,
    String? exerciseType,
    String? suitableFor,
    bool foundationalOnly = false,
    Set<String>? excludeNames,
    List<String>? injuryExclusions,
    int? limit,
  }) {
    var results = getAll();

    // 1. Movement pattern (ALWAYS applied — never dropped)
    results = results.where((e) =>
        (e['movement_pattern'] as String?)?.toLowerCase() ==
        movementPattern.toLowerCase()).toList();

    // 2. Target focus (substring match on target_focus field)
    if (targetFocus != null && targetFocus.isNotEmpty) {
      final tf = targetFocus.toLowerCase();
      results = results.where((e) {
        final focus = (e['target_focus'] as String?)?.toLowerCase() ?? '';
        return focus.contains(tf);
      }).toList();
    }

    // 2b. Target muscle (broader — matches if target_focus contains the muscle name)
    if (targetMuscle != null && targetMuscle.isNotEmpty) {
      final tm = targetMuscle.toLowerCase();
      results = results.where((e) {
        final focus = (e['target_focus'] as String?)?.toLowerCase() ?? '';
        final muscles = e['primary_muscles'];
        if (focus.contains(tm)) return true;
        if (muscles is List) {
          return muscles.any((m) => m.toString().toLowerCase().contains(tm));
        }
        return false;
      }).toList();
    }

    // 3. Equipment tier (exercise must include user's tier in its equipment_tier list)
    if (equipmentTier != null && equipmentTier.isNotEmpty) {
      final tier = equipmentTier.toLowerCase();
      results = results.where((e) {
        final tiers = e['equipment_tier'];
        if (tiers is! List || tiers.isEmpty) return true;
        return tiers.any((t) => t.toString().toLowerCase() == tier);
      }).toList();
    }

    // 4. Exercise type (compound / isolation)
    if (exerciseType != null && exerciseType.isNotEmpty) {
      results = results.where((e) =>
          (e['exercise_type'] as String?)?.toLowerCase() ==
          exerciseType.toLowerCase()).toList();
    }

    // 5. Suitable for (experience level)
    if (suitableFor != null) {
      results = results.where((e) {
        final suitable = e['suitable_for'];
        if (suitable == null) return true;
        if (suitable is List) {
          return suitable.any(
            (s) => s.toString().toLowerCase() == suitableFor.toLowerCase(),
          );
        }
        return true;
      }).toList();
    }

    // 6. Foundational only (Phase 1)
    if (foundationalOnly) {
      results = results.where((e) => e['is_foundational'] == true).toList();
    }

    // 7. Exclude already-selected names
    if (excludeNames != null && excludeNames.isNotEmpty) {
      results = results.where((e) =>
          !excludeNames.contains(e['name'] as String? ?? '')).toList();
    }

    // 8. Injury exclusion
    if (injuryExclusions != null && injuryExclusions.isNotEmpty) {
      results = results.where((e) {
        final contra = e['injury_contraindications'];
        if (contra is! List || contra.isEmpty) return true;
        for (final injury in injuryExclusions) {
          if (contra.any((c) =>
              c.toString().toLowerCase() == injury.toLowerCase())) {
            return false;
          }
        }
        return true;
      }).toList();
    }

    // Sort: compounds first, then by priority_tier, then foundational first
    results.sort((a, b) {
      final aType = a['exercise_type']?.toString().toLowerCase() ?? '';
      final bType = b['exercise_type']?.toString().toLowerCase() ?? '';
      if (aType == 'compound' && bType != 'compound') return -1;
      if (aType != 'compound' && bType == 'compound') return 1;
      final aPri = a['priority_tier'] as int? ?? 3;
      final bPri = b['priority_tier'] as int? ?? 3;
      if (aPri != bPri) return aPri.compareTo(bPri);
      final aFound = a['is_foundational'] == true ? 0 : 1;
      final bFound = b['is_foundational'] == true ? 0 : 1;
      return aFound.compareTo(bFound);
    });

    if (limit != null && results.length > limit) {
      results = results.sublist(0, limit);
    }

    return results;
  }

  /// Returns all user-created custom exercises from the customBox.
  List<Map<String, dynamic>> getCustomExercises() {
    final customBox = _hive.customBox;
    final results = <Map<String, dynamic>>[];
    for (final raw in customBox.values) {
      if (raw is! Map) continue;
      final ex = Map<String, dynamic>.from(raw);
      if (ex['type'] == 'exercise') {
        results.add(ex);
      }
    }
    return results;
  }

  /// Returns all distinct categories present in the exercise library.
  List<String> getCategories() {
    final categories = <String>{};
    for (final e in getAll()) {
      final cat = e['category'] as String?;
      if (cat != null) categories.add(cat);
    }
    return categories.toList()..sort();
  }
}
