import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'custom_food_sheet.dart';

/// `YOUR FOODS` strip on the Nutrition page (APK Test #3 / Plan D).
///
/// Mirrors `_buildYourExercisesSection` from `train_screen.dart` (APK
/// Test #1 D6). Header has a mono `YOUR FOODS` eyebrow + a `+ ADD
/// CUSTOM` `WardChip` pill on the right. Body is a horizontal scroll
/// of `WardChip` rows, one per `custom_food_*` key in `customBox`,
/// sorted newest-first.
///
/// Status pill rules:
///   * `approved == true`               → APPROVED (ok)
///   * `submitted_to_db == true` only   → PENDING  (warn)
///   * neither                           → DRAFT    (textMute)
///
/// Tap any chip → existing `CustomFoodSheet` opens for edit/submit/
/// delete. Same sheet opens in create mode from the `+ ADD CUSTOM`
/// pill.
class YourFoodsSection extends ConsumerWidget {
  const YourFoodsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customBox = HiveService.instance.customBox;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'YOUR FOODS',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => showCustomFoodSheet(context),
                child: const WardChip(
                  label: '+ ADD CUSTOM',
                  tone: WardChipTone.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<Box<dynamic>>(
            valueListenable: customBox.listenable(),
            builder: (context, box, _) {
              final foods = _collectCustomFoods(box);
              if (foods.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(
                    children: [
                      Text(
                        'No custom foods yet — tap ',
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.textDim),
                      ),
                      GestureDetector(
                        onTap: () => showCustomFoodSheet(context),
                        child: Text(
                          '+ ADD CUSTOM',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        ' to add one.',
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.textDim),
                      ),
                    ],
                  ),
                );
              }
              return SizedBox(
                height: 68,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: foods.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) =>
                      _CustomFoodChip(food: foods[i]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Reads every `custom_food_*` entry from `customBox` newest-first.
  /// Filters out malformed entries.
  List<Map<String, dynamic>> _collectCustomFoods(Box<dynamic> box) {
    final out = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('custom_food_')) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      map['_key'] = key;
      out.add(map);
    }
    // Newest first. Hive keys are `custom_food_<ms>` so descending
    // string sort == recency order.
    out.sort((a, b) => (b['_key'] as String).compareTo(a['_key'] as String));
    return out;
  }
}

class _CustomFoodChip extends StatelessWidget {
  const _CustomFoodChip({required this.food});

  final Map<String, dynamic> food;

  @override
  Widget build(BuildContext context) {
    final name = food['name'] as String? ?? 'Unnamed';
    final submitted = food['submitted_to_db'] == true;
    final approved = food['approved'] == true;

    final (String statusLabel, Color statusColor) = approved
        ? ('APPROVED', AppColors.ok)
        : submitted
            ? ('PENDING', AppColors.warn)
            : ('DRAFT', AppColors.textMute);

    return GestureDetector(
      onTap: () => showCustomFoodSheet(context),
      child: Container(
        constraints: const BoxConstraints(minWidth: 140, maxWidth: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.line2),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              statusLabel,
              style: AppTypography.monoXs.copyWith(
                color: statusColor,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
