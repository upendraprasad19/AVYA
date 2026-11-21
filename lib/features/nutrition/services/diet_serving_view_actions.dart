// lib/features/nutrition/services/diet_serving_view_actions.dart
//
// OI-517 (docs/plans/diet-grams-toggle.md): THE write door for the Diet
// chart's Portions / Grams view. ONE local profile key `diet_serving_view`
// ('portions' | 'grams'), written through the profile notifier's one door
// (`updateProfile` -> `patchProfile`, never a `saveProfile` of a stale map).
// The key is never pushed (the profile push is a column whitelist), so a
// reinstall or a second device falls back to the default. A stored value
// equal to the new one writes nothing.
library;

import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'diet_serving_label.dart';

Future<void> setDietServingView(
    UserProfileNotifier profile, DietServingView next) async {
  final stored = UserRepository.instance.getProfile()?['diet_serving_view'];
  if (stored == next.storageKey) return;
  await profile.updateProfile({'diet_serving_view': next.storageKey});
}
