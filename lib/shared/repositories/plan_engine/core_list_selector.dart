// Batch B1 (docs/plans/2026-10-22-library-core-list-pool.md, spec §4): the
// core-list pool. Pure and static — ExerciseSelector._pickCoreList calls
// [CoreListSelector.rankedPool] once per slot when `enable_core_list_pool` is
// ON and the library carries `core_levels`; with the flag OFF nothing here runs.
//
// Every list field read from Hive arrives as List<dynamic>; [_strs] maps it to
// strings before comparing.
import 'package:flutter/foundation.dart';

import '../../../core/utils/equipment_vocab.dart';
import 'equipment_capability.dart';
import 'models.dart';

/// One slot's record in [CoreListTrace].
class CoreListTraceSlot {
  final int day;
  final String variant;
  final MuscleSlot slot;
  final String level;
  /// `core`, `fill`, `drop`, or `emergency` (an any-level core pick, Ruling 12).
  final String source;
  final String? pickedId;
  final int poolSize;
  final bool improvisedRemoved;
  final int nonImprovisedInPool;
  final Set<String> families;
  final String? pickedFamily;
  const CoreListTraceSlot({
    required this.day,
    required this.variant,
    required this.slot,
    required this.level,
    required this.source,
    required this.pickedId,
    required this.poolSize,
    required this.improvisedRemoved,
    required this.nonImprovisedInPool,
    required this.families,
    required this.pickedFamily,
  });
}

/// Provenance of the ON path, written by production code and read only by
/// tests (plan Ruling 9) — not a reimplementation, so not a mirror.
class CoreListTrace {
  int delegations = 0;
  final List<CoreListTraceSlot> slots = [];
  /// (day, variant) whose emptied list copied the other variant's.
  final List<({int day, String variant})> copied = [];
  /// (day, variant) re-run with core rows of ANY level (both variants empty).
  final List<({int day, String variant})> emergencyAnyLevel = [];
  /// (day, variant) that fell back to the OFF cascade (`_fillSlots`).
  final List<({int day, String variant})> refilled = [];
}

class CoreListSelector {
  @visibleForTesting
  static CoreListTrace? debugTrace;

  static const _rank = {'beginner': 0, 'intermediate': 1, 'advanced': 2};

  /// Patterns where an implement row beats an improvised one (OI-387/388).
  static const _implementPatterns = {
    'elbow_flexion',
    'elbow_extension',
    'shoulder_isolation',
    'horizontal_pull',
    'vertical_pull',
  };

  /// What a bodyweight user always has: none, bodyweight and the household
  /// baseline (`EquipmentVocab.tierItems['bodyweight']`).
  static final Set<String> improvisedTokens =
      EquipmentVocab.tierItems['bodyweight']!.toSet();

  static List<String> _strs(Object? v) {
    if (v is List) return [for (final e in v) e.toString()];
    if (v is String) return [v];
    return const [];
  }

  /// True iff any row carries a `core_levels` key. A v12 Hive box has none, so
  /// the ON path delegates to the OFF cascade until the v13 re-seed lands.
  static bool hasCoreFields(Iterable<Map<String, dynamic>> rows) =>
      rows.any((r) => r.containsKey('core_levels'));

  /// True iff the user has any kit beyond the improvised set. Keyed on the
  /// capability set, not the tier label, so a bodyweight user who OWNS
  /// dumbbells gets the implement preference too.
  static bool needsImplementPreference(
      Set<String>? capability, String equipmentTier) {
    final kit = capability ??
        EquipmentVocab.tierItems[equipmentTier]?.toSet() ??
        const <String>{};
    return kit.any((t) => !improvisedTokens.contains(t));
  }

