import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/injury_substitutes.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'query_v4_mirror.dart';

enum CascadePickSource {
  attempt1Exact,
  attempt2DropSubFocus,
  attempt3DropTypeAndTarget,
  attempt4DropEquipment,
  universalPool,
  universalPoolPlaceholder,
  // U2: the whole universal pool for this slot's pattern was contraindicated
  // for the user's injuries → the slot is SAFELY OMITTED (not a bug-`(none)`).
  // Mirrors production `_cascadeFill` returning null after the injury filter.
  safelyOmitted,
}

class CascadeAttempt {
  final int number; // 1..5
  final String signature;
  final int resultCount;
  final List<String> sampleNames; // first 5 result names
  const CascadeAttempt({
    required this.number,
    required this.signature,
    required this.resultCount,
    required this.sampleNames,
  });
}

class CascadePick {
  final String name;
  final CascadePickSource source;
  const CascadePick(this.name, this.source);
}

class CascadeTrace {
  final MuscleSlot slot;
  final List<CascadeAttempt> attempts;
  final CascadePick? finalPick;
  const CascadeTrace({
    required this.slot,
    required this.attempts,
    required this.finalPick,
  });
}

/// Universal bodyweight pool — mirrored verbatim from
/// lib/shared/repositories/plan_engine/exercise_selector.dart:493-505.
/// Any change there must be reflected here.
const _universalPoolV4 = <String, List<String>>{
  'horizontal_push':    ['Push Up', 'Incline Push Up', 'Wall Push Up', 'Decline Push Up', 'Diamond Push Up'],
  'vertical_push':      ['Pike Push Up', 'Handstand Hold', 'Dand (Hindu Pushup)'],
  'horizontal_pull':    ['Inverted Row', 'TRX Row', 'Inverted Row', 'Dead Bug'],
  'vertical_pull':      ['Pull Up', 'Chin Up', 'Inverted Row'],
  'knee_dominant':      ['Baithak (Hindu Squat)', 'Reverse Lunge', 'Bulgarian Split Squat', 'Jump Squat'],
  'hip_dominant':       ['Glute Bridge', 'Single Leg Romanian Deadlift', 'Good Morning'],
  'core':               ['Plank', 'Dead Bug', 'Hollow Body Hold', 'Bicycle Crunch', 'Mountain Climber'],
  'elbow_flexion':      ['Chin Up', 'Inverted Row'],
  'elbow_extension':    ['Diamond Push Up', 'Bench Dips', 'Dip (Parallel Bars)'],
  'shoulder_isolation': ['Pike Push Up', 'Arm Circles', 'Band Pull Apart'],
  'hip_isolation':      ['Glute Bridge', 'Side Plank', 'Glute Bridge'],
};

class CascadeTracer {
  /// Trace ALL 5 attempts; return a full record. Mirrors `_cascadeFill`.
  ///
  /// Unlike production `_cascadeFill` which early-returns on first non-empty
  /// result, this always records every attempt's signature + count so the
  /// trace shows the full fallback path.
  /// ①.1d (Batch 11-C) mirror of `ExerciseSelector._selectCandidate`: pick the
  /// name from a non-empty result list, preferring a curated `InjurySubstitutes`
  /// sub (in map order) when the flag is ON. OFF → `results.first` (verbatim).
  static String _selectCandidateName(
    List<Map<String, dynamic>> results,
    List<String> injuries,
    bool applyInjurySubstitutePreference,
    Set<String> avoidNames, // W3.4 (Batch 11-B mirror)
  ) {
    var pool = results;
    if (applyInjurySubstitutePreference) {
      final prefs = InjurySubstitutes.preferredFor(injuries);
      if (prefs.isNotEmpty) {
        final subs = results
            .where(
                (c) => prefs.contains((c['name'] as String? ?? '').toLowerCase()))
            .toList();
        if (subs.isNotEmpty) {
          subs.sort((a, b) => prefs
              .indexOf((a['name'] as String? ?? '').toLowerCase())
              .compareTo(prefs.indexOf((b['name'] as String? ?? '').toLowerCase())));
          pool = subs;
        }
      }
    }
    return _preferNovelName(pool, avoidNames);
  }

