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
      List<String> equipmentExclusions = const [],
      List<String> originalEquipmentExclusions = const [],
      List<String> equipmentOwned = const [],
      List<String> originalEquipmentOwned = const [],
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
        equipmentExclusions: equipmentExclusions,
        originalEquipmentExclusions: originalEquipmentExclusions,
        equipmentOwned: equipmentOwned,
        originalEquipmentOwned: originalEquipmentOwned,
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

    test('only equipment exclusions changed → true (⑥ C1)', () {
      expect(callWith(equipmentExclusions: const ['cables']), isTrue);
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

    test('⑦ OI-89: acquiring equipment changes the plan — true', () {
      // Owning a new item WIDENS the pool, so the plan can genuinely improve.
      // It joins the existing eight fields on the "Reschedule Workouts?" prompt
      // rather than regenerating silently.
      expect(callWith(equipmentOwned: const ['pull-up bar']), isTrue);
    });

    test('⑦ OI-89: LOSING equipment changes the plan — true', () {
      expect(
        callWith(
          equipmentOwned: const [],
          originalEquipmentOwned: const ['pull-up bar'],
        ),
        isTrue,
      );
    });

    test('⑦ OI-89: an unchanged owned list does NOT trigger — false', () {
      // The chip handler sorts on every tap for exactly this reason: an
      // order-only difference would make listEquals report a change that is not
      // one, and fire the reschedule prompt on a no-op edit.
      expect(
        callWith(
          equipmentOwned: const ['dumbbells', 'pull-up bar'],
          originalEquipmentOwned: const ['dumbbells', 'pull-up bar'],
        ),
        isFalse,
      );
    });
  });
}
