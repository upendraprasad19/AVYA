import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet_phase_variant.dart';

/// Full 12-week phase roadmap (3 phases × 4 weeks).
///
/// Route: `/train/roadmap`  (Plan C Task 8 / Q7 surface B)
///
/// Free users: Phase I card active, Phases II-III locked with lock icon.
///   Sticky UPGRADE TO PRO bottom CTA always visible.
/// PRO users: all three cards tappable (navigates to /train/preview — added
///   in Task 9). No sticky CTA.
class PhaseRoadmapScreen extends ConsumerWidget {
  const PhaseRoadmapScreen({super.key});

  static const _phases = <_PhaseInfo>[
    _PhaseInfo(
      number: 'I',
      name: 'FOUNDATION',
      weekRange: 'Wk 1–4',
      focus: 'Movement patterns + baseline strength.',
      bullets: [
        'Master the big lifts under load',
        'Build the work-capacity engine',
        'Sample: Full Body A · 6 exercises · 60 min',
      ],
    ),
    _PhaseInfo(
      number: 'II',
      name: 'STRENGTH BLOCK',
      weekRange: 'Wk 5–8',
      focus: 'Heavier compounds, lower reps, real progression.',
      bullets: [
        'Strength benchmarks established',
        '+5–10% on big lifts over 4 weeks',
        'Sample: Heavy Push · 7 exercises · 75 min',
      ],
    ),
    _PhaseInfo(
      number: 'III',
      name: 'HYPERTROPHY',
      weekRange: 'Wk 9–12',
      focus: 'Volume push. Muscle-building emphasis.',
      bullets: [
        'Lean mass gains visible',
        'Higher rep ranges, tighter rest periods',
        'Sample: Chest + Triceps · 8 exercises · 70 min',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = SubscriptionService.instance.isPro();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          'Phase Roadmap',
          style: AppTypography.titleL.copyWith(fontSize: 20),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        itemCount: _phases.length,
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, i) {
          final phase = _phases[i];
          final isActive = i == 0;
          final isLocked = !isActive && !isPro;
          return _PhaseCard(
            phase: phase,
            isActive: isActive,
            isLocked: isLocked,
            onTap: () {
              if (isActive) return; // Phase I already in progress — no nav
              if (isLocked) {
                showPaywallSheetPhaseVariant(context);
              } else {
                // Task 9 adds the preview screen; for now nothing happens
                // for PRO users (route is not yet registered).
                // TODO(task9): context.push('/train/preview?phase=...');
              }
            },
          );
        },
      ),
      bottomNavigationBar: isPro
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              child: SizedBox(
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
                      fontSize: 13,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: AppColors.bg,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Data class ───────────────────────────────────────────────────────────────

class _PhaseInfo {
  final String number;
  final String name;
  final String weekRange;
  final String focus;
  final List<String> bullets;

  const _PhaseInfo({
    required this.number,
    required this.name,
    required this.weekRange,
    required this.focus,
    required this.bullets,
  });
}

// ── Phase card ───────────────────────────────────────────────────────────────

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({
    required this.phase,
    required this.isActive,
    required this.isLocked,
    required this.onTap,
  });

  final _PhaseInfo phase;
  final bool isActive;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.accent : AppColors.line2,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row: circle + name + week range + status icon ──────
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accent),
                    color: isActive ? AppColors.accentBg : Colors.transparent,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    phase.number,
                    style: AppTypography.mono.copyWith(
                      fontSize: 12,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    phase.name,
                    style: AppTypography.titleL.copyWith(fontSize: 16),
                  ),
                ),
                Text(
                  phase.weekRange,
                  style: AppTypography.mono.copyWith(
                    fontSize: 9,
                    color: AppColors.textMute,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 8),
                if (isActive)
                  const Icon(Icons.check_circle, size: 16, color: AppColors.ok)
                else if (isLocked)
                  const Icon(Icons.lock, size: 14, color: AppColors.accent),
              ],
            ),

            // ── Gold rule divider ─────────────────────────────────────────
            const SizedBox(height: 12),
            Container(width: 56, height: 1, color: AppColors.line),
            const SizedBox(height: 12),

            // ── Focus line ────────────────────────────────────────────────
            Text(
              phase.focus,
              style: AppTypography.bodyM.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            // ── Bullets ───────────────────────────────────────────────────
            ...phase.bullets.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: AppTypography.bodyS
                          .copyWith(color: AppColors.accent),
                    ),
                    Expanded(
                      child: Text(
                        b,
                        style: AppTypography.bodyS
                            .copyWith(color: AppColors.textDim),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── PRO tap hint (unlocked non-active phases only) ─────────────
            if (!isActive && !isLocked) ...[
              const SizedBox(height: 8),
              Text(
                'TAP ANY WEEK FOR A PREVIEW →',
                style: AppTypography.mono.copyWith(
                  fontSize: 9,
                  letterSpacing: 1.2,
                  color: AppColors.accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
