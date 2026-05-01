import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/screens/edit_profile_screen.dart';

void main() {
  group('computePlanChanged', () {
    // Baseline: nothing changed.
    bool callWith({
      int daysPerWeek = 4,
      int originalDaysPerWeek = 4,
      String goal = 'build_muscle',
      String originalGoal = 'build_muscle',
      String equipment = 'full_gym',
      String originalEquipment = 'full_gym',
      String fitnessExperience = 'intermediate',
      String originalFitnessExperience = 'intermediate',
      int? sessionDuration = 60,
      int? originalSessionDuration = 60,
      String physiqueFocus = 'balanced',
      String originalPhysiqueFocus = 'balanced',
      List<String> injuries = const ['none'],
      List<String> originalInjuries = const ['none'],
    }) {
      return computePlanChanged(
        daysPerWeek: daysPerWeek,
        originalDaysPerWeek: originalDaysPerWeek,
        goal: goal,
        originalGoal: originalGoal,
        equipment: equipment,
        originalEquipment: originalEquipment,
        fitnessExperience: fitnessExperience,
        originalFitnessExperience: originalFitnessExperience,
        sessionDuration: sessionDuration,
        originalSessionDuration: originalSessionDuration,
        physiqueFocus: physiqueFocus,
        originalPhysiqueFocus: originalPhysiqueFocus,
        injuries: injuries,
        originalInjuries: originalInjuries,
      );
    }

    test('no plan-driving fields changed → false', () {
      expect(callWith(), isFalse);
    });

    test('only experience changed → true', () {
      expect(
        callWith(fitnessExperience: 'advanced'),
        isTrue,
      );
    });

    test('only session duration changed → true', () {
      expect(
        callWith(sessionDuration: 90),
        isTrue,
      );
    });

    test('only physique focus changed → true', () {
      expect(
        callWith(physiqueFocus: 'glutes_legs'),
        isTrue,
      );
    });

    test('only injuries list changed → true', () {
      expect(
        callWith(injuries: const ['none', 'knee']),
        isTrue,
      );
    });

    test('injuries list contents reordered but same set → true (order matters)', () {
      // listEquals is order-sensitive. Profile model never reorders the
      // injuries list at rest, so order-flip should still trigger
      // regen — the saved chips list IS the order. If we wanted a
      // set-equal semantics, we'd switch to Set comparison.
      expect(
        callWith(
          injuries: const ['knee', 'none'],
          originalInjuries: const ['none', 'knee'],
        ),
        isTrue,
      );
    });

    test('session duration null → 60 → true', () {
      expect(
        callWith(sessionDuration: 60, originalSessionDuration: null),
        isTrue,
      );
    });

    test('legacy 4 fields still trigger (regression guard)', () {
      expect(callWith(daysPerWeek: 6), isTrue);
      expect(callWith(goal: 'lose_fat'), isTrue);
      expect(callWith(equipment: 'home_dumbbells'), isTrue);
    });
  });
}
