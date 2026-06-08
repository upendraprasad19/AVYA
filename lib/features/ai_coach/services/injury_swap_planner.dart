import 'package:icanbefitter/core/utils/ist_date.dart';

import '../../../core/services/hive_service.dart';

/// One planned swap for a single date.
class InjurySwap {
  final String date; // YYYY-MM-DD
  final String fromId;
  final String fromName;
  final String toId;
  final String toName;

  const InjurySwap({
    required this.date,
    required this.fromId,
    required this.fromName,
    required this.toId,
    required this.toName,
  });
}

/// Plans exercise swaps for a `modify_workout_for_injury` intent.
///
/// Reads scheduled workouts (Hive workoutBox) + exercise library
/// (Hive exerciseBox) to find safe substitutes that don't load the
/// affected body part.
///
/// Two-phase contract with the dispatcher:
///   1. [InjuryModifyDiff] calls [plan] then [cacheSwaps] in initState.
///   2. On user Confirm, the dispatcher reads [getCachedSwaps] and executes.
///   3. [clearCache] is called after execution (success or fail).
class InjurySwapPlanner {
  InjurySwapPlanner._();
  static final InjurySwapPlanner instance = InjurySwapPlanner._();

  final Map<String, List<InjurySwap>> _cache = {};

  /// Compute the list of swaps required to modify the next [daysAhead] days.
  /// Returns an empty list if no upcoming exercises hit the affected body part.
  Future<List<InjurySwap>> plan({
    required String bodyPart,
    required String severity,
    required int daysAhead,
  }) async {
    final swaps = <InjurySwap>[];
    final today = DateTime.now();
    final affectedMuscles = _affectedMusclesForBodyPart(bodyPart);
    if (affectedMuscles.isEmpty) return swaps;

    for (var i = 0; i < daysAhead; i++) {
      final d = today.add(Duration(days: i));
      final dateStr = istDateStr(d);
      final raw = HiveService.instance.workoutBox.get('schedule_$dateStr');
      if (raw is! Map) continue;
      if (raw['status'] == 'completed') continue;

      final exercisesRaw = raw['exercises'];
      if (exercisesRaw is! List) continue;

      for (final ex in exercisesRaw) {
        if (ex is! Map) continue;
        final exId = (ex['exercise_id'] ?? ex['exercise_name'] ?? '')
            .toString();
        final exName = (ex['exercise_name'] ?? exId).toString();
        if (exId.isEmpty) continue;

        if (_exerciseHitsMuscles(ex, affectedMuscles)) {
          // Enrich the exercise lookup with library data — schedule entries
          // sometimes don't have primary_muscles populated. If the library
          // entry exists and disagrees, trust the richer library data.
          final libEntry = _resolveLibraryEntry(exId);
          if (libEntry != null &&
              !_exerciseHitsMuscles(libEntry, affectedMuscles)) {
            continue;
          }

          final sub = _findSubstitute(
            fromId: exId,
            category: (ex['category'] ?? libEntry?['category'])?.toString(),
            avoidMuscles: affectedMuscles,
          );
          if (sub != null) {
            swaps.add(InjurySwap(
              date: dateStr,
              fromId: exId,
              fromName: exName,
              toId: sub.id,
              toName: sub.name,
            ));
          }
        } else {
          // Schedule entry didn't have muscle data — check the library entry.
          final libEntry = _resolveLibraryEntry(exId);
          if (libEntry != null &&
              _exerciseHitsMuscles(libEntry, affectedMuscles)) {
            final sub = _findSubstitute(
              fromId: exId,
              category: libEntry['category']?.toString(),
              avoidMuscles: affectedMuscles,
            );
            if (sub != null) {
              swaps.add(InjurySwap(
                date: dateStr,
                fromId: exId,
                fromName: exName,
                toId: sub.id,
                toName: sub.name,
              ));
            }
          }
        }
      }
    }
    return swaps;
  }

