import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:flutter/services.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/shared/widgets/scroll_date_picker.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import '../providers/onboarding_provider.dart';

class OnboardingChatScreen extends ConsumerStatefulWidget {
  const OnboardingChatScreen({super.key});

  @override
  ConsumerState<OnboardingChatScreen> createState() =>
      _OnboardingChatScreenState();
}

class _OnboardingChatScreenState extends ConsumerState<OnboardingChatScreen>
    with TickerProviderStateMixin {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showSummary = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final onboardingState = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);

    // Listen for errors.
    ref.listen<OnboardingState>(onboardingProvider, (prev, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              next.error!,
              style: AppTypography.bodySm.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.bad,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: onboardingState.isFirstStep && !_showSummary
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                onPressed: () {
                  if (_showSummary) {
                    setState(() => _showSummary = false);
                  } else {
                    notifier.previousStep();
                  }
                },
              ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ENLISTMENT',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Getting started',
              style: AppTypography.h3,
            ),
          ],
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: _buildProgressHeader(onboardingState),
        ),
      ),
      body: _showSummary
          ? _buildSummaryView(onboardingState, notifier)
          : _buildChatView(onboardingState, notifier),
    );
  }

  // ── Progress Bar ────────────────────────────────────────────────

  Widget _buildProgressHeader(OnboardingState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Step counter text
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STEP ${state.currentStep + 1} / ${state.totalSteps}',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 2,
                ),
              ),
              Text(
                '${(state.progress * 100).round()}% COMPLETE',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        // Progress bar
        _buildProgressBar(state),
      ],
    );
  }

  Widget _buildProgressBar(OnboardingState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: WardBar(pct: state.progress, height: 4),
    );
  }

  // ── Chat View ───────────────────────────────────────────────────

  Widget _buildChatView(OnboardingState state, OnboardingNotifier notifier) {
    _scrollToBottom();

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              // Step indicator
              Center(
                child: WardChip(
                  label: 'STEP ${state.currentStep + 1} / ${state.totalSteps}',
                  tone: WardChipTone.gold,
                ),
              ),
              const SizedBox(height: 24),

              // Show previously answered Q&A pairs.
              ..._buildChatHistory(state),

              // Current question (bot bubble).
              _buildBotBubble(state.currentStepData.question),
              const SizedBox(height: 16),
            ],
          ),
        ),

        // Input area
        _buildInputArea(state, notifier),
      ],
    );
  }

  /// Builds the chat history of answered questions up to the current step.
  List<Widget> _buildChatHistory(OnboardingState state) {
    final widgets = <Widget>[];
    for (int i = 0; i < state.currentStep; i++) {
      final step = onboardingSteps[i];
      final answer = state.answers[step.key];
      if (answer != null) {
        widgets.add(_buildBotBubble(step.question));
        widgets.add(const SizedBox(height: 8));
        widgets.add(_buildUserBubble(_formatAnswer(step.key, answer)));
        widgets.add(const SizedBox(height: 16));
      }
    }
    return widgets;
  }

  // ── Chat Bubbles ────────────────────────────────────────────────

  Widget _buildBotBubble(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: WardCard(
          variant: WardCardVariant.inset,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            text,
            style: AppTypography.body.copyWith(
              color: AppColors.textDim,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserBubble(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.33),
            ),
          ),
          child: Text(
            text,
            style: AppTypography.body.copyWith(
              color: AppColors.accent,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  // ── Input Area ──────────────────────────────────────────────────

  Widget _buildInputArea(OnboardingState state, OnboardingNotifier notifier) {
    final step = state.currentStepData;
    final currentAnswer = state.answers[step.key];

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        12,
        AppSpacing.screenPadding,
        AppSpacing.screenPadding,
      ),
      decoration: const BoxDecoration(
        color: AppColors.header,
        border: Border(top: BorderSide(color: AppColors.line2)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Type-specific input.
            switch (step.inputType) {
              OnboardingInputType.text => _buildTextInput(state, notifier),
              OnboardingInputType.datePicker =>
                _buildDatePickerInput(state, notifier, currentAnswer),
              OnboardingInputType.chips =>
                _buildChipsInput(state, notifier, step.options ?? []),
              OnboardingInputType.number =>
                _buildNumberInput(state, notifier),
              OnboardingInputType.selector =>
                _buildSelectorInput(state, notifier, step.options ?? []),
            },
          ],
        ),
      ),
    );
  }

  Widget _buildTextInput(OnboardingState state, OnboardingNotifier notifier) {
    // Pre-fill if already answered.
    final existing = state.answers[state.currentStepData.key];
    if (existing is String && _textController.text != existing) {
      _textController.text = existing;
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _textController,
            style: AppTypography.body.copyWith(color: AppColors.textPrimary),
            cursorColor: AppColors.accent,
            textCapitalization: TextCapitalization.words,
            decoration: _sharpInputDecoration('Type your answer...'),
            onSubmitted: (value) => _submitTextAnswer(
              value,
              state,
              notifier,
            ),
          ),
        ),
        const SizedBox(width: 10),
        _buildSendButton(() {
          _submitTextAnswer(_textController.text, state, notifier);
        }),
      ],
    );
  }

  InputDecoration _sharpInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.body.copyWith(
        color: AppColors.textDisabled,
      ),
      filled: true,
      fillColor: AppColors.input,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        borderSide: const BorderSide(color: AppColors.line2, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        borderSide: const BorderSide(color: AppColors.line2, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        borderSide: const BorderSide(
          color: AppColors.accent,
          width: 2,
        ),
      ),
    );
  }

  void _submitTextAnswer(
    String value,
    OnboardingState state,
    OnboardingNotifier notifier,
  ) {
    if (value.trim().isEmpty) return;
    notifier.setAnswer(state.currentStepData.key, value.trim());
    _textController.clear();
    _handleNext(state, notifier);
  }

  void _submitNumberAnswer(
    String value,
    OnboardingState state,
    OnboardingNotifier notifier,
  ) {
    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please enter a valid number greater than 0',
              style: AppTypography.bodySm.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.bad,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    notifier.setAnswer(state.currentStepData.key, value);
    _textController.clear();
    _handleNext(state, notifier);
  }

  Widget _buildNumberInput(
    OnboardingState state,
    OnboardingNotifier notifier,
  ) {
    final existing = state.answers[state.currentStepData.key];
    if (existing != null && _textController.text != existing.toString()) {
      _textController.text = existing.toString();
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _textController,
            style: AppTypography.body.copyWith(color: AppColors.textPrimary),
            cursorColor: AppColors.accent,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: _sharpInputDecoration('Enter a number...'),
            onSubmitted: (value) => _submitNumberAnswer(value, state, notifier),
          ),
        ),
        const SizedBox(width: 10),
        _buildSendButton(() {
          _submitNumberAnswer(_textController.text, state, notifier);
        }),
      ],
    );
  }

  Widget _buildDatePickerInput(
    OnboardingState state,
    OnboardingNotifier notifier,
    dynamic currentAnswer,
  ) {
    DateTime? initial;
    if (currentAnswer is String && currentAnswer.isNotEmpty) {
      initial = DateTime.tryParse(currentAnswer);
    }
    final seededInitial = initial ?? DateTime(1998, 1, 1);

    // Bug fix 2026-04-18: ScrollDatePicker's `onDateChanged` fires ONLY
    // when the user actively scrolls the wheels. If they see the default
    // displayed date (1 Jan 1998) and tap Next without scrolling — which
    // is what most users do when the default matches — the answer state
    // stays empty and `date_of_birth` lands in Hive as `""`. That's why
    // icanbefitter@gmail.com had `date_of_birth = NULL` in Supabase and
    // profile completeness stuck at 94% despite completing onboarding.
    //
    // Seed the answer map with the initial date as soon as this step
    // mounts, so Next always persists something valid even without
    // interaction. If the user does scroll, `onDateChanged` overwrites.
    if (currentAnswer is! String || currentAnswer.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Guard against race: only seed if the step is still the DOB
        // step and the answer is still unset. setAnswer is safe to
        // re-call with the same value (idempotent).
        final stillEmpty = state.answers[state.currentStepData.key] == null ||
            (state.answers[state.currentStepData.key] is String &&
                (state.answers[state.currentStepData.key] as String).isEmpty);
        if (stillEmpty && state.currentStepData.key == 'date_of_birth') {
          notifier.setAnswer(
            state.currentStepData.key,
            seededInitial.toIso8601String().split('T').first,
          );
        }
      });
    }

    return Column(
      children: [
        // Format hint
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 12, color: AppColors.textMute),
              const SizedBox(width: 4),
              Text(
                'SCROLL TO SELECT  ·  DD / MM / YYYY',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        ScrollDatePicker(
          initialDate: seededInitial,
          firstDate: DateTime(1940),
          lastDate: DateTime.now().subtract(const Duration(days: 365 * 16)),
          onDateChanged: (picked) {
            notifier.setAnswer(
              state.currentStepData.key,
              picked.toIso8601String().split('T').first,
            );
          },
        ),
        const SizedBox(height: 12),
        _buildNextButton(state, notifier),
      ],
    );
  }

  Widget _buildChipsInput(
    OnboardingState state,
    OnboardingNotifier notifier,
    List<String> options,
  ) {
    final selected = state.answers[state.currentStepData.key] as String?;

    return Wrap(
      spacing: AppSpacing.gridGap,
      runSpacing: AppSpacing.gridGap,
      children: options.map((option) {
        final isSelected = selected == option;
        return GestureDetector(
          onTap: () {
            notifier.setAnswer(state.currentStepData.key, option);
            // Auto-advance after a short delay so the user sees the selection.
            Future.delayed(const Duration(milliseconds: 300), () {
              _handleNext(state, notifier);
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.accentSoft : AppColors.input,
              borderRadius: BorderRadius.circular(AppRadius.sharp),
              border: Border.all(
                color: isSelected
                    ? AppColors.accent
                    : AppColors.line2,
                width: 2,
              ),
            ),
            child: Text(
              _formatOptionLabel(option),
              style: AppTypography.body.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.accent : AppColors.textPrimary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSelectorInput(
    OnboardingState state,
    OnboardingNotifier notifier,
    List<String> options,
  ) {
    final selected = state.answers[state.currentStepData.key] as String?;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: options.map((option) {
        final isSelected = selected == option;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: () {
              notifier.setAnswer(state.currentStepData.key, option);
              Future.delayed(const Duration(milliseconds: 300), () {
                _handleNext(state, notifier);
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : AppColors.input,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
                border: Border.all(
                  color: isSelected ? AppColors.accent : AppColors.line2,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                option,
                style: AppTypography.h3.copyWith(
                  fontSize: 18,
                  color: isSelected ? AppColors.bgDeep : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Buttons ─────────────────────────────────────────────────────

  Widget _buildSendButton(VoidCallback onPressed) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppRadius.sharp),
      ),
      child: IconButton(
        icon: const Icon(Icons.arrow_forward, color: AppColors.bgDeep),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildNextButton(OnboardingState state, OnboardingNotifier notifier) {
    return WardButton(
      label: state.isLastStep ? 'REVIEW' : 'NEXT',
      variant: WardButtonVariant.primary,
      onPressed: () => _handleNext(state, notifier),
    );
  }

  void _handleNext(OnboardingState state, OnboardingNotifier notifier) {
    if (state.isLastStep) {
      setState(() => _showSummary = true);
    } else {
      notifier.nextStep();
      _textController.clear();
    }
  }

  // ── Summary View ────────────────────────────────────────────────

  Widget _buildSummaryView(
    OnboardingState state,
    OnboardingNotifier notifier,
  ) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              const SizedBox(height: 8),
              Text(
                'REVIEW YOUR PROFILE',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Final check',
                style: AppTypography.h2.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Make sure everything looks good before we build your plan.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textDim,
                ),
              ),
              const SizedBox(height: 24),

              // Summary card
              WardCard(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Column(
                  children: [
                    for (int i = 0; i < onboardingSteps.length; i++) ...[
                      _buildSummaryRow(
                        label: _stepLabel(onboardingSteps[i].key),
                        value: _formatAnswer(
                          onboardingSteps[i].key,
                          state.answers[onboardingSteps[i].key],
                        ),
                        onEdit: () {
                          notifier.goToStep(i);
                          setState(() => _showSummary = false);
                        },
                      ),
                      if (i < onboardingSteps.length - 1)
                        const Divider(
                          color: AppColors.line2,
                          height: 24,
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // Confirm button
        Container(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          decoration: const BoxDecoration(
            color: AppColors.header,
            border: Border(top: BorderSide(color: AppColors.line2)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: state.isCompleting
                    ? null
                    : () async {
                        final phase = await notifier.completeOnboarding();
                        if (phase != null && mounted) {
                          // Refresh all home/nutrition/train providers so fresh
                          // onboarding data (name, macros, plan) is visible immediately.
                          ref.invalidate(calendarWeekProvider);
                          ref.invalidate(userFirstNameProvider);
                          ref.invalidate(userInitialProvider);
                          ref.invalidate(userGreetingProvider);
                          ref.invalidate(nutritionSummaryProvider);
                          ref.invalidate(macroTargetsProvider);
                          ref.invalidate(currentPlanProvider);
                          ref.invalidate(todayWorkoutProvider);
                          ref.invalidate(streakProvider);
                          // Read computed targets from provider state — set by
                          // completeOnboarding() just before it returned.
                          // This avoids a Hive re-read and eliminates the old
                          // hardcoded fallback (which was 184g — someone's specific value).
                          final s = ref.read(onboardingProvider);
                          final targets = s.lastComputedTargets;
                          final daysStr = s.answers['days_per_week'] as String? ?? '4';
                          final daysPerWeek = int.tryParse(daysStr) ?? 4;
                          context.go('/plan-generation', extra: {
                            'phase': phase,
                            'daysPerWeek': daysPerWeek,
                            'dailyCalories': targets?.dailyCalories ?? 2000,
                            'proteinGrams': targets?.proteinGrams ?? 120,
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bgDeep,
                  disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.39),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                  ),
                  elevation: 0,
                ),
                child: state.isCompleting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.bgDeep,
                        ),
                      )
                    : Text(
                        "LET'S GO",
                        style: AppTypography.h3.copyWith(
                          fontSize: 12,
                          color: AppColors.bgDeep,
                          letterSpacing: 2.5,
                          height: 1,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow({
    required String label,
    required String value,
    required VoidCallback onEdit,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: onEdit,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.sharp),
            ),
            child: const Icon(
              Icons.edit_outlined,
              size: 16,
              color: AppColors.accent,
            ),
          ),
        ),
      ],
    );
  }

  // ── Formatting Helpers ──────────────────────────────────────────

  String _formatAnswer(String key, dynamic value) {
    if (value == null) return '--';
    final str = value.toString();

    switch (key) {
      case 'date_of_birth':
        final parsed = DateTime.tryParse(str);
        if (parsed != null) {
          return DateFormat('d MMM yyyy').format(parsed);
        }
        return str;
      case 'height_cm':
        return '$str cm';
      case 'current_weight_kg':
      case 'target_weight_kg':
        return '$str kg';
      case 'days_per_week':
        return '$str days/week';
      default:
        return _formatOptionLabel(str);
    }
  }

  String _formatOptionLabel(String option) {
    switch (option) {
      case 'build_muscle':
        return 'Build Muscle';
      case 'lose_fat':
        return 'Lose Fat';
      case 'general_fitness':
        return 'General Fitness';
      case 'strength':
        return 'Strength';
      case 'recompose':
        return 'Recomposition';
      case 'beginner':
        return 'Beginner';
      case 'intermediate':
        return 'Intermediate';
      case 'advanced':
        return 'Advanced';
      case 'desk_job':
        return 'Desk Job (office/WFH)';
      case 'lightly_active':
        return 'Lightly Active';
      case 'very_active_job':
        return 'Very Active Job';
      case 'bodyweight':
        return 'Bodyweight Only';
      case 'home_dumbbells':
        return 'Home + Dumbbells';
      case 'basic_gym':
        return 'Basic Gym';
      case 'full_gym':
        return 'Full Gym';
      case 'male':
        return 'Male';
      case 'female':
        return 'Female';
      case 'other':
        return 'Other';
      case 'start_today':
        return 'Start Today';
      case 'this_monday':
        return 'This Monday';
      case 'next_monday':
        return 'Next Monday';
      default:
        return option;
    }
  }

  String _stepLabel(String key) {
    switch (key) {
      case 'full_name':
        return 'Name';
      case 'date_of_birth':
        return 'Date of Birth';
      case 'gender':
        return 'Gender';
      case 'height_cm':
        return 'Height';
      case 'current_weight_kg':
        return 'Current Weight';
      case 'target_weight_kg':
        return 'Target Weight';
      case 'primary_goal':
        return 'Goal';
      case 'pace_preference': // Bug #24
        return 'Pace';
      case 'fitness_experience':
        return 'Experience';
      case 'days_per_week':
        return 'Training Days';
      case 'lifestyle_activity':
        return 'Daily Lifestyle';
      case 'equipment_access':
        return 'Equipment';
      case 'start_date':
        return 'Start Date';
      default:
        return key;
    }
  }
}
