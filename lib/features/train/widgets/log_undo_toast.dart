import 'package:flutter/material.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// The Active Workout list area in LOG mode: [list] with [toast] over its top
/// edge. The tree shape is the SAME whether or not a toast shows (the list is
/// always child 0 of one Stack), so showing or clearing the toast never
/// rebuilds the list: no scroll reset and no disposed cards losing typed
/// values (B-pass finding 1). Disabled (flag OFF): the bare list, as before.
class LogUndoToastHost extends StatelessWidget {
  const LogUndoToastHost({
    super.key,
    required this.enabled,
    required this.list,
    this.toast,
  });

  final bool enabled;
  final Widget list;
  final Widget? toast;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return list;
    return Stack(
      fit: StackFit.expand,
      children: [
        list,
        if (toast != null)
          Positioned(top: 8, left: 16, right: 16, child: toast!),
      ],
    );
  }
}

/// The toast after a LOG (flag `enable_log_exercise_button`, batch 2,
/// docs/plans/log-exercise-batch2.md §5.1): `{Exercise} logged · …` + UNDO.
///
/// Built inside the active-workout screen's own tree, not as a SnackBar, so it
/// cannot outlive the screen. Only UNDO takes touches: the background and text
/// sit in [IgnorePointer], so a drag or tap on the rest of the toast reaches
/// the list underneath.
class LogUndoToast extends StatelessWidget {
  const LogUndoToast({super.key, required this.text, required this.onUndo});

  final String text;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
                border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3)),
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.textPrimary),
                  ),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: WardroomCopy.activeLogUndo,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onUndo,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: 44, minWidth: 64),
                  child: Center(
                    child: Text(
                      WardroomCopy.activeLogUndo,
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.accent,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
