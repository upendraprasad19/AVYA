import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/ai_coach_provider.dart';

/// "SUGGESTED ACTIONS" block on the AI Coach screen — matches the
/// Wardroom handoff spec (`design_handoff_wardroom/src/screens/coach.
/// jsx` lines 63–92): mono eyebrow with right-aligned "N NEW" count
/// and three cards, each with a 46-px [WardCategorySidebar] (rotated
/// vertical mono label) on the left and title + rationale + APPLY /
/// SKIP mono CTAs on the right.
///
/// For now the 3 suggestions are a static hand-picked set matching
/// the JSX sample (training / sleep / meal). Wiring to a real
/// server-side `coachSuggestionsProvider` is deferred — the coach
/// would need to emit structured action suggestions with `apply`
/// and `skip` tool-calls attached, which isn't in the ai-proxy
/// contract yet. APPLY → sends the suggestion as a user message to
/// the coach (which keeps the loop sensible even without a real
/// apply tool — the coach will explain or execute).
class CoachSuggestedActions extends ConsumerWidget {
  const CoachSuggestedActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = _SuggestedAction.defaults;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'SUGGESTED ACTIONS',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${suggestions.length} NEW',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textGhost,
                  fontSize: 9,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < suggestions.length; i++) ...[
            _SuggestionCard(
              suggestion: suggestions[i],
              onApply: () => _apply(ref, suggestions[i]),
              onSkip: () {
                // No-op for now — static list; when a real provider
                // lands the skip handler will mark the item dismissed
                // so it doesn't reappear on the next rebuild.
              },
            ),
            if (i < suggestions.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  void _apply(WidgetRef ref, _SuggestedAction suggestion) {
    // Sending the suggestion as a user-authored chat message is the
    // pragmatic MVP: the coach then explains / modifies the plan /
    // generates a tool-intent for confirmation, reusing the existing
    // tool-calling pipeline rather than inventing a parallel apply
    // channel. Consistent with AppConstants.featureAiCoachUnlimited.
    ref.read(sendMessageProvider.notifier).send(suggestion.applyPrompt);
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.onApply,
    required this.onSkip,
  });

  final _SuggestedAction suggestion;
  final VoidCallback onApply;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line2),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Vertical category rail — 46px wide, rotated mono label.
              WardCategorySidebar(
                label: suggestion.category,
                width: 46,
                color: AppColors.accent,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        suggestion.title,
                        style: AppTypography.h3.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        suggestion.rationale,
                        style: AppTypography.body.copyWith(
                          fontSize: 12,
                          color: AppColors.textDim,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: onApply,
                            behavior: HitTestBehavior.opaque,
                            child: Text(
                              'APPLY \u2192',
                              style: AppTypography.monoXs.copyWith(
                                fontSize: 9,
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: onSkip,
                            behavior: HitTestBehavior.opaque,
                            child: Text(
                              'SKIP',
                              style: AppTypography.monoXs.copyWith(
                                fontSize: 9,
                                color: AppColors.textGhost,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestedAction {
  const _SuggestedAction({
    required this.category,
    required this.title,
    required this.rationale,
    required this.applyPrompt,
  });

  /// Vertical rail label (e.g. `TRAINING`, `SLEEP`, `MEAL`). Kept
  /// short — the rail is only 46 px wide.
  final String category;
  final String title;
  final String rationale;

  /// Message sent to the coach when APPLY is tapped. Framed as a
  /// user-authored intent so the coach can explain / adjust / execute
  /// via its existing tool-calling contract.
  final String applyPrompt;

  static const defaults = <_SuggestedAction>[
    _SuggestedAction(
      category: 'TRAINING',
      title: 'Review this week\u2019s volume',
      rationale:
          'Tell me if my training load is balanced for this phase.',
      applyPrompt:
          'Can you review my training volume this week and tell me '
          'if it\'s balanced for this phase?',
    ),
    _SuggestedAction(
      category: 'SLEEP',
      title: 'Check my sleep trend',
      rationale:
          'How has my sleep looked over the last 7 days vs. training days?',
      applyPrompt:
          'How has my sleep looked this week, and is it affecting '
          'my training?',
    ),
    _SuggestedAction(
      category: 'MEAL',
      title: 'Plan my next meal',
      rationale:
          'Suggest something high-protein that fits my remaining macros.',
      applyPrompt:
          'Suggest a high-protein meal that fits my remaining macros '
          'for today.',
    ),
  ];
}
