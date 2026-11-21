import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/models/achievement_badge.dart';
import 'package:icanbefitter/shared/widgets/compact_achievements_row.dart';

void main() {
  group('CompactAchievementsRow', () {
    final now = DateTime(2026, 4, 12);

    testWidgets('shows 3 most recent unlocked badges', (tester) async {
      final badges = [
        AchievementBadge(id: BadgeId.firstWorkout, name: 'First Rep',   description: 'x', emoji: '💪', unlockedAt: now.subtract(const Duration(days: 5))),
        AchievementBadge(id: BadgeId.firstPr,      name: 'New Heights', description: 'x', emoji: '🏆', unlockedAt: now.subtract(const Duration(days: 1))),
        AchievementBadge(id: BadgeId.workouts10,   name: 'On a Roll',   description: 'x', emoji: '🔥', unlockedAt: now.subtract(const Duration(days: 3))),
        AchievementBadge(id: BadgeId.workouts50,   name: 'Iron Will',   description: 'x', emoji: '🏋️', unlockedAt: now.subtract(const Duration(days: 10))),
        AchievementBadge(id: BadgeId.earlyAdopter, name: 'OG Fitter',   description: 'x', emoji: '⭐',  unlockedAt: null), // locked
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CompactAchievementsRow(badges: badges, onOpenAll: () {})),
      ));

      // The 3 most recently unlocked are: New Heights (1d), On a Roll (3d), First Rep (5d)
      expect(find.text('🏆'), findsOneWidget);
      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('💪'), findsOneWidget);
      // Iron Will (10d ago) is older, should NOT appear
      expect(find.text('🏋️'), findsNothing);
      // Early Adopter is locked, should NOT appear
      expect(find.text('⭐'), findsNothing);
    });

    testWidgets('pads with locked badges when fewer than 3 unlocked', (tester) async {
      final badges = [
        AchievementBadge(id: BadgeId.firstWorkout, name: 'First Rep',   description: 'x', emoji: '💪', unlockedAt: now),
        AchievementBadge(id: BadgeId.workouts10,   name: 'On a Roll',   description: 'x', emoji: '🔥', unlockedAt: null),
        AchievementBadge(id: BadgeId.workouts50,   name: 'Iron Will',   description: 'x', emoji: '🏋️', unlockedAt: null),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CompactAchievementsRow(badges: badges, onOpenAll: () {})),
      ));

      // Row always shows 3 slots: 1 unlocked + 2 locked padding.
      expect(find.text('💪'), findsOneWidget);
      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('🏋️'), findsOneWidget);
    });

    testWidgets('chevron tap fires onOpenAll', (tester) async {
      var opened = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CompactAchievementsRow(badges: const [], onOpenAll: () => opened = true)),
      ));

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      expect(opened, isTrue);
    });
  });
}
