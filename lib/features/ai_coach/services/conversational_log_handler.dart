import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/body_measurement_sites.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/measurement_flags.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/train/providers/workout_surface_invalidation.dart';
import '../providers/ai_coach_provider.dart';

/// Routes AI-detected log actions to existing Riverpod providers.
///
/// Each action type maps to an existing write path:
/// - water → [WaterIntakeNotifier.addWater]
/// - weight → [WeightLogNotifier.logWeight]
/// - food → [FoodLogNotifier.logFood] (with fuzzy Hive search)
/// - sleep → [HealthWriteService.logSleep]
/// - measurement → [HealthWriteService.logMeasurement] (the bounds and the
///   0.1 cm rounding are enforced there; the chat parse already drops an
///   out-of-range value, so a writer refusal here means the two tiers disagree)
///
/// All writes are Hive-first (offline). Cross-screen invalidation happens
/// via the target providers themselves (fixed in A.0).
class ConversationalLogHandler {
  final WidgetRef ref;

  const ConversationalLogHandler(this.ref);

  /// Execute a pending log action. Returns true on success.
  Future<bool> executeAction(PendingLogAction action) async {
    try {
      switch (action.type) {
        case LogActionType.water:
          return await _logWater(action.data);
        case LogActionType.weight:
          return await _logWeight(action.data);
        case LogActionType.food:
          return await _logFood(action.data);
        case LogActionType.sleep:
          return await _logSleep(action.data);
        case LogActionType.measurement:
          return await _logMeasurement(action.data);
      }
    } catch (_) {
      return false;
    }
  }

  // ── Water ───────────────────────────────────────────────────────

  Future<bool> _logWater(Map<String, dynamic> data) async {
    final ml = (data['ml'] as num?)?.toInt();
    if (ml == null || ml <= 0 || ml > 5000) return false;
    await ref.read(waterIntakeProvider.notifier).addWater(ml);
    return true;
  }

  // ── Weight ──────────────────────────────────────────────────────

  // Bug w7r4c3 (APK Test #16.2) — await the awaitable WeightLogNotifier
  // and invalidate the reader providers AFTER the Hive put resolves so
  // the AI coach response reads the freshly-written value rather than
  // a stale snapshot from the prior rebuild tick. Mirrors the
  // WeightLogSheet._save fix.
  Future<bool> _logWeight(Map<String, dynamic> data) async {
    final kg = (data['weight_kg'] as num?)?.toDouble();
    if (kg == null || kg < 20 || kg > 300) return false;
    await ref.read(weightLogNotifierProvider.notifier).logWeight(kg);
    ref.invalidate(weightHistoryProvider);
    ref.invalidate(todayWeightLoggedProvider);
    return true;
  }

  // ── Food ────────────────────────────────────────────────────────

  Future<bool> _logFood(Map<String, dynamic> data) async {
    final foodName = data['food_name'] as String? ?? '';
    final mealType = _validateMealType(data['meal_type'] as String?);
    final quantityG = (data['quantity_g'] as num?)?.toDouble() ?? 100.0;

    if (foodName.isEmpty) return false;

    // Fuzzy search Hive foodBox (case-insensitive substring match)
    final matches = FoodRepository.instance.search(foodName, limit: 5);

    final Map<String, dynamic> foodMap;
    if (matches.isNotEmpty) {
      foodMap = matches.first; // best substring match from 5K database
    } else {
      // No match — create a minimal food map from AI calorie estimates.
      // Scale per-serving estimates back to per-100g so
      // FoodLogNotifier.logFood() calculates correctly.
      foodMap = _buildEstimatedFood(data, quantityG);
    }

    // audit-fixwave 2026-07-02 / F2 — HONOR the write result. Pre-fix this
    // returned bare `true` regardless of whether the log actually persisted,
    // so a failed food write (e.g. logFood returns success:false without
    // throwing) still flipped LogConfirmCard to the green "LOGGED ✓" state — a
    // false-success card contradicting a 0-row write. Sibling handlers
    // (_logSleep/_logMeasurement) already return result.success; food now does
    // too. foodLogProvider.logFood returns ({bool success, String? error,
    // String? logKey}) (nutrition_provider.dart).
    final r = await ref.read(foodLogProvider.notifier).logFood(
          food: foodMap,
          mealType: mealType,
          quantityG: quantityG,
        );
    return r.success;
  }

  // ── Sleep ───────────────────────────────────────────────────────

