part of '../restoring_screen.dart';

/// Obs 4 (2026-06-05): post-restore heals for the background-restore path —
/// runs AFTER the in-flight cloud restore finishes (no concurrent Hive writer),
/// entirely ref-free (singletons) so it survives RestoringScreen disposal.
/// Mirrors the post-restore sequence in `_ensureOwnershipBeforeHome`: key
/// migrators → phase reconciler → weekly refill → bump the home refresh tick.
/// Every step is independently guarded.
///
/// Extracted verbatim from `restoring_screen.dart` (2026-08-10) as a `part` of
/// the same library, so the private name is unchanged and no call site moves.
/// The extraction bought the Gate 43 headroom the Google-OAuth misroute fix
/// needed — that file sat at 791 lines against the 800-line ceiling.
Future<void> _healAfterRestoreInBackground() async {
  // Hermes L34: each step records a non-fatal on failure (mirrors the foreground
  // twin _ensureOwnershipBeforeHome) — a heal that throws in the background must
  // not be a SILENT loss of observability (also surfaces the L27 migrator-race).
  try {
    await ExlogKeyMigrator.runIfNeeded();
  } catch (e, st) {
    unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: 'bg_heal_exlog'));
  }
  try {
    await NlogKeyMigrator.runIfNeeded();
  } catch (e, st) {
    unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: 'bg_heal_nlog'));
  }
  try {
    await SavedMealKeyMigrator.runIfNeeded();
  } catch (e, st) {
    unawaited(
        ErrorTelemetry.recordNonFatal(e, st, reason: 'bg_heal_saved_meal'));
  }
  try {
    // ignore: deprecated_member_use — singleton read in a ref-free bg context
    await PhaseProgressReconciler.reconcile(
        WorkoutScheduleReadService.instance);
  } catch (e, st) {
    unawaited(ErrorTelemetry.recordNonFatal(e, st,
        reason: 'bg_heal_phase_reconcile'));
  }
  try {
    // ignore: deprecated_member_use — singleton read in a ref-free bg context
    await PlanIntegrityReconciler.reconcile(
        WorkoutScheduleReadService.instance);
  } catch (e, st) {
    unawaited(ErrorTelemetry.recordNonFatal(e, st,
        reason: 'bg_heal_plan_integrity'));
  }
  try {
    StreakProgressService.instance.refillIfNewWeek();
  } catch (e, st) {
    unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: 'bg_heal_refill'));
  }
  try {
    // coach_memory backfill (Obs#3): bg-restore twin of the foreground call in
    // _ensureOwnershipBeforeHome — also AFTER openForUser, ref-free singleton.
    await AiCoachRepository.instance.backfillCoachMemoryIfNeeded();
  } catch (e, st) {
    unawaited(
        ErrorTelemetry.recordNonFatal(e, st, reason: 'bg_heal_coach_memory'));
  }
  try {
    // Defense-in-depth (c5a1f2): rebuild every exercise_log_index_<date> as the
    // UNION of the actual exlog_ keys present — self-heals any index drift from
    // a lost index write (e4a8b1 class) or a rogue writer. Runs AFTER the key
    // migrators above so re-keyed rows are indexed too.
    await WorkoutWriteService.instance.reconcileExlogIndexes();
  } catch (e, st) {
    unawaited(
        ErrorTelemetry.recordNonFatal(e, st, reason: 'bg_heal_exlog_index'));
  }
  // Notify the (now-mounted) home screen to refresh from the updated Hive.
  SyncService.instance.bumpRestoreCompleted();
}
