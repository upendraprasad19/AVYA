import 'package:flutter/material.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// The ghost line at the foot of the Profile tab: the app version and the
/// purchase mode this binary was built with (ADR-0022, plan section 3).
///
/// It exists so the founder can see on a phone which AAB is installed (the
/// mode is a compile-time define and cannot be read any other way). Settings
/// is not linked from the app, so the line lives on the Profile tab.
class BuildStamp extends StatelessWidget {
  const BuildStamp({super.key});

  /// The text, pure so a test can pin it without pumping a widget.
  static String label() =>
      'v${AppConstants.appVersion} · purchases: ${PurchaseMode.current.wireName}';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label(),
        key: const ValueKey('build-stamp'),
        style: AppTypography.monoXs.copyWith(color: AppColors.textGhost),
      ),
    );
  }
}
