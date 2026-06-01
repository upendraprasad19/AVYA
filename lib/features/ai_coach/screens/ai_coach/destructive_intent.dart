part of 'screen.dart';

extension _DestructiveIntent on _AiCoachScreenState {

  // ────────────────────────────────────────────────────────────────
  // Phase A.11 — destructive tool intent tile (opens modal sheet)
  // ────────────────────────────────────────────────────────────────

  Widget _buildDestructiveIntentTile(BuildContext context, ToolIntent intent) {
    // C-6: Terminal states collapse to a small pill so the chat thread
    // doesn't pile up with stale "Review" cards. Mirrors
    // ToolConfirmCard._buildExecutedState / _buildRejectedState.
    if (intent.status == ToolIntentStatus.executed) {
      return _buildIntentTerminalPill(
        intent: intent,
        label: 'Applied',
        color: AppColors.ok,
        icon: Icons.check_circle,
      );
    }
    if (intent.status == ToolIntentStatus.rejected) {
      return _buildIntentTerminalPill(
        intent: intent,
        label: 'Dismissed',
        color: AppColors.textDim,
        icon: Icons.cancel_outlined,
      );
    }
    if (intent.status == ToolIntentStatus.expired) {
      return _buildIntentTerminalPill(
        intent: intent,
        label: 'Expired',
        color: AppColors.textDim,
        icon: Icons.schedule,
      );
    }

    final isExecuting = intent.status == ToolIntentStatus.executing;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.accent.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Review: ${intent.previewSummary}',
                      style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap APPLY to review and confirm changes.',
                      style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // C-3: Explicit Apply / Dismiss buttons replace the old chevron
          // tap target — testers were not discovering the row was tappable.
          Row(
            children: [
              Expanded(
                child: WardButton(
                  label: 'APPLY',
                  variant: WardButtonVariant.primary,
                  size: WardButtonSize.small,
                  onPressed: isExecuting
                      ? null
                      : () => _openIntentSheet(context, intent),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WardButton(
                  label: 'DISMISS',
                  variant: WardButtonVariant.ghost,
                  size: WardButtonSize.small,
                  onPressed: isExecuting
                      ? null
                      : () {
                          ref
                              .read(pendingToolIntentsProvider.notifier)
                              .reject(intent.id);
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIntentTerminalPill({
    required ToolIntent intent,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label: ${intent.previewSummary}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  void _openIntentSheet(BuildContext context, ToolIntent intent) {
    final Widget diffPreview;
    switch (intent.type) {
      case 'swap_exercise':
        diffPreview = SwapExerciseDiff(intent: intent);
        break;
      case 'modify_workout_for_injury':
        diffPreview = InjuryModifyDiff(intent: intent);
        break;
      case 'reschedule_week':
        diffPreview = RescheduleWeekDiff(intent: intent);
        break;
      case 'generate_hotel_workout':
        diffPreview = HotelWorkoutDiff(intent: intent);
        break;
      case 'regenerate_plan_block':
        diffPreview = RegeneratePlanDiff(intent: intent);
        break;
      case 'pause_plan':
        diffPreview = PausePlanDiff(intent: intent);
        break;
      case 'switch_goal':
        diffPreview = SwitchGoalDiff(intent: intent);
        break;
      case 'create_custom_template':
        diffPreview = CustomTemplateDiff(intent: intent);
        break;
      case 'schedule_template':
        diffPreview = ScheduleTemplateDiff(intent: intent);
        break;
      default:
        diffPreview = const Text('Confirm this action?');
    }
    ToolConfirmSheet.show(
      context,
      intent: intent,
      diffPreview: diffPreview,
    );
  }
}
