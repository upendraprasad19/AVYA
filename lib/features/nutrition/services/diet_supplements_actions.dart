// lib/features/nutrition/services/diet_supplements_actions.dart
//
// Diet plan Unit 4a (docs/plans/diet-supplements.md section 3): the Diet Plan
// screen's Supplements switch tap. Turning it ON is a PRO action (gate, then
// the write); turning it OFF is always allowed, so a lapsed user can remove
// it. The age rule is the section's, not this file's: the switch is not
// shown to anyone under 18.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';

/// The paywall's display label for this feature (a `case` in
/// `paywall_sheet.dart`'s subtitle switch).
const String kDietSupplementsPaywallLabel = 'Diet Supplements';

/// The snackbar when a change could not be written.
const String kDietSupplementsChangeFailedMessage =
    "Couldn't change Supplements. Try again.";

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text, style: AppTypography.body.copyWith(fontSize: 13)),
      backgroundColor: AppColors.card,
    ),
  );
}

/// The switch tap. [current] is the stored switch as the screen shows it.
/// Returns once the change is written, refused or cancelled.
Future<void> handleDietSupplementsToggle(
  BuildContext context,
  WidgetRef ref,
  bool next, {
  required bool current,
}) async {
  if (next == current) return;
  if (next) {
    var allowed = false;
    await SubscriptionService.instance.gateAndVerify(
      AppConstants.featureDietSupplements,
      onPro: () => allowed = true,
      onFree: () {
        if (context.mounted) {
          showPaywallSheet(context, feature: kDietSupplementsPaywallLabel);
        }
      },
    );
    if (!allowed || !context.mounted) return;
  }
  bool applied;
  try {
    applied = await ref.read(userProfileProvider.notifier).setDietSupplements(next);
  } catch (e, st) {
    unawaited(ErrorTelemetry.recordNonFatal(e, st,
        reason: 'diet_supplements_change_failed'));
    applied = false;
  }
  if (!context.mounted) return;
  if (!applied) _snack(context, kDietSupplementsChangeFailedMessage);
}