  /// W3.4 (Batch 11-B) mirror of `ExerciseSelector._preferNovel`: first name NOT
  /// in [avoidNames], else `pool.first` ([avoidNames] empty → `pool.first`).
  static String _preferNovelName(
    List<Map<String, dynamic>> pool,
    Set<String> avoidNames,
  ) {
    if (avoidNames.isEmpty) return pool.first['name'] as String;
    for (final c in pool) {
      if (!avoidNames.contains((c['name'] as String? ?? '').toLowerCase())) {
        return c['name'] as String;
      }
    }
    return pool.first['name'] as String;
  }

  static CascadeTrace trace(
    List<Map<String, dynamic>> library, {
    required MuscleSlot slot,
    required String equipmentTier,
    required String effectiveExp,
    required int phase,
    required List<String> injuries,
    required Set<String> pickedNames,
    bool applyInjurySubstitutePreference = false, // ①.1d (Batch 11-C mirror)
    Set<String> avoidNames = const {}, // W3.4 (Batch 11-B mirror; default → no-op)
    Set<String> exclusions = const {}, // ⑥ B1 (mirror; default {} → no-op)
  }) {
    final attempts = <CascadeAttempt>[];
    CascadePick? pick;

    // Attempt 1
    final a1Sig = QueryV4Mirror.signature(
      movementPattern: slot.movementPattern,
      targetFocus: slot.subFocus != null
          ? '${slot.targetMuscle} (${slot.subFocus})'
          : null,
      targetMuscle: slot.targetMuscle,
      equipmentTier: equipmentTier,
      exerciseType: slot.exerciseType,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      foundationalOnly: phase == 1,
      excludeNamesCount: pickedNames.length,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    final a1Results = QueryV4Mirror.query(
      library,
      movementPattern: slot.movementPattern,
      targetFocus: slot.subFocus != null
          ? '${slot.targetMuscle} (${slot.subFocus})'
          : null,
      targetMuscle: slot.targetMuscle,
      equipmentTier: equipmentTier,
      exerciseType: slot.exerciseType,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      foundationalOnly: phase == 1,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
      exclusions: exclusions,
    );
    attempts.add(_attempt(1, a1Sig, a1Results));
    // pick is always null on attempt 1 (declared at top of method); the
    // null-check is kept symmetric with attempts 2-4 below for readability.
    // ignore: unnecessary_null_comparison
    if (a1Results.isNotEmpty && pick == null) {
      pick = CascadePick(
        _selectCandidateName(a1Results, injuries, applyInjurySubstitutePreference, avoidNames),
        CascadePickSource.attempt1Exact,
      );
    }

    // Attempt 2: drop subFocus
    final a2Sig = QueryV4Mirror.signature(
      movementPattern: slot.movementPattern,
      targetMuscle: slot.targetMuscle,
      equipmentTier: equipmentTier,
      exerciseType: slot.exerciseType,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNamesCount: pickedNames.length,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    final a2Results = QueryV4Mirror.query(
      library,
      movementPattern: slot.movementPattern,
      targetMuscle: slot.targetMuscle,
      equipmentTier: equipmentTier,
      exerciseType: slot.exerciseType,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
      exclusions: exclusions,
    );
    attempts.add(_attempt(2, a2Sig, a2Results));
    if (a2Results.isNotEmpty && pick == null) {
      pick = CascadePick(
        _selectCandidateName(a2Results, injuries, applyInjurySubstitutePreference, avoidNames),
        CascadePickSource.attempt2DropSubFocus,
      );
    }

    // Attempt 3: drop target + exerciseType
    final a3Sig = QueryV4Mirror.signature(
      movementPattern: slot.movementPattern,
      equipmentTier: equipmentTier,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNamesCount: pickedNames.length,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    final a3Results = QueryV4Mirror.query(
      library,
      movementPattern: slot.movementPattern,
      equipmentTier: equipmentTier,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
      exclusions: exclusions,
    );
    attempts.add(_attempt(3, a3Sig, a3Results));
    if (a3Results.isNotEmpty && pick == null) {
      pick = CascadePick(
        _selectCandidateName(a3Results, injuries, applyInjurySubstitutePreference, avoidNames),
        CascadePickSource.attempt3DropTypeAndTarget,
      );
    }

    // Attempt 4: drop equipment
    final a4Sig = QueryV4Mirror.signature(
      movementPattern: slot.movementPattern,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNamesCount: pickedNames.length,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    final a4Results = QueryV4Mirror.query(
      library,
      movementPattern: slot.movementPattern,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
      exclusions: exclusions,
    );
    attempts.add(_attempt(4, a4Sig, a4Results));
    if (a4Results.isNotEmpty && pick == null) {
      pick = CascadePick(
        _selectCandidateName(a4Results, injuries, applyInjurySubstitutePreference, avoidNames),
        CascadePickSource.attempt4DropEquipment,
      );
    }

    // Attempt 5: universal pool
    final pool = _universalPoolV4[slot.movementPattern] ?? const <String>[];
    attempts.add(CascadeAttempt(
      number: 5,
      signature: 'universal_pool[${slot.movementPattern}]',
      resultCount: pool.length,
      sampleNames: pool.take(5).toList(),
    ));
    if (pick == null) {
      // U2 mirror of exercise_selector `_cascadeFill` attempt-5: skip a
      // contraindicated pool pick; if the whole pool is contraindicated, the
      // slot is safely omitted (distinct from a bug-`(none)`).
      var poolHadContra = false;
      for (final name in pool) {
        if (pickedNames.contains(name)) continue;
        // Mirror of ExerciseRepository.search (exercise_repository.dart:43-58):
        // case-insensitive substring match on name + name_aliases.
        final q = name.toLowerCase();
        final libraryMatch = library.where((e) {
          final n = (e['name'] as String?)?.toLowerCase() ?? '';
          if (n.contains(q)) return true;
          final aliases = e['name_aliases'];
          if (aliases is List) {
            return aliases.any((a) => a.toString().toLowerCase().contains(q));
          }
          return false;
        }).toList();
        if (libraryMatch.isNotEmpty) {
          // Mirror production: resolve to the EXACT-name record (substring
          // search also matches superstrings), matching the scorecard's
          // exact-name enrichment (generator_matrix byName[name]).
          final resolved = libraryMatch.firstWhere(
            (e) => (e['name'] as String?)?.toLowerCase() == q,
            orElse: () => libraryMatch.first,
          );
          // ⑥ B1 mirror (of exercise_selector att5): skip a pool move requiring
          // excluded equipment. Floor-sanitize guarantees a pure-bodyweight move
          // survives per pattern, so a valid pick always follows — NOT a safety
          // omission, so do not set poolHadContra.
          if (exclusions.isNotEmpty &&
              EquipmentVocab.fromProfile(resolved['equipment_needed'])
                  .any(exclusions.contains)) {
            continue;
          }
          if (_isContraindicated(resolved, injuries)) {
            poolHadContra = true;
            continue;
          }
          pick = CascadePick(name, CascadePickSource.universalPool);
        } else {
          // Un-vettable placeholder — production skips it when injured.
          if (injuries.isNotEmpty) {
            poolHadContra = true;
            continue;
          }
          pick = CascadePick(name, CascadePickSource.universalPoolPlaceholder);
        }
        break;
      }
      if (pick == null && poolHadContra) {
        pick = const CascadePick('(safely omitted)', CascadePickSource.safelyOmitted);
      }
    }

    return CascadeTrace(slot: slot, attempts: attempts, finalPick: pick);
  }

  /// Mirror of exercise_selector `_isContraindicated` / queryV4 injury match:
  /// exact lowercase equality between the exercise's `injury_contraindications`
  /// and the user's (already-canonical) injuries.
  static bool _isContraindicated(
    Map<String, dynamic> ex,
    List<String> injuries,
  ) {
    if (injuries.isEmpty) return false;
    final contra = ex['injury_contraindications'];
    if (contra is! List || contra.isEmpty) return false;
    for (final injury in injuries) {
      final inj = injury.toLowerCase();
      if (contra.any((c) => c.toString().toLowerCase() == inj)) return true;
    }
    return false;
  }

  static CascadeAttempt _attempt(
    int number,
    String signature,
    List<Map<String, dynamic>> results,
  ) {
    return CascadeAttempt(
      number: number,
      signature: signature,
      resultCount: results.length,
      sampleNames: results
          .take(5)
          .map((e) => e['name']?.toString() ?? '?')
          .toList(),
    );
  }
}
