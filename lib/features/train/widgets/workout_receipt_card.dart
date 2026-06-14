import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';
import 'package:icanbefitter/shared/widgets/shareable_card.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/train_provider.dart';
import '../services/quote_picker.dart';

// ── Category-specific taglines ───────────────────────────────────
const _taglinesPull = <String>[
  'Back wider than your comfort zone.',
  'Pulled more weight than your excuses.',
  'Lats loading... rows complete.',
  'Back day done. Posture improved by 1%.',
  'If rowing was easy, they\'d call it sitting.',
  'Deadlifts hit. Grip strength secured.',
  'The bar came up. So did you.',
  'Wide back energy activated.',
];

const _taglinesPush = <String>[
  'Chest pressed. Triceps fired. Mission complete.',
  'Push day: shoulders, ego, and reps — all up.',
  'Bench done. Pressing on.',
  'Pressed more than yesterday\'s bad decisions.',
  'Shoulders like boulders. Almost.',
  'OHP? Done. Respect? Earned.',
  'Chest day energy. Arm day regrets.',
  'Push it. Then push it some more.',
];

const _taglinesLegs = <String>[
  'Legs? Destroyed. Ego? Inflated.',
  'Squats done. Stairs now optional.',
  'Skipping leg day? Couldn\'t be me. (Today.)',
  'Ground shook. Quads spoke.',
  'Deadlift + Squat combo. The classic.',
  'Legs trained. Walking tomorrow: unlikely.',
  'Don\'t skip legs. You didn\'t.',
  'The squat rack was afraid of me today.',
];

const _taglinesCore = <String>[
  'Core locked in. Spine approved.',
  'Six-pack in progress. Beer not included.',
  'Abs worked. Excuses destroyed.',
  'Planked longer than my attention span.',
  'Core strong. Everything else negotiable.',
  'Crunched the numbers. And my abs.',
];

const _taglinesCardio = <String>[
  'Cardio done. Dignity optional.',
  'Ran from nothing. Felt great.',
  'Heart rate elevated. Life improved.',
  'Sweat is just fat crying. You made a lot cry today.',
  'Calories burned > Excuses made.',
  'Distance covered. Goals closer.',
];

const _taglinesGeneric = <String>[
  'Muscles confused. Gains secured.',
  'Gym done. Personality still under construction.',
  'Another day of being better than yesterday\'s lazy version.',
  'My therapist said lift heavy. So here we are.',
  'The only drama I need is in my set count.',
  'Protein shake incoming in 3... 2... 1...',
  'Not bad for someone who almost skipped today.',
  'Built different. Also built sore.',
  'Your workout is my warm-up. (Just kidding. I\'m dying.)',
  'Zero missed reps. Infinite missed calls.',
  'Did I PR? Maybe. Am I sore? Definitely.',
  'Coach said one more set. That was four sets ago.',
  'Crushed it like a protein bar wrapper.',
  'Rest days are for people without goals. (Jk rest is important.)',
  'One step closer to looking like my profile picture.',
  'Workout complete. Nap pending.',
  'Discipline hit. Brain still buffering.',
];

/// Deterministic tagline picker — same (exercises, workoutName, seed) always
/// returns the same tagline so the post-completion card and the "View Card"
/// sheet don't drift. Category is derived from the workout's EXERCISES (shared
/// with the async QuotePicker path via `QuotePicker.categoryForExercises`), so
/// a custom-named workout still gets a matching tagline (Unit 3 obs 2).
String _pickTagline(List<String> exerciseNames, String workoutName, int seed) {
  final rng = Random(seed);
  final category =
      QuotePicker.categoryForExercises(exerciseNames, workoutName);
  switch (category) {
    case 'pull':
      return _taglinesPull[rng.nextInt(_taglinesPull.length)];
    case 'push':
      return _taglinesPush[rng.nextInt(_taglinesPush.length)];
    case 'legs':
      return _taglinesLegs[rng.nextInt(_taglinesLegs.length)];
    case 'core':
      return _taglinesCore[rng.nextInt(_taglinesCore.length)];
    case 'cardio':
      return _taglinesCardio[rng.nextInt(_taglinesCardio.length)];
    default:
      // full_body / arms / general → local generic pool (the async JSON path
      // carries dedicated full_body/arms quotes; this sync fallback is brief).
      return _taglinesGeneric[rng.nextInt(_taglinesGeneric.length)];
  }
}

