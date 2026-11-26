import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/ai_coach_provider.dart';

/// "TODAY'S INSIGHT" quote card at the top of the AI Coach screen —
/// renders the latest [coachInsightProvider] string inside a
/// [WardInsightQuote] surface. Matches the Wardroom handoff spec
/// (`design_handoff_wardroom/src/screens/coach.jsx` lines 33–61):
/// gradient cardTop→card background, 40%-accent border, giant gold
/// watermark `"` top-right, italic Fraunces body.
///
/// No primary/secondary CTAs for now — the JSX sample shows
/// `REST TODAY ✓` / `WHY?` buttons, but those labels only make sense
/// when the insight text is specifically a rest recommendation.
/// Until the coach emits structured action suggestions (deferred to
/// PR AH or later), shipping hardcoded CTA labels that don't match
/// variable body text would look broken more often than not.
class CoachInsightSection extends ConsumerWidget {
  const CoachInsightSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(coachInsightProvider);
    if (insight.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
      child: WardInsightQuote(
        eyebrow: "TODAY'S INSIGHT",
        segments: [InsightSegment(insight)],
      ),
    );
  }
}
