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

/// The five modes hosted by [LogFoodSheet]. AI is the default tab.
enum LogFoodMode { ai, scan, cart, barcode, search }

/// Opens the LogFoodSheet bottom sheet (75% screen height).
void showLogFoodSheet(BuildContext context, {LogFoodMode? initial}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LogFoodSheet(initial: initial ?? LogFoodMode.ai),
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
  const LogFoodSheet({super.key, required this.initial});
  final LogFoodMode initial;

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
            'LOG FOOD',
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