/// Data required to render a Workout Receipt card.
///
/// Single source of truth: all three views (post-completion card, Home
/// "View Card", Train expanded view) read from [fromExerciseLogs] so the
/// same workout always renders identically. [fromActiveWorkout] is a thin
/// wrapper that tries [fromExerciseLogs] first (since logs are already in
/// Hive by the time the post-completion card renders) and falls back to
/// in-memory aggregation only if the read path returns nothing.
class WorkoutReceiptData {
  final DateTime date;
  final String workoutName;
  final int phase;
  final List<ReceiptExercise> exercises;
  final double totalVolumeKg;
  final int totalSets;
  final List<String> prs;
  final int streakWeeks;
  final String tagline; // deterministic — same workout always renders same line

  /// APK Test #12 / Task A-5 — session sequence label.
  ///
  /// `null` for single-session days (the common case) — header renders
  /// `workoutName` clean. When > 1 distinct `workout_log_id`s exist for
  /// the IST date, this is "SESSION N" (1-indexed by chronological order
  /// of the session's first exercise log) and the header renders
  /// `workoutName · SESSION N`.
  ///
  /// Computed by [fromExerciseLogs] when a `workoutLogId` is supplied;
  /// pure-Hive [fromActiveWorkout] doesn't compute this (in-memory builds
  /// are always single-session).
  final String? sessionLabel;

  const WorkoutReceiptData({
    required this.date,
    required this.workoutName,
    this.phase = 1,
    required this.exercises,
    required this.totalVolumeKg,
    required this.totalSets,
    this.prs = const [],
    this.streakWeeks = 0,
    required this.tagline,
    this.sessionLabel,
  });

  int get totalExercises => exercises.length;

  /// Public seed for quote/tagline selection — same workout always produces
  /// the same value so [WorkoutReceiptCard] and [QuotePicker] stay in sync.
  int get taglineSeed =>
      _taglineSeed(date, workoutName, totalVolumeKg, totalSets);

  /// Deterministic tagline seed — same (date, name, volume, sets) produces
  /// the same tagline across every render.
  static int _taglineSeed(
      DateTime date, String name, double volume, int totalSets) {
    return date.year * 10000 +
        date.month * 100 +
        date.day +
        volume.round() +
        totalSets * 31 +
        name.hashCode;
  }

  /// Build from ActiveWorkoutData — pure in-memory aggregation using the
  /// exact same per-logging-type rules as [fromExerciseLogs] so the two
  /// paths produce identical outputs. No Hive reads (tests don't init Hive).
  factory WorkoutReceiptData.fromActiveWorkout(ActiveWorkoutData data,
      {int? phase}) {
    final workoutDate = data.workoutDay?.date ?? DateTime.now();
    double totalVolume = 0;
    int totalSets = 0;
    final seen = <String, ReceiptExercise>{};

    for (int exIdx = 0; exIdx < data.exercises.length; exIdx++) {
      final ex = data.exercises[exIdx];

      double bestWeight = 0;
      int totalReps = 0;
      int totalDuration = 0;
      double totalDistance = 0;
      int completedSets = 0;
      // APK Test #12.6 — capture per-set breakdown so the post-completion
      // receipt renders one chip per set (matching the Train expanded view
      // and the home/calendar "View Card" path which read via
      // [fromExerciseLogs]). Without this, [WardSetChips] saw an empty
      // perSetBreakdown and fell back to a single summary chip — founder
      // observation 2026-05-07 ("[3 sets · 30 reps · 80 kg]" rendered
      // instead of three "[80 kg × 10 reps]" chips).
      final perSetBreakdown = <ReceiptSet>[];

      // Scan for dynamically added sets beyond the template's prescribed count.
      int maxSet = int.tryParse(ex.sets) ?? 3;
      for (final key in data.checkedSets.keys) {
        if (key.startsWith('$exIdx-')) {
          final s = int.tryParse(key.split('-').last) ?? 0;
          if (s + 1 > maxSet) maxSet = s + 1;
        }
      }

      for (int s = 0; s < maxSet; s++) {
        final key = '$exIdx-$s';
        if (!data.checkedSets.containsKey(key)) continue;
        if (data.warmUpSets.containsKey(key)) continue; // warm-ups excluded
        completedSets++;
        final vals = data.setInputValues[key];
        final reps = vals?.reps ?? 0;
        final weight = vals?.weight ?? 0.0;
        final dur = vals?.durationSeconds ?? 0;
        final dist = vals?.distanceKm ?? 0.0;
        totalReps += reps;
        totalDuration += dur;
        totalDistance += dist;
        if (weight > bestWeight) bestWeight = weight;
        totalVolume += reps * weight;
        perSetBreakdown.add(ReceiptSet(
          weightKg: weight > 0 ? weight : null,
          reps: reps > 0 ? reps : null,
          durationSeconds: dur > 0 ? dur : null,
        ));
      }

      if (completedSets == 0) continue;
      totalSets += completedSets;

      final entry = ReceiptExercise(
        name: ex.name,
        loggingType: ex.loggingType,
        sets: completedSets,
        totalReps: totalReps,
        totalDurationSeconds: totalDuration,
        totalDistanceKm: totalDistance,
        maxWeightKg: bestWeight,
        perSetBreakdown: perSetBreakdown,
      );

      final key = ex.name.toLowerCase().trim();
      final existing = seen[key];
      seen[key] = existing == null ? entry : existing.mergedWith(entry);
    }

    final workoutName = data.workoutDay?.name ?? 'WORKOUT';
    final exerciseList = seen.values.toList();
    return WorkoutReceiptData(
      date: workoutDate,
      workoutName: workoutName,
      phase: phase ?? 1,
      exercises: exerciseList,
      totalVolumeKg: totalVolume,
      totalSets: totalSets,
      prs: data.detectedPRs,
      tagline: _pickTagline(
        exerciseList.map((e) => e.name).toList(),
        workoutName,
        _taglineSeed(workoutDate, workoutName, totalVolume, totalSets),
      ),
    );
  }