  /// The built exercise's type (OI-385): `compound` / `isolation` when the row
  /// says so anywhere in `exercise_type` (shipped rows list `calisthenics`
  /// first), else the slot's own type.
  static String typeFor(Map<String, dynamic> row, MuscleSlot slot) {
    final types = [for (final t in _strs(row['exercise_type'])) t.toLowerCase()];
    if (types.contains('compound')) return 'compound';
    if (types.contains('isolation')) return 'isolation';
    return slot.exerciseType;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[_/()]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// The ranked candidate list for one slot (plan Task 3, "The rankedPool
  /// algorithm"). `ordered` is empty iff `source == 'drop'`. [anyCoreLevel]
  /// admits core rows of any level and skips family fill (the empty-day
  /// emergency, Ruling 12); a row with `core_levels: []` never enters.
  static ({
    List<Map<String, dynamic>> ordered,
    String source,
    bool improvisedRemoved,
    int nonImprovisedInPool,
    Set<String> families,
  }) rankedPool({
    required List<Map<String, dynamic>> rows,
    required MuscleSlot slot,
    required String level,
    required int phase,
    required String equipmentTier,
    required Set<String>? capability,
    required Set<String> exclusions,
    required bool Function(Map<String, dynamic>) isContraindicated,
    required Set<String> pickedNames,
    required Set<String> demotedNames,
    Set<String> softAvoidNames = const {},
    bool anyCoreLevel = false,
  }) {
    final pattern = slot.movementPattern;
    final muscle = slot.targetMuscle.toLowerCase();
    final tier = equipmentTier.toLowerCase();
    final levelRank = _rank[level] ?? 0;

    bool patternOk(Map<String, dynamic> r) =>
        _strs(r['slot_pattern'] ?? r['movement_pattern']).contains(pattern);
    bool target(Map<String, dynamic> r) =>
        _strs(r['slot_focus'] ?? r['target_focus'])
            .any((l) => l.toLowerCase().contains(muscle)) ||
        _strs(r['primary_muscles']).any((m) => m.toLowerCase().contains(muscle));
    List<String> levels(Map<String, dynamic> r) => _strs(r['core_levels']);

    // 1. Hard filter F.
    bool passes(Map<String, dynamic> r) {
      if (!patternOk(r) || !r.containsKey('core_levels')) return false;
      final discipline = r['discipline'];
      if (discipline == 'calisthenics_skill' || discipline == 'olympic') {
        return false;
      }
      if (capability != null) {
        if (!EquipmentCapability.canPerform(r['equipment_needed'], capability)) {
          return false;
        }
      } else if (tier.isNotEmpty) {
        // queryV4's tier rule (exercise_repository.dart, capability == null).
        final tiers = r['equipment_tier'];
        if (tiers is List &&
            tiers.isNotEmpty &&
            !tiers.any((t) => t.toString().toLowerCase() == tier)) {
          return false;
        }
      }
      if (exclusions.isNotEmpty &&
          EquipmentVocab.fromProfile(r['equipment_needed'])
              .any(exclusions.contains)) {
        return false;
      }
      if (isContraindicated(r)) return false;
      return !pickedNames.contains(r['name']);
    }

    // 2-3. Core pool, else family fill.
    var source = 'core';
    var families = <String>{};
    var pool = [
      for (final r in rows)
        if (passes(r) &&
            target(r) &&
            (anyCoreLevel ? levels(r).isNotEmpty : levels(r).contains(level)))
          r
    ];
    if (pool.isEmpty && !anyCoreLevel) {
      families = {
        for (final r in rows)
          if (patternOk(r) &&
              target(r) &&
              levels(r).contains(level) &&
              r['variant_family'] is String)
            r['variant_family'] as String
      };
      final capLevel =
          level.isEmpty ? level : level[0].toUpperCase() + level.substring(1);
      pool = [
        for (final r in rows)
          if (passes(r) &&
              target(r) &&
              families.contains(r['variant_family']) &&
              !levels(r).any((l) => (_rank[l] ?? 0) <= levelRank) &&
              _strs(r['suitable_for']).contains(capLevel))
            r
      ];
      source = 'fill';
    }
    if (pool.isEmpty) {
      return (
        ordered: const <Map<String, dynamic>>[],
        source: 'drop',
        improvisedRemoved: false,
        nonImprovisedInPool: 0,
        families: families,
      );
    }

    // 4. Improvised filter (OI-387/388), never emptying the pool.
    bool improvised(Map<String, dynamic> r) =>
        EquipmentVocab.fromProfile(r['equipment_needed'])
            .every(improvisedTokens.contains);
    final nonImprovised = pool.where((r) => !improvised(r)).length;
    var improvisedRemoved = false;
    if (needsImplementPreference(capability, equipmentTier) &&
        _implementPatterns.contains(pattern) &&
        nonImprovised > 0 &&
        nonImprovised < pool.length) {
      pool = pool.where((r) => !improvised(r)).toList();
      improvisedRemoved = true;
    }

    // 5. Order: L6 partition, soft avoid, then keys a-e, ties by id.
    final sub = slot.subFocus;
    final subNeedle = sub == null ? null : _norm('${slot.targetMuscle} $sub');
    bool subMatch(Map<String, dynamic> r) {
      if (sub == 'cable') {
        return _strs(r['equipment_needed']).contains('cables');
      }
      if (sub == 'isolation') {
        return _strs(r['exercise_type']).contains('isolation');
      }
      return [
        ..._strs(r['slot_focus'] ?? r['target_focus']),
        ..._strs(r['primary_muscles']),
      ].any((l) => _norm(l).contains(subNeedle!));
    }

    final type = slot.exerciseType.toLowerCase();
    bool foundational(Map<String, dynamic> r) => r['is_foundational'] == true;
    List<int> keys(Map<String, dynamic> r) => [
          demotedNames.contains(r['name']) ? 1 : 0,
          softAvoidNames.contains(r['name']) ? 1 : 0,
          phase == 1 && !foundational(r) ? 1 : 0,
          sub != null && !subMatch(r) ? 1 : 0,
          _strs(r['exercise_type']).any((t) => t.toLowerCase() == type) ? 0 : 1,
          (r['priority_tier'] as num?)?.toInt() ?? 3,
          foundational(r) ? 0 : 1,
        ];
    final keyed = [for (final r in pool) (r, keys(r))];
    keyed.sort((x, y) {
      for (var i = 0; i < x.$2.length; i++) {
        final c = x.$2[i].compareTo(y.$2[i]);
        if (c != 0) return c;
      }
      return (x.$1['id'] ?? '').toString().compareTo((y.$1['id'] ?? '').toString());
    });
    return (
      ordered: [for (final k in keyed) k.$1],
      source: source,
      improvisedRemoved: improvisedRemoved,
      nonImprovisedInPool: nonImprovised,
      families: families,
    );
  }
}
