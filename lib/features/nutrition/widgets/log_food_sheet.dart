import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'log_food_modes/ai_mode_body.dart';
import 'log_food_modes/scan_mode_body.dart';
import 'log_food_modes/cart_mode_body.dart';
import 'log_food_modes/barcode_mode_body.dart';
import 'log_food_modes/search_mode_body.dart';
import '../providers/nutrition_provider.dart' show mealTypeProvider;
import '../services/meal_slot_inference.dart' show inferMealSlot, mealSlotLabel;

/// The five modes hosted by [LogFoodSheet]. AI is the default tab.
enum LogFoodMode { ai, scan, cart, barcode, search }

/// Opens the LogFoodSheet bottom sheet (75% screen height).
void showLogFoodSheet(BuildContext context, {LogFoodMode? initial, String? lockedSlot}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LogFoodSheet(
      initial: initial ?? LogFoodMode.ai,
      lockedSlot: lockedSlot,
    ),
  );
}

/// + LOG FOOD bottom sheet (APK Test #3 / Plan D).
///
/// Header: title + close affordance.
/// Tabs:   segmented WardChip row [✨ AI · 📷 SCAN · 🛒 CART ·
///         🔢 BAR · 🔍 SEARCH].
/// Body:   active mode renders inside a 75%-height container.
///         AI is default. Each mode dismisses the sheet via [_dismiss]
///         on successful save.
class LogFoodSheet extends ConsumerStatefulWidget {
  const LogFoodSheet({super.key, required this.initial, this.lockedSlot});
  final LogFoodMode initial;

  /// When set (opened from a specific meal-slot's `+ LOG` CTA), the sheet
  /// SEEDS `mealTypeProvider` with this slot on open and titles itself
  /// "LOG TO {SLOT}" instead of the generic "LOG FOOD". The title tracks
  /// the live provider value thereafter (not the static [lockedSlot]
  /// param) — a tab's own meal-slot selector (the AI chip, the Barcode
  /// pill row) can still change it, which is a deliberate user choice, not
  /// a bug; the title staying in sync with that choice is what "locked"
  /// means here (B-pass finding, 2026-09-20 — the title previously stayed
  /// frozen on the originally-tapped slot even after a tab's own selector
  /// moved the actual write destination elsewhere).
  final String? lockedSlot;

  @override
  ConsumerState<LogFoodSheet> createState() => _LogFoodSheetState();
}

class _LogFoodSheetState extends ConsumerState<LogFoodSheet> {
  // Default tab — pinned by test/contracts/log_food_sheet_test.dart.
  // Overridden in initState() from widget.initial for caller-specified
  // entry points.
  LogFoodMode _active = LogFoodMode.ai;

  @override
  void initState() {
    super.initState();
    _active = widget.initial;
    // Always seed mealTypeProvider on open — round-2 plan review finding,
    // 2026-09-20: when lockedSlot is null (the free-floating "+ LOG FOOD"
    // entry), the provider previously kept whatever value a PRIOR locked
    // sheet had last written, since MealTypeNotifier.build() only infers
    // once per app session. A user opening "LOG TO BREAKFAST" earlier and
    // "+ LOG FOOD" later would silently log the second entry to breakfast
    // too. Re-inferring the current time-of-day slot on every unlocked
    // open closes that leak.
    final slot = widget.lockedSlot ?? inferMealSlot(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(mealTypeProvider.notifier).select(slot);
    });
  }

  void _dismiss() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final sheetH = screenH * 0.75;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: sheetH,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.card)),
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildTabs(),
            const WardRule(margin: EdgeInsets.zero),
            Expanded(child: _buildActiveBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    // Watches the live provider value (not the static widget.lockedSlot)
    // so the title never goes stale if a tab's own selector moves the
    // actual write destination after open — B-pass finding, 2026-09-20.
    final currentSlot = ref.watch(mealTypeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
      child: Row(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Spacer(),
          Text(
            widget.lockedSlot == null
                ? 'LOG FOOD'
                : 'LOG TO ${mealSlotLabel(currentSlot)}',
            style: AppTypography.mono.copyWith(
              color: AppColors.textPrimary,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.close, color: AppColors.textDim),
            onPressed: _dismiss,
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          _tab(LogFoodMode.ai, '✨ AI'),
          const SizedBox(width: 6),
          _tab(LogFoodMode.scan, '📷 SCAN'),
          const SizedBox(width: 6),
          _tab(LogFoodMode.cart, '🛒 CART'),
          const SizedBox(width: 6),
          _tab(LogFoodMode.barcode, '🔢 BAR'),
          const SizedBox(width: 6),
          _tab(LogFoodMode.search, '🔍 SEARCH'),
        ],
      ),
    );
  }

  Widget _tab(LogFoodMode mode, String label) {
    final selected = _active == mode;
    return Center(
      child: GestureDetector(
        onTap: () => setState(() => _active = mode),
        child: WardChip(
          label: label,
          tone: selected ? WardChipTone.gold : WardChipTone.neutral,
        ),
      ),
    );
  }

  Widget _buildActiveBody() {
    return switch (_active) {
      LogFoodMode.ai => AiModeBody(onLogged: _dismiss),
      LogFoodMode.scan => ScanModeBody(onLogged: _dismiss),
      LogFoodMode.cart => const CartModeBody(),
      LogFoodMode.barcode => BarcodeModeBody(onLogged: _dismiss),
      LogFoodMode.search => SearchModeBody(onLogged: _dismiss),
    };
  }
}