  /// Reconstruct receipt data from Hive exercise logs for a given date.
  /// Returns null if no exercise logs are found for that date.
  ///
  /// THIS IS THE CANONICAL SOURCE OF TRUTH. All receipt views read from here.
  /// Build receipt data from exercise logs.
  ///
  /// If [workoutLogId] is provided (APK Test #12 / Task A-3), filters
  /// the date's index to logs whose `workout_log_id` matches — so a day
  /// with multiple workout sessions yields a per-session receipt.
  /// When absent, legacy behavior: aggregates ALL exercises logged that
  /// IST date (matches pre-Test-#12 receipts).
  static WorkoutReceiptData? fromExerciseLogs(
    DateTime date, {
    String? workoutLogId,
    int? phase,
  }) {
    final Box wb = HiveService.instance.workoutBox;
    final dateKey = formatDateKey(date);

    final indexKey = 'exercise_log_index_$dateKey';
    final indexRaw = wb.get(indexKey);
    // APK Test #16.1 / Agent A — defence-in-depth fallback. Before the
    // rogue-restore-writer fix, `_restoreExerciseLogs` wrote rows under
    // a UTC-date index key while the receipt reader looked up an
    // IST-date index. Symptom: "View Card does nothing" for the founder
    // on May 14 even though 26+ exlog_* rows existed in workoutBox.
    // When the index is missing, scan workoutBox for any `exlog_*` row
    // whose stored `date` matches `dateKey` (IST) and synthesise the
    // id list on the fly. The migrator v8 normally rebuilds the index;
    // this fallback covers the window between rogue-write and
    // next-launch migration.
    List logIds;
    if (indexRaw is List && indexRaw.isNotEmpty) {
      logIds = indexRaw;
    } else {
      final synthesized = <String>[];
      for (final k in wb.keys) {
        final ks = k.toString();
        if (!ks.startsWith('exlog_')) continue;
        final v = wb.get(k);
        if (v is! Map) continue;
        if (v['date'] == dateKey) synthesized.add(ks);
      }
      if (synthesized.isEmpty) return null;
      logIds = synthesized;
    }

    double totalVolume = 0;
    int totalSets = 0;
    final prs = <String>[];
    final seen = <String, ReceiptExercise>{};

    for (final logId in logIds) {
      final log = wb.get(logId);
      if (log == null || log is! Map) continue;

      // APK Test #12 / Task A-3 — workout_log_id scoping. If caller
      // supplied a workoutLogId AND this row has one, skip rows that
      // belong to a different session. Rows without workout_log_id
      // (legacy data) always pass through (best-effort backward compat).
      if (workoutLogId != null) {
        final rowWid = log['workout_log_id'] as String?;
        if (rowWid != null && rowWid != workoutLogId) continue;
      }

      final name = log['exercise_name'] as String? ?? 'Unknown';
      // APK Test #12.4 / Task #1b — reverted the Test #12.2 defensive
      // logging_type re-inference. The migrator (v2) now fixes the
      // data + type pair correctly at splash time; the reader's job
      // is just to render what's stored. The defensive correction
      // mis-flipped library-known timed exercises (e.g. Jump Rope)
      // when their data had been corrupted by pre-Test-#12 swap drift.
      final loggingType = log['logging_type'] as String? ?? 'weight_reps';
      final weightKg = (log['weight_kg'] as num?)?.toDouble() ?? 0.0;
      final reps = (log['reps_completed'] as num?)?.toInt() ?? 0;
      // Theme A · Test #8 — WorkoutWriteService writes `set_number`; older
      // logs use `sets_completed`. Read new key first, fall back to legacy.
      // APK Test #12.1 — take the MAX of both rather than first-non-null.
      // APK Test #12.2 — extend MAX with the array length too (sets[]
      // OR sets_detail[]). Cloud audit revealed local rows where ALL of
      // (set_number=0, sets_completed=0) but the per-set arrays are
      // populated. Cloud projection prefers array length, so cloud
      // shipped set_number=4 to the server while the receipt still
      // rendered "0 sets". Founder observation 2026-05-06.
      final setNum = (log['set_number'] as num?)?.toInt() ?? 0;
      final setsCompletedField = (log['sets_completed'] as num?)?.toInt() ?? 0;
      final setsArrRaw = log['sets'];
      final setsArrLen = setsArrRaw is List ? setsArrRaw.length : 0;
      final setsDetailRaw = log['sets_detail'];
      final setsDetailLen = setsDetailRaw is List ? setsDetailRaw.length : 0;
      final sets = [setNum, setsCompletedField, setsArrLen, setsDetailLen]
          .reduce((a, b) => a > b ? a : b);
      // Drift-fix 2026-05-24 / T6 — `WorkoutWriteService` does NOT emit
      // a top-level `duration_seconds` on exlog rows. The receipt's
      // semantic for "total time held" is the SUM across per-set
      // entries, which gets computed below as `perSetDurationSum`.
      // The pre-fix top-level read was dead — always 0 for modern rows,
      // so the `duration > 0 ? duration : perSetDurationSum` ternary
      // (line ~417 below) silently always took the sum branch anyway.
      // Setting `duration = 0` here keeps the sum path canonical and
      // removes the dead read without changing receipt rendering.
      const int duration = 0;
      final distance = (log['distance_km'] as num?)?.toDouble() ?? 0.0;
      final isPr = log['is_pr'] as bool? ?? false;

      // F13 · Volume math — prefer exact sum of per-set volumes over the
      // misleading `max_weight × total_reps` fallback. Priority order:
      //   1. `sets_detail` list (F4 per-set restore) — sum(weight × reps).
      //   2. `volume_kg` stored directly at log time (new logs since v4).
      //   3. Approximation `weight × reps` — only for legacy pre-v4 logs.
      double exerciseVolume;
      // Theme A · Test #8 — WorkoutWriteService writes `sets`; older logs use
      // `sets_detail`. Read new key first, fall back to legacy.
      final setsDetail = log['sets'] ?? log['sets_detail'];
      final perSetBreakdown = <ReceiptSet>[];
      int perSetDurationSum = 0;
      if (setsDetail is List && setsDetail.isNotEmpty) {
        double sum = 0;
        for (final s in setsDetail) {
          if (s is! Map) continue;
          final w = (s['weight_kg'] as num?)?.toDouble() ?? 0;
          final r = (s['reps'] as num?)?.toInt() ?? 0;
          // Theme A · Test #8 — WorkoutWriteService writes per-set
          // `duration_sec`; legacy entries used `duration_seconds`.
          final d = (s['duration_sec'] as num?)?.toInt()
              ?? (s['duration_seconds'] as num?)?.toInt()
              ?? 0;
          sum += w * r;
          perSetDurationSum += d;
          perSetBreakdown.add(ReceiptSet(
            weightKg: w > 0 ? w : null,
            reps: r > 0 ? r : null,
            durationSeconds: d > 0 ? d : null,
          ));
        }
        exerciseVolume = sum;
      } else {
        final storedVolume = (log['volume_kg'] as num?)?.toDouble();
        exerciseVolume = storedVolume ?? (weightKg * reps);
      }
      // Theme A · Test #8 — WorkoutWriteService doesn't store a top-level
      // `duration_seconds` aggregate. Sum from per-set breakdown when the
      // top-level field is missing/zero.
      final effectiveDuration = duration > 0 ? duration : perSetDurationSum;

      if (isPr) {
        if (weightKg > 0) {
          prs.add('$name — ${weightKg.toStringAsFixed(0)}kg');
        } else if (reps > 0) {
          prs.add('$name — $reps reps');
        } else {
          prs.add(name);
        }
      }

      totalVolume += exerciseVolume;
      totalSets += sets;

      final key = name.toLowerCase().trim();
      final entry = ReceiptExercise(
        name: name,
        loggingType: loggingType,
        sets: sets,
        totalReps: reps,
        totalDurationSeconds: effectiveDuration,
        totalDistanceKm: distance,
        maxWeightKg: weightKg,
        perSetBreakdown: perSetBreakdown,
      );
      final existing = seen[key];
      seen[key] = existing == null ? entry : existing.mergedWith(entry);
    }

    if (seen.isEmpty) return null;

    // Read workout_log for workout name.
    String workoutName = 'WORKOUT';
    final allKeys = wb.keys.toList();
    for (final k in allKeys) {
      final val = wb.get(k);
      if (val is Map &&
          val['type'] == 'workout_log' &&
          val['date'] == dateKey) {
        workoutName = (val['workout_name'] as String?) ?? 'WORKOUT';
        break;
      }
    }

    // APK Test #12 / Task A-5 — session sequence. Compute only when
    // caller supplied a workoutLogId AND the date has >1 distinct
    // workout_log_ids (i.e. multi-session day).
    String? sessionLabel;
    if (workoutLogId != null) {
      final distinctIds = <String>{};
      final earliestByWid = <String, int>{};
      for (final id in logIds) {
        final row = wb.get(id);
        if (row is! Map) continue;
        final wid = row['workout_log_id'] as String?;
        if (wid == null) continue;
        distinctIds.add(wid);
        final ts = (row['updated_at_ms'] as num?)?.toInt() ??
            (row['logged_at_ms'] as num?)?.toInt() ??
            0;
        final cur = earliestByWid[wid];
        if (cur == null || ts < cur) earliestByWid[wid] = ts;
      }
      if (distinctIds.length > 1) {
        final ordered = distinctIds.toList()
          ..sort((a, b) =>
              (earliestByWid[a] ?? 0).compareTo(earliestByWid[b] ?? 0));
        final idx = ordered.indexOf(workoutLogId);
        if (idx >= 0) sessionLabel = 'SESSION ${idx + 1}';
      }
    }

    final exerciseList = seen.values.toList();
    return WorkoutReceiptData(
      date: date,
      workoutName: workoutName,
      // ignore: deprecated_member_use — singleton read until full provider migration
      phase: phase ?? WorkoutScheduleReadService.instance.phaseForDate(date),
      exercises: exerciseList,
      totalVolumeKg: totalVolume,
      totalSets: totalSets,
      prs: prs,
      sessionLabel: sessionLabel,
      tagline: _pickTagline(
        exerciseList.map((e) => e.name).toList(),
        workoutName,
        _taglineSeed(date, workoutName, totalVolume, totalSets),
      ),
    );
  }
}

