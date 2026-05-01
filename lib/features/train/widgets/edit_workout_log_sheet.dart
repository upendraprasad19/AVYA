import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Bottom sheet for editing the aggregate values of a completed workout's
/// exercise logs. Reads directly from Hive (`exercise_log_index_YYYY-MM-DD`
/// → `exlog_*`), shows one editable row per exercise shaped by logging_type,
/// writes back to the same Hive keys on Save, recomputes volume_kg and is_pr
/// flags, invalidates affected providers, and triggers cloud sync +
/// pushSnapshot so the AI coach sees the correction.
///
/// When `sets_detail` is present in the log (new logs), the sheet renders
/// individual set rows for per-set editing. For old logs without `sets_detail`,
/// it falls back to the flattened aggregate view.
///
/// This is the **only** edit path for completed workout logs. Entry points:
///   - WorkoutReceiptSheet (covers post-completion, Home "View Card",
///     calendar day detail)
///   - Train screen expanded view (for past completed days)
class EditWorkoutLogSheet extends ConsumerStatefulWidget {
  final DateTime date;

  const EditWorkoutLogSheet({super.key, required this.date});

  /// Convenience: show as a modal bottom sheet.
  static void show(BuildContext context, DateTime date) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EditWorkoutLogSheet(date: date),
    );
  }

  @override
  ConsumerState<EditWorkoutLogSheet> createState() =>
      _EditWorkoutLogSheetState();
}

