// lib/features/nutrition/widgets/diet_supplements_section.dart
//
// Diet plan Unit 4a (docs/plans/diet-supplements.md section 3): the Diet Plan
// screen's Supplements block under the strategy block. The screen mounts it
// only when DietSupplementsFlags.enabled (the section reads the providers
// itself, so a flag-off screen never builds it).
//
//   - under 18, or no date of birth the app can read: no switch (a hint says
//     where to add the date when it is merely unreadable);
//   - adult, free: the switch is shown and a tap opens the paywall;
//   - adult, PRO: the switch writes `diet_supplements`; the card shows below
//     it only while Supplements are ACTIVE (the one rule);
//   - a stored "on" that PRO lapsed shows the switch off plus a paused hint.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/diet_supplement_doses.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/diet_supplements_rule.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_card.dart';
import '../providers/diet_supplements_active_provider.dart';
import '../services/diet_supplements_actions.dart';

/// The hint for a stored "on" that is not applied because PRO lapsed.
const String kDietSupplementsPausedHint =
    'Supplements are paused. They come back with PRO.';

/// The hint when the date of birth cannot be read.
const String kDietSupplementsNeedsDobHint =
    'Add your date of birth in Edit Profile to unlock Supplements.';

class DietSupplementsSection extends ConsumerStatefulWidget {
  const DietSupplementsSection({super.key});

  @override
  ConsumerState<DietSupplementsSection> createState() =>
      _DietSupplementsSectionState();
}

class _DietSupplementsSectionState
    extends ConsumerState<DietSupplementsSection> {
  bool _busy = false;

  Future<void> _onToggle(bool next, bool current) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await handleDietSupplementsToggle(context, ref, next, current: current);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dob = ref.watch(userProfileProvider.select((p) => p['date_of_birth']));
    final age = ageYearsOn(dob, DateTime.now());
    // A minor sees nothing at all.
    if (age != null && age < kSupplementsMinAgeYears) {
      return const SizedBox.shrink();
    }
    final dim =
        AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim);
    if (age == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Supplements', style: dim),
          const SizedBox(height: 8),
          Text(kDietSupplementsNeedsDobHint,
              key: const ValueKey('diet_supplements_needs_dob_hint'),
              style: dim),
        ],
      );
    }

    final isPro = ref.watch(subscriptionInfoProvider.select((s) => s.isPro));
    final stored = ref.watch(userProfileProvider
        .select((p) => p['diet_supplements'] == true));
    final active = ref.watch(dietSupplementsActiveProvider);
    final foodType =
        ref.watch(userProfileProvider.select((p) => foodTypeOfProfile(p)));
    final paused = stored && !isPro;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Supplements', style: dim),
        const SizedBox(height: 8),
        WardCard(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add supplements to my plan',
                        style: AppTypography.body.copyWith(
                            fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                        'A daily supplement card, and a protein shake when '
                        'your food falls short.',
                        style: dim),
                  ],
                ),
              ),
              if (!isPro)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.lock_outline,
                      size: 16, color: AppColors.textMute),
                ),
              Switch(
                key: const ValueKey('diet_supplements_switch'),
                value: active,
                onChanged: _busy ? null : (v) => _onToggle(v, active),
                activeThumbColor: AppColors.accent,
                activeTrackColor: AppColors.accent.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
        if (paused) ...[
          const SizedBox(height: 8),
          Text(kDietSupplementsPausedHint,
              key: const ValueKey('diet_supplements_paused_hint'), style: dim),
        ],
        if (active) ...[
          const SizedBox(height: 12),
          DietSupplementCard(foodType: foodType),
        ],
      ],
    );
  }
}

/// The supplement card for [foodType]: one row per supplement, then the
/// footer lines. No brands; the doses are the constants in
/// diet_supplement_doses.dart.
class DietSupplementCard extends StatelessWidget {
  const DietSupplementCard({super.key, required this.foodType});

  final FoodType foodType;

  @override
  Widget build(BuildContext context) {
    final dim =
        AppTypography.body.copyWith(fontSize: 12, color: AppColors.textDim);
    return WardCard(
      key: const ValueKey('diet_supplement_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Daily supplements',
              style: AppTypography.body.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          for (final r in supplementCardFor(foodType)) ...[
            const SizedBox(height: 12),
            Text(r.name,
                style: AppTypography.body.copyWith(
                    fontSize: 13, color: AppColors.textPrimary)),
            Text(r.dose,
                style: AppTypography.body
                    .copyWith(fontSize: 13, color: AppColors.accent)),
            Text(r.note, style: dim),
          ],
          const SizedBox(height: 14),
          for (final line in kSupplementCardFooter) ...[
            Text(line, style: dim),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}