/// One completed set within an exercise. Used for the F13 expandable
/// per-set breakdown on the receipt card.
class ReceiptSet {
  final double? weightKg;
  final int? reps;
  final int? durationSeconds;

  const ReceiptSet({this.weightKg, this.reps, this.durationSeconds});
}

/// Per-exercise aggregated summary. Fields are already totals across all
/// completed sets (reps, duration, distance) or the best across sets (weight).
class ReceiptExercise {
  final String name;
  final String loggingType;
  final int sets; // total completed sets
  final int totalReps; // summed across sets (0 for timed/cardio-only)
  final int totalDurationSeconds; // summed (0 for rep-only)
  final double totalDistanceKm; // summed (0 for non-cardio)
  final double maxWeightKg; // best weight across sets (0 for bodyweight)

  /// F13 · Per-set detail for the tap-to-expand breakdown on the receipt.
  /// Empty for legacy logs that predate per-set persistence.
  final List<ReceiptSet> perSetBreakdown;

  const ReceiptExercise({
    required this.name,
    required this.loggingType,
    required this.sets,
    this.totalReps = 0,
    this.totalDurationSeconds = 0,
    this.totalDistanceKm = 0,
    this.maxWeightKg = 0,
    this.perSetBreakdown = const [],
  });

  /// Merge this exercise with another of the same name (supersets etc.).
  /// Sets, reps, duration, distance add; max weight takes the best.
  ReceiptExercise mergedWith(ReceiptExercise other) {
    return ReceiptExercise(
      name: name,
      loggingType: loggingType,
      sets: sets + other.sets,
      totalReps: totalReps + other.totalReps,
      totalDurationSeconds: totalDurationSeconds + other.totalDurationSeconds,
      totalDistanceKm: totalDistanceKm + other.totalDistanceKm,
      maxWeightKg:
          maxWeightKg > other.maxWeightKg ? maxWeightKg : other.maxWeightKg,
      perSetBreakdown: [...perSetBreakdown, ...other.perSetBreakdown],
    );
  }
}

