import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/shared/utils/card_share_service.dart';
import 'package:icanbefitter/shared/widgets/shareable_card.dart';

/// Future Prediction card display.
///
/// Shows post-onboarding prediction for all users.
/// PRO users get a "Get Updated Prediction" button (monthly refresh).
class PredictionCard extends StatelessWidget {
  final String? predictionText;
  final DateTime? generatedAt;
  final bool isPro;
  final bool canRefresh;
  final bool isStale;
  final VoidCallback onRefreshTap;

  const PredictionCard({
    super.key,
    this.predictionText,
    this.generatedAt,
    required this.isPro,
    required this.canRefresh,
    this.isStale = false,
    required this.onRefreshTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPrediction =
        predictionText != null && predictionText!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.15),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0e1219),
            Color(0xFF0a1425),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.auto_graph,
                  color: AppColors.accent,
                  size: 15,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'YOUR FUTURE PREDICTION',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: AppColors.accent,
                  ),
                ),
              ),
              if (generatedAt != null)
                Text(
                  _formatDate(generatedAt!),
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 9,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Prediction text or placeholder
          if (hasPrediction) ...[
            Text(
              predictionText!,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 12,
                fontWeight: FontWeight.w400,
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
                    'Read More →',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
          ] else
            Text(
              'Complete onboarding to get your personalised fitness prediction.',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),

          // Stale prediction badge (free users whose goal changed)
          if (isStale && hasPrediction) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.proGold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.proGold.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: AppColors.proGold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your goal has changed. Refresh prediction (PRO)',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.proGold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Action buttons
          if (hasPrediction) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                // Share button
                GestureDetector(
                  onTap: () => _showShareSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.accentTint,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.share, size: 13,
                            color: AppColors.accent),
                        const SizedBox(width: 6),
                        Text(
                          'Share My Prediction',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
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
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isPro
                          ? (canRefresh
                              ? AppColors.accentTint
                              : AppColors.textDisabled.withValues(alpha: 0.3))
                          : AppColors.proGold.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: isPro
                            ? (canRefresh
                                ? AppColors.accent.withValues(alpha: 0.3)
                                : AppColors.border)
                            : AppColors.proGold.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh,
                          size: 13,
                          color: isPro
                              ? (canRefresh
                                  ? AppColors.accent
                                  : AppColors.textSecondary)
                              : AppColors.proGold,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isPro
                              ? (canRefresh ? 'Update' : 'Updated')
                              : 'PRO',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isPro
                                ? (canRefresh
                                    ? AppColors.accent
                                    : AppColors.textSecondary)
                                : AppColors.proGold,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'YOUR 90-DAY PREDICTION',
                style: GoogleFonts.getFont('DM Sans',
                  fontSize: 11, fontWeight: FontWeight.w700,
                  letterSpacing: 1.2, color: AppColors.accent),
              ),
              if (generatedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Generated ${_formatDate(generatedAt!)}',
                  style: GoogleFonts.getFont('DM Sans',
                    fontSize: 9, color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                predictionText!,
                style: GoogleFonts.getFont('DM Sans',
                  fontSize: 13, fontWeight: FontWeight.w400,
                  color: AppColors.textPrimary, height: 1.7),
              ),
              const SizedBox(height: 20),
              // Share button
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
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Center(
                      child: Text('Share to Instagram / WhatsApp',
                        style: GoogleFonts.getFont('DM Sans',
                          fontSize: 14, fontWeight: FontWeight.w900,
                          color: Colors.black)),
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
    final months = [
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

          // Share button
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
                borderRadius: BorderRadius.circular(100),
              ),
              child: Center(
                child: Text(
                  'Share to Instagram / WhatsApp',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
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
                'Close',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
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
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_graph,
                    color: AppColors.accent, size: 15),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'YOUR 90-DAY PREDICTION',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Stats grid (if structured data available)
          if (stats != null) ...[
            _buildStatsGrid(stats),
            const SizedBox(height: 12),

            // Lift predictions
            if (stats.lifts.isNotEmpty) ...[
              Text(
                'KEY LIFTS',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppColors.textSecondary,
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
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.textPrimary,
              height: 1.6,
            ),
          ),

          // Motivational tagline
          if (stats?.motivationalTagline != null) ...[
            const SizedBox(height: 10),
            Text(
              stats!.motivationalTagline!,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
                color: AppColors.accent,
              ),
            ),
          ],

          // Date generated
          if (widget.generatedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              'Generated ${_formatDate(widget.generatedAt!)}',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 9,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
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
        color: AppColors.input,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                current,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
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
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppColors.accent,
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
    final changeStr =
        change >= 0 ? '+${change.toStringAsFixed(0)}' : change.toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              lift.name,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            '${lift.currentKg.toStringAsFixed(0)}kg',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
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
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${changeStr}kg',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
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
