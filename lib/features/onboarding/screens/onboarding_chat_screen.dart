import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:flutter/services.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
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
              style: AppTypography.bodyM.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        elevation: 0,
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
        title: Text(
          'Getting Started',
          style: AppTypography.titleM.copyWith(color: AppColors.textPrimary),
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
                'Step ${state.currentStep + 1} of ${state.totalSteps}',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '${(state.progress * 100).round()}% complete',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
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
    return Container(
      width: double.infinity,
      height: 4,
      color: AppColors.input,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: state.progress,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
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
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentTint,
                    borderRadius: BorderRadius.circular(AppRadius.badge),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.20),
                    ),
                  ),
                  child: Text(
                    'Step ${state.currentStep + 1} of ${state.totalSteps}',
                    style: AppTypography.bodyS.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          text,
          style: AppTypography.bodyL.copyWith(
            color: AppColors.textPrimary,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildUserBubble(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accentTint,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.20)),
        ),
        child: Text(
          text,
          style: AppTypography.bodyL.copyWith(
            color: AppColors.accent,
            height: 1.4,
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
        border: Border(top: BorderSide(color: AppColors.border)),
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
            style: AppTypography.bodyL.copyWith(color: AppColors.textPrimary),
            cursorColor: AppColors.accent,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Type your answer...',
              hintStyle: AppTypography.bodyL.copyWith(
                color: AppColors.textDisabled,
              ),
              filled: true,
              fillColor: AppColors.input,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: const BorderSide(
                  color: AppColors.accent,
                  width: 1.5,
                ),
              ),
            ),
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
              style: AppTypography.bodyM.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.red,
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
            style: AppTypography.bodyL.copyWith(color: AppColors.textPrimary),
            cursorColor: AppColors.accent,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: InputDecoration(
              hintText: 'Enter a number...',
              hintStyle: AppTypography.bodyL.copyWith(
                color: AppColors.textDisabled,
              ),
              filled: true,
              fillColor: AppColors.input,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: const BorderSide(
                  color: AppColors.accent,
                  width: 1.5,
                ),
              ),
            ),
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

    return Column(
      children: [
        // Format hint
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 12, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                'Scroll to select  ·  DD / MM / YYYY',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        ScrollDatePicker(
          initialDate: initial ?? DateTime(1998, 1, 1),
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
              color: isSelected ? AppColors.accentTint : AppColors.input,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: isSelected
                    ? AppColors.accent.withValues(alpha: 0.50)
                    : AppColors.border,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Text(
              _formatOptionLabel(option),
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 14,
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
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.accent : AppColors.border,
                  width: isSelected ? 2 : 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                option,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.black : AppColors.textPrimary,
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
      decoration: const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: const Icon(Icons.arrow_forward, color: Colors.black),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildNextButton(OnboardingState state, OnboardingNotifier notifier) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: () => _handleNext(state, notifier),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
        child: Text(
          state.isLastStep ? 'Review' : 'Next',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: Colors.black,
          ),
        ),
      ),
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
                'Review Your Profile',
                style: AppTypography.titleL.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Make sure everything looks good before we build your plan.',
                style: AppTypography.bodyM.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // Summary card
              Container(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadius.cardM),
                  border: Border.all(color: AppColors.border),
                ),
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
                          color: AppColors.border,
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
            border: Border(top: BorderSide(color: AppColors.border)),
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
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.39),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  elevation: 4,
                  shadowColor: AppColors.accent.withValues(alpha: 0.24),
                ),
                child: state.isCompleting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.black,
                        ),
                      )
                    : Text(
                        "Let's Go!",
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
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
                label,
                style: AppTypography.bodyS.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTypography.bodyL.copyWith(
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
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(8),
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
