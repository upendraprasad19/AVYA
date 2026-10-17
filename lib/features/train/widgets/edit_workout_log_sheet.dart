import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/services/workout_read_service.dart';
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
  late final List<EditLogExerciseRow> _rows;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rows = _loadRows();
  }

  List<EditLogExerciseRow> _loadRows() {
    // WorkoutRepository handles both the O(1) index path AND the legacy
    // full-scan fallback for pre-index data, so this covers every log shape.
    final logs =
        WorkoutRepository.instance.getExerciseLogsForDate(widget.date);
    return logs
        .where((log) => log['id'] is String)
        .map((log) => EditLogExerciseRow.fromLog(log['id'] as String, log))
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

          // Unit 7 / OI-50 round-1 F5 — a RESTORED row can carry `sets[]`
          // entries with no per-set durations alongside a real top-level
          // total (`sync_workout.dart:766` writes the aggregate; `:792`
          // only carries a per-set duration when the cloud row had one).
          // The computed total is then 0, and writing it over the
          // surviving aggregate is data loss — visibly so now that the
          // receipt renders that aggregate: the user would watch the
          // duration vanish the moment they saved an unrelated edit.
          // Round-2: `!row.hadPerSetDuration` is load-bearing. Without it a
          // row carrying BOTH per-set durations and a top-level total could
          // never be cleared — the user zeroes every box, this guard drops the
          // write, `editLog` merges (it does not replace), and the stale
          // top-level value is read back forever.
          if (totalDuration == 0 &&
              row.hasAggregateDuration &&
              !row.hadPerSetDuration) {
            updates.remove('duration_seconds');
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

          // Unit 7 / OI-50 — never stamp a fabricated `sets_completed: 0`
          // over a count that was simply ABSENT. `hasAggregateData` is
          // false only when the row carried no set-count signal at all;
          // combined with a still-blank box that means "unknown", not
          // "zero". A user who deliberately types 0 leaves the text
          // non-empty, so an explicit zero is still written.
          if (!row.hasAggregateData && row.setsCtrl.text.trim().isEmpty) {
            updates.remove('sets_completed');
          }
          if (!row.hasAggregateDuration &&
              row.durationCtrl.text.trim().isEmpty) {
            updates.remove('duration_seconds');
          }
          // NOTE (round-1 F5, scoped deliberately): `reps_completed`,
          // `weight_kg` and `distance_km` are still written as 0 from an
          // empty box on a row that never carried them. That is cosmetic,
          // not data loss — unlike sets and duration, no OTHER key holds a
          // surviving value for them (nothing reads a second source), so a
          // fabricated 0 destroys nothing. Guarding sets + duration is the
          // proportionate fix; widening to all five would add three more
          // flags for no behavioural gain.
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

  Widget _buildEditRow(EditLogExerciseRow row) {
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
  Widget _buildPerSetFields(EditLogExerciseRow row) {
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

  Widget _buildSetRow(EditLogSetRow setRow, int setNumber, String loggingType) {
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

  List<Widget> _buildSetInputFields(EditLogSetRow setRow, String loggingType) {
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
  Widget _buildFlattenedFields(EditLogExerciseRow row) {
    return _buildFieldsForLoggingType(row);
  }

  Widget _buildFieldsForLoggingType(EditLogExerciseRow row) {
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
/// Per-set edit row. Carries one set's controllers (reps / weight /
/// duration / distance).
///
/// Marked [visibleForTesting] so the contract test at
/// `test/contracts/edit_workout_log_sets_field_contract_test.dart`
/// can drive `fromSetDetail` directly without mounting the widget.
/// Not part of the public widget API.
@visibleForTesting
class EditLogSetRow {
  final TextEditingController repsCtrl;
  final TextEditingController weightCtrl;
  final TextEditingController durationCtrl;
  final TextEditingController distanceCtrl;

  EditLogSetRow({
    required this.repsCtrl,
    required this.weightCtrl,
    required this.durationCtrl,
    required this.distanceCtrl,
  });

  /// APK Test #15.3 / Bug 6 (e1f8a2) — accept BOTH 'duration_sec'
  /// (canonical, written by `ExerciseSet.toMap`) AND 'duration_seconds'
  /// (legacy, written by `SyncService._restoreExerciseLogs` and
  /// pre-Test-#6 edit-sheet payloads).
  ///
  /// Mirrors the dual-name fallback that `ExerciseSet.fromMap` got in
  /// Bug 4c (6e1b45). Without this, modern WriteService rows with
  /// `duration_sec` per-set lose their duration when the edit sheet
  /// re-reads them.
  factory EditLogSetRow.fromSetDetail(Map<String, dynamic> set) {
    final reps = (set['reps'] as num?)?.toInt() ?? 0;
    final weight = (set['weight_kg'] as num?)?.toDouble() ?? 0;
    final duration = (set['duration_sec'] as num?)?.toInt() ??
        (set['duration_seconds'] as num?)?.toInt() ??
        0;
    final distance = (set['distance_km'] as num?)?.toDouble() ?? 0;

    String fmtDouble(double v) =>
        v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

    return EditLogSetRow(
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
///
/// When the log has a non-empty per-set array (either canonical `'sets'`
/// written by `WorkoutWriteService.logExercise` post-Test-#6, OR legacy
/// `'sets_detail'` written by pre-Test-#6 paths), `setRows` is populated
/// and `hasPerSetData` is true. Otherwise, falls back to aggregate
/// controllers (`setsCtrl` / `repsCtrl` / `weightCtrl` / `durationCtrl` /
/// `distanceCtrl`).
///
/// Marked [visibleForTesting] so the contract test at
/// `test/contracts/edit_workout_log_sets_field_contract_test.dart` can
/// drive `fromLog` directly without mounting the widget. Not part of the
/// public widget API.
@visibleForTesting
class EditLogExerciseRow {
  final String logId;
  final String exerciseName;
  final String loggingType;
  final bool hasPerSetData;

  /// Whether the source row carried ANY set-count signal at all
  /// (`set_number`, `sets_completed`, or a per-set array).
  ///
  /// Unit 7 / OI-50 — distinguishes "the user logged 0 sets" from "every
  /// count key was absent on this row". Both render as an empty box, so
  /// without this flag `save` stamped a fabricated `sets_completed: 0`
  /// over a genuine gap.
  final bool hasAggregateData;

  /// Whether the source row carried ANY duration signal (a per-set duration
  /// to sum, or a top-level `duration_seconds`).
  ///
  /// Unit 7 / OI-50 round-1 F5 — separate from [hasAggregateData] because
  /// duration is the one aggregate whose fabrication is real DATA LOSS: a
  /// restored row's top-level total is the only surviving copy, and both
  /// save branches would otherwise write a computed 0 straight over it.
  final bool hasAggregateDuration;

  /// Whether the ORIGINAL row's per-set entries carried durations.
  ///
  /// Unit 7 / OI-50 round-2 — without this, [hasAggregateDuration] alone made
  /// a duration permanently un-clearable on any row holding BOTH per-set
  /// durations and a top-level total (a restored row whose workout_log_sets
  /// join was non-empty carries both). The user clears every per-set box, the
  /// save guard fires, `editLog` merges rather than replaces, and the stale
  /// top-level value is resurrected on the very next read — forever.
  final bool hadPerSetDuration;

  // Per-set rows (populated when per-set array exists on the log)
  final List<EditLogSetRow> setRows;

  // Legacy aggregate controllers (used when no per-set array)
  final TextEditingController setsCtrl;
  final TextEditingController repsCtrl;
  final TextEditingController weightCtrl;
  final TextEditingController durationCtrl;
  final TextEditingController distanceCtrl;

  EditLogExerciseRow._({
    required this.logId,
    required this.exerciseName,
    required this.loggingType,
    required this.hasPerSetData,
    required this.hasAggregateData,
    required this.hasAggregateDuration,
    required this.hadPerSetDuration,
    required this.setRows,
    required this.setsCtrl,
    required this.repsCtrl,
    required this.weightCtrl,
    required this.durationCtrl,
    required this.distanceCtrl,
  });

  /// APK Test #15.3 / Bug 6 (e1f8a2) — prefer canonical `'sets'`
  /// (written by `WorkoutWriteService.logExercise` post-Test-#6) with
  /// legacy `'sets_detail'` fallback for pre-Test-#6 rows that may
  /// still exist in long-installed devices' Hive (or until the
  /// editLog migration in `WorkoutWriteService.editLog` line 643
  /// promotes them).
  ///
  /// Pre-fix this factory read only `log['sets_detail']`. Modern
  /// WriteService rows have `sets` (not `sets_detail`), so the per-set
  /// path was bypassed and the user fell back to the aggregate view
  /// with empty duration inputs. Same class as Bug 4c (6e1b45) — see
  /// `docs/diagnoses/2026-05-12-edit-log-sets-detail-legacy-e1f8a2.md`.
  factory EditLogExerciseRow.fromLog(
      String logId, Map<String, dynamic> log) {
    final name = (log['exercise_name'] as String?) ?? 'Exercise';
    final type = (log['logging_type'] as String?) ?? 'weight_reps';
    // Canonical `'sets'` first (post-Test-#6); legacy `'sets_detail'`
    // fallback for pre-Test-#6 rows.
    final setsListRaw = log['sets'] ?? log['sets_detail'];
    // Unit 7 / OI-50 — computed once, carried into BOTH branches.
    final hasAggregate = WorkoutReadService.hasAggregateSetCount(log);
    final hasAggregateDur =
        WorkoutReadService.aggregateDurationSeconds(log) != null;
    // Round-2 — did the ORIGINAL per-set entries carry any duration? If they
    // did, clearing them all is a deliberate user action and the save guard
    // must not resurrect the top-level aggregate behind their back.
    final hadPerSetDur = setsListRaw is List &&
        setsListRaw.whereType<Map>().any((s) =>
            (((s['duration_sec'] as num?)?.toInt() ??
                    (s['duration_seconds'] as num?)?.toInt() ??
                    0)) >
                0);

    // Check if per-set data exists and is a non-empty list
    if (setsListRaw is List && setsListRaw.isNotEmpty) {
      final setRows = setsListRaw
          .whereType<Map>()
          .map((s) =>
              EditLogSetRow.fromSetDetail(Map<String, dynamic>.from(s)))
          .toList();

      if (setRows.isNotEmpty) {
        return EditLogExerciseRow._(
          logId: logId,
          exerciseName: name,
          loggingType: type,
          hasPerSetData: true,
          hasAggregateData: hasAggregate,
          hasAggregateDuration: hasAggregateDur,
          hadPerSetDuration: hadPerSetDur,
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
    // Unit 7 / OI-50 — was `log['sets_completed']` alone, which is only
    // the LEGACY key. The restore writer (`sync/sync_workout.dart:762-763`)
    // stamps `set_number` and NEVER `sets_completed`, so every
    // cloud-restored aggregate row rendered a BLANK sets box while the
    // receipt — which already MAXed both keys — showed the real count.
    // Both surfaces now share one reader so they cannot disagree.
    final sets = WorkoutReadService.aggregateSetCount(log);
    final reps = (log['reps_completed'] as num?)?.toInt() ?? 0;
    final weight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
    // Unit 7 / OI-50 — was `bestPerSetDuration`, which is a per-set MAX.
    // This box is the TOTAL: `save` writes it straight to top-level
    // `duration_seconds`, which the writer contract defines as the SUM
    // across sets. `bestPerSetDuration` gates its top-level fallback on
    // `setCount <= 1`, so on a restored MULTI-set timed row it returned 0
    // — the box rendered blank and saving then WIPED the real total to 0.
    final duration = WorkoutReadService.aggregateDurationSeconds(log) ?? 0;
    final distance = (log['distance_km'] as num?)?.toDouble() ?? 0;

    String fmtDouble(double v) =>
        v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

    return EditLogExerciseRow._(
      logId: logId,
      exerciseName: name,
      loggingType: type,
      hasPerSetData: false,
      hasAggregateData: hasAggregate,
      hasAggregateDuration: hasAggregateDur,
      hadPerSetDuration: hadPerSetDur,
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

