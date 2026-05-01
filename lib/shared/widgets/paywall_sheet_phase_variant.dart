import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Phase-specific paywall bottom sheet.
///
/// Shown when a free user taps a locked phase card or the lock icon on
/// weeks 5-12 in the week selector. Emphasises the phase-unlock value prop
/// rather than a generic features list.
void showPaywallSheetPhaseVariant(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _PaywallSheetPhaseBody(),
  );
}

class _PaywallSheetPhaseBody extends StatelessWidget {
  const _PaywallSheetPhaseBody();

  static const _bullets = [
    'Auto-generate Phases II–XII as you complete each block',
    'Unlimited AI coach (no daily cap)',
    'Weekly AI report powered by Gemini Pro reasoning',
    'Adaptive plans from your biometrics',
    'Photo transformation timeline',
    'Voice notes + AI-personalised morning alerts',
    'Fresh prediction card every month',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Eyebrow ───────────────────────────────────────────────────
          Text(
            '⊙ AVYA · CONTINUE THE MISSION',
            style: AppTypography.mono.copyWith(
              fontSize: 9,
              letterSpacing: 1.2,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          Container(width: 56, height: 1, color: AppColors.accent),
          const SizedBox(height: 14),

          // ── Headline ──────────────────────────────────────────────────
          Text(
            'Beyond Phase I.',
            style: AppTypography.titleL.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 14),

          // ── Body copy ─────────────────────────────────────────────────
          Text(
            'Phases II–XII unlock automatically when you finish each '
            'block — your AI coach generates the next 4 weeks the '
            'moment you\'re ready.',
            style: AppTypography.bodyM.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 20),

          // ── PRO benefits list ─────────────────────────────────────────
          Text(
            'PRO UNLOCKS TODAY:',
            style: AppTypography.mono.copyWith(
              fontSize: 9,
              letterSpacing: 1.2,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 10),
          ..._bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: AppTypography.bodyM.copyWith(color: AppColors.accent),
                  ),
                  Expanded(
                    child: Text(
                      b,
                      style: AppTypography.bodyM
                          .copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 22),

          // ── CTA button ────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Pricing / checkout navigation is handled by the
                // existing PRO upgrade flow (Profile → Subscription).
                // TODO: wire to direct checkout route once available.
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.bg,
                elevation: 0,
                shape: const StadiumBorder(),
              ),
              child: Text(
                'UPGRADE TO PRO  →',
                style: AppTypography.mono.copyWith(
                  fontSize: 13,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: AppColors.bg,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '₹349 / month  ·  ₹2,999 / year (save 28%)',
              style: AppTypography.mono.copyWith(
                fontSize: 10,
                color: AppColors.textMute,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
