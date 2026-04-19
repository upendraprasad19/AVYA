import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/plan_generator.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Animated plan generation screen shown at end of onboarding.
///
/// Steps animate in one by one, then a reveal card slides up with the
/// generated plan summary. The actual generation has already happened
/// before this screen is shown — this is pure UX theatre.
class PlanGenerationScreen extends StatefulWidget {
  final Phase? phase;
  final int daysPerWeek;
  final int dailyCalories;
  final int proteinGrams;

  const PlanGenerationScreen({
    super.key,
    required this.phase,
    required this.daysPerWeek,
    required this.dailyCalories,
    required this.proteinGrams,
  });

  @override
  State<PlanGenerationScreen> createState() => _PlanGenerationScreenState();
}

class _PlanGenerationScreenState extends State<PlanGenerationScreen>
    with TickerProviderStateMixin {
  final _steps = <_GenStep>[
    _GenStep('Analysing your profile', Icons.person_search),
    _GenStep('Calculating BMR & TDEE', Icons.calculate_outlined),
    _GenStep('Building your workout split', Icons.fitness_center),
    _GenStep('Selecting exercises from library', Icons.library_books_outlined),
    _GenStep('Scheduling your 4 weeks', Icons.calendar_month),
    _GenStep('Setting progressive overload', Icons.trending_up),
  ];

  int _completedSteps = 0;
  bool _showReveal = false;
  late AnimationController _revealController;
  late Animation<Offset> _revealSlide;
  late Animation<double> _revealFade;

  @override
  void initState() {
    super.initState();

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _revealSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
    ));
    _revealFade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeIn,
    ));

    _animateSteps();
  }

  Future<void> _animateSteps() async {
    for (int i = 0; i < _steps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() => _completedSteps = i + 1);
    }

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _showReveal = true);
    _revealController.forward();
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 1),
                  // Wardroom mono eyebrow — gold caps
                  Text(
                    'COMMISSIONING PLAN',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Fraunces serif subtitle
                  Text(
                    'Building your plan',
                    style: AppTypography.h2,
                  ),
                  const SizedBox(height: 32),
                  // Steps list
                  ...List.generate(_steps.length, (i) {
                    final done = i < _completedSteps;
                    final active = i == _completedSteps;
                    return _buildStepRow(_steps[i], done: done, active: active);
                  }),
                  const SizedBox(height: 32),
                  // Reveal card
                  if (_showReveal) _buildRevealCard(),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow(_GenStep step, {required bool done, required bool active}) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: done || active ? 1.0 : 0.2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: done
                  ? const Icon(Icons.check_circle, color: AppColors.accent, size: 20, key: ValueKey('done'))
                  : active
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          key: ValueKey('loading'),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(AppColors.accent),
                          ),
                        )
                      : Icon(step.icon, color: AppColors.textMute, size: 20, key: const ValueKey('pending')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${step.label}${done ? '' : '...'}',
                style: AppTypography.body.copyWith(
                  fontWeight: done ? FontWeight.w700 : FontWeight.w400,
                  color: done ? AppColors.textPrimary : AppColors.textDim,
                ),
              ),
            ),
            if (done)
              Text(
                '\u2713',
                style: AppTypography.h3.copyWith(color: AppColors.accent),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevealCard() {
    final phase = widget.phase;
    final splitNames = phase?.workouts.map((w) => w.name).join(' / ') ?? 'Custom Plan';

    return SlideTransition(
      position: _revealSlide,
      child: FadeTransition(
        opacity: _revealFade,
        child: WardCard(
          variant: WardCardVariant.hero,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                'ORDERS RECEIVED',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 2.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your plan is ready',
                style: AppTypography.h2,
              ),
              const SizedBox(height: 12),
              Text(
                splitNames,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.daysPerWeek} DAYS \u00B7 4 WEEKS \u00B7 PHASE 1',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _statChip('\u{1F525}', '${widget.dailyCalories} kcal'),
                  const SizedBox(width: 16),
                  _statChip('\u{1F4AA}', '${widget.proteinGrams}g protein'),
                ],
              ),
              const SizedBox(height: 20),
              WardButton(
                label: "LET'S GO",
                variant: WardButtonVariant.primary,
                trailing: const Icon(Icons.arrow_forward, color: AppColors.bgDeep, size: 16),
                onPressed: () => context.go('/home'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(String emoji, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        border: Border.all(color: AppColors.line2),
      ),
      child: Text(
        '$emoji $text',
        style: AppTypography.bodySm.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _GenStep {
  final String label;
  final IconData icon;
  const _GenStep(this.label, this.icon);
}
