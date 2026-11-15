// lib/features/nutrition/providers/diet_supplements_active_provider.dart
//
// Diet plan Unit 4a (docs/plans/diet-supplements.md section 2): the reactive
// form of the ONE rule `dietSupplementsActive`. It watches the profile's two
// inputs (the switch and the date of birth), PRO and the restore tick, like
// `_watchDietStrategyInputs`; with the kill switch off it watches NONE of
// them, so a flag-off reader keeps exactly its pre-Unit-4 dependency set.
//
// `now` is read when the provider builds, so a long-lived web session does
// not see a birthday pass until a watched input changes; that only delays an
// adult (fail safe).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/utils/diet_supplements_rule.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart'
    show restoreCompletedTickProvider;
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import '../services/diet_supplements_flags.dart';

/// The two profile inputs of the rule.
typedef _SupplementInputs = ({Object? switchValue, Object? dob});

/// True when Supplements are on and effective for the signed-in user.
final dietSupplementsActiveProvider = Provider<bool>((ref) {
  if (!DietSupplementsFlags.enabled) return false;
  final pro = ref.watch(subscriptionInfoProvider.select((s) => s.isPro));
  ref.watch(restoreCompletedTickProvider);
  final inputs = ref.watch(userProfileProvider.select<_SupplementInputs>(
      (p) => (switchValue: p['diet_supplements'], dob: p['date_of_birth'])));
  return dietSupplementsActive(
    profile: {
      'diet_supplements': inputs.switchValue,
      'date_of_birth': inputs.dob,
    },
    pro: pro,
    enabled: true,
    now: DateTime.now(),
  );
});

/// True when the Supplements section may be shown (flag on, adult): no PRO,
/// no switch. Free users see the section locked.
final dietSupplementsEligibleProvider = Provider<bool>((ref) {
  if (!DietSupplementsFlags.enabled) return false;
  final dob = ref.watch(userProfileProvider.select((p) => p['date_of_birth']));
  return dietSupplementsEligible(
    profile: {'date_of_birth': dob},
    enabled: true,
    now: DateTime.now(),
  );
});
