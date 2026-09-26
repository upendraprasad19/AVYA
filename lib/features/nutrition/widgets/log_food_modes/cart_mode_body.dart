import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import '../cart_auditor_section.dart';

/// CART mode body for `LogFoodSheet`. Cart Auditor is read-only: user
/// uploads a grocery screenshot → Gemini returns an audit JSON → user
/// reads the suggestions but no food log is written. Sheet stays open
/// until the user taps the close affordance.
class CartModeBody extends ConsumerWidget {
  const CartModeBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: const CartAuditorSection(),
    );
  }
}
