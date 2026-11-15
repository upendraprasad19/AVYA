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
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import '../services/diet_supplements_flags.dart';

/// The two profile inputs of the rule.
typedef SupplementInputs = ({Object? switchValue, Object? dob});

/// The two inputs, read from the stored profile. A profile write rebuilds it
/// through [userProfileProvider] (a trigger only); a RESTORE writes Hive
/// without touching that provider's state (sign-in on a second device), so
/// the restore tick rebuilds it and the value is read from Hive, never from
/// the provider's possibly stale state. Watched only with the kill switch on.
final dietSupplementsInputsProvider = Provider<SupplementInputs>((ref) {
  ref.watch(restoreCompletedTickProvider);
  ref.watch(userProfileProvider.select<SupplementInputs>(
      (p) => (switchValue: p['diet_supplements'], dob: p['date_of_birth'])));
  final p = UserRepository.instance.getProfile() ?? const <String, dynamic>{};
  return (switchValue: p['diet_supplements'], dob: p['date_of_birth']);
});

/// True when Supplements are on and effective for the signed-in user.
final dietSupplementsActiveProvider = Provider<bool>((ref) {
  if (!DietSupplementsFlags.enabled) return false;
  final pro = ref.watch(subscriptionInfoProvider.select((s) => s.isPro));
  final inputs = ref.watch(dietSupplementsInputsProvider);
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
  final dob = ref.watch(dietSupplementsInputsProvider.select((i) => i.dob));
  return dietSupplementsEligible(
    profile: {'date_of_birth': dob},
    enabled: true,
    now: DateTime.now(),
  );
});
