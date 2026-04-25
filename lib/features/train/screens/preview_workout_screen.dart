import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/train/providers/preview_plan_provider.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet_phase_variant.dart';

/// Read-only workout preview screen.
///
/// Route: /train/preview?phase=II&week=5&day=1
///
/// Shows a real generated workout from [PlanGenerator.generateV4] using the
/// user's actual profile inputs. Accessible when a free user (or a PRO user
/// browsing ahead) taps a locked week chip on the Train screen.
///
/// State-aware banner explains what is needed to unlock the phase.
/// Free users see an UPGRADE TO PRO CTA at the bottom.
class PreviewWorkoutScreen extends ConsumerWidget {
  const PreviewWorkoutScreen({
    super.key,
    required this.phaseNumber,
    required this.week,
    required this.day,
  });

  /// Roman numeral phase identifier, e.g. 'II', 'III'.
  final String phaseNumber;

  /// Global week number (1-12), e.g. 5 for the first week of Phase II.
  final int week;

  /// Day within the week (1-indexed).
  final int day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = SubscriptionService.instance.isPro();
    final previewAsync = ref.watch(
      previewPlanProvider(PreviewKey(phaseNumber, week, day)),
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: AppColors.textDim),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'PREVIEW',
          style: AppTypography.mono.copyWith(
            fontSize: 10,
            letterSpacing: 2.5,
            color: AppColors.textMute,
          ),
        ),
      ),
      body: previewAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            strokeWidth: 2,
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppColors.warn, size: 32),
                const SizedBox(height: 12),
                Text(
                  'Could not load preview',
                  style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  e.toString(),
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.textDim),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        data: (workout) => _WorkoutPreviewBody(
          workout: workout,
          phaseNumber: phaseNumber,
          week: week,
          day: day,
          isPro: isPro,
        ),
      ),
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

class _WorkoutPreviewBody extends StatelessWidget {
  const _WorkoutPreviewBody({
    required this.workout,
    required this.phaseNumber,
    required this.week,
    required this.day,
    required this.isPro,
  });

  final Map<String, dynamic> workout;
  final String phaseNumber;
  final int week;
  final int day;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    final exercises = (workout['exercises'] as List?)
            ?.whereType<Map>()
            .toList() ??
        const <Map>[];
    final warmupCount = (workout['warmup_count'] as int?) ?? 0;
    final cooldownCount = (workout['cooldown_count'] as int?) ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Phase / week / day eyebrow ─────────────────────────────
          Text(
            'PHASE $phaseNumber  ·  WEEK $week  ·  DAY $day',
            style: AppTypography.mono.copyWith(
              fontSize: 10,
              letterSpacing: 1.4,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 8),

          // ── Workout name ───────────────────────────────────────────
          Text(
            (workout['name'] as String?) ?? 'Preview',
            style: AppTypography.h1.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),

          // ── Focus subtitle ─────────────────────────────────────────
          Text(
            (workout['focus_text'] as String?) ??
                '${exercises.length} exercises',
            style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
          ),

          // ── Warmup/cooldown mini-note ──────────────────────────────
          if (warmupCount > 0 || cooldownCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${[
                if (warmupCount > 0) '$warmupCount warm-up',
                if (cooldownCount > 0) '$cooldownCount cool-down',
              ].join(' · ')} exercises included',
              style: AppTypography.monoXs.copyWith(
                fontSize: 9,
                color: AppColors.textMute,
                letterSpacing: 1.0,
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ── State-aware banner ─────────────────────────────────────
          _UnlockBanner(phaseNumber: phaseNumber, isPro: isPro),

          const SizedBox(height: 24),

          // ── Divider ────────────────────────────────────────────────
          Container(height: 1, color: AppColors.line2),
          const SizedBox(height: 20),

          // ── Exercise list ──────────────────────────────────────────
          if (exercises.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'This is a rest day.',
                  style: AppTypography.body.copyWith(color: AppColors.textDim),
                ),
              ),
            )
          else
            ...exercises.asMap().entries.map((entry) {
              final i = entry.key;
              final ex = entry.value;
              return _ExerciseRow(index: i + 1, ex: ex);
            }),

          const SizedBox(height: 32),

          // ── Upgrade CTA (free users only) ─────────────────────────
          if (!isPro) ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => showPaywallSheetPhaseVariant(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bg,
                  elevation: 0,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  'UPGRADE TO PRO  →',
                  style: AppTypography.mono.copyWith(
                    fontSize: 12,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w800,
                    color: AppColors.bg,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Roadmap cross-link ─────────────────────────────────────
          Center(
            child: GestureDetector(
              onTap: () => context.go('/train/roadmap'),
              child: Text(
                'See the 12-week roadmap →',
                style: AppTypography.mono.copyWith(
                  fontSize: 10,
                  color: AppColors.accent,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.accent,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Banner ────────────────────────────────────────────────────────────────────

class _UnlockBanner extends StatelessWidget {
  const _UnlockBanner({
    required this.phaseNumber,
    required this.isPro,
  });

  final String phaseNumber;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    // PRO user browsing ahead — different message.
    final title = isPro
        ? 'Keep going — Phase $phaseNumber is your next block'
        : 'Complete Phase I to unlock Phase $phaseNumber';
    final subtitle = isPro
        ? 'Your AI coach auto-generates the next 4 weeks the moment you finish the current block.'
        : 'Your AI coach generates the next 4 weeks the moment you finish.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isPro ? Icons.lock_open_outlined : Icons.lock_outline,
            size: 18,
            color: AppColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Exercise row ──────────────────────────────────────────────────────────────

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.index, required this.ex});

  final int index;
  final Map ex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Index number
          SizedBox(
            width: 24,
            child: Text(
              '$index',
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Exercise details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (ex['name'] as String?) ?? 'Exercise',
                  style: AppTypography.h3.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _summarizeSet(ex),
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.textDim),
                ),
                if (ex['notes'] is String && (ex['notes'] as String).isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    ex['notes'] as String,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textMute,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _summarizeSet(Map ex) {
    final sets = ex['sets'];
    final reps = ex['reps'];
    final rest = ex['restSeconds'];
    final weight = ex['weightKg'];
    final loggingType = ex['loggingType'] as String? ?? 'weight_reps';

    final parts = <String>[];
    if (sets != null) parts.add('$sets sets');
    if (reps != null) {
      // reps is a String like "8-12" in PlannedExercise
      final repsStr = reps.toString();
      if (loggingType == 'timed') {
        parts.add('$repsStr s');
      } else if (loggingType == 'cardio') {
        parts.add('$repsStr min');
      } else {
        parts.add('$repsStr reps');
      }
    }
    if (rest != null) parts.add('${rest}s rest');
    if (weight != null) parts.add('~${weight}kg');
    return parts.join(' · ');
  }
}
