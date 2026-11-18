// lib/features/nutrition/providers/diet_serving_view_provider.dart
//
// OI-517 (docs/plans/diet-grams-toggle.md section 3): the reactive form of the
// profile key `diet_serving_view`. A profile write rebuilds it through
// [userProfileProvider] (a trigger only); a RESTORE writes Hive without
// touching that provider's state, so the restore tick rebuilds it and the
// value is read from Hive, never from the possibly stale state (the same
// contract as `dietSupplementsInputsProvider`). Key absent = Portions.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart'
    show restoreCompletedTickProvider;
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import '../services/diet_serving_label.dart';

/// The user's current Portions / Grams choice.
final dietServingViewProvider = Provider<DietServingView>((ref) {
  ref.watch(authUserIdTokenProvider);
  ref.watch(restoreCompletedTickProvider);
  ref.watch(userProfileProvider
      .select((p) => p['diet_serving_view'])); // trigger only
  final p = UserRepository.instance.getProfile() ?? const <String, dynamic>{};
  return DietServingView.fromStorage(p['diet_serving_view']);
});

/// The text a plan row shows for one serving in [view]: Portions returns the
/// description unchanged; Grams adds the weight (ml for an audited liquid).
String servingLabelFor(
        String foodId, String desc, double grams, DietServingView view) =>
    servingLabel(desc, grams, view,
        isLiquid: view == DietServingView.grams && isLiquidFood(foodId));

/// True when the food row [foodId] is an audited liquid (`weight_unit: "ml"`).
/// Total: a missing id (a retired id in an old saved plan), a custom food or
/// the protein shake's synthetic id all read as grams. Local Hive read only.
bool isLiquidFood(String foodId) {
  if (foodId.isEmpty) return false;
  try {
    return FoodRepository.instance.getById(foodId)?['weight_unit'] == 'ml';
  } catch (_) {
    return false;
  }
}
