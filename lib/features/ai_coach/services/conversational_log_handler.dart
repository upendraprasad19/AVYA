import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/body_measurement_sites.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/measurement_flags.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/completion_prompt_store.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/train/providers/workout_surface_invalidation.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/services/coach_day_completion.dart';
import 'package:icanbefitter/features/train/services/workout_completion_bookkeeping.dart';
import '../providers/ai_coach_provider.dart';
import 'coach_meal_log.dart';

/// Routes AI-detected log actions to existing Riverpod providers.
///
/// Each action type maps to an existing write path:
/// - water → [WaterIntakeNotifier.addWater]
/// - weight → [WeightLogNotifier.logWeight]
/// - food → [CoachMealLog.write] (the coach's own estimate; the one coach
///   meal writer, shared with the `logMealByText` tool, OI-493)
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

  /// OI-493 Landing B (B6): the save in flight for each action id. STATIC
  /// because a handler is built fresh per call (`LogConfirmCard._execute`), so
  /// a card remounted while its first save runs reaches the same entry.
  static final Map<String, Future<bool>> _inFlight = <String, Future<bool>>{};

  @visibleForTesting
  static int get debugInFlightCount => _inFlight.length;

  /// Execute a pending log action. Returns true on success.
  ///
  /// One action, one write (OI-493 Landing B, B6): a second call for the same
  /// action id while the first runs returns the SAME future (the same bool),
  /// so a remounted card's countdown cannot save the meal twice. The entry is
  /// dropped when the save completes (success or failure), so a failed save
  /// can be retried.
  Future<bool> executeAction(PendingLogAction action) {
    final running = _inFlight[action.id];
    if (running != null) return running;
    // A block body, never `() => _inFlight.remove(id)`: `remove` returns the
    // removed value, which IS this future, and `whenComplete` awaits a future
    // its callback returns, so the save would wait on itself forever.
    final future = _executeOnce(action).whenComplete(() {
      _inFlight.remove(action.id);
    });
    _inFlight[action.id] = future;
    return future;
  }

  Future<bool> _executeOnce(PendingLogAction action) async {
    try {
      switch (action.type) {
        case LogActionType.water:
          return await _logWater(action.data);
        case LogActionType.weight:
          return await _logWeight(action.data);
        case LogActionType.food:
          return await _logFood(action.data, action.createdAt);
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

  /// OI-493 Landing A: a `log_food` tag writes what the `logMealByText` tool
  /// writes, through the one coach meal writer: the coach's own name and
  /// estimate (never a food-database substitute, never invented defaults),
  /// the slot by the screen's clock rule when the tag names none, and the day
  /// of [at], the card's creation (its 5 s countdown can cross midnight).
  Future<bool> _logFood(Map<String, dynamic> data, DateTime at) async {
    final item = coachItemFromTag(data);
    if (item == null) return false;
    final r = await CoachMealLog.write(
      at: at,
      mealType: data['meal_type'] as String?,
      items: [item],
    );
    if (r.success) {
      // logMeal refreshes the core nutrition providers; the weekly chart is
      // the one it does not cover (FoodLogNotifier.logFood adds it too). A
      // disposed widget must not turn a stored meal into a failure.
      try {
        ref.invalidate(weeklyNutritionProvider);
      } catch (e) {
        debugPrint('[ConversationalLogHandler] weekly refresh skipped: $e');
      }
    }
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

  /// What the coach-day rule did with the day (1b, OI-490).
  final DraftDayState dayState;
  final int plannedCount;
  final int loggedCount;

  /// The day is completed after this CONFIRM (marked now, or already done).
  bool get dayMarked => dayState == DraftDayState.completed;

  const DraftSubmitOutcome({
    this.started = true,
    this.nothingToLog = false,
    this.savedIndices = const [],
    this.failedIndices = const [],
    this.skippedIndices = const [],
    this.dayState = DraftDayState.none,
    this.plannedCount = 0,
    this.loggedCount = 0,
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
/// (by index); one with no usable set is skipped and named. The day follows
/// the coach-day rule (`decideCoachDay`, 1b): marked only when every planned
/// exercise is logged, else the completion tile today (`markCompleted`
/// replaces `wlog_<date>` wholesale, so an already-done day is left alone). A
/// retry writes to
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
  // Coach workout parity 1a: the Hive owner, captured before the first await
  // (the debug gate, then the logExercise loop); the shared completion step
  // refuses to write if it changed.
  final owner = HiveUserSession.currentOwnerFullId;
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
    // Coach workout parity 1b: the day decision below READS the schedule row
    // and may write the prompt or the mark. After an account change it would
    // read (and write into) the NEW account's boxes, so it stops here, before
    // any read (the 1a bookkeeping guard sits later, after the mark).
    if (HiveUserSession.currentOwnerFullId != owner) {
      unawaited(ErrorTelemetry.logEvent('chat_card_owner_changed'));
      return DraftSubmitOutcome(savedIndices: saved, failedIndices: failed);
    }

    final savedNames = [for (final i in saved) draft.exercises[i].name];
    final skippedNames = [for (final i in skipped) draft.exercises[i].name];
    final everSaved = savedNames.isNotEmpty ||
        (container.read(workoutDraftProvider)?.savedNames.isNotEmpty ?? false);

    // Coach workout parity 1b (OI-490; plan coach-workout-parity-1b.md D2):
    // the card follows the ONE coach-day rule (`decideCoachDay`, shared with
    // the typed backstop, the tile and Train). It marks the day only when
    // every planned exercise is logged (or repairs a completed row with no
    // wlog_, the old F5); a partial day TODAY gets the "X of Y · Complete"
    // tile; a partial PAST day (a retry after IST midnight keeps the first
    // attempt's date) stays not done (decision F); a rest / moved / dropped /
    // no-plan day is never marked. Before 1b the card marked the day on ANY
    // save, which 1a would have counted permanently.
    var dayState = DraftDayState.none;
    var plannedCount = 0;
    var loggedCount = 0;
    var markedNow = false;
    var promptChanged = false;
    if (everSaved) {
      final today = istTodayStr();
      final dateStr = istDateStr(now);
      Map<String, dynamic>? raw;
      var readOk = true;
      var hasWlog = false;
      try {
        raw = WorkoutScheduleReadService.instance.rawScheduleRow(now);
        hasWlog = HiveService.instance.workoutBox
            .get(WorkoutWriteService.wlogKey(now)) is Map;
      } catch (_) {
        readOk = false; // the box is unavailable: report the day as not marked
      }
      if (!readOk) {
        dayState = DraftDayState.markFailed;
      } else {
        // Everything from the decision to the last write is guarded: a throw
        // here (a Hive put, the bookkeeping guards) must still give the card
        // a saved state, never escape the submit (B-pass 2026-11-10). The
        // sets are already saved; a day marked before the throw stays
        // completed.
        try {
          loggedCount = raw == null ? 0 : loggedPlannedExerciseCount(now, raw);
          plannedCount = raw == null ? 0 : plannedExercisesOf(raw).length;
          final decision = decideCoachDay(
            rawRow: raw,
            loggedCount: loggedCount,
            hasWlog: hasWlog,
            dateStr: dateStr,
            istToday: today,
          );
          switch (decision) {
            case CoachDayDecision.completeNow:
            case CoachDayDecision.repairDone:
              final result = await WorkoutWriteService.instance.markCompleted(
                date: now,
                workoutName: planWorkoutName(raw, fallback: kChatWorkoutName),
                durationSec: savedDurationSec,
              );
              if (result.success) {
                markedNow = true;
                dayState = DraftDayState.completed;
                // Coach workout parity 1a (OI-379): the same after-completion
                // step Active Workout runs (count once per day + heal, streaks,
                // badges, rank), before the invalidation below so every reader
                // sees it.
                await WorkoutCompletionBookkeeping.instance.afterCompletion(
                  workoutDate: now,
                  newlyCompleted: result.newlyCompleted,
                  expectedOwner: owner,
                  mintProgressIfMissing: false,
                  door: CompletionDoor.chatCard,
                );
                // afterCompletion resolved the day's prompt (owner-checked).
                promptChanged = true;
              } else {
                dayState = DraftDayState.markFailed;
              }
            case CoachDayDecision.alreadyDone:
              dayState = DraftDayState.completed;
            case CoachDayDecision.askToComplete:
              if (dateStr == today) {
                await CompletionPromptStore.instance.write(
                  dateStr: dateStr,
                  plannedCount: plannedCount,
                  loggedCount: loggedCount,
                );
                promptChanged = true;
                dayState = DraftDayState.awaitingComplete;
              } else {
                dayState = DraftDayState.pastNotMarked;
              }
            case CoachDayDecision.rest:
            case CoachDayDecision.terminal:
            case CoachDayDecision.noPlan:
            case CoachDayDecision.future:
              dayState = DraftDayState.notCounted;
          }
        } catch (e, st) {
          debugPrint('[submitWorkoutDraft] day decision failed: $e');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'chat_card_day_decision_failed'));
          dayState =
              markedNow ? DraftDayState.completed : DraftDayState.markFailed;
        }
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
    // The tile is written AFTER the coach reply rendered: rebuild the thread
    // so it shows (or a resolved one drops) at once, as the typed path does
    // after a log_set (A-F2).
    if (promptChanged) {
      try {
        container.read(chatHistoryProvider.notifier).refreshFromHive();
      } catch (e) {
        debugPrint('[submitWorkoutDraft] chat refresh failed: $e');
      }
    }

    if (failed.isEmpty) {
      notifier.markSaved(draftId,
          dayState: dayState,
          plannedCount: plannedCount,
          loggedCount: loggedCount,
          skippedNames: skippedNames);
    } else {
      notifier.keepFailed(draftId, failed, savedNames,
          dayState: dayState,
          plannedCount: plannedCount,
          loggedCount: loggedCount,
          skippedNames: skippedNames);
    }
    return DraftSubmitOutcome(
      savedIndices: saved,
      failedIndices: failed,
      skippedIndices: skipped,
      dayState: dayState,
      plannedCount: plannedCount,
      loggedCount: loggedCount,
    );
  } finally {
    // Defensive: no reachable path throws past markSaved / keepFailed.
    notifier.endSubmit(draftId);
  }
}
