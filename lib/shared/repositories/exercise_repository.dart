import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/equipment_capability.dart';

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

  /// Returns the library exercise whose `name` matches [name] EXACTLY
  /// (case-insensitive), or null if none.
  ///
  /// Unlike [search] (pure substring — "Push Up" would resolve to
  /// "Pike Push Up"), this is an exact-equality lookup, so callers that hold
  /// only a display name (e.g. the Active Workout `ExerciseData`, which carries
  /// no id) can safely fetch the full library map — coaching cues, common
  /// mistakes, breathing/warm-up, etc. Returns null for swapped/custom
  /// exercises absent from the library (caller renders nothing).
  Map<String, dynamic>? getByExactName(String name) {
    final target = name.trim().toLowerCase();
    if (target.isEmpty) return null;
    for (final raw in _hive.exerciseBox.values) {
      if (raw is! Map) continue;
      final n = (raw['name'] as String?)?.trim().toLowerCase();
      if (n == target) return Map<String, dynamic>.from(raw);
    }
    return null;
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

  /// True iff [name] resolves (exact-name) to a library exercise whose
  /// `exercise_type` is EXACTLY 'compound'. The shared "main lift" predicate for
  /// the e1RM scans — DeloadE1rmScan (W2.4) + PlateauScan (W3.5) — extracted so
  /// they don't each hand-roll it (the #1 writer/reader-drift class). Custom /
  /// swapped names absent from the library → false (not a main lift).
  bool isCompoundByExactName(String name) {
    final row = getByExactName(name);
    if (row == null) return false;
    return _fieldContains(row['exercise_type'], 'compound');
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
    // ⑥ slice B1: user-excluded equipment (canonical, floor-sanitized tokens).
    // REQUIRED (not optional) so a missed cascade call site fails to COMPILE
    // rather than silently skip the drop — equipment exclusion is a HARD
    // constraint that must reach every pick path. Empty set → inert.
    required Set<String> exclusions,
    // ⑦ OI-89: the user's real capability set, or NULL for "do not enforce".
    // REQUIRED (not defaulted) so a missed call site fails to COMPILE rather
    // than silently skip the drop — same contract as `exclusions` above.
    required Set<String>? capability,
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

      // 2c. Equipment EXCLUSIONS (⑥ slice B1 — pure-exclusion filter). A HARD
      // constraint: drop the exercise iff any item it REQUIRES is one the user
      // excluded. Placed BEFORE the tier block so a no-tier community row (which
      // the tier block passes at the `return true` below) is also subject.
      // Reads crash-safe + normalizing via EquipmentVocab.fromProfile (a
      // bare-String / community / mixed-case equipment_needed can't crash [the
      // e9d1c7 class] and is compared as canonical). Empty set → inert →
      // byte-identical to pre-B1.
      if (exclusions.isNotEmpty) {
        final needed = EquipmentVocab.fromProfile(e['equipment_needed']);
        if (needed.any(exclusions.contains)) return false;
      }

      // 2d. ⑦ OI-89 capability floor. NULL = enforcement OFF (a genuine SKIP).
      // A "universal set" would NOT be inert: canPerform fails CLOSED on an
      // unreadable requirement regardless of what the set contains. Placed here
      // for the same reason as 2c — before the tier block, so a no-tier
      // community row is subject to it too.
      if (capability != null &&
          !EquipmentCapability.canPerform(e['equipment_needed'], capability)) {
        return false;
      }

      // 3. Equipment tier (exercise must include user's tier in its equipment_tier list)
      if (tierLower != null) {
        final tiers = e['equipment_tier'];
        // ⑦ OI-89 seam 5: this was `return true` — an early return from the
        // WHOLE fused predicate, so a row with a missing/empty equipment_tier
        // also skipped filters 4-8 below, INCLUDING the injury exclusion. The
        // tier is genuinely unknown for such a row (community sync writes them),
        // but that is no reason to hand an injured user a contraindicated
        // exercise. Fall through instead of returning.
        if (tiers is List && tiers.isNotEmpty) {
          final hasTier =
              tiers.any((t) => t.toString().toLowerCase() == tierLower);
          if (!hasTier) return false;
        }
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
  ///
  /// Identifies custom exercises by EITHER the legacy `type: 'exercise'`
  /// value field (entries written by `CreateCustomExerciseSheet` /
  /// `WorkoutRepository.createCustomExercise`) OR the canonical Hive
  /// key prefix `custom_exercise_*` (entries restored from cloud via
  /// `SyncService._restoreCustomExercises`, which writes raw
  /// `user_custom_exercises` rows that do NOT carry the `type` field).
  ///
  /// Without the key-prefix fallback, restored custom exercises were
  /// silently invisible to every reader (swap sheet, train screen,
  /// active workout add-exercise picker, template builder) on fresh
  /// installs — bug discovered in APK Test #15.4 post-install when
  /// founder's `Single Leg Front Lever` (created 2026-05-02, present
  /// in cloud row `29aeaa20-...`) returned "No matching exercises
  /// found" in the swap picker after reinstall.
  List<Map<String, dynamic>> getCustomExercises() {
    final customBox = _hive.customBox;
    final results = <Map<String, dynamic>>[];
    for (final key in customBox.keys) {
      final raw = customBox.get(key);
      if (raw is! Map) continue;
      final ex = Map<String, dynamic>.from(raw);
      final isExercise = ex['type'] == 'exercise' ||
          (key is String && key.startsWith('custom_exercise_'));
      if (isExercise) {
        // Inject Hive key as `id` per Gate 16 / feedback_id_must_be_injected_on_get.md.
        // Restored entries from sync_community._restoreCustomExercises do not
        // carry an `id` value field — the deterministic v5 UUID lives in the
        // Hive key (custom_exercise_<uuid>). Without this injection,
        // downstream consumers (swap picker, template builder) see id=null
        // and cannot diff or delete the entry.
        if (ex['id'] == null) {
          ex['id'] = key;
        }
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
