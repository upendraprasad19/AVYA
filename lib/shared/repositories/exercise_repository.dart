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
  ///
  /// gate16-exempt: seed-data read. The exercise JSON already carries
  /// its `id` field (stable seed identifier); the Hive key equals the
  /// id. No re-injection needed.
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
    // Precompute normalized values for filter predicates
    final equipLower = equipment != null && equipment.isNotEmpty
        ? equipment.map((e) => e.toLowerCase()).toSet()
        : null;
    final suitableLower = suitableFor?.toLowerCase();
    final targetLower =
        targetMuscles != null && targetMuscles.isNotEmpty
            ? targetMuscles.map((m) => m.toLowerCase()).toList()
            : null;
    final excludeLower =
        excludeMuscles != null && excludeMuscles.isNotEmpty
            ? excludeMuscles.map((m) => m.toLowerCase()).toList()
            : null;
    final categoryLower = category?.toLowerCase();

    // Single fused filter predicate
    var results = getAll().where((e) {
      // 1. Category filter
      if (categoryLower != null) {
        final eCat = (e['category'] as String?)?.toLowerCase();
        if (eCat != categoryLower) return false;
      }

      // 2. Equipment filter
      if (equipLower != null) {
        final needed = e['equipment_needed'];
        if (needed != null && needed is List) {
          // Exercise is usable if ALL its required equipment is in user's set.
          final hasAllEquip = needed.every((item) {
            final lower = item.toString().toLowerCase();
            return equipLower.contains(lower) ||
                lower == 'none' ||
                lower == 'bodyweight';
          });
          if (!hasAllEquip) return false;
        }
      }

      // 3. Suitable for filter
      if (suitableLower != null) {
        final suitable = e['suitable_for'];
        if (suitable is List) {
          final hasSuitable = suitable.any(
            (s) => s.toString().toLowerCase() == suitableLower,
          );
          if (!hasSuitable) return false;
        } else if (suitable != null) {
          return false;
        }
      }

      // 4. Foundational only filter
      if (foundationalOnly && e['is_foundational'] != true) {
        return false;
      }

      // 5. Target muscles filter
      if (targetLower != null) {
        final muscles = e['primary_muscles'];
        if (muscles is! List || muscles.isEmpty) return false;
        final hasTarget = muscles.any((m) {
          final ml = m.toString().toLowerCase();
          return targetLower.any((t) => ml.contains(t));
        });
        if (!hasTarget) return false;
      }

      // 6. Exclude muscles filter
      if (excludeLower != null) {
        final muscles = e['primary_muscles'];
        if (muscles is List && muscles.isNotEmpty) {
          final hasExcluded = muscles.any((m) {
            final ml = m.toString().toLowerCase();
            return excludeLower.any((ex) => ml.contains(ex));
          });
          if (hasExcluded) return false;
        }
      }

      return true;
    }).toList();

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

  /// Returns true if [field] (String or List of String) contains [value] (exact, case-insensitive).
  static bool _fieldContains(dynamic field, String value) {
    final v = value.toLowerCase();
    if (field is List) return field.any((e) => e.toString().toLowerCase() == v);
    return (field as String?)?.toLowerCase() == v;
  }

  /// Returns true if any element in [field] (String or List of String) contains [substring] (case-insensitive).
  static bool _fieldSubstringMatch(dynamic field, String substring) {
    final s = substring.toLowerCase();
    if (field is List) return field.any((e) => e.toString().toLowerCase().contains(s));
    return ((field as String?)?.toLowerCase() ?? '').contains(s);
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
    // Precompute normalized values for filter predicates
    final tierLower = equipmentTier?.isNotEmpty == true
        ? equipmentTier!.toLowerCase()
        : null;
    final suitableLower = suitableFor?.toLowerCase();
    final injuryLower = injuryExclusions != null && injuryExclusions.isNotEmpty
        ? injuryExclusions.map((i) => i.toLowerCase()).toList()
        : null;

    // Single fused filter predicate
    var results = getAll().where((e) {
      // 1. Movement pattern (ALWAYS applied — never dropped)
      if (!_fieldContains(e['movement_pattern'], movementPattern)) return false;

      // 2. Target focus (substring match on target_focus field)
      if (targetFocus != null && targetFocus.isNotEmpty) {
        if (!_fieldSubstringMatch(e['target_focus'], targetFocus)) return false;
      }

      // 2b. Target muscle (broader — matches if target_focus contains the muscle name)
      if (targetMuscle != null && targetMuscle.isNotEmpty) {
        if (!_fieldSubstringMatch(e['target_focus'], targetMuscle)) {
          final muscles = e['primary_muscles'];
          if (muscles is List) {
            final tm = targetMuscle.toLowerCase();
            final hasTarget = muscles.any(
              (m) => m.toString().toLowerCase().contains(tm),
            );
            if (!hasTarget) return false;
          } else {
            return false;
          }
        }
      }

      // 3. Equipment tier (exercise must include user's tier in its equipment_tier list)
      if (tierLower != null) {
        final tiers = e['equipment_tier'];
        if (tiers is! List || tiers.isEmpty) {
          return true; // No tier specified on exercise, pass
        }
        final hasTier =
            tiers.any((t) => t.toString().toLowerCase() == tierLower);
        if (!hasTier) return false;
      }

      // 4. Exercise type (compound / isolation)
      if (exerciseType != null && exerciseType.isNotEmpty) {
        if (!_fieldContains(e['exercise_type'], exerciseType)) return false;
      }

      // 5. Suitable for (experience level)
      if (suitableLower != null) {
        final suitable = e['suitable_for'];
        if (suitable is List) {
          final hasSuitable = suitable.any(
            (s) => s.toString().toLowerCase() == suitableLower,
          );
          if (!hasSuitable) return false;
        } else if (suitable != null) {
          return false;
        }
      }

      // 6. Foundational only (Phase 1)
      if (foundationalOnly && e['is_foundational'] != true) return false;

      // 7. Exclude already-selected names
      if (excludeNames != null && excludeNames.isNotEmpty) {
        if (excludeNames.contains(e['name'] as String? ?? '')) return false;
      }

      // 8. Injury exclusion
      if (injuryLower != null) {
        final contra = e['injury_contraindications'];
        if (contra is List && contra.isNotEmpty) {
          for (final injury in injuryLower) {
            if (contra.any((c) => c.toString().toLowerCase() == injury)) {
              return false;
            }
          }
        }
      }

      return true;
    }).toList();

    // Sort: compounds first, then by priority_tier, then foundational first
    results.sort((a, b) {
      final aCompound = _fieldContains(a['exercise_type'], 'compound');
      final bCompound = _fieldContains(b['exercise_type'], 'compound');
      if (aCompound && !bCompound) return -1;
      if (!aCompound && bCompound) return 1;
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
