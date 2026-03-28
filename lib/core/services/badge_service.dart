import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/shared/models/achievement_badge.dart';

/// Tracks and unlocks achievement badges stored in Hive configBox.
class BadgeService {
  BadgeService._();
  static final BadgeService instance = BadgeService._();

  static const _badgesKey = 'unlockedBadges';

  Box get _box => Hive.box('configBox');

  /// Checks milestones and unlocks any newly earned badges.
  /// Returns the list of newly unlocked BadgeIds (empty if none).
  List<BadgeId> checkAndUnlock({
    required int totalWorkouts,
    required int totalPrs,
    required int currentStreakWeeks,
    required int weightLogCount,
    required bool phase1Complete,
    required bool hasChattedWithAI,
    required bool hasBeatCoach,
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
    tryUnlock(BadgeId.challengeWon,   hasBeatCoach);
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
}