class _EditWorkoutLogSheetState extends ConsumerState<EditWorkoutLogSheet> {
  /// One entry per exlog row — preserves original id + loggingType and
  /// carries the live controllers the user edits.
  late final List<_ExerciseEditRow> _rows;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rows = _loadRows();
  }

  List<_ExerciseEditRow> _loadRows() {
    // WorkoutRepository handles both the O(1) index path AND the legacy
    // full-scan fallback for pre-index data, so this covers every log shape.
    final logs =
        WorkoutRepository.instance.getExerciseLogsForDate(widget.date);
    return logs
        .where((log) => log['id'] is String)
        .map((log) => _ExerciseEditRow.fromLog(log['id'] as String, log))
        .toList();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  // ── Save handler ──────────────────────────────────────────────
  // Plan A Task A-14: per-row edits route through WorkoutWriteService.editLog.
  // We construct a per-loggingType updates map (excluding the canonical
  // `sets` key — service only recomputes from sets when present, and our
  // existing schema uses `sets_detail` with field names that don't match
  // ExerciseSet.fromMap exactly). Service handles chronological PR rescan
  // across all logs of the exercise and fire-and-forget sync.
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      for (final row in _rows) {
        final updates = <String, dynamic>{};

        if (row.hasPerSetData) {
          // ── Per-set data path: recompute aggregates from individual sets ──
          final setsDetail = <Map<String, dynamic>>[];
          double maxWeight = 0;
          int totalReps = 0;
          int totalDuration = 0;
          double totalDistance = 0;
          double volumeKg = 0;
          int bestSingleSetReps = 0;
          int bestSingleSetDuration = 0;

          for (int i = 0; i < row.setRows.length; i++) {
            final setRow = row.setRows[i];
            final reps = int.tryParse(setRow.repsCtrl.text) ?? 0;
            final weight = double.tryParse(setRow.weightCtrl.text) ?? 0;
            final duration = int.tryParse(setRow.durationCtrl.text) ?? 0;
            final distance = double.tryParse(setRow.distanceCtrl.text) ?? 0;

            final setMap = <String, dynamic>{
              'set_number': i + 1,
            };
            if (weight > 0) setMap['weight_kg'] = weight;
            if (reps > 0) setMap['reps'] = reps;
            if (duration > 0) setMap['duration_seconds'] = duration;
            if (distance > 0) setMap['distance_km'] = distance;

            setsDetail.add(setMap);

            // Aggregate
            if (weight > maxWeight) maxWeight = weight;
            totalReps += reps;
            totalDuration += duration;
            totalDistance += distance;
            volumeKg += weight * reps;
            if (reps > bestSingleSetReps) bestSingleSetReps = reps;
            if (duration > bestSingleSetDuration) {
              bestSingleSetDuration = duration;
            }
          }

          final sets = row.setRows.length;

          switch (row.loggingType) {
            case 'weight_reps':
              updates['sets_completed'] = sets;
              updates['reps_completed'] = totalReps;
              updates['weight_kg'] = maxWeight;
              updates['volume_kg'] = volumeKg;
              break;
            case 'bodyweight_reps':
              updates['sets_completed'] = sets;
              updates['reps_completed'] = totalReps;
              updates['volume_kg'] = 0.0;
              break;
            case 'weighted_bodyweight':
              updates['sets_completed'] = sets;
              updates['reps_completed'] = totalReps;
              updates['weight_kg'] = maxWeight;
              updates['volume_kg'] = volumeKg;
              break;
            case 'timed':
              updates['sets_completed'] = sets;
              updates['duration_seconds'] = totalDuration;
              updates['volume_kg'] = 0.0;
              break;
            case 'cardio':
              updates['duration_seconds'] = totalDuration;
              updates['distance_km'] = totalDistance;
              updates['volume_kg'] = 0.0;
              break;
            case 'distance':
              updates['distance_km'] = totalDistance;
              updates['weight_kg'] = maxWeight;
              updates['volume_kg'] = 0.0;
              break;
            default:
              updates['sets_completed'] = sets;
              updates['reps_completed'] = totalReps;
              updates['weight_kg'] = maxWeight;
              updates['volume_kg'] = volumeKg;
          }

          updates['sets_detail'] = setsDetail;
          updates['best_single_set_reps'] = bestSingleSetReps;
          updates['best_single_set_duration'] = bestSingleSetDuration;
        } else {
          // ── Legacy flattened path (old logs without sets_detail) ──
          final sets = int.tryParse(row.setsCtrl.text) ?? 0;
          final reps = int.tryParse(row.repsCtrl.text) ?? 0;
          final weight = double.tryParse(row.weightCtrl.text) ?? 0;
          final duration = int.tryParse(row.durationCtrl.text) ?? 0;
          final distance = double.tryParse(row.distanceCtrl.text) ?? 0;

          switch (row.loggingType) {
            case 'weight_reps':
              updates['sets_completed'] = sets;
              updates['reps_completed'] = reps;
              updates['weight_kg'] = weight;
              updates['volume_kg'] = weight * reps;
              break;
            case 'bodyweight_reps':
              updates['sets_completed'] = sets;
              updates['reps_completed'] = reps;
              updates['volume_kg'] = 0.0;
              break;
            case 'weighted_bodyweight':
              updates['sets_completed'] = sets;
              updates['reps_completed'] = reps;
              updates['weight_kg'] = weight;
              updates['volume_kg'] = weight * reps;
              break;
            case 'timed':
              updates['sets_completed'] = sets;
              updates['duration_seconds'] = duration;
              updates['volume_kg'] = 0.0;
              break;
            case 'cardio':
              updates['duration_seconds'] = duration;
              updates['distance_km'] = distance;
              updates['volume_kg'] = 0.0;
              break;
            case 'distance':
              updates['distance_km'] = distance;
              updates['weight_kg'] = weight;
              updates['volume_kg'] = 0.0;
              break;
            default:
              updates['sets_completed'] = sets;
              updates['reps_completed'] = reps;
              updates['weight_kg'] = weight;
              updates['volume_kg'] = weight * reps;
          }
        }

        updates['edited_at'] = DateTime.now().toIso8601String();

        final result = await WorkoutWriteService.instance.editLog(
          logKey: row.logId,
          updates: updates,
          source: WriteSource.editSheet,
        );
        if (!result.success) {
          debugPrint(
              '[EditWorkoutLogSheet] editLog failed for ${row.logId}: ${result.errorMessage}');
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    if (!mounted) return;

    // Invalidate every provider the completion flow invalidates. Riverpod
    // batches these within the same frame. Service already fired
    // syncWorkoutData + pushSnapshot fire-and-forget per row.
    ref.invalidate(currentPlanProvider);
    ref.invalidate(workoutStatsProvider);
    ref.invalidate(calendarWeekProvider);
    ref.invalidate(streakProvider);
    ref.invalidate(todayWorkoutProvider);
    ref.invalidate(allExercisePRsProvider);

    // Capture the messenger before pop — context becomes invalid after.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Workout log updated',
          style: AppTypography.bodySm
              .copyWith(fontWeight: FontWeight.w700),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.card,
      ),
    );
  }

  // PR rescan now handled by WorkoutWriteService.editLog (via service-internal
  // _rescanAllPrsFor). Removed local _recomputePrFlagsForExercise + _PrScanEntry
  // as part of Plan A Task A-14.

  // ── UI ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: mq.size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.line2, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            if (_rows.isEmpty)
              _buildEmptyState()
            else
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    children: [
                      for (final row in _rows) _buildEditRow(row),
                    ],
                  ),
                ),
              ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final monthAbbr = const [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ][widget.date.month - 1];
    final dateLabel =
        '$monthAbbr ${widget.date.day.toString().padLeft(2, '0')} · ${widget.date.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EDIT WORKOUT',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.accent,
                    letterSpacing: 2.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Review sets',
                  style: AppTypography.h2,
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: AppTypography.mono.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                color: AppColors.textDim, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.fitness_center,
              color: AppColors.textDim.withValues(alpha: 0.4), size: 36),
          const SizedBox(height: 12),
          Text(
            'No exercise logs for this day',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditRow(_ExerciseEditRow row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WardCard(
        variant: WardCardVariant.inset,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.exerciseName,
              style: AppTypography.h3.copyWith(fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            if (row.hasPerSetData)
              _buildPerSetFields(row)
            else
              _buildFlattenedFields(row),
          ],
        ),
      ),
    );
  }

  /// Per-set editing: renders a header row + individual set rows.
  Widget _buildPerSetFields(_ExerciseEditRow row) {
    return Column(
      children: [
        // Header labels
        _buildSetHeader(row.loggingType),
        const SizedBox(height: 6),
        // Individual set rows
        for (int i = 0; i < row.setRows.length; i++) ...[
          _buildSetRow(row.setRows[i], i + 1, row.loggingType),
          if (i < row.setRows.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _buildSetHeader(String loggingType) {
    final labels = _fieldsForLoggingType(loggingType);
    return Padding(
      padding: const EdgeInsets.only(left: 36),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Text(
                labels[i],
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Returns the field labels for a given logging type.
  List<String> _fieldsForLoggingType(String loggingType) {
    switch (loggingType) {
      case 'bodyweight_reps':
        return ['REPS'];
      case 'weighted_bodyweight':
        return ['+KG', 'REPS'];
      case 'timed':
        return ['SECONDS'];
      case 'cardio':
        return ['DURATION (S)', 'DIST (KM)'];
      case 'distance':
        return ['DIST (KM)', 'LOAD (KG)'];
      default: // weight_reps
        return ['KG', 'REPS'];
    }
  }

  Widget _buildSetRow(_SetEditRow setRow, int setNumber, String loggingType) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          // Set number badge — sharp square in Wardroom voice
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(AppRadius.sharp),
            ),
            child: Center(
              child: Text(
                '$setNumber',
                style: AppTypography.mono.copyWith(
                  fontSize: 11,
                  color: AppColors.bgDeep,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Input fields based on logging type
          ..._buildSetInputFields(setRow, loggingType),
        ],
      ),
    );
  }

  List<Widget> _buildSetInputFields(_SetEditRow setRow, String loggingType) {
    switch (loggingType) {
      case 'bodyweight_reps':
        return [
          Expanded(child: _compactField(setRow.repsCtrl)),
        ];
      case 'weighted_bodyweight':
        return [
          Expanded(child: _compactField(setRow.weightCtrl, allowDecimal: true)),
          const SizedBox(width: 8),
          Expanded(child: _compactField(setRow.repsCtrl)),
        ];
      case 'timed':
        return [
          Expanded(child: _compactField(setRow.durationCtrl)),
        ];
      case 'cardio':
        return [
          Expanded(child: _compactField(setRow.durationCtrl)),
          const SizedBox(width: 8),
          Expanded(
              child: _compactField(setRow.distanceCtrl, allowDecimal: true)),
        ];
      case 'distance':
        return [
          Expanded(
              child: _compactField(setRow.distanceCtrl, allowDecimal: true)),
          const SizedBox(width: 8),
          Expanded(
              child: _compactField(setRow.weightCtrl, allowDecimal: true)),
        ];
      default: // weight_reps
        return [
          Expanded(child: _compactField(setRow.weightCtrl, allowDecimal: true)),
          const SizedBox(width: 8),
          Expanded(child: _compactField(setRow.repsCtrl)),
        ];
    }
  }

  /// Compact input field for per-set rows — no label, just the value.
  Widget _compactField(TextEditingController ctrl,
      {bool allowDecimal = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: [
        if (allowDecimal)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
        else
          FilteringTextInputFormatter.digitsOnly,
      ],
      textAlign: TextAlign.center,
      style: AppTypography.h3.copyWith(
        fontSize: 16,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        filled: true,
        fillColor: AppColors.bgDeep,
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
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
      ),
    );
  }

  /// Legacy flattened view for old logs without per-set data.
  Widget _buildFlattenedFields(_ExerciseEditRow row) {
    return _buildFieldsForLoggingType(row);
  }

  Widget _buildFieldsForLoggingType(_ExerciseEditRow row) {
    switch (row.loggingType) {
      case 'bodyweight_reps':
        return Row(
          children: [
            Expanded(child: _numField(row.setsCtrl, 'Sets')),
            const SizedBox(width: 8),
            Expanded(child: _numField(row.repsCtrl, 'Total Reps')),
          ],
        );
      case 'weighted_bodyweight':
        return Row(
          children: [
            Expanded(child: _numField(row.setsCtrl, 'Sets')),
            const SizedBox(width: 8),
            Expanded(child: _numField(row.repsCtrl, 'Total Reps')),
            const SizedBox(width: 8),
            Expanded(
                child: _numField(row.weightCtrl, '+Weight (kg)',
                    allowDecimal: true)),
          ],
        );
      case 'timed':
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: _numField(row.setsCtrl, 'Sets')),
                const SizedBox(width: 8),
                Expanded(
                    child: _numField(row.durationCtrl, 'Total Duration (s)')),
              ],
            ),
            _buildDurationHint(row.durationCtrl),
          ],
        );
      case 'cardio':
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: _numField(row.durationCtrl, 'Duration (s)')),
                const SizedBox(width: 8),
                Expanded(
                    child: _numField(row.distanceCtrl, 'Distance (km)',
                        allowDecimal: true)),
              ],
            ),
            _buildDurationHint(row.durationCtrl),
          ],
        );
      case 'distance':
        return Row(
          children: [
            Expanded(
                child: _numField(row.distanceCtrl, 'Distance (km)',
                    allowDecimal: true)),
            const SizedBox(width: 8),
            Expanded(
                child: _numField(row.weightCtrl, 'Load (kg)',
                    allowDecimal: true)),
          ],
        );
      default: // weight_reps
        return Row(
          children: [
            Expanded(child: _numField(row.setsCtrl, 'Sets')),
            const SizedBox(width: 8),
            Expanded(child: _numField(row.repsCtrl, 'Total Reps')),
            const SizedBox(width: 8),
            Expanded(
                child: _numField(row.weightCtrl, 'Weight (kg)',
                    allowDecimal: true)),
          ],
        );
    }
  }

  Widget _buildDurationHint(TextEditingController ctrl) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final secs = int.tryParse(ctrl.text) ?? 0;
        if (secs < 60) return const SizedBox.shrink();
        final m = secs ~/ 60;
        final s = secs % 60;
        final formatted = s == 0 ? '${m}m' : '${m}m ${s}s';
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '= $formatted',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textMute,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _numField(TextEditingController ctrl, String label,
      {bool allowDecimal = false}) {
    return TextField(
      controller: ctrl,
      keyboardType:
          TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: [
        if (allowDecimal)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
        else
          FilteringTextInputFormatter.digitsOnly,
      ],
      style: AppTypography.h3.copyWith(
        fontSize: 16,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label.toUpperCase(),
        labelStyle: AppTypography.mono.copyWith(
          color: AppColors.textMute,
          letterSpacing: 2,
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        filled: true,
        fillColor: AppColors.bgDeep,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          borderSide:
              const BorderSide(color: AppColors.line2, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          borderSide:
              const BorderSide(color: AppColors.line2, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: WardButton(
              label: 'CANCEL',
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              variant: WardButtonVariant.ghost,
              size: WardButtonSize.medium,
              fullWidth: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _saving
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.4),
                      borderRadius:
                          BorderRadius.circular(AppRadius.sharp),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.4)),
                    ),
                    child: const Center(
                      child: SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.bgDeep,
                        ),
                      ),
                    ),
                  )
                : WardButton(
                    label: 'SAVE CHANGES',
                    onPressed: _rows.isEmpty ? null : _save,
                    variant: WardButtonVariant.primary,
                    size: WardButtonSize.medium,
                    fullWidth: true,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Per-set controllers for individual set editing.
class _SetEditRow {
  final TextEditingController repsCtrl;
  final TextEditingController weightCtrl;
  final TextEditingController durationCtrl;
  final TextEditingController distanceCtrl;

  _SetEditRow({
    required this.repsCtrl,
    required this.weightCtrl,
    required this.durationCtrl,
    required this.distanceCtrl,
  });

  factory _SetEditRow.fromSetDetail(Map<String, dynamic> set) {
    final reps = (set['reps'] as num?)?.toInt() ?? 0;
    final weight = (set['weight_kg'] as num?)?.toDouble() ?? 0;
    final duration = (set['duration_seconds'] as num?)?.toInt() ?? 0;
    final distance = (set['distance_km'] as num?)?.toDouble() ?? 0;

    String fmtDouble(double v) =>
        v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

    return _SetEditRow(
      repsCtrl: TextEditingController(text: reps > 0 ? reps.toString() : ''),
      weightCtrl:
          TextEditingController(text: weight > 0 ? fmtDouble(weight) : ''),
      durationCtrl: TextEditingController(
          text: duration > 0 ? duration.toString() : ''),
      distanceCtrl: TextEditingController(
          text: distance > 0 ? fmtDouble(distance) : ''),
    );
  }

  void dispose() {
    repsCtrl.dispose();
    weightCtrl.dispose();
    durationCtrl.dispose();
    distanceCtrl.dispose();
  }
}

/// Carries the original log id + loggingType + controllers for one exlog row.
/// When `sets_detail` is present, `setRows` is populated and `hasPerSetData`
/// is true. Otherwise, falls back to aggregate controllers.
class _ExerciseEditRow {
  final String logId;
  final String exerciseName;
  final String loggingType;
  final bool hasPerSetData;

  // Per-set rows (populated when sets_detail exists)
  final List<_SetEditRow> setRows;

  // Legacy aggregate controllers (used when no sets_detail)
  final TextEditingController setsCtrl;
  final TextEditingController repsCtrl;
  final TextEditingController weightCtrl;
  final TextEditingController durationCtrl;
  final TextEditingController distanceCtrl;

  _ExerciseEditRow._({
    required this.logId,
    required this.exerciseName,
    required this.loggingType,
    required this.hasPerSetData,
    required this.setRows,
    required this.setsCtrl,
    required this.repsCtrl,
    required this.weightCtrl,
    required this.durationCtrl,
    required this.distanceCtrl,
  });

  factory _ExerciseEditRow.fromLog(String logId, Map<String, dynamic> log) {
    final name = (log['exercise_name'] as String?) ?? 'Exercise';
    final type = (log['logging_type'] as String?) ?? 'weight_reps';
    final setsDetailRaw = log['sets_detail'];

    // Check if per-set data exists and is a non-empty list
    if (setsDetailRaw is List && setsDetailRaw.isNotEmpty) {
      final setRows = setsDetailRaw
          .whereType<Map>()
          .map((s) => _SetEditRow.fromSetDetail(Map<String, dynamic>.from(s)))
          .toList();

      if (setRows.isNotEmpty) {
        return _ExerciseEditRow._(
          logId: logId,
          exerciseName: name,
          loggingType: type,
          hasPerSetData: true,
          setRows: setRows,
          // Aggregate controllers unused but need to be initialized
          setsCtrl: TextEditingController(),
          repsCtrl: TextEditingController(),
          weightCtrl: TextEditingController(),
          durationCtrl: TextEditingController(),
          distanceCtrl: TextEditingController(),
        );
      }
    }

    // Fallback: legacy aggregate view
    final sets = (log['sets_completed'] as num?)?.toInt() ?? 0;
    final reps = (log['reps_completed'] as num?)?.toInt() ?? 0;
    final weight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
    final duration = (log['duration_seconds'] as num?)?.toInt() ?? 0;
    final distance = (log['distance_km'] as num?)?.toDouble() ?? 0;

    String fmtDouble(double v) =>
        v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

    return _ExerciseEditRow._(
      logId: logId,
      exerciseName: name,
      loggingType: type,
      hasPerSetData: false,
      setRows: [],
      setsCtrl: TextEditingController(text: sets > 0 ? sets.toString() : ''),
      repsCtrl: TextEditingController(text: reps > 0 ? reps.toString() : ''),
      weightCtrl:
          TextEditingController(text: weight > 0 ? fmtDouble(weight) : ''),
      durationCtrl: TextEditingController(
          text: duration > 0 ? duration.toString() : ''),
      distanceCtrl: TextEditingController(
          text: distance > 0 ? fmtDouble(distance) : ''),
    );
  }

  void dispose() {
    for (final sr in setRows) {
      sr.dispose();
    }
    setsCtrl.dispose();
    repsCtrl.dispose();
    weightCtrl.dispose();
    durationCtrl.dispose();
    distanceCtrl.dispose();
  }
}

