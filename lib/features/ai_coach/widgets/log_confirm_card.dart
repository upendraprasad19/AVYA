import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import '../providers/ai_coach_provider.dart';
import '../services/conversational_log_handler.dart';

/// Inline confirmation card for an AI-detected log action.
///
/// Wardroom styling: sharp 2-px accent outline card with Mono-caps
/// CONFIRM / SKIP slabs and a semantic strip keyed to the log type.
/// Appears below the last AI message bubble in the chat list.
/// Auto-confirms after 5 seconds with a countdown indicator.
class LogConfirmCard extends ConsumerStatefulWidget {
  final PendingLogAction action;

  const LogConfirmCard({super.key, required this.action});

  @override
  ConsumerState<LogConfirmCard> createState() => _LogConfirmCardState();
}

class _LogConfirmCardState extends ConsumerState<LogConfirmCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _countdownController;
  bool _isExecuting = false;

  @override
  void initState() {
    super.initState();
    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    // Auto-confirm after 5 seconds
    _countdownController.forward().whenComplete(_onAutoConfirm);
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
    setState(() => _isExecuting = true);
    _countdownController.stop();

    final handler = ConversationalLogHandler(ref);
    final success = await handler.executeAction(widget.action);

    if (success && mounted) {
      ref.read(pendingLogActionsProvider.notifier).markLogged(widget.action.id);
      // Brief "Logged ✓" state, then remove
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        ref.read(pendingLogActionsProvider.notifier).removeSettled();
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
}