  Future<bool> _logSleep(Map<String, dynamic> data) async {
    final hrs = (data['duration_hrs'] as num?)?.toDouble();
    final quality = data['quality'] as String? ?? 'fair';
    if (hrs == null || hrs <= 0 || hrs > 24) return false;

    // audit-2026-05-16 reader-side / F2-R3 — dual-key hazard close-out.
    //
    // Pre-fix this handler wrote ONLY to the legacy `sleep_logs` LIST
    // key. Canonical readers (`profile_provider.dailySleepProvider`,
    // `ai_coach_repository._countSleepLogsLast7Days`, AI snapshot's
    // sleep_7d series) all key off `sleep_log_<istDate>` per-day. So a
    // user who reported sleep through the AI chat had ZERO sleep data
    // visible to the coach's own context — surfaced as "your sleep
    // data isn't logged" responses despite the chat turn appearing to
    // succeed.
    //
    // Fix: route through `HealthWriteService.logSleep` — same canonical
    // writer the manual UI uses. Writes `sleep_log_<istDate>` with
    // overwrite-per-day semantics, fires `syncSleepNow + pushSnapshot`
    // exactly as the audit-2026-05-16 E.7 health-domain pattern
    // mandates. Multiple chat mentions in one IST day collapse to the
    // last-mentioned value (matches how the user actually wants sleep
    // tracked — one value per night).
    //
    // The legacy `sleep_logs` LIST is no longer written from the chat
    // path. `syncSleepNow`'s list-path remains for back-compat with
    // pre-fix on-device data; once devices upgrade past +28, that path
    // can be retired in a follow-up cleanup.
    //
    // closes-diagnose: 2026-05-16-sleep-dual-key
    final result = await HealthWriteService.instance.logSleep(
      date: DateTime.now(),
      hours: hrs,
      quality: quality,
      source: WriteSource.aiCoach,
    );
    return result.success;
  }

  // ── Body Measurements ─────────────────────────────────────────

  Future<bool> _logMeasurement(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    final valueCm = (data['value_cm'] as num?)?.toDouble();
    if (type == null || valueCm == null || valueCm <= 0) return false;
    if (!isBodyMeasurementSite(type)) return false;

    // L2b Landing B: with the flag ON a successful chat write refreshes the
    // measurements history (the notifier's own Ref outlives this widget). With
    // the flag OFF no provider is read at all, so this path is byte-identical
    // to before. Both the read and the call are guarded: neither may turn a
    // successful write into a `false` from executeAction's catch-all.
    final notifier = MeasurementFlags.bodyMeasurementsEnabled
        ? _tryMeasurementNotifier()
        : null;

    // audit-2026-05-16 task E.7 — route through HealthWriteService so the
    // measurement key uses `istDateStr` and the sync fan-out + telemetry
    // pattern is identical to every other health-domain mutation.
    final result = await HealthWriteService.instance.logMeasurement(
      date: DateTime.now(),
      partName: type,
      valueCm: valueCm,
      source: WriteSource.aiCoach,
    );
    if (result.success) {
      try {
        notifier?.noteWritten();
      } catch (_) {
        // The write succeeded; only the history refresh failed. Record it (the
        // history would otherwise stay stale with no trace) and carry on.
        unawaited(ErrorTelemetry.logEvent('measurement_chat_refresh_failed',
            message: 'stage=note'));
      }
    }
    return result.success;
  }

