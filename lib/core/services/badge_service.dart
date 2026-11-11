import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/utils/exercise_name_identity.dart';
import 'package:icanbefitter/shared/models/achievement_badge.dart';

/// Tracks and unlocks achievement badges stored in Hive configBox.
class BadgeService {
  BadgeService._();
  static final BadgeService instance = BadgeService._();

  static const _badgesKey = 'unlockedBadges';

  // Use HiveService singleton instead of Hive.box() directly to avoid
  // HiveError if the box is not yet open.
  Box<dynamic> get _box => HiveService.instance.configBox;

  /// Checks milestones and unlocks any newly earned badges.
  /// Returns the list of newly unlocked BadgeIds (empty if none).
  ///
  /// OI-45 finding 3 / Unit 3a: downgraded from a claimed HIGH-severity race
  /// — confirmed by reading the body that there is genuinely no `await`
  /// between the `_getUnlocked()` read and the `_box.put()` write, so under
  /// Dart's single-threaded event loop nothing can interleave TODAY. This
  /// method and [checkAll] MUST stay fully synchronous (not `async`, no
  /// `await` in the body) to preserve that guarantee — adding one would
  /// reopen a real read-modify-write race with no lock to catch it.
  /// `test/contracts/badge_service_synchronous_invariant_test.dart` fails
  /// loudly if either method's signature ever becomes `async`.
  List<BadgeId> checkAndUnlock({
    required int totalWorkouts,
    required int totalPrs,
    required int currentStreakWeeks,
    required int weightLogCount,
    required bool phase1Complete,
    required bool hasChattedWithAI,
    required bool hasCustomExercise,
  }) {
    final unlocked = _getUnlocked();
    final newlyUnlocked = <BadgeId>[];

    void tryUnlock(BadgeId id, bool condition) {
      if (condition && !unlocked.containsKey(id.name)) {
        unlocked[id.name] = DateTime.now().toIso8601String();
        newlyUnlocked.add(id);
      }
    }

    tryUnlock(BadgeId.firstWorkout,   totalWorkouts >= 1);
    tryUnlock(BadgeId.workouts10,     totalWorkouts >= 10);
    tryUnlock(BadgeId.workouts50,     totalWorkouts >= 50);
    tryUnlock(BadgeId.firstPr,        totalPrs >= 1);
    tryUnlock(BadgeId.prs5,           totalPrs >= 5);
    tryUnlock(BadgeId.phase1Complete, phase1Complete);
    tryUnlock(BadgeId.streak4Weeks,   currentStreakWeeks >= 4);
    tryUnlock(BadgeId.streak8Weeks,   currentStreakWeeks >= 8);
    tryUnlock(BadgeId.streak12Weeks,  currentStreakWeeks >= 12);
    tryUnlock(BadgeId.weightLogged30, weightLogCount >= 30);
    tryUnlock(BadgeId.aiCoachChat,    hasChattedWithAI);
    tryUnlock(BadgeId.customExercise, hasCustomExercise);
    // Every current user is an early adopter
    tryUnlock(BadgeId.earlyAdopter, true);

    if (newlyUnlocked.isNotEmpty) {
      _box.put(_badgesKey, unlocked);
    }
    return newlyUnlocked;
  }

  Map<String, String> _getUnlocked() {
    final raw = _box.get(_badgesKey);
    if (raw == null) return {};
    return Map<String, String>.from(raw as Map);
  }

  List<AchievementBadge> getAllWithStatus() {
    final unlocked = _getUnlocked();
    return AchievementBadge.all.map((b) {
      final iso = unlocked[b.id.name];
      return AchievementBadge(
        id: b.id,
        name: b.name,
        description: b.description,
        emoji: b.emoji,
        unlockedAt: iso != null ? DateTime.tryParse(iso) : null,
      );
    }).toList();
  }

  int get unlockedCount => _getUnlocked().length;

  /// PURE, synchronous. Counts the exercise-log rows whose best per-set weight
  /// beats the best per-set weight of every STRICTLY earlier-dated row of the
  /// same exercise ([exerciseNameKey]). A first-ever log (no earlier row, or an
  /// earlier max of 0) never counts. A row with no IST date is skipped.
  static int countBeatenPrs(Iterable<Map> exlogRows) {
    final groups = <String, List<MapEntry<String, double>>>{};
    for (final raw in exlogRows) {
      final row = Map<String, dynamic>.from(raw);
      final key = exerciseNameKey(row['exercise_name']?.toString() ?? '');
      if (key.isEmpty) continue;
      final date = WorkoutReadService.istDateForExlogRow(row);
      if (date == null) continue;
      groups
          .putIfAbsent(key, () => [])
          .add(MapEntry(date, WorkoutReadService.bestPerSetWeight(row)));
    }
    var count = 0;
    for (final rows in groups.values) {
      for (final r in rows) {
        var earlierMax = 0.0;
        for (final other in rows) {
          if (other.key.compareTo(r.key) < 0 && other.value > earlierMax) {
            earlierMax = other.value;
          }
        }
        final w = r.value;
        if (earlierMax > 0 && w > earlierMax) count++;
      }
    }
    return count;
  }

  /// Convenience: gathers all stats from Hive and checks all badge conditions.
  /// Call this after any trigger event (workout complete, meal logged, weight logged, etc.).
  List<BadgeId> checkAll() {
    final hive = HiveService.instance;

    // Coach workout parity 1a: completed workout DAYS through the one shared
    // count (distinct dates; a legacy duplicate wlog never doubles a day).
    final int totalWorkouts =
        WorkoutReadService.instance.completedWorkoutDayCount();
    // Rows come from the shared `exlog_` key predicate (the `type` field is
    // stamped only by the restore writer), and a PR is computed from the rows
    // themselves, never from the stored `is_pr` (a back-filled earlier heavier
    // row leaves a stale flag).
    final int totalPrs =
        countBeatenPrs(WorkoutReadService.exlogRows(hive.workoutBox));
    bool hasCustomExercise = false;

    for (final key in hive.customBox.keys) {
      if (key is String && key.startsWith('custom_exercise_')) {
        hasCustomExercise = true;
        break;
      }
    }

    final progress = hive.userBox.get('progress') as Map? ?? {};
    final streakWeeks = (progress['current_streak_weeks'] as int?) ?? 0;
    final currentPhase = (progress['current_phase'] as int?) ?? 1;
    final totalDone = (progress['total_workouts_done'] as int?) ?? 0;
    // Phase 1 complete if user graduated to phase 2+
    final phase1Complete = currentPhase >= 2;

    int weightLogCount = 0;
    for (final key in hive.healthBox.keys) {
      if (key is String && key.startsWith('weight_')) weightLogCount++;
    }

    final hasChattedWithAI = hive.coachBox.isNotEmpty;

    return checkAndUnlock(
      totalWorkouts: totalWorkouts > 0 ? totalWorkouts : totalDone,
      totalPrs: totalPrs,
      currentStreakWeeks: streakWeeks,
      weightLogCount: weightLogCount,
      phase1Complete: phase1Complete,
      hasChattedWithAI: hasChattedWithAI,
      hasCustomExercise: hasCustomExercise,
    );
  }
}
