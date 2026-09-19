import 'package:flutter/material.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Unit 1 (coach-completion-tap-card) — the coach's early-finish prompt.
///
/// Rendered by the chat area for a `ChatMessage(kind: 'completion_prompt')`
/// after a coach `logSet` on an active scheduled day that is NOT yet
/// all-logged. It supersedes the old hidden side-effect where one logged
/// exercise silently flipped the whole day to `completed` (inflating streak /
/// rank / deployment). Now the user decides: keep logging, or complete now.
///
/// Coach-styled to match the AI [ChatBubble] (left tail, [AppColors.card] on a
/// hairline [AppColors.line2] border), then a two-button row using WardSet
/// primitives ([WardButton]) in the Campaign-Gold Wardroom voice.
///
/// While a tap is in flight, [isBusy] disables both buttons and swaps the
/// [Complete workout] label for a small spinner so a double-tap can't fire two
/// completions (the writer is idempotent regardless — this is UX polish).
class CompletionPromptCard extends StatelessWidget {
  /// Total planned exercises for the day.
  final int planned;

  /// How many planned exercises already have a log today.
  final int logged;

  /// [Complete workout] — mark the scheduled day complete now.
  final VoidCallback? onComplete;

  /// [Log more] — dismiss the card and return focus to the composer.
  final VoidCallback? onLogMore;

  /// True while a [Complete workout] tap is being processed.
  final bool isBusy;

  const CompletionPromptCard({
    super.key,
    required this.planned,
    required this.logged,
    required this.onComplete,
    required this.onLogMore,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    const soft = Radius.circular(6);
    const tail = Radius.circular(2);

    // Progress line — only shown when we have a real planned count, so an
    // ad-hoc day (planned == 0) doesn't read "0 of 0 down".
    final String? progress =
        planned > 0 ? '$logged of $planned logged so far.' : null;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.only(
            topLeft: tail,
            topRight: soft,
            bottomLeft: soft,
            bottomRight: soft,
          ),
          border: Border.all(color: AppColors.line2, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'BRIDGE',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Recruit — log more exercises?',
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 4),
              Text(
                progress,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.textMute,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // finding-3 — the two CTAs live SIDE-BY-SIDE when the card is wide
            // enough and STACK VERTICALLY on a narrow device. WardButton renders
            // its label UPPERCASE in 11px Fraunces with +2.5 letter-spacing and
            // its inner Text neither wraps nor ellipsizes; two Expanded buttons
            // carrying 'LOG MORE' + 'COMPLETE' (plus, while busy, a 12px spinner
            // + 10px gap in the primary) horizontal-overflow the Row on a 375px
            // device (the busy state overflowed by 12px in the widget test).
            // Stacking below a width threshold guarantees no RenderFlex overflow
            // in ANY state (busy or idle) at ANY device width — the label stays
            // full, so the CTA copy is never clipped.
            LayoutBuilder(
              builder: (context, constraints) {
                final logMore = WardButton(
                  label: 'Log more',
                  variant: WardButtonVariant.ghost,
                  size: WardButtonSize.small,
                  onPressed: isBusy ? null : onLogMore,
                );
                final complete = WardButton(
                  label: 'Complete',
                  variant: WardButtonVariant.primary,
                  size: WardButtonSize.small,
                  onPressed: isBusy ? null : onComplete,
                  trailing: isBusy
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.bgDeep,
                          ),
                        )
                      : null,
                );

                // Below ~320px the two small WardButtons (each needs ~150px for
                // its uppercased label + padding, + the primary's spinner when
                // busy) can't sit side-by-side without overflow. Stack them.
                const sideBySideMinWidth = 320.0;
                if (constraints.maxWidth < sideBySideMinWidth) {
                  return Column(
                    children: [
                      complete,
                      const SizedBox(height: AppSpacing.inlineGap),
                      logMore,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: logMore),
                    const SizedBox(width: AppSpacing.inlineGap),
                    Expanded(child: complete),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
