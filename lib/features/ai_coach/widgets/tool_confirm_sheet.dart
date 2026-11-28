import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/colors.dart';
import '../models/tool_intent.dart';
import '../providers/pending_tool_intents_provider.dart';
import '../services/tool_dispatcher.dart' show profileInjuryAdded;
import 'tool_confirm_card.dart' show executedMessageFor;
import 'package:icanbefitter/core/theme/typography.dart';

/// Bottom sheet modal for `destructive` confirmation class tool intents.
///
/// Renders a per-intent diff preview (passed via [diffPreview]) above
/// Cancel + Confirm buttons. No countdown — destructive actions require
/// explicit user confirmation.
///
/// Use [ToolConfirmSheet.show] to present it.
class ToolConfirmSheet extends ConsumerStatefulWidget {
  final ToolIntent intent;
  final Widget diffPreview;

  const ToolConfirmSheet({
    super.key,
    required this.intent,
    required this.diffPreview,
  });

  static Future<void> show(
    BuildContext context, {
    required ToolIntent intent,
    required Widget diffPreview,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ToolConfirmSheet(intent: intent, diffPreview: diffPreview),
    );
  }

  @override
  ConsumerState<ToolConfirmSheet> createState() => _ToolConfirmSheetState();
}

class _ToolConfirmSheetState extends ConsumerState<ToolConfirmSheet> {
  bool _executing = false;

  Future<void> _confirm() async {
    if (_executing) return;
    setState(() => _executing = true);
    final result = await ref
        .read(pendingToolIntentsProvider.notifier)
        .confirm(widget.intent.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    if (!result.success) {
      messenger.showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? 'Failed')),
      );
    } else if (profileInjuryAdded(result) != null ||
        _changedNoWorkout(result.data)) {
      // Unit 3C (d77, B-pass seat B F1): a destructive intent is confirmed here, not on the chat card, so the
      // injury the coach saved to the profile is announced here: `Workouts updated · Knee added to your injuries`.
      // An injury change that swapped nothing says so, or the tap looks like it did something.
      messenger.showSnackBar(
        SnackBar(content: Text(executedMessageFor(widget.intent, result.data))),
      );
    }
  }

  bool _changedNoWorkout(Object? data) {
    if (widget.intent.type != 'modify_workout_for_injury' || data is! Map) {
      return false;
    }
    final swaps = data['swaps'];
    return swaps is List && swaps.isEmpty;
  }

  void _cancel() {
    ref.read(pendingToolIntentsProvider.notifier).reject(widget.intent.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              widget.intent.previewSummary.isNotEmpty
                  ? widget.intent.previewSummary
                  : 'Confirm action',
              style: AppTypography.body.copyWith(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            Flexible(child: SingleChildScrollView(child: widget.diffPreview)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _executing ? null : _cancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: Text(
                      'Cancel',
                      style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _executing ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _executing
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            'Confirm',
                            style: AppTypography.body.copyWith(fontWeight: FontWeight.w800),
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
