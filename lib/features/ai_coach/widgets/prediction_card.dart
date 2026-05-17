import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/utils/card_share_service.dart';
import 'package:icanbefitter/shared/widgets/shareable_card.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Future Prediction card display — AI-Coach-scoped variant.
///
/// Wardroom styling: hero [WardCard] with Mono-caps eyebrow,
/// Fraunces body prose, gold [WardRule] separators, and sharp 2-px
/// accent slab CTAs. Shows post-onboarding prediction for all users;
/// PRO users get a "Update" action (monthly refresh).
class PredictionCard extends StatelessWidget {
  final String? predictionText;
  final DateTime? generatedAt;
  final bool isPro;
  final bool canRefresh;
  final bool isStale;
  final VoidCallback onRefreshTap;

  /// audit-2026-05-16 reader-side / R7 — prediction card placeholder
  /// copy used to say "Complete onboarding to get your personalised
  /// fitness prediction" whenever [predictionText] was empty, even for
  /// onboarded users whose prediction simply hadn't been generated yet
  /// (e.g. fresh install on a returning account — `prediction_text` is
  /// not restored from cloud). Caller now passes the actual onboarding
  /// state so the placeholder can branch:
  ///   - !onboarded  → "Complete onboarding..."
  ///   - onboarded   → "Tap UPDATE to generate your prediction"
  /// closes-diagnose: 2026-05-16-prediction-card-onboarding-copy
  final bool onboardingCompleted;