  MeasurementWriteNotifier? _tryMeasurementNotifier() {
    try {
      return ref.read(measurementWriteProvider.notifier);
    } catch (_) {
      unawaited(ErrorTelemetry.logEvent('measurement_chat_refresh_failed',
          message: 'stage=lookup'));
      return null;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────

  String _validateMealType(String? raw) {
    const valid = ['breakfast', 'lunch', 'dinner', 'snacks'];
    final lower = raw?.toLowerCase() ?? '';
    return valid.contains(lower) ? lower : 'snacks';
  }

  /// Build a minimal food map from AI calorie estimates, scaled to per-100g.
  ///
  /// FoodLogNotifier.logFood() multiplies per-100g values by (quantityG / 100),
  /// so we must scale the AI's per-serving estimates back to per-100g first.
  Map<String, dynamic> _buildEstimatedFood(
      Map<String, dynamic> data, double quantityG) {
    final factor = quantityG > 0 ? 100.0 / quantityG : 1.0;
    return {
      'id': 'chat_food_${DateTime.now().millisecondsSinceEpoch}',
      'name': data['food_name'] ?? 'Unknown Food',
      'calories_per_100g':
          ((data['calories_estimate'] as num?)?.toDouble() ?? 200) * factor,
      'protein_per_100g':
          ((data['protein_estimate'] as num?)?.toDouble() ?? 10) * factor,
      'carbs_per_100g':
          ((data['carbs_estimate'] as num?)?.toDouble() ?? 25) * factor,
      'fat_per_100g':
          ((data['fat_estimate'] as num?)?.toDouble() ?? 5) * factor,
      'fiber_per_100g': 0.0,
      'source': 'chat_estimate',
    };
  }
}

/// The sets [submitWorkoutDraft] writes for one draft exercise: only sets
/// that carry something (weight, reps or a duration above 0), so an all-blank
/// set is never written as a 0×0 set. Cardio is one synthetic set carrying the
/// total duration, when it has a duration or a distance (B-pass finding 1).
List<ExerciseSet> draftExerciseSets(DraftExercise exercise) {
  if (exercise.loggingType == 'cardio') {
    final mins = exercise.durationMins ?? 0;
    if (mins <= 0 && (exercise.distanceKm ?? 0) <= 0) return const [];
    return [ExerciseSet(weightKg: 0, reps: 0, durationSec: mins * 60)];
  }
  return [
    for (final s in exercise.sets)
      if ((s.weightKg ?? 0) > 0 ||
          (s.reps ?? 0) > 0 ||
          (s.durationSecs ?? 0) > 0)
        ExerciseSet(
          weightKg: s.weightKg ?? 0,
          reps: s.reps ?? 0,
          durationSec: s.durationSecs,
        ),
  ];
}

/// OI-361: true when [submitWorkoutDraft] would write at least one set. The
/// confirm card and the submit share it.
bool draftHasLoggableSet(WorkoutDraft draft) =>
    draft.exercises.any((e) => draftExerciseSets(e).isNotEmpty);

/// Test seams for [submitWorkoutDraft]. Production never sets them.
class DraftSubmitDebug {
  /// The clock a first attempt takes its date from.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Awaited right after `beginSubmit`, before any write.
  @visibleForTesting
  static Completer<void>? debugSubmitGate;

  /// Awaited after the writes, before the day-mark re-check.
  @visibleForTesting
  static Completer<void>? debugBeforeMarkGate;
}

/// What one CONFIRM of the chat workout card did, by exercise index.
@immutable
class DraftSubmitOutcome {
  /// False when the submit was refused (a second tap, a stale card).
  final bool started;

  /// The OI-361 guard: no exercise had a set to write.
  final bool nothingToLog;
  final List<int> savedIndices;
  final List<int> failedIndices;

  /// No usable set (`draftExerciseSets` is empty): never written, named.
  final List<int> skippedIndices;
  final bool dayMarked;

  const DraftSubmitOutcome({
    this.started = true,
    this.nothingToLog = false,
    this.savedIndices = const [],
    this.failedIndices = const [],
    this.skippedIndices = const [],
    this.dayMarked = false,
  });
}

int _draftExerciseDurationSec(DraftExercise e) {
  if (e.loggingType == 'cardio') return (e.durationMins ?? 0) * 60;
  if (e.loggingType == 'timed') {
    return e.sets.fold<int>(0, (s, set) => s + (set.durationSecs ?? 0));
  }
  return 0;
}

/// Submit a confirmed workout draft through [WorkoutWriteService].
///
/// Called by [WorkoutLogConfirmCard] on CONFIRM. Every exercise is attempted
/// (by index); one with no usable set is skipped and named. The day is marked
/// done as soon as anything from this card has saved, unless it was already
/// done (`markCompleted` replaces `wlog_<date>` wholesale). A retry writes to
/// the first attempt's date. Failures stay on the card with a note; the card
/// state lives in [workoutDraftProvider], reached through the container
/// captured before the first await, because the card can be unmounted
/// mid-submit (b7f3e2). If the current draft changes mid-submit (an auth
/// change), the submit stops at once: nothing more is written or marked.
///
/// C-8 (audit-2026-05-11): routed through [WorkoutWriteService] so chat
/// workouts carry the canonical field shape (`sets[]`, `set_number`, IST date,
/// deterministic key, PR rescan, 3-tier cloud sync).
Future<DraftSubmitOutcome> submitWorkoutDraft(WorkoutDraft draft, WidgetRef ref) async {
  // OI-361: a draft with no set to write completes nothing. The card disables
  // CONFIRM on the same predicate; this is the defence for any other caller.
  if (!draftHasLoggableSet(draft)) {
    return const DraftSubmitOutcome(nothingToLog: true);
  }

  final draftId = draft.id;
  final container = ProviderScope.containerOf(ref.context, listen: false);
  final notifier = container.read(workoutDraftProvider.notifier);
  final now = notifier.beginSubmit(draftId, DraftSubmitDebug.clock());
  if (now == null) return const DraftSubmitOutcome(started: false);
  bool stillCurrent() => container.read(workoutDraftProvider)?.id == draftId;

  final saved = <int>[];
  final failed = <int>[];
  final skipped = <int>[];
  try {
    final gate = DraftSubmitDebug.debugSubmitGate;
    if (gate != null) await gate.future;

    var savedDurationSec = 0;
    for (var i = 0; i < draft.exercises.length; i++) {
      final exercise = draft.exercises[i];
      final sets = draftExerciseSets(exercise);
      if (sets.isEmpty) {
        skipped.add(i);
        continue;
      }
      if (!stillCurrent()) {
        return DraftSubmitOutcome(savedIndices: saved, failedIndices: failed);
      }
      final result = await WorkoutWriteService.instance.logExercise(
        date: now,
        exerciseName: exercise.name,
        sets: sets,
        source: WriteSource.aiCoach,
        // No ref: it only feeds the unwired onInvalidate hook, and this ref
        // may belong to a card disposed mid-submit; the helper below
        // invalidates through the container (B-pass fb5048e68fae F8).
      );
      if (result.success) {
        saved.add(i);
        savedDurationSec += _draftExerciseDurationSec(exercise);
      } else {
        failed.add(i);
      }
    }

    final markGate = DraftSubmitDebug.debugBeforeMarkGate;
    if (markGate != null) await markGate.future;
    if (!stillCurrent()) {
      return DraftSubmitOutcome(savedIndices: saved, failedIndices: failed);
    }

    final savedNames = [for (final i in saved) draft.exercises[i].name];
    final skippedNames = [for (final i in skipped) draft.exercises[i].name];
    final everSaved = savedNames.isNotEmpty ||
        (container.read(workoutDraftProvider)?.savedNames.isNotEmpty ?? false);

    // Mark the day as soon as anything from this card saved: Train shows a
    // day's logs only once it is done. An already-done day (status completed
    // AND its wlog_ present) is left alone; a completed status with no wlog_
    // still gets one, as on origin/main (B-pass fb5048e68fae F5).
    var dayMarked = true;
    var markedNow = false;
    if (everSaved) {
      var wasCompletedBefore = false;
      try {
        wasCompletedBefore = WorkoutScheduleService.instance
                    .getScheduleForDate(now)?['status'] ==
                'completed' &&
            HiveService.instance.workoutBox
                .get(WorkoutWriteService.wlogKey(now)) is Map;
      } catch (_) {
        // The schedule box is unavailable: markCompleted reports its own failure.
      }
      if (!wasCompletedBefore) {
        final result = await WorkoutWriteService.instance.markCompleted(
          date: now,
          workoutName: kChatWorkoutName,
          durationSec: savedDurationSec,
        );
        dayMarked = result.success;
        markedNow = result.success;
      }
    }

    // A retry that saves nothing new but marks the day still changes what
    // Train shows (B-pass fb5048e68fae F1).
    if (saved.isNotEmpty || markedNow) {
      invalidateWorkoutSurfaces(container.invalidate, source: 'chat_draft');
      // Defensive: WorkoutWriteService may already have pushed; the snapshot
      // compile is idempotent and rate-limited inside SyncService.
      unawaited(SyncService.instance.pushSnapshot());
    }

    if (failed.isEmpty) {
      notifier.markSaved(draftId,
          dayMarked: dayMarked, skippedNames: skippedNames);
    } else {
      notifier.keepFailed(draftId, failed, savedNames,
          dayMarked: dayMarked, skippedNames: skippedNames);
    }
    return DraftSubmitOutcome(
      savedIndices: saved,
      failedIndices: failed,
      skippedIndices: skipped,
      dayMarked: everSaved && dayMarked,
    );
  } finally {
    // Defensive: no reachable path throws past markSaved / keepFailed.
    notifier.endSubmit(draftId);
  }
}
