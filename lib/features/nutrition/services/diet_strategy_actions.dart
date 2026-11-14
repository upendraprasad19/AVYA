// lib/features/nutrition/services/diet_strategy_actions.dart
//
// Diet plan Unit 3a (2026-11-14, docs/plans/diet-strategy.md §3.4-§3.6): the
// pure preview behind the confirm dialog, and the Diet Plan screen's tap
// handler (kept out of diet_plan_screen.dart, which sits near its 800-line
// ceiling).
//
// The dialog's OLD side is `effectiveMacroTargets` with the CURRENT PRO
// state (so it equals the targets on screen); the NEW side uses `pro: true`
// (the gate has just passed, so a user mid-verification still sees the real
// change). When the two sides round to the same four integers, there is no
// dialog: the field is written and the snackbar says so.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/effective_macro_targets.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import '../providers/nutrition_provider.dart';
import '../widgets/diet_strategy_confirm_dialog.dart';

/// The paywall's display label for this feature (a `case` in
/// `paywall_sheet.dart`'s subtitle switch).
const String kDietStrategyPaywallLabel = 'Diet Strategy';

/// Old and new SHOWN targets for a strategy change.
class DietStrategyChangePreview {
  const DietStrategyChangePreview({required this.before, required this.after});

  final EffectiveMacroTargets before;
  final EffectiveMacroTargets after;

  /// True when the user would see the same four rounded numbers.
  bool get sameShown =>
      before.calories.round() == after.calories.round() &&
      before.protein.round() == after.protein.round() &&
      before.carbs.round() == after.carbs.round() &&
      before.fat.round() == after.fat.round();

  /// True when calories or protein move (only possible in Edit Profile,
  /// where other edited fields feed the recompute).
  bool get caloriesOrProteinMove =>
      before.calories.round() != after.calories.round() ||
      before.protein.round() != after.protein.round();
}

/// Null when either pack is missing (only the hard-coded defaults are left;
/// the strategy never applies to those).
DietStrategyChangePreview? previewDietStrategyChange({
  required MacroPack? beforeBase,
  required MacroPack? afterBase,
  required Object? storedStrategy,
  required DietStrategy next,
  required bool currentPro,
}) {
  final before = effectiveMacroTargets(beforeBase, storedStrategy,
      pro: currentPro, enabled: true);
  final after = effectiveMacroTargets(afterBase, next.storageKey,
      pro: true, enabled: true);
  if (before == null || after == null) return null;
  return DietStrategyChangePreview(before: before, after: after);
}

/// The snackbar after a change that did not move any shown number.
String dietStrategyUnchangedMessage(DietStrategy next) =>
    next == DietStrategy.balanced
        ? 'Targets updated for ${next.label}'
        : 'Your targets are already low in carbs.';

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text, style: AppTypography.body.copyWith(fontSize: 13)),
      backgroundColor: AppColors.card,
    ),
  );
}

/// The Diet Plan screen's chip tap. [current] is the EFFECTIVE strategy
/// (the selected chip): a tap on it does nothing, so a lapsed user's paused
/// choice is never erased by tapping the Balanced chip shown as selected.
/// Returns once the change is written, refused or cancelled.
Future<void> handleDietStrategyTap(
  BuildContext context,
  WidgetRef ref,
  DietStrategy next, {
  required DietStrategy current,
}) async {
  if (next == current) return;
  if (next != DietStrategy.balanced) {
    var allowed = false;
    await SubscriptionService.instance.gateAndVerify(
      AppConstants.featureDietStrategy,
      onPro: () => allowed = true,
      onFree: () => showPaywallSheet(context, feature: kDietStrategyPaywallLabel),
    );
    if (!allowed || !context.mounted) return;
  }

  final profile = UserRepository.instance.getProfile();
  final base = resolveBaseMacroPack(profile);
  final preview = previewDietStrategyChange(
    beforeBase: base,
    afterBase: base,
    storedStrategy: profile?['diet_strategy'],
    next: next,
    currentPro: ref.read(subscriptionInfoProvider).isPro,
  );
  final notifier = ref.read(userProfileProvider.notifier);

  if (preview != null && !preview.sameShown) {
    final confirmed = await showDietStrategyConfirmDialog(
      context,
      next: next,
      preview: preview,
    );
    if (!confirmed || !context.mounted) return;
  }

  final applied = await notifier.setDietStrategy(next);
  if (!context.mounted) return;
  if (!applied) {
    _snack(context, "Couldn't change the diet strategy. Try again.");
    return;
  }
  _snack(
    context,
    preview != null && preview.sameShown
        ? dietStrategyUnchangedMessage(next)
        : 'Targets updated for ${next.label}',
  );
}

/// Edit Profile's Save step for a changed strategy (plan §3.4/§3.6). Returns
/// null when the user cancelled (nothing is saved), true when `diet_strategy`
/// goes into the save, false when it must not (a non-Balanced choice whose
/// PRO lapsed between the tap and Save; the rest of the form still saves).
///
/// The preview covers all four targets: [profile] as stored before the save,
/// against the full recompute [recomputeAfter] gives for the edited form
/// (null = the recompute's inputs are incomplete, so the stored pack stays).
Future<bool?> confirmEditProfileDietStrategy(
  BuildContext context, {
  required Map<String, dynamic> profile,
  required Map<String, dynamic> edited,
  required Map<String, dynamic>? recomputeAfter,
  required DietStrategy next,
  required bool pro,
}) async {
  if (next != DietStrategy.balanced && !pro) return false;
  final afterProfile = <String, dynamic>{...edited, ...?recomputeAfter};
  final preview = previewDietStrategyChange(
    beforeBase: resolveBaseMacroPack(profile),
    afterBase: resolveBaseMacroPack(afterProfile),
    storedStrategy: profile['diet_strategy'],
    next: next,
    currentPro: pro,
  );
  if (preview == null || preview.sameShown) return true;
  final confirmed =
      await showDietStrategyConfirmDialog(context, next: next, preview: preview);
  return confirmed ? true : null;
}
