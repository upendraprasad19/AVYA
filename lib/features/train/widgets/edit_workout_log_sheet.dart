import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

/// Bottom sheet for editing the aggregate values of a completed workout's
/// exercise logs. Reads directly from Hive (`exercise_log_index_YYYY-MM-DD`
/// → `exlog_*`), shows one editable row per exercise shaped by logging_type,
/// writes back to the same Hive keys on Save, recomputes volume_kg and is_pr
/// flags, invalidates affected providers, and triggers cloud sync +
/// pushSnapshot so the AI coach sees the correction.
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
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final box = HiveService.instance.workoutBox;
    final editedExerciseNames = <String>{};

    try {
      for (final row in _rows) {
        final existing = box.get(row.logId);
        if (existing is! Map) continue;
        final log = Map<String, dynamic>.from(existing);

        // Parse controller values (parse-or-zero, matches nutrition pattern)
        final sets = int.tryParse(row.setsCtrl.text) ?? 0;
        final reps = int.tryParse(row.repsCtrl.text) ?? 0;
        final weight = double.tryParse(row.weightCtrl.text) ?? 0;
        final duration = int.tryParse(row.durationCtrl.text) ?? 0;
        final distance = double.tryParse(row.distanceCtrl.text) ?? 0;

        // Rebuild the log per logging_type (same shape as completeWorkout).
        switch (row.loggingType) {
          case 'weight_reps':
            log['sets_completed'] = sets;
            log['reps_completed'] = reps;
            log['weight_kg'] = weight;
            log['volume_kg'] = weight * reps;
            break;
          case 'bodyweight_reps':
            log['sets_completed'] = sets;
            log['reps_completed'] = reps;
            log['volume_kg'] = 0.0;
            break;
          case 'weighted_bodyweight':
            log['sets_completed'] = sets;
            log['reps_completed'] = reps;
            log['weight_kg'] = weight;
            log['volume_kg'] = weight * reps;
            break;
          case 'timed':
            log['sets_completed'] = sets;
            log['duration_seconds'] = duration;
            log['volume_kg'] = 0.0;
            break;
          case 'cardio':
            log['duration_seconds'] = duration;
            log['distance_km'] = distance;
            log['volume_kg'] = 0.0;
            break;
          case 'distance':
            log['distance_km'] = distance;
            log['weight_kg'] = weight;
            log['volume_kg'] = 0.0;
            break;
          default:
            log['sets_completed'] = sets;
            log['reps_completed'] = reps;
            log['weight_kg'] = weight;
            log['volume_kg'] = weight * reps;
        }

        log['edited_at'] = DateTime.now().toIso8601String();
        await box.put(row.logId, log);

        final exName = log['exercise_name'] as String?;
        if (exName != null) editedExerciseNames.add(exName);
      }

      // Recompute is_pr flags for every edited exercise across all history.
      // A log is a PR iff its value is strictly greater than every prior log
      // of the same exercise (ordered by date ascending).
      for (final name in editedExerciseNames) {
        _recomputePrFlagsForExercise(name);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    if (!mounted) return;

    // Invalidate every provider the completion flow invalidates. Riverpod
    // batches these within the same frame.
    ref.invalidate(currentPlanProvider);
    ref.invalidate(workoutStatsProvider);
    ref.invalidate(calendarWeekProvider);
    ref.invalidate(streakProvider);
    ref.invalidate(todayWorkoutProvider);
    ref.invalidate(allExercisePRsProvider);

    // Fire-and-forget cloud sync so the corrected log reaches Supabase and
    // the AI coach snapshot catches up.
    SyncService.instance.syncWorkoutData();
    SyncService.instance.pushSnapshot();

    // Capture the messenger before pop — context becomes invalid after.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Workout log updated',
          style: GoogleFonts.getFont('DM Sans', fontWeight: FontWeight.w700),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.card,
      ),
    );
  }

  /// Walks every exlog for a given exercise name chronologically and rewrites
  /// the `is_pr` flag. PR rule:
  ///   - `weight_reps` / `weighted_bodyweight`: strict increase in `weight_kg`
  ///   - `bodyweight_reps`: strict increase in `reps_completed`
  ///   - `timed`: strict increase in `duration_seconds`
  ///   - `cardio` / `distance`: strict increase in `distance_km`
  /// The earliest log with a baseline value is NOT a PR (needs something to
  /// beat). This matches `completeWorkout`'s "must beat prior best" rule.
  void _recomputePrFlagsForExercise(String name) {
    final box = HiveService.instance.workoutBox;
    final lower = name.toLowerCase();

    // Collect all logs for this exercise.
    final entries = <_PrScanEntry>[];
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('exlog_')) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      if (map['type'] != 'exercise_log') continue;
      final exName = (map['exercise_name'] as String?) ?? '';
      if (exName.toLowerCase() != lower) continue;
      final dateStr = (map['date'] as String?) ?? '';
      entries.add(_PrScanEntry(key: key, dateStr: dateStr, map: map));
    }

    if (entries.isEmpty) return;

    // Sort chronologically. Ties use created_at as a secondary key.
    entries.sort((a, b) {
      final d = a.dateStr.compareTo(b.dateStr);
      if (d != 0) return d;
      final aC = (a.map['created_at'] as String?) ?? '';
      final bC = (b.map['created_at'] as String?) ?? '';
      return aC.compareTo(bC);
    });

    double runningMaxWeight = 0;
    int runningMaxReps = 0;
    int runningMaxDuration = 0;
    double runningMaxDistance = 0;

    for (final e in entries) {
      final loggingType = (e.map['logging_type'] as String?) ?? 'weight_reps';
      final weight = (e.map['weight_kg'] as num?)?.toDouble() ?? 0;
      final reps = (e.map['reps_completed'] as num?)?.toInt() ?? 0;
      final duration = (e.map['duration_seconds'] as num?)?.toInt() ?? 0;
      final distance = (e.map['distance_km'] as num?)?.toDouble() ?? 0;

      bool isPr = false;
      switch (loggingType) {
        case 'weight_reps':
        case 'weighted_bodyweight':
          if (weight > runningMaxWeight && runningMaxWeight > 0) isPr = true;
          if (weight > runningMaxWeight) runningMaxWeight = weight;
          break;
        case 'bodyweight_reps':
          if (reps > runningMaxReps && runningMaxReps > 0) isPr = true;
          if (reps > runningMaxReps) runningMaxReps = reps;
          break;
        case 'timed':
          if (duration > runningMaxDuration && runningMaxDuration > 0) {
            isPr = true;
          }
          if (duration > runningMaxDuration) runningMaxDuration = duration;
          break;
        case 'cardio':
        case 'distance':
          if (distance > runningMaxDistance && runningMaxDistance > 0) {
            isPr = true;
          }
          if (distance > runningMaxDistance) runningMaxDistance = distance;
          break;
      }

      if (e.map['is_pr'] != isPr) {
        e.map['is_pr'] = isPr;
        box.put(e.key, e.map);
      }
    }
  }

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
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 1),
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
    final dateLabel =
        '${widget.date.day.toString().padLeft(2, '0')}/${widget.date.month.toString().padLeft(2, '0')}/${widget.date.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EDIT WORKOUT',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                color: AppColors.textSecondary, size: 20),
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
              color: AppColors.textSecondary.withValues(alpha: 0.4), size: 36),
          const SizedBox(height: 12),
          Text(
            'No exercise logs for this day',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditRow(_ExerciseEditRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.exerciseName,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          _buildFieldsForLoggingType(row),
        ],
      ),
    );
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
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
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
      style: GoogleFonts.getFont(
        'DM Sans',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        filled: true,
        fillColor: AppColors.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: AppColors.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: AppColors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
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
            child: GestureDetector(
              onTap: _saving ? null : () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.input,
                  borderRadius: BorderRadius.circular(100),
                  border:
                      Border.all(color: AppColors.border, width: 1),
                ),
                child: Center(
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: (_saving || _rows.isEmpty) ? null : _save,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: (_saving || _rows.isEmpty)
                      ? AppColors.accent.withValues(alpha: 0.4)
                      : AppColors.accent,
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: (_saving || _rows.isEmpty)
                      ? null
                      : [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: Center(
                  child: _saving
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          'SAVE CHANGES',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carries the original log id + loggingType + controllers for one exlog row.
class _ExerciseEditRow {
  final String logId;
  final String exerciseName;
  final String loggingType;

  final TextEditingController setsCtrl;
  final TextEditingController repsCtrl;
  final TextEditingController weightCtrl;
  final TextEditingController durationCtrl;
  final TextEditingController distanceCtrl;

  _ExerciseEditRow._({
    required this.logId,
    required this.exerciseName,
    required this.loggingType,
    required this.setsCtrl,
    required this.repsCtrl,
    required this.weightCtrl,
    required this.durationCtrl,
    required this.distanceCtrl,
  });

  factory _ExerciseEditRow.fromLog(String logId, Map<String, dynamic> log) {
    final name = (log['exercise_name'] as String?) ?? 'Exercise';
    final type = (log['logging_type'] as String?) ?? 'weight_reps';
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
    setsCtrl.dispose();
    repsCtrl.dispose();
    weightCtrl.dispose();
    durationCtrl.dispose();
    distanceCtrl.dispose();
  }
}

class _PrScanEntry {
  final String key;
  final String dateStr;
  final Map<String, dynamic> map;
  _PrScanEntry({required this.key, required this.dateStr, required this.map});
}