  const PredictionCard({
    super.key,
    this.predictionText,
    this.generatedAt,
    required this.isPro,
    required this.canRefresh,
    this.isStale = false,
    required this.onRefreshTap,
    this.onboardingCompleted = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasPrediction =
        predictionText != null && predictionText!.isNotEmpty;

    return WardCard(
      variant: WardCardVariant.hero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — Mono eyebrow + generated date
          Row(
            children: [
              const Icon(Icons.auto_graph, color: AppColors.accent, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  generatedAt != null
                      ? 'FORECAST \u00B7 ${_formatDate(generatedAt!).toUpperCase()}'
                      : 'FORECAST',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.accent,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const WardRule(gold: true, margin: EdgeInsets.zero),
          const SizedBox(height: 12),

          // Prediction text or placeholder
          if (hasPrediction) ...[
            Text(
              predictionText!,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
                height: 1.6,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            // "Read More" — opens full prediction in bottom sheet
            if (predictionText!.length > 120)
              GestureDetector(
                onTap: () => _showFullPrediction(context),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'READ MORE \u2192',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
              ),
          ] else ...[
            Text(
              onboardingCompleted
                  ? 'Your forecast is queued. Tap UPDATE to generate it now.'
                  : 'Complete onboarding to get your personalised fitness prediction.',
              style: AppTypography.body.copyWith(
                color: AppColors.textDim,
                height: 1.6,
              ),
            ),
            // Empty-state CTA for onboarded users — first prediction is
            // free per CLAUDE.md §14; surface a single UPDATE button so
            // they can actually trigger generation instead of staring at
            // a static "queued" message.
            if (onboardingCompleted) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: onRefreshTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.sharp),
                      border: Border.all(color: AppColors.accent, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.refresh,
                            size: 12, color: AppColors.bgDeep),
                        const SizedBox(width: 6),
                        Text(
                          'UPDATE',
                          style: AppTypography.mono.copyWith(
                            color: AppColors.bgDeep,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],

          // Stale prediction badge (free users whose goal changed)
          if (isStale && hasPrediction) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warn.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.soft),
                border: Border.all(
                  color: AppColors.warn.withValues(alpha: 0.33),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: AppColors.warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your goal has changed. Refresh prediction (PRO)',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.warn,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Action buttons
          if (hasPrediction) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                // Share button — sharp 2-px accent outline slab
                GestureDetector(
                  onTap: () => _showShareSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(AppRadius.sharp),
                      border: Border.all(color: AppColors.accent, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.share,
                            size: 12, color: AppColors.accent),
                        const SizedBox(width: 6),
                        Text(
                          'DISPATCH',
                          style: AppTypography.mono.copyWith(
                            color: AppColors.accent,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // Refresh button — PRO: functional, Free: gold PRO indicator
                GestureDetector(
                  onTap: isPro
                      ? (canRefresh ? onRefreshTap : null)
                      : onRefreshTap, // Free users tap → SnackBar in parent
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: isPro
                          ? (canRefresh
                              ? AppColors.accent
                              : AppColors.textDisabled.withValues(alpha: 0.3))
                          : AppColors.proGoldTint,
                      borderRadius: BorderRadius.circular(AppRadius.sharp),
                      border: Border.all(
                        color: isPro
                            ? (canRefresh
                                ? AppColors.accent
                                : AppColors.line2)
                            : AppColors.proGold,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh,
                          size: 12,
                          color: isPro
                              ? (canRefresh
                                  ? AppColors.bgDeep
                                  : AppColors.textDim)
                              : AppColors.proGold,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isPro
                              ? (canRefresh ? 'UPDATE' : 'UPDATED')
                              : 'PRO',
                          style: AppTypography.mono.copyWith(
                            color: isPro
                                ? (canRefresh
                                    ? AppColors.bgDeep
                                    : AppColors.textDim)
                                : AppColors.proGold,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showShareSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ShareablePredictionSheet(
        predictionText: predictionText!,
        generatedAt: generatedAt,
        predictionStats: null,
      ),
    );
  }

  void _showFullPrediction(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line2,
                    borderRadius: BorderRadius.circular(AppRadius.soft),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'YOUR 90-DAY PREDICTION',
                style: AppTypography.mono.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 1.8,
                ),
              ),
              if (generatedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Generated ${_formatDate(generatedAt!)}',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textMute,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const WardRule(gold: true, margin: EdgeInsets.zero),
              const SizedBox(height: 14),
              Text(
                predictionText!,
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 20),
              // Share button — sharp 2-px accent slab
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showShareSheet(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.sharp),
                    ),
                    child: Center(
                      child: Text(
                        'DISPATCH TO INSTAGRAM / WHATSAPP',
                        style: AppTypography.mono.copyWith(
                          color: AppColors.bgDeep,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

// ── Prediction Data for shareable card ──────────────────────────

/// Structured prediction stats for the shareable card.
class PredictionStats {
  final double? currentWeight;
  final double? predictedWeight;
  final double? currentBodyFat;
  final double? predictedBodyFat;
  final Map<String, PredictionLiftChange> lifts;
  final String? motivationalTagline;

  const PredictionStats({
    this.currentWeight,
    this.predictedWeight,
    this.currentBodyFat,
    this.predictedBodyFat,
    this.lifts = const {},
    this.motivationalTagline,
  });
}

class PredictionLiftChange {
  final String name;
  final double currentKg;
  final double predictedKg;

  const PredictionLiftChange({
    required this.name,
    required this.currentKg,
    required this.predictedKg,
  });
}

// ── Shareable Prediction Sheet ──────────────────────────────────

class _ShareablePredictionSheet extends StatefulWidget {
  final String predictionText;
  final DateTime? generatedAt;
  final PredictionStats? predictionStats;

  const _ShareablePredictionSheet({
    required this.predictionText,
    this.generatedAt,
    this.predictionStats,
  });

  @override
  State<_ShareablePredictionSheet> createState() =>
      _ShareablePredictionSheetState();
}

class _ShareablePredictionSheetState
    extends State<_ShareablePredictionSheet> {
  final _cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The shareable card
          ShareableCard(
            repaintKey: _cardKey,
            child: _buildPredictionContent(),
          ),
          const SizedBox(height: 16),

          // Share button — sharp 2-px accent slab
          GestureDetector(
            onTap: () async {
              await CardShareService.captureAndShare(
                _cardKey,
                filename: 'icanbefitter_prediction.png',
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
              child: Center(
                child: Text(
                  'DISPATCH TO INSTAGRAM / WHATSAPP',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.bgDeep,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Close
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'CLOSE',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textDim,
                  letterSpacing: 1.6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPredictionContent() {
    final stats = widget.predictionStats;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.auto_graph,
                  color: AppColors.accent, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'YOUR 90-DAY PREDICTION',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.accent,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const WardRule(gold: true, margin: EdgeInsets.zero),
          const SizedBox(height: 14),

          // Stats grid (if structured data available)
          if (stats != null) ...[
            _buildStatsGrid(stats),
            const SizedBox(height: 12),

            // Lift predictions
            if (stats.lifts.isNotEmpty) ...[
              Text(
                'KEY LIFTS',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 6),
              ...stats.lifts.values.map(_buildLiftRow),
              const SizedBox(height: 10),
            ],
          ],

          // Prediction text — capped at 500 chars for shareable image sizing.
          // Full text is available in the "Read More" bottom sheet.
          Text(
            widget.predictionText.length > 500
                ? '${widget.predictionText.substring(0, 500)}...'
                : widget.predictionText,
            style: AppTypography.body.copyWith(
              color: AppColors.textPrimary,
              height: 1.6,
            ),
          ),

          // Motivational tagline
          if (stats?.motivationalTagline != null) ...[
            const SizedBox(height: 10),
            Text(
              stats!.motivationalTagline!,
              style: AppTypography.displayItalicAccent.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          // Date generated
          if (widget.generatedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              'GENERATED ${_formatDate(widget.generatedAt!).toUpperCase()}',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsGrid(PredictionStats stats) {
    return Row(
      children: [
        if (stats.currentWeight != null && stats.predictedWeight != null)
          Expanded(
            child: _statCard(
              'WEIGHT',
              '${stats.currentWeight!.toStringAsFixed(1)} kg',
              '${stats.predictedWeight!.toStringAsFixed(1)} kg',
              stats.predictedWeight! < stats.currentWeight!,
            ),
          ),
        if (stats.currentWeight != null && stats.currentBodyFat != null)
          const SizedBox(width: 8),
        if (stats.currentBodyFat != null && stats.predictedBodyFat != null)
          Expanded(
            child: _statCard(
              'BODY FAT',
              '${stats.currentBodyFat!.toStringAsFixed(1)}%',
              '${stats.predictedBodyFat!.toStringAsFixed(1)}%',
              stats.predictedBodyFat! < stats.currentBodyFat!,
            ),
          ),
      ],
    );
  }

  Widget _statCard(
      String label, String current, String predicted, bool isPositive) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bgRaise,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                current,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.textDim,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward,
                size: 12,
                color: AppColors.accent.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Text(
                predicted,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiftRow(PredictionLiftChange lift) {
    final change = lift.predictedKg - lift.currentKg;
    final changeStr = change >= 0
        ? '+${change.toStringAsFixed(0)}'
        : change.toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              lift.name,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${lift.currentKg.toStringAsFixed(0)}kg',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.textDim,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.arrow_forward,
              size: 10,
              color: AppColors.accent.withValues(alpha: 0.5),
            ),
          ),
          Text(
            '${lift.predictedKg.toStringAsFixed(0)}kg',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          WardChip(label: '${changeStr}KG', tone: WardChipTone.gold),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
