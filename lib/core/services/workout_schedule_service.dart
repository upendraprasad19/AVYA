// lib/core/services/workout_schedule_service.dart
//
// Tech-debt audit 2026-05-20 / A2 (final closure batch B5 D13-D17) — SHIM.
//
// This file used to be ~1970 lines containing every schedule-related
// operation. A2 split it into 4 services:
//
//   - WorkoutScheduleReadService — plan generation orchestration + reads.
//   - WorkoutScheduleWriteService — markCompleted / markSkipped / pause /
//     redoWeek4 / copyWeek.
//   - SwapService — swap days, swap exercises, shorten, travel mode.
//   - TemplateService — assign / unschedule / cleanSync templates.
//
// This file is now a [@Deprecated] re-export shim so existing callers
// continue to compile while caller migration lands progressively. The
// shim deletion is a follow-up batch (CLAUDE.md §4.11 — gate ships
// first; see Gate 47 + check_workout_schedule_split.dart).
//
// closes-diagnose: 2026-05-22-a2-workout-schedule-4way-split-<6char>

import 'singleton_lifecycle_registry.dart';
import 'swap_service.dart' as swap;
import 'template_service.dart' as tmpl;
import 'workout_schedule_read_service.dart' as read;
import 'workout_schedule_write_service.dart' as write;
import '../../shared/repositories/plan_generator.dart';

// Re-exports — old callers that imported these from workout_schedule_service
// continue to work.
export 'swap_service.dart'
    show
        SwapExerciseResult,
        SwapExerciseException,
        ShortenDayResult,
        ShortenDayException;
export 'workout_schedule_write_service.dart' show PausePlanException;
export 'template_service.dart'
    show
        AssignTemplateResult,
        AssignTemplateOk,
        AssignTemplateRejected,
        AssignTemplateRejectionReason,
        LoggingTypeResolver;

/// @deprecated Re-export shim for the now-split schedule services.
///
/// Use the split services directly:
///   - [WorkoutScheduleReadService] (plan + reads)
///   - [WorkoutScheduleWriteService] (mark / pause / copy)
///   - [SwapService] (swap + travel)
///   - [TemplateService] (templates)
///
/// Every method on this class is a thin pass-through to the
/// corresponding split service. Full removal of this shim is a follow-up
/// batch when caller count reaches 0.
@Deprecated('Use the split services — Read / Write / Swap / Template')
class WorkoutScheduleService {
  WorkoutScheduleService._() {
    _registerLifecycle();
  }
  static final WorkoutScheduleService _instance = WorkoutScheduleService._();

  @Deprecated(
      'Use ref.read(workoutScheduleServiceProvider) — split into Read/Write/Swap/Template Providers')
  static WorkoutScheduleService get instance => _instance;

  void _registerLifecycle() {
    SingletonLifecycleRegistry.register(
        'WorkoutScheduleService', _onUserChanged);
  }

  void _onUserChanged() {
    // No-op shim — state lives in the split services' boxes.
  }

  // ── Read / plan generation pass-throughs ─────────────────────────

  Future<Phase> generateAndSchedule({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    required DateTime startDate,
    String experienceLevel = 'beginner',
    int phase = 1,
    List<int>? preferredDays,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
  }) =>
      read.WorkoutScheduleReadService.instance.generateAndSchedule(
        goal: goal,
        equipment: equipment,
        daysPerWeek: daysPerWeek,
        startDate: startDate,
        experienceLevel: experienceLevel,
        phase: phase,
        preferredDays: preferredDays,
        injuries: injuries,
        bodyFocus: bodyFocus,
        sessionDuration: sessionDuration,
        cardioPreference: cardioPreference,
      );

  Future<Phase> generateAndScheduleFromDate({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    required DateTime fromDate,
    String experienceLevel = 'beginner',
    int phase = 1,
    List<int>? preferredDays,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
  }) =>
      read.WorkoutScheduleReadService.instance.generateAndScheduleFromDate(
        goal: goal,
        equipment: equipment,
        daysPerWeek: daysPerWeek,
        fromDate: fromDate,
        experienceLevel: experienceLevel,
        phase: phase,
        preferredDays: preferredDays,
        injuries: injuries,
        bodyFocus: bodyFocus,
        sessionDuration: sessionDuration,
        cardioPreference: cardioPreference,
      );

  Future<({bool generated, bool repeated})> autoGenerateNextPhaseIfNeeded({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    String experienceLevel = 'intermediate',
    int currentPhase = 1,
    List<int>? preferredDays,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
    bool repeatContent = false, // ⑧ 2-int (W2.5): forward to the read-service
  }) =>
      read.WorkoutScheduleReadService.instance.autoGenerateNextPhaseIfNeeded(
        goal: goal,
        equipment: equipment,
        daysPerWeek: daysPerWeek,
        experienceLevel: experienceLevel,
        currentPhase: currentPhase,
        preferredDays: preferredDays,
        injuries: injuries,
        bodyFocus: bodyFocus,
        sessionDuration: sessionDuration,
        cardioPreference: cardioPreference,
        repeatContent: repeatContent,
      );

  Map<String, dynamic>? getScheduleForDate(DateTime date) =>
      read.WorkoutScheduleReadService.instance.getScheduleForDate(date);