/// Workout Receipt Card — rendered inside a ShareableCard wrapper.
///
/// Tier: FREE for all users.
class WorkoutReceiptCard extends StatelessWidget {
  final WorkoutReceiptData data;
  final GlobalKey repaintKey;

  const WorkoutReceiptCard({
    super.key,
    required this.data,
    required this.repaintKey,
  });

  @override
  Widget build(BuildContext context) {
    final tagline = data.tagline;

    return ShareableCard(
      repaintKey: repaintKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Date row
            _buildDateRow(),
            const SizedBox(height: 10),

            // Workout title
            _buildTitle(),
            const SizedBox(height: 14),

            // Exercise list
            ..._buildExerciseRows(),
            const SizedBox(height: 12),

            // Thin gold rule — letterhead closer.
            const WardRule(gold: true, margin: EdgeInsets.zero),
            const SizedBox(height: 12),

            // Summary row
            _buildSummaryRow(),

            // PRs
            if (data.prs.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildPRSection(),
            ],

            // Streak badge
            if (data.streakWeeks > 0) ...[
              const SizedBox(height: 10),
              _buildStreakBadge(),
            ],

            // Category-tagged quote (deterministic per workout seed)
            const SizedBox(height: 14),
            FutureBuilder<String>(
              future: QuotePicker.pickForCategory(
                category: QuotePicker.categoryForExercises(
                    data.exercises.map((e) => e.name).toList(),
                    data.workoutName),
                seed: data.taglineSeed,
              ),
              builder: (context, snapshot) {
                // While loading, fall back to the pre-computed tagline so
                // there is never a flash of empty space.
                final quote = (snapshot.hasData && snapshot.data!.isNotEmpty)
                    ? snapshot.data!
                    : tagline;
                return Text(
                  quote,
                  style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w400, fontStyle: FontStyle.italic, color: AppColors.textMute),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRow() {
    const dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const monthNames = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    final dayName = dayNames[data.date.weekday - 1];
    final monthName = monthNames[data.date.month - 1];

    // JB Mono eyebrow in accent gold — Wardroom letterhead cadence.
    return Text(
      '$dayName \u00b7 ${data.date.day} $monthName ${data.date.year}',
      style: AppTypography.mono.copyWith(
        color: AppColors.accent,
        letterSpacing: 2.4,
      ),
    );
  }

  Widget _buildTitle() {
    // Fraunces display for the workout name, Mono meta for the phase code.
    // APK Test #12 / Task A-5 — multi-session days append "· SESSION N"
    // to the meta line so receipts from the same date are distinguishable.
    final phaseLine = data.sessionLabel != null
        ? 'PHASE ${data.phase} · ${data.sessionLabel}'
        : 'PHASE ${data.phase}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          data.workoutName,
          style: AppTypography.h2.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          phaseLine,
          style: AppTypography.monoXs.copyWith(
            color: AppColors.textMute,
            letterSpacing: 2.0,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildExerciseRows() {
    return data.exercises.map((ex) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Exercise name + total sets count header
            Row(
              children: [
                Expanded(
                  child: Text(
                    ex.name.toUpperCase(),
                    style: AppTypography.mono.copyWith(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${ex.sets} set${ex.sets == 1 ? '' : 's'}',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textDim,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Per-set chips — shared WardSetChips primitive (Theme E-3).
            _buildSetChips(ex),
          ],
        ),
      );
    }).toList();
  }

  /// Build set chips for one exercise. Uses per-set breakdown when available;
  /// gracefully degrades to a single cumulative chip for legacy logs.
  ///
  /// APK Test #12 / Theme E-3 — delegates to the shared [WardSetChips]
  /// primitive (also used by Train screen expanded view) so receipt and
  /// train surfaces render set chips identically.
  Widget _buildSetChips(ReceiptExercise ex) {
    final ward = ex.perSetBreakdown
        .map((s) => WardSetChip(
              weightKg: s.weightKg,
              reps: s.reps,
              durationSeconds: s.durationSeconds,
            ))
        .toList();
    return WardSetChips(
      loggingType: ex.loggingType,
      perSetBreakdown: ward,
      fallbackLabel: ward.isEmpty ? _exerciseDetail(ex) : null,
    );
  }

  /// Format a duration in seconds as e.g. "3s", "45s", "2m 0s", "10m".
  static String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    if (secs == 0) return '${mins}m';
    return '${mins}m ${secs}s';
  }

  /// Build the per-exercise summary string. Rules per logging type are the
  /// single source of truth — the same logic backs every view of a workout.
  String _exerciseDetail(ReceiptExercise ex) {
    switch (ex.loggingType) {
      case 'bodyweight_reps':
        return '${ex.sets} sets \u00b7 ${ex.totalReps} reps';
      case 'weighted_bodyweight':
        return '${ex.sets} sets \u00b7 ${ex.totalReps} reps \u00b7 +${ex.maxWeightKg.toStringAsFixed(0)}kg';
      case 'timed':
        return '${ex.sets} sets \u00b7 ${_formatDuration(ex.totalDurationSeconds)}';
      case 'cardio':
        final mins = ex.totalDurationSeconds ~/ 60;
        return '$mins min \u00b7 ${ex.totalDistanceKm.toStringAsFixed(1)} km';
      case 'distance':
        final dist = '${ex.totalDistanceKm.toStringAsFixed(1)} km';
        return ex.maxWeightKg > 0
            ? '$dist \u00b7 ${ex.maxWeightKg.toStringAsFixed(0)}kg'
            : dist;
      default: // weight_reps
        if (ex.maxWeightKg > 0) {
          return '${ex.sets} sets \u00b7 ${ex.totalReps} reps \u00b7 ${ex.maxWeightKg.toStringAsFixed(0)}kg';
        }
        return '${ex.sets} sets \u00b7 ${ex.totalReps} reps';
    }
  }

  Widget _buildSummaryRow() {
    // "22 sets · 6 exercises" label replaces duration
    final setsExLabel = '${data.totalSets} sets \u00b7 ${data.totalExercises} exercises';

    return Row(
      children: [
        _summaryChip(
          '${data.totalVolumeKg.toStringAsFixed(0)} kg',
          'VOLUME',
        ),
        const SizedBox(width: 12),
        _summaryChip(setsExLabel, 'WORKOUT'),
      ],
    );
  }

  Widget _summaryChip(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.bgRaise,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(color: AppColors.line2, width: 1),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPRSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.military_tech, color: AppColors.accent, size: 14),
              const SizedBox(width: 6),
              Text(
                'PERSONAL RECORDS',
                style: AppTypography.mono.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 2.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...data.prs.map((pr) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  pr,
                  style: AppTypography.body.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildStreakBadge() {
    // Sharp Wardroom chip — no more pill.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department,
              color: AppColors.accent, size: 13),
          const SizedBox(width: 6),
          Text(
            '${data.streakWeeks} WEEK STREAK',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.accent,
              letterSpacing: 2.0,
            ),
          ),
        ],
      ),
    );
  }
}

// APK Test #12 / Theme E-3 — `_SetChip` + `_RawLabelSet` removed.
// Per-set chip rendering lives in `lib/shared/widgets/wardroom/
// ward_set_chips.dart` (WardSetChips) — shared between receipt and
// Train expanded view. The receipt's `_buildSetChips(ex)` now wraps
// that primitive directly.
