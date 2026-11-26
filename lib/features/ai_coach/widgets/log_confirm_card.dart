import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import '../providers/ai_coach_provider.dart';
import '../services/coach_meal_log.dart';
import '../services/conversational_log_handler.dart';
import 'coach_meal_items_view.dart';

/// Inline confirmation card for an AI-detected log action.
///
/// Wardroom styling: sharp 2-px accent outline card with Mono-caps
/// CONFIRM / SKIP slabs and a semantic strip keyed to the log type.
/// Appears below the last AI message bubble in the chat list.
/// Water, weight, sleep and measurement cards auto-confirm after 5 seconds
/// with a countdown indicator. A FOOD card (OI-348 Landing 3b, founder P5)
/// shows one row per food and waits for CONFIRM, with no countdown, for at
/// most an hour ([PendingLogAction.foodCardTtl]); the kill switch
/// `disable_coach_meal_items_card` restores the old 5 s food card.
class LogConfirmCard extends ConsumerStatefulWidget {
  final PendingLogAction action;

  const LogConfirmCard({super.key, required this.action});

  @override
  ConsumerState<LogConfirmCard> createState() => LogConfirmCardState();
}

/// Public for tests only (OI-348 Landing 3b reads [debugCountdown]).
@visibleForTesting
class LogConfirmCardState extends ConsumerState<LogConfirmCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _countdownController;
  bool _isExecuting = false;

  /// OI-348 Landing 3b: a food card with the meal card on has no countdown.
  /// Decided once per mount, so the switch flipping mid-card changes nothing.
  late final bool _waitsForTap;

  /// The countdown controller, for tests (`isAnimating` proves no timer).
  @visibleForTesting
  AnimationController get debugCountdown => _countdownController;

  @override
  void initState() {
    super.initState();
    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _waitsForTap = widget.action.type == LogActionType.food &&
        coachMealItemsCardEnabled();
    // Auto-confirm after 5 seconds (never for a food card that waits for a tap)
    if (!_waitsForTap) {
      _countdownController.forward().whenComplete(_onAutoConfirm);
    }
  }

  @override
  void dispose() {
    _countdownController.dispose();
    super.dispose();
  }

  Future<void> _onAutoConfirm() async {
    if (mounted &&
        !widget.action.isLogged &&
        !widget.action.isDismissed &&
        !_isExecuting) {
      await _execute();
    }
  }

  Future<void> _execute() async {
    if (_isExecuting) return;
    // OI-348 Landing 3b: checked FIRST, before the save is claimed. A tap on
    // a food card past its hour (or a retry of a failed save past it) writes
    // nothing; a tap inside the hour runs to the end on createdAt's day.
    if (widget.action.isStaleFood(nowWall())) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('This suggestion has expired.')),
      );
      _dismiss();
      return;
    }
    setState(() => _isExecuting = true);
    _countdownController.stop();

    // OI-493 Landing B (B6): captured BEFORE the await (a non-autoDispose
    // provider), so a card unmounted during its save still marks the action
    // logged (the shared action object: a remounted card's countdown stops)
    // and still clears it.
    final actions = ref.read(pendingLogActionsProvider.notifier);
    final handler = ConversationalLogHandler(ref);
    final success = await handler.executeAction(widget.action);

    if (success) {
      actions.markLogged(widget.action.id);
      if (!mounted) {
        actions.removeSettled();
        return;
      }
      // Brief "Logged ✓" state, then remove
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        actions.removeSettled();
      }
    } else if (mounted) {
      setState(() => _isExecuting = false);
    }
  }

  void _dismiss() {
    _countdownController.stop();
    ref.read(pendingLogActionsProvider.notifier).dismiss(widget.action.id);
    ref.read(pendingLogActionsProvider.notifier).removeSettled();
  }

  Color get _typeColor {
    switch (widget.action.type) {
      case LogActionType.water:
        return AppColors.info;
      case LogActionType.weight:
        return AppColors.warn;
      case LogActionType.food:
        return AppColors.ok;
      case LogActionType.sleep:
        return AppColors.info;
      case LogActionType.measurement:
        return AppColors.proGold;
    }
  }

  IconData get _typeIcon {
    switch (widget.action.type) {
      case LogActionType.water:
        return Icons.water_drop_outlined;
      case LogActionType.weight:
        return Icons.monitor_weight_outlined;
      case LogActionType.food:
        return Icons.restaurant_outlined;
      case LogActionType.sleep:
        return Icons.bedtime_outlined;
      case LogActionType.measurement:
        return Icons.straighten_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLogged = widget.action.isLogged;
    if (_waitsForTap && !isLogged) return _buildFoodCard();

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: widget.action.isDismissed ? 0.0 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 4, left: 4, right: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.accent, width: 2),
        ),
        child: Row(
          children: [
            // Left color strip keyed to log type
            Container(
              width: 3,
              height: 36,
              decoration: BoxDecoration(
                color: _typeColor,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
            ),
            const SizedBox(width: 10),

            // Type icon
            Icon(_typeIcon, size: 18, color: _typeColor),
            const SizedBox(width: 10),

            // Label
            Expanded(
              child: isLogged
                  ? Text(
                      'LOGGED',
                      style: AppTypography.mono.copyWith(
                        color: AppColors.ok,
                        letterSpacing: 1.6,
                      ),
                    )
                  : Text(
                      widget.action.displayText,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),

            if (isLogged)
              const Icon(Icons.check_circle, size: 18, color: AppColors.ok)
            else ...[
              // Countdown progress
              SizedBox(
                width: 20,
                height: 20,
                child: AnimatedBuilder(
                  animation: _countdownController,
                  builder: (_, _) {
                    return CircularProgressIndicator(
                      value: 1.0 - _countdownController.value,
                      strokeWidth: 2,
                      backgroundColor: AppColors.line2,
                      valueColor: AlwaysStoppedAnimation(_typeColor),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),

              // CONFIRM slab — sharp 2-px accent
              GestureDetector(
                onTap: _isExecuting ? null : _execute,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                  ),
                  child: Text(
                    'CONFIRM',
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.bgDeep,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // SKIP button — Mono caps
              GestureDetector(
                onTap: _dismiss,
                child: Text(
                  'SKIP',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textDim,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// OI-348 Landing 3b: the food card waits for CONFIRM and shows one row per
  /// food, the slot and the total `logMeal` will store. A Column (header,
  /// rows, actions), not today's single Row, so the rows get the card's full
  /// width.
  Widget _buildFoodCard() {
    final data = widget.action.data;
    final items = coachItemsFromTag(data) ?? const [];
    final totals = NutritionWriteService.mealTotals(items);
    final slot =
        resolveCoachMealSlot(coachMealTypeOf(data), widget.action.createdAt);
    final stale = widget.action.isStaleFood(nowWall());
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: widget.action.isDismissed ? 0.0 : 1.0,
      child: Container(
        key: const Key('coach_food_card'),
        margin: const EdgeInsets.only(top: 6, bottom: 4, left: 4, right: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
              color: stale ? AppColors.line2 : AppColors.accent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _typeColor,
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(_typeIcon, size: 18, color: _typeColor),
                const SizedBox(width: 10),
                Text(
                  stale ? 'EXPIRED: MEAL' : 'MEAL',
                  style: AppTypography.mono.copyWith(
                    color: stale ? AppColors.textDim : AppColors.textPrimary,
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),
            if (!stale) ...[
              const SizedBox(height: 8),
              CoachMealItemsView(
                items: items,
                totalKcal: totals.kcal,
                totalProtein: totals.protein,
                slot: slot[0].toUpperCase() + slot.substring(1),
              ),
            ],
            const SizedBox(height: 10),
            // B-pass F1: an expired card keeps SKIP, so it can always be
            // cleared from the chat; only CONFIRM goes.
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!stale) ...[
                  GestureDetector(
                    key: const Key('coach_food_card_confirm'),
                    onTap: _isExecuting ? null : _execute,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppRadius.sharp),
                      ),
                      child: Text(
                        'CONFIRM',
                        style: AppTypography.monoXs.copyWith(
                          color: AppColors.bgDeep,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                GestureDetector(
                  key: const Key('coach_food_card_skip'),
                  onTap: _dismiss,
                  child: Text(
                    'SKIP',
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.textDim,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
