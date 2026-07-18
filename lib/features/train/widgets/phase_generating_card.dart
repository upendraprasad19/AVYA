import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/services/app_events_service.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/services/pro_phase_advance.dart';

/// PRO recourse card (REG-1 fix, a4e2d9) shown on Home + Train when a PRO user's
/// phase has expired but the silent splash auto-advance has NOT (yet) produced
/// the next phase — i.e. it failed or raced. It REPLACES the free-tier
/// [PlanExpiredCard] (a "go PRO" upsell), which is nonsensical for a paying
/// user, and it replaces the silent RECOVERY rest-day dead-end a naive
/// suppression would leave. One tap regenerates the next phase; double-tap
/// guarded via [_busy].
///
/// It does NOT auto-generate on mount — the splash's single unawaited attempt is
/// the automatic path; auto-firing here could race that in-flight call and
/// double-generate. The card is the explicit, safe fallback.
class PhaseGeneratingCard extends ConsumerStatefulWidget {
  /// Called after a successful generation so the host can refresh its providers.
  final VoidCallback? onGenerated;

  const PhaseGeneratingCard({super.key, this.onGenerated});

  @override
  ConsumerState<PhaseGeneratingCard> createState() =>
      _PhaseGeneratingCardState();
}

class _PhaseGeneratingCardState extends ConsumerState<PhaseGeneratingCard> {
  bool _busy = false;
  bool _seenLogged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_seenLogged && mounted) {
        _seenLogged = true;
        AppEventsService.instance.log('pro_phase_generating_card_seen');
      }
    });
  }

  Future<void> _generate() async {
    if (_busy) return; // double-tap guard
    setState(() => _busy = true);
    AppEventsService.instance.log('pro_phase_generate_tapped');
    try {
      final generated = await advanceProPhaseIfExpired(ref);
      if (!mounted) return;
      if (generated) {
        AppEventsService.instance.log('pro_phase_generate_succeeded');
        widget.onGenerated?.call();
      } else {
        _snack("Still finishing up — give it a moment, then tap again.");
      }
    } catch (e, st) {
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'pro_phase_generate_card'));
      if (!mounted) return;
      _snack("Couldn't generate your next phase. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: AppTypography.body.copyWith(fontSize: 13),
        ),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Phase complete, Officer.',
            style: AppTypography.body.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Your next phase is ready. Generate it now to get fresh orders.',
            style: AppTypography.body.copyWith(
                fontSize: 13, color: AppColors.textDim, height: 1.4),
          ),
          const SizedBox(height: 18),
          _generateCta(),
        ],
      ),
    );
  }

  Widget _generateCta() {
    return GestureDetector(
      onTap: _busy ? null : _generate,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Text(
                  'Generate next phase  →',
                  style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w900, color: Colors.black),
                ),
        ),
      ),
    );
  }
}