  List<Map<String, dynamic>> getWeek(int weekNumber) =>
      read.WorkoutScheduleReadService.instance.getWeek(weekNumber);

  int getCurrentWeekNumber() =>
      read.WorkoutScheduleReadService.instance.getCurrentWeekNumber();

  String phaseName(int phase) =>
      read.WorkoutScheduleReadService.instance.phaseName(phase);

  int getProgramWeek(int currentPhase) =>
      read.WorkoutScheduleReadService.instance.getProgramWeek(currentPhase);

  /// The honest week identity for today — week-in-phase, or the hold ordinal
  /// while holding. See [read.WeekIdentity]; FOB-1 / OI-60.
  read.WeekIdentity weekIdentity() =>
      read.WorkoutScheduleReadService.instance.weekIdentity();

  int getCurrentDayInPhase() =>
      read.WorkoutScheduleReadService.instance.getCurrentDayInPhase();

  bool isPhaseExpired() =>
      read.WorkoutScheduleReadService.instance.isPhaseExpired();

  /// ⑧ 3-a2 (W2.5): completion rate (0-1) of the CURRENT (expiring) phase — the
  /// low-adherence signal for the repeat-content default. Pass-through.
  double currentPhaseCompletionRate() =>
      read.WorkoutScheduleReadService.instance.currentPhaseCompletionRate();

  /// ⑥ Batch 7-A (W3.2): read-only phase-arc wave characters (see read service).
  List<String> currentWaveCharacters() =>
      read.WorkoutScheduleReadService.instance.currentWaveCharacters();

  /// Batch 10 (W3.1): the one-line deload "why" for the current phase's week 4,
  /// or null (flag OFF / no reason stamped).
  String? currentDeloadReason() =>
      read.WorkoutScheduleReadService.instance.currentDeloadReason();

  DateTime? getPlanStartDate() =>
      read.WorkoutScheduleReadService.instance.getPlanStartDate();

  DateTime? getPlanEndDate() =>
      read.WorkoutScheduleReadService.instance.getPlanEndDate();

  Phase? getCurrentPlan() =>
      read.WorkoutScheduleReadService.instance.getCurrentPlan();

  Map<String, dynamic>? getCurrentPlanMap() =>
      read.WorkoutScheduleReadService.instance.getCurrentPlanMap();

  bool hasPlan() => read.WorkoutScheduleReadService.instance.hasPlan();

  List<Map<String, dynamic>> getCurrentCalendarWeek() =>
      read.WorkoutScheduleReadService.instance.getCurrentCalendarWeek();

  // ── Write pass-throughs ──────────────────────────────────────────

  Future<void> markCompleted(DateTime date, {int durationSeconds = 0}) =>
      write.WorkoutScheduleWriteService.instance
          .markCompleted(date, durationSeconds: durationSeconds);

  Future<void> markSkipped(DateTime date) =>
      write.WorkoutScheduleWriteService.instance.markSkipped(date);

  Future<List<String>> pauseRange({
    required DateTime startDate,
    required int days,
    String? reason,
  }) =>
      write.WorkoutScheduleWriteService.instance.pauseRange(
        startDate: startDate,
        days: days,
        reason: reason,
      );

  Future<void> redoWeek4() =>
      write.WorkoutScheduleWriteService.instance.redoWeek4();

  Future<void> copyWeek({
    required int sourceWeek,
    required int targetWeek,
    required String planStartDateIso,
  }) =>
      write.WorkoutScheduleWriteService.instance.copyWeek(
        sourceWeek: sourceWeek,
        targetWeek: targetWeek,
        planStartDateIso: planStartDateIso,
      );

  // ── Swap pass-throughs ───────────────────────────────────────────

  Future<String?> swapDays(DateTime dateA, DateTime dateB,
          {required bool isPro}) =>
      swap.SwapService.instance.swapDays(dateA, dateB, isPro: isPro);

  Future<swap.SwapExerciseResult> swapExerciseInDay({
    required String date,
    required String fromExerciseId,
    required String toExerciseId,
  }) =>
      swap.SwapService.instance.swapExerciseInDay(
        date: date,
        fromExerciseId: fromExerciseId,
        toExerciseId: toExerciseId,
      );

  Future<swap.ShortenDayResult> shortenDay({
    required String date,
    required int targetMinutes,
  }) =>
      swap.SwapService.instance
          .shortenDay(date: date, targetMinutes: targetMinutes);

  Future<String?> activateTravelMode(DateTime start, DateTime end) =>
      swap.SwapService.instance.activateTravelMode(start, end);

  bool isTravelDay(DateTime date) =>
      swap.SwapService.instance.isTravelDay(date);

  // ── Template pass-throughs ───────────────────────────────────────

  Future<tmpl.AssignTemplateResult> assignTemplateToDate(
          String templateId, DateTime date) =>
      tmpl.TemplateService.instance.assignTemplateToDate(templateId, date);

  Future<void> unscheduleTemplateFromDate(DateTime date) =>
      tmpl.TemplateService.instance.unscheduleTemplateFromDate(date);

  Future<void> cleanSyncTemplateSchedule(String templateId) =>
      tmpl.TemplateService.instance.cleanSyncTemplateSchedule(templateId);
}
