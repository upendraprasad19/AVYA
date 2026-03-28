enum BadgeId {
  firstWorkout,
  workouts10,
  workouts50,
  firstPr,
  prs5,
  phase1Complete,
  streak4Weeks,
  streak8Weeks,
  streak12Weeks,
  nutritionWeek,
  weightLogged30,
  aiCoachChat,
  challengeWon,
  customExercise,
  earlyAdopter,
}

class AchievementBadge {
  final BadgeId id;
  final String name;
  final String description;
  final String emoji;
  final DateTime? unlockedAt;

  const AchievementBadge({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    this.unlockedAt,
  });

  bool get isUnlocked => unlockedAt != null;

  static const List<AchievementBadge> all = [
    AchievementBadge(id: BadgeId.firstWorkout,   name: 'First Rep',         description: 'Complete your first workout',           emoji: '💪'),
    AchievementBadge(id: BadgeId.workouts10,     name: 'On a Roll',         description: 'Complete 10 workouts',                  emoji: '🔥'),
    AchievementBadge(id: BadgeId.workouts50,     name: 'Iron Will',         description: 'Complete 50 workouts',                  emoji: '🏋️'),
    AchievementBadge(id: BadgeId.firstPr,        name: 'New Heights',       description: 'Set your first personal record',        emoji: '🏆'),
    AchievementBadge(id: BadgeId.prs5,           name: 'PR Machine',        description: 'Set 5 personal records',                emoji: '⚡'),
    AchievementBadge(id: BadgeId.phase1Complete, name: 'Phase 1 Graduate',  description: 'Complete Phase 1 (4 weeks)',            emoji: '🎓'),
    AchievementBadge(id: BadgeId.streak4Weeks,   name: '4-Week Warrior',    description: 'Maintain a 4-week streak',              emoji: '📅'),
    AchievementBadge(id: BadgeId.streak8Weeks,   name: '8-Week Beast',      description: 'Maintain an 8-week streak',             emoji: '🦁'),
    AchievementBadge(id: BadgeId.streak12Weeks,  name: '12-Week Legend',    description: 'Maintain a 12-week streak',             emoji: '👑'),
    AchievementBadge(id: BadgeId.nutritionWeek,  name: 'Clean Eater',       description: 'Log meals every day for a week',       emoji: '🥗'),
    AchievementBadge(id: BadgeId.weightLogged30, name: 'Scale Watcher',     description: 'Log weight 30 times',                  emoji: '⚖️'),
    AchievementBadge(id: BadgeId.aiCoachChat,    name: "Coach's Pet",       description: 'Send your first message to AI Coach',  emoji: '🤖'),
    AchievementBadge(id: BadgeId.challengeWon,   name: 'Coach Slayer',      description: 'Beat the coach in a HIIT challenge',   emoji: '🥊'),
    AchievementBadge(id: BadgeId.customExercise, name: 'Innovator',         description: 'Create a custom exercise',             emoji: '🔬'),
    AchievementBadge(id: BadgeId.earlyAdopter,   name: 'OG Fitter',         description: 'Joined ICANBEFITTER early',            emoji: '⭐'),
  ];
}
