/// Pure-Dart mirror of `ExerciseRepository.queryV4`.
///
/// Operates on an in-memory list of exercise maps (loaded via LibraryLoader).
/// Used by the V4 diagnostic harness to avoid pulling in Hive + HiveService
/// in a unit-test context.
///
/// The filter order and semantics MUST stay in sync with
/// lib/shared/repositories/exercise_repository.dart:177-295 — any change there
/// requires an equivalent change here + an updated spot-check test.
class QueryV4Mirror {
  /// Returns true if [field] (String or List of String) contains [value] (case-insensitive exact).
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

  static List<Map<String, dynamic>> query(
    List<Map<String, dynamic>> source, {
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
    var results = List<Map<String, dynamic>>.from(source);

    // 1. Movement pattern — ALWAYS applied
    results = results.where((e) =>
        _fieldContains(e['movement_pattern'], movementPattern)).toList();

    // 2. Target focus (substring match)
    if (targetFocus != null && targetFocus.isNotEmpty) {
      results = results.where((e) =>
          _fieldSubstringMatch(e['target_focus'], targetFocus)).toList();
    }

    // 2b. Target muscle (broader)
    if (targetMuscle != null && targetMuscle.isNotEmpty) {
      results = results.where((e) {
        if (_fieldSubstringMatch(e['target_focus'], targetMuscle)) return true;
        final muscles = e['primary_muscles'];
        if (muscles is List) {
          final tm = targetMuscle.toLowerCase();
          return muscles.any((m) => m.toString().toLowerCase().contains(tm));
        }
        return false;
      }).toList();
    }

    // 3. Equipment tier
    if (equipmentTier != null && equipmentTier.isNotEmpty) {
      final tier = equipmentTier.toLowerCase();
      results = results.where((e) {
        final tiers = e['equipment_tier'];
        if (tiers is! List || tiers.isEmpty) return true;
        return tiers.any((t) => t.toString().toLowerCase() == tier);
      }).toList();
    }

    // 4. Exercise type
    if (exerciseType != null && exerciseType.isNotEmpty) {
      results = results.where((e) =>
          _fieldContains(e['exercise_type'], exerciseType)).toList();
    }

    // 5. Suitable for
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

    // 6. Foundational only
    if (foundationalOnly) {
      results = results.where((e) => e['is_foundational'] == true).toList();
    }

    // 7. Exclude names
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

    // Sort: compounds first, then priority_tier asc, then foundational first
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

  /// Build a short filter signature string for trace logs.
  static String signature({
    required String movementPattern,
    String? targetFocus,
    String? targetMuscle,
    String? equipmentTier,
    String? exerciseType,
    String? suitableFor,
    bool foundationalOnly = false,
    int? excludeNamesCount,
    List<String>? injuryExclusions,
  }) {
    final parts = <String>['mp=$movementPattern'];
    if (targetFocus != null) parts.add('tf="$targetFocus"');
    if (targetMuscle != null) parts.add('tm="$targetMuscle"');
    if (equipmentTier != null) parts.add('eq=$equipmentTier');
    if (exerciseType != null) parts.add('type=$exerciseType');
    parts.add('suit=${suitableFor ?? "any"}');
    if (foundationalOnly) parts.add('foundational=true');
    if (excludeNamesCount != null && excludeNamesCount > 0) {
      parts.add('excluded=$excludeNamesCount');
    }
    if (injuryExclusions != null && injuryExclusions.isNotEmpty) {
      parts.add('injuries=${injuryExclusions.join(",")}');
    }
    return parts.join(', ');
  }
}
