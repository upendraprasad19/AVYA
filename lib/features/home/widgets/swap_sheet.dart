import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';

/// Bottom sheet that allows swapping a workout day with another day
/// in the same week. Long-press a day on the weekly calendar to open.
class SwapSheet extends StatefulWidget {
  /// The date of the day that was long-pressed.
  final DateTime sourceDate;

  /// Called after a successful swap so the caller can refresh state.
  final VoidCallback? onSwapComplete;

  const SwapSheet({
    super.key,
    required this.sourceDate,
    this.onSwapComplete,
  });

  /// Shows the swap sheet as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required DateTime sourceDate,
    VoidCallback? onSwapComplete,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SwapSheet(
        sourceDate: sourceDate,
        onSwapComplete: onSwapComplete,
      ),
    );
  }

  @override
  State<SwapSheet> createState() => _SwapSheetState();
}

class _SwapSheetState extends State<SwapSheet> {
  final _scheduleService = WorkoutScheduleService.instance;
  final _subscriptionService = SubscriptionService.instance;

  DateTime? _selectedTarget;
  String? _errorText;
  bool _isSwapping = false;

  late final DateTime _weekStart;
  late final List<DateTime> _weekDays;
  late final List<Map<String, dynamic>?> _schedules;
  late final Map<String, dynamic>? _sourceSchedule;
  late final bool _isPro;

  static const _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _isPro = _subscriptionService.isPro();
    final src = widget.sourceDate;
    _weekStart = DateTime(src.year, src.month, src.day)
        .subtract(Duration(days: src.weekday - 1));
    _weekDays = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    _schedules = _weekDays
        .map((d) => _scheduleService.getScheduleForDate(d))
        .toList();
    _sourceSchedule = _scheduleService.getScheduleForDate(widget.sourceDate);
  }

  String _workoutLabel(Map<String, dynamic>? schedule) {
    if (schedule == null) return 'No Plan';
    final type = schedule['type'] as String? ?? 'none';
    if (type == 'rest') return 'Rest Day';
    return schedule['workout_name'] as String? ?? 'Workout';
  }

  bool _wouldCauseThreeConsecutiveRest(DateTime target) {
    // Build current week types
    final types = <String>[];
    for (final s in _schedules) {
      types.add(s?['type'] as String? ?? 'rest');
    }
    // Simulate swap
    final idxA = widget.sourceDate.difference(_weekStart).inDays;
    final idxB = target.difference(_weekStart).inDays;
    if (idxA < 0 || idxA > 6 || idxB < 0 || idxB > 6) return false;
    final temp = types[idxA];
    types[idxA] = types[idxB];
    types[idxB] = temp;
    // Check
    int consecutive = 0;
    for (final t in types) {
      if (t == 'rest') {
        consecutive++;
        if (consecutive >= 3) return true;
      } else {
        consecutive = 0;
      }
    }
    return false;
  }

  Future<void> _onConfirm() async {
    if (_selectedTarget == null) return;

    setState(() {
      _isSwapping = true;
      _errorText = null;
    });

    final result = await _scheduleService.swapDays(
      widget.sourceDate,
      _selectedTarget!,
      isPro: _isPro,
    );

    if (!mounted) return;

    if (result != null) {
      setState(() {
        _errorText = result;
        _isSwapping = false;
      });
      return;
    }

    // Success
    Navigator.of(context).pop();
    widget.onSwapComplete?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Workout swapped \u2713',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sourceDayName =
        _dayNames[widget.sourceDate.weekday - 1];
    final sourceWorkout = _workoutLabel(_sourceSchedule);

    final bool confirmDisabled = _selectedTarget == null ||
        _isSwapping ||
        (_selectedTarget != null &&
            _wouldCauseThreeConsecutiveRest(_selectedTarget!));

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.cardL),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            12,
            AppSpacing.screenPadding,
            AppSpacing.screenPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),

              // Header
              Text(
                'SWAP WORKOUT',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$sourceDayName \u2014 $sourceWorkout',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),

              // Day list
              ...List.generate(7, (index) {
                final day = _weekDays[index];
                final schedule = _schedules[index];
                final isSameAsSource =
                    day.year == widget.sourceDate.year &&
                        day.month == widget.sourceDate.month &&
                        day.day == widget.sourceDate.day;

                if (isSameAsSource) return const SizedBox.shrink();

                final dayName = _dayNames[index];
                final workoutName = _workoutLabel(schedule);
                final isSelected = _selectedTarget != null &&
                    _selectedTarget!.year == day.year &&
                    _selectedTarget!.month == day.month &&
                    _selectedTarget!.day == day.day;

                final wouldCauseError =
                    _wouldCauseThreeConsecutiveRest(day);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedTarget = day;
                        if (wouldCauseError) {
                          _errorText =
                              'Swap would create 3+ consecutive rest days';
                        } else {
                          _errorText = null;
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.cardPadding,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.accent.withValues(alpha: 0.06)
                            : AppColors.input,
                        borderRadius:
                            BorderRadius.circular(AppRadius.row),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.accent
                              : AppColors.border,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dayName,
                                  style: GoogleFonts.getFont(
                                    'DM Sans',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected
                                        ? AppColors.accent
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  workoutName,
                                  style: GoogleFonts.getFont(
                                    'DM Sans',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.swap_horiz_rounded,
                              color: AppColors.accent,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const SizedBox(height: 4),

              // Error text
              if (_errorText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _errorText!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.red,
                    ),
                  ),
                ),

              // Confirm button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: confirmDisabled ? null : _onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: confirmDisabled
                        ? AppColors.input
                        : AppColors.accent,
                    foregroundColor: confirmDisabled
                        ? AppColors.textDisabled
                        : Colors.black,
                    disabledBackgroundColor: AppColors.input,
                    disabledForegroundColor: AppColors.textDisabled,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  child: _isSwapping
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          'CONFIRM SWAP',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),

              // Swap limit info
              Text(
                'Free: 1 swap/week \u00B7 PRO: 3 swaps/week',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
