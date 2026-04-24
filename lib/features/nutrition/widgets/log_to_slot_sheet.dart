import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../providers/nutrition_provider.dart';
import '../services/meal_slot_inference.dart';
import 'ai_breakdown_card.dart';
import 'food_logger_section.dart';
import 'food_search_sheet.dart';
import 'scan_meal_section.dart';

/// Bottom sheet launched from the `+ LOG` CTA on each slot row in
/// `TodaysMealsCard`. Slot is locked (chosen by the tap), user picks
/// between AI / SCAN / SEARCH tabs. AI selected by default because that's
/// the primary always-visible input on the page anyway — the sheet
/// mirrors the same pattern without the scroll cost.
///
/// Wires `mealTypeProvider` to the locked slot on open so any save path
/// (AI breakdown save, scan save, food-search tile-log) picks up the
/// correct slot. The chip inside the AI breakdown / scan result can
/// still override it — that's a user choice, not a bug.
class LogToSlotSheet {
  LogToSlotSheet._();

  static void show(BuildContext context, {required String slot}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogToSlotSheetBody(slot: slot),
    );
  }
}

class _LogToSlotSheetBody extends ConsumerStatefulWidget {
  const _LogToSlotSheetBody({required this.slot});
  final String slot;

  @override
  ConsumerState<_LogToSlotSheetBody> createState() =>
      _LogToSlotSheetBodyState();
}

class _LogToSlotSheetBodyState extends ConsumerState<_LogToSlotSheetBody> {
  int _tabIndex = 0; // 0=AI, 1=SCAN, 2=SEARCH

  @override
  void initState() {
    super.initState();
    // Lock the global meal slot to the tapped row so every save path in
    // the sheet writes to the right bucket. Deferred so Riverpod isn't
    // mutated during build/init.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(mealTypeProvider.notifier).select(widget.slot);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: screenH * 0.80,
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.cardL)),
          border: Border(
            top: BorderSide(color: AppColors.line2, width: 1),
          ),
        ),
        child: Column(
          children: [
            // -- Grab handle --
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // -- Header --
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Text(
                    'LOG TO ${mealSlotLabel(widget.slot)}',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 2,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: AppColors.textDim, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // -- Tab bar --
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  _tab(0, 'AI'),
                  const SizedBox(width: 8),
                  _tab(1, 'SCAN'),
                  const SizedBox(width: 8),
                  _tab(2, 'SEARCH'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const WardRule(margin: EdgeInsets.zero),

            // -- Content --
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  14,
                  AppSpacing.screenPadding,
                  24,
                ),
                child: _buildTabContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(int index, String label) {
    final isActive = index == _tabIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                label,
                style: AppTypography.mono.copyWith(
                  color: isActive ? AppColors.accent : AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
            ),
            Container(
              height: 2,
              color: isActive ? AppColors.accent : AppColors.line2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tabIndex) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            FoodLoggerSection(),
            SizedBox(height: 10),
            // Conditional breakdown card — appears once analysis completes,
            // same card as on the main screen. Slot is already locked by
            // initState so the save path uses this slot by default.
            AiBreakdownCard(),
          ],
        );
      case 1:
        return const ScanMealSection();
      case 2:
        // For search, we pop and open the existing search sheet with the
        // slot threaded through. Keeps behavior consistent with the
        // page-level "+ LOG" tap-to-search flow and avoids double-sheet
        // nesting inside this sheet's scroll view.
        return _SearchRedirect(slot: widget.slot);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _SearchRedirect extends StatelessWidget {
  const _SearchRedirect({required this.slot});
  final String slot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(Icons.search, color: AppColors.textDim, size: 36),
          const SizedBox(height: 10),
          Text(
            'Open the full food search',
            style: AppTypography.body.copyWith(color: AppColors.textDim),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              // Defer so the sheet fully dismisses before pushing the
              // next one (avoids double-animation on slower devices).
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showFoodSearchSheet(context, mealType: slot);
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
              child: Text(
                'OPEN SEARCH',
                style: AppTypography.mono.copyWith(
                  color: AppColors.bgDeep,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