  void cacheSwaps(String intentId, List<InjurySwap> swaps) {
    _cache[intentId] = swaps;
  }

  List<InjurySwap>? getCachedSwaps(String intentId) => _cache[intentId];

  void clearCache(String intentId) => _cache.remove(intentId);

  // ---- helpers ----

  /// Map a top-level body part to the muscle / category names that the
  /// exercise library uses. Lower-cased substring matching is used downstream.
  Set<String> _affectedMusclesForBodyPart(String bodyPart) {
    switch (bodyPart) {
      case 'shoulder':
        return {'shoulder', 'rear delt', 'front delt', 'lateral delt', 'rotator cuff', 'delt'};
      case 'elbow':
        return {'biceps', 'triceps', 'forearm'};
      case 'wrist':
        return {'forearm', 'wrist'};
      case 'lower_back':
        return {'lower back', 'erector', 'spinal erector'};
      case 'upper_back':
        return {'upper back', 'trap', 'lat', 'rhomboid'};
      case 'knee':
        return {'quad', 'hamstring', 'knee'};
      case 'ankle':
        return {'calf', 'calves', 'ankle'};
      case 'hip':
        return {'hip', 'glute', 'hip flexor'};
      case 'neck':
        return {'neck', 'trap'};
      case 'chest':
        return {'chest', 'pec'};
      case 'hamstring':
        return {'hamstring'};
      case 'quad':
        return {'quad', 'quadricep'};
      case 'calf':
        return {'calf', 'calves'};
      default:
        return {};
    }
  }

  /// Returns true if the exercise (schedule entry OR library entry) loads
  /// any of the [affectedMuscles] (case-insensitive substring match).
  bool _exerciseHitsMuscles(Map ex, Set<String> affectedMuscles) {
    final muscles = <String>[];
    final pm = ex['primary_muscles'];
    if (pm is List) {
      muscles.addAll(pm.map((e) => e.toString().toLowerCase()));
    }
    final sm = ex['secondary_muscles'];
    if (sm is List) {
      muscles.addAll(sm.map((e) => e.toString().toLowerCase()));
    }
    final mg = ex['muscle_group'];
    if (mg is String) muscles.add(mg.toLowerCase());
    final cat = ex['category'];
    if (cat is String) muscles.add(cat.toLowerCase());
    final tf = ex['target_focus'];
    if (tf is String) muscles.add(tf.toLowerCase());

    for (final affected in affectedMuscles) {
      if (muscles.any((m) => m.contains(affected))) return true;
    }
    return false;
  }

  Map? _resolveLibraryEntry(String id) {
    final lib = HiveService.instance.exerciseBox.get(id);
    if (lib is Map) return lib;
    final cust = HiveService.instance.customBox.get(id);
    if (cust is Map) return cust;
    // Custom items keyed differently — scan for inner id match.
    for (final k in HiveService.instance.customBox.keys) {
      final v = HiveService.instance.customBox.get(k);
      if (v is Map && v['id'] == id) return v;
    }
    return null;
  }

  /// Find an exercise in the library that:
  ///   - is NOT [fromId]
  ///   - matches [category] (if provided)
  ///   - does NOT load any of [avoidMuscles]
  ({String id, String name})? _findSubstitute({
    required String fromId,
    required String? category,
    required Set<String> avoidMuscles,
  }) {
    final box = HiveService.instance.exerciseBox;
    final wantedCat = category?.toLowerCase();
    for (final key in box.keys) {
      final ex = box.get(key);
      if (ex is! Map) continue;
      final id = (ex['id'] ?? key).toString();
      if (id == fromId) continue;
      final cat = ex['category']?.toString().toLowerCase();
      if (wantedCat != null && cat != null && cat != wantedCat) continue;

      // Skip if this candidate hits the affected muscles too.
      if (_exerciseHitsMuscles(ex, avoidMuscles)) continue;

      final name = (ex['name'] ?? id).toString();
      return (id: id, name: name);
    }
    return null;
  }
}
