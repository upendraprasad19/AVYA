import 'package:flutter/material.dart';

import 'package:icanbefitter/core/theme/colors.dart';

/// Shared `builder:` for `showTimePicker` / `showDatePicker`.
///
/// Two jobs:
///  1. Apply the Wardroom dark theme to the stock Material picker.
///  2. Keep the dialog — INCLUDING its OK/Cancel action row — reachable at short
///     viewports. Obs#5 (2026-06-13 live web E2E): on the ~698px web mobile-frame
///     the time picker's action row fell BELOW the fold (only the keyboard-toggle
///     icon was visible), so the user could not confirm a time → muster Q2 (and
///     onboarding DOB) became an unpassable blocker. Wrapping the dialog in a
///     centered SingleChildScrollView lets a dialog taller than the viewport be
///     scrolled to reveal its actions; when it fits, Center keeps it dialog-positioned.
///
/// NOTE (device verify): Android uses native pickers with a different viewport,
/// so this primarily hardens the WEB surface — confirm on device.
Widget responsivePickerBuilder(BuildContext context, Widget? child) {
  final themed = Theme(
    data: Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.accent,
            onPrimary: AppColors.bgDeep,
            surface: AppColors.card,
            onSurface: AppColors.textPrimary,
          ),
      dialogTheme: const DialogThemeData(backgroundColor: AppColors.card),
    ),
    child: child ?? const SizedBox.shrink(),
  );
  return Center(
    child: SingleChildScrollView(
      child: themed,
    ),
  );
}
