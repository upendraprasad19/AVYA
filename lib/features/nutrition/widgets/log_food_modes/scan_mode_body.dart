import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import '../scan_meal_section.dart';

/// SCAN mode body for `LogFoodSheet`. Wraps `ScanMealSection` with
/// a scrollable padded container — ScanMealSection grows tall when the
/// result editor is open.
class ScanModeBody extends ConsumerWidget {
  const ScanModeBody({super.key, required this.onLogged});

  final VoidCallback onLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Note: ScanMealSection writes to nutrition_log internally. Since
    // the existing widget doesn't expose an onSave callback, we keep
    // onLogged plumbed but unused for now — the page refresh after
    // sheet dismissal still picks up the new log via dailyNutrition
    // provider invalidation. Future refactor of ScanMealSection can
    // accept onSave for tighter UX (auto-dismiss the sheet on save).
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: const ScanMealSection(),
    );
  }
}
