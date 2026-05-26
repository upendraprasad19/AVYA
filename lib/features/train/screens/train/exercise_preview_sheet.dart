part of 'screen.dart';

extension _ExercisePreviewSheet on _TrainScreenState {
  // ── Exercise Preview Bottom Sheet ────────────────────────────

  void _showExercisePreviewSheet(BuildContext context, WorkoutDayData day) {
    // Format the date label
    String dateLabel = '';
    if (day.date != null) {
      const dayNames = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
      ];
      const monthNames = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      dateLabel =
          '${dayNames[day.date!.weekday - 1]}, ${monthNames[day.date!.month - 1]} ${day.date!.day}';
    }

    // Load actual exercise logs if this day is completed
    final actualLogs = day.isDone && day.date != null
        ? WorkoutRepository.instance.getExerciseLogsForDate(day.date!)
        : <Map<String, dynamic>>[];
    final hasActualLogs = actualLogs.isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.9,
          builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Title row: workout name + completed badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      day.isDone
                          ? '${day.name.toUpperCase()} ✓'
                          : day.name.toUpperCase(),
                      style: AppTypography.mono.copyWith(
                        fontSize: 13,
                        color: day.isDone
                            ? AppColors.ok
                            : AppColors.textPrimary,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ),
                ],
              ),
              if (dateLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Section label
              Text(
                hasActualLogs ? 'LOGGED EXERCISES' : 'PLANNED EXERCISES',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),

              // Exercise list: actual logs if available, else planned
              Flexible(
                child: ListView(
                  controller: scrollCtrl,
                  shrinkWrap: true,
                  children: hasActualLogs
                      ? actualLogs.map((log) {
                          final name = log['exercise_name'] as String? ?? 'Exercise';
                          // Theme A · Test #8 — WriteService writes
                          // `set_number`; legacy entries used `sets_completed`.
                          // APK Test #12.1 — read MAX of both rather than
                          // first-non-null. APK Test #12.2 — extend with
                          // 3rd + 4th fallback to the array length itself.
                          // Cloud audit 2026-05-06 revealed many local rows
                          // have ALL of (set_number=0, sets_completed=0)
                          // but a populated `sets[]` or `sets_detail[]`
                          // array. The cloud projection prefers the array
                          // length, so cloud is correct (set_number=4)
                          // while local readers showed "0 sets · 26 reps".
                          final setNum = (log['set_number'] as num?)?.toInt() ?? 0;
                          final setsCompleted = (log['sets_completed'] as num?)?.toInt() ?? 0;
                          final setsArr = log['sets'];
                          final setsArrLen = setsArr is List ? setsArr.length : 0;
                          final setsDetail = log['sets_detail'];
                          final setsDetailLen = setsDetail is List ? setsDetail.length : 0;
                          final sets = [setNum, setsCompleted, setsArrLen, setsDetailLen]
                              .reduce((a, b) => a > b ? a : b);
                          final reps = (log['reps_completed'] as num?)?.toInt() ?? 0;
                          final weight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
                          final duration = WorkoutReadService.bestPerSetDuration(log);
                          // APK Test #12.4 / Task #1b — reverted defensive
                          // re-inference. Migrator v2 fixes the type+data
                          // pair correctly at splash; reader trusts stored
                          // logging_type now.
                          final loggingType =
                              log['logging_type'] as String? ?? 'weight_reps';

                          // APK Test #12 / Theme E-2 — Train expanded view
                          // adopts per-set chip rendering (the same widget
                          // the receipt uses). Pre-fix this screen showed a
                          // single summary line ("4 sets · 33 reps · 110 kg")
                          // hiding actual progression. WardSetChips renders
                          // every set's weight/reps/duration as its own chip.
                          final perSet = <WardSetChip>[];
                          // WriteService writes `sets`; legacy is `sets_detail`.
                          final rawSets = log['sets'] ?? log['sets_detail'];
                          if (rawSets is List) {
                            for (final s in rawSets) {
                              if (s is! Map) continue;
                              final w =
                                  (s['weight_kg'] as num?)?.toDouble();
                              final r = (s['reps'] as num?)?.toInt();
                              final d =
                                  (s['duration_sec'] as num?)?.toInt() ??
                                      (s['duration_seconds'] as num?)?.toInt();
                              final dist =
                                  (s['distance_km'] as num?)?.toDouble();
                              perSet.add(WardSetChip(
                                weightKg: w,
                                reps: r,
                                durationSeconds: d,
                                distanceKm: dist,
                              ));
                            }
                          }

                          // Cumulative fallback when per-set absent (legacy).
                          String fallbackLabel;
                          if (loggingType == 'timed') {
                            final mins = duration ~/ 60;
                            final secs = duration % 60;
                            fallbackLabel = sets > 1
                                ? '$sets sets · ${mins > 0 ? '${mins}m ' : ''}${secs}s'
                                : '${mins > 0 ? '${mins}m ' : ''}${secs}s';
                          } else if (loggingType == 'cardio') {
                            final dist = (log['distance_km'] as num?)?.toDouble() ?? 0;
                            fallbackLabel =
                                '${duration ~/ 60} min · ${dist.toStringAsFixed(1)} km';
                          } else if (weight > 0) {
                            fallbackLabel =
                                '$sets sets · $reps reps · ${weight.toStringAsFixed(1)} kg';
                          } else {
                            fallbackLabel = '$sets sets · $reps reps';
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 1),
                                  child: Icon(Icons.check_circle,
                                      color: AppColors.ok, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: AppTypography.h3
                                                  .copyWith(fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            sets > 0
                                                ? '$sets ${sets == 1 ? "set" : "sets"}'
                                                : '',
                                            style: AppTypography.monoXs.copyWith(
                                              color: AppColors.textMute,
                                              letterSpacing: 1.0,
                                              fontSize: 9,
                                            ),
                                          ),
                                          if (log['is_pr'] == true) ...[
                                            const SizedBox(width: 6),
                                            const WardChip(
                                                label: 'PR',
                                                tone: WardChipTone.gold),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      WardSetChips(
                                        loggingType: loggingType,
                                        perSetBreakdown: perSet,
                                        fallbackLabel: fallbackLabel,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList()
                      : day.exercises.isEmpty
                          ? [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                child: Text(
                                  day.isDone
                                      ? 'Logged details not saved'
                                      : 'No exercises scheduled',
                                  style: AppTypography.bodySm
                                      .copyWith(color: AppColors.textDim),
                                ),
                              ),
                            ]
                          : [
                              // Warm-up section (Bug #15a: collapsed by default)
                              if (day.warmup.isNotEmpty) ...[
                                _CollapsibleExerciseSection(
                                  label: 'WARM-UP',
                                  color: AppColors.warn,
                                  exercises: day.warmup,
                                  buildRow: (ex) => _buildPreviewExerciseRow(
                                    ex, null, AppColors.warn,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildPreviewSectionLabel(
                                    'WORKOUT', AppColors.accent),
                              ],
                              // Main exercises (always expanded — focal content)
                              ...List.generate(day.exercises.length, (index) {
                                final ex = day.exercises[index];
                                return _buildPreviewExerciseRow(
                                  ex,
                                  index + 1,
                                  AppColors.accent,
                                );
                              }),
                              // Cool-down section (Bug #15a: collapsed by default)
                              if (day.cooldown.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _CollapsibleExerciseSection(
                                  label: 'COOL-DOWN',
                                  color: AppColors.info,
                                  exercises: day.cooldown,
                                  buildRow: (ex) => _buildPreviewExerciseRow(
                                    ex, null, AppColors.info,
                                  ),
                                ),
                              ],
                            ],
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  // ── Preview sheet helpers ────────────────────────────────────

  Widget _buildPreviewSectionLabel(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: AppTypography.mono.copyWith(
          color: color.withValues(alpha: 0.7),
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _buildPreviewExerciseRow(ExerciseData ex, int? number, Color color) {
    // Format detail based on logging type
    String detail;
    if (ex.loggingType == 'timed') {
      // ExerciseData.reps is now a clean numeric string for timed exercises
      // (set by _parseTimedDurationSecs in train_provider.dart). Defensive
      // fallback to 30s if upstream parsing somehow failed (Bug #16 guard).
      final raw = ex.reps.replaceAll(RegExp(r'[^0-9]'), '');
      final parsedSecs = int.tryParse(raw) ?? 0;
      final secs = parsedSecs > 0 ? parsedSecs : 30;
      if (secs >= 60) {
        final mins = secs ~/ 60;
        final remainder = secs % 60;
        detail = remainder == 0 ? '${mins}m' : '${mins}m ${remainder}s';
      } else {
        detail = '${secs}s';
      }
    } else {
      final restSecs = ex.rest.replaceAll('s', '');
      detail = '${ex.sets} sets · ${ex.reps} reps · ${restSecs}s rest';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (number != null)
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$number',
                style: AppTypography.monoXs.copyWith(
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
            )
          else
            Icon(
              Icons.circle,
              size: 6,
              color: color.withValues(alpha: 0.5),
            ),
          SizedBox(width: number != null ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ex.name,
                  style: AppTypography.h3.copyWith(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  ex.muscleLabel != null
                      ? '${ex.muscleLabel} · $detail'
                      : detail,
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textDim,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
