import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'query_v4_mirror.dart';

enum CascadePickSource {
  attempt1Exact,
  attempt2DropSubFocus,
  attempt3DropTypeAndTarget,
  attempt4DropEquipment,
  universalPool,
  universalPoolPlaceholder,
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
  static CascadeTrace trace(
    List<Map<String, dynamic>> library, {
    required MuscleSlot slot,
    required String equipmentTier,
    required String effectiveExp,
    required int phase,
    required List<String> injuries,
    required Set<String> pickedNames,
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
    );
    attempts.add(_attempt(1, a1Sig, a1Results));
    // pick is always null on attempt 1 (declared at top of method); the
    // null-check is kept symmetric with attempts 2-4 below for readability.
    // ignore: unnecessary_null_comparison
    if (a1Results.isNotEmpty && pick == null) {
      pick = CascadePick(
        a1Results.first['name'] as String,
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
    );
    attempts.add(_attempt(2, a2Sig, a2Results));
    if (a2Results.isNotEmpty && pick == null) {
      pick = CascadePick(
        a2Results.first['name'] as String,
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
    );
    attempts.add(_attempt(3, a3Sig, a3Results));
    if (a3Results.isNotEmpty && pick == null) {
      pick = CascadePick(
        a3Results.first['name'] as String,
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
    );
    attempts.add(_attempt(4, a4Sig, a4Results));
    if (a4Results.isNotEmpty && pick == null) {
      pick = CascadePick(
        a4Results.first['name'] as String,
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
        });
        if (libraryMatch.isNotEmpty) {
          pick = CascadePick(name, CascadePickSource.universalPool);
        } else {
          pick = CascadePick(name, CascadePickSource.universalPoolPlaceholder);
        }
        break;
      }
    }

    return CascadeTrace(slot: slot, attempts: attempts, finalPick: pick);
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
