import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/auth_session_bootstrapper.dart';
import 'package:icanbefitter/core/services/day_rollover_service.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/exlog_key_migrator.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/nlog_key_migrator.dart';
import 'package:icanbefitter/core/services/saved_meal_key_migrator.dart';
import 'package:icanbefitter/core/services/phase_progress_reconciler.dart';
import 'package:icanbefitter/core/services/plan_integrity_reconciler.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

/// Gate screen shown immediately after sign-in success.
///
/// Parallel: queries [user_profile.onboarding_completed_at] + starts
/// [SyncService.restoreFromCloudForUser].
///
/// Decision tree:
///   row + onboarding_completed_at IS NOT NULL → await restore → /home
///   row + onboarding_completed_at IS NULL     → cancel restore → resume onboarding
///   no row                                    → cancel restore → /onboarding/mission-brief
///
/// 15-second safety net: if restore is still running, shows an escape CTA
/// that lets the user skip straight to /home.
class RestoringScreen extends ConsumerStatefulWidget {
  const RestoringScreen({super.key, this.next});

  /// Optional post-restore destination, carried via `/restoring?next=...` by
  /// `_authRedirect` when a session-gated route is cold-loaded (currently only
  /// `/admin` — a fresh-tab bookmark of the founder dashboard). Null for the
  /// ordinary sign-in / splash → `/restoring` flow, which keeps defaulting to
  /// `/home`. See [resolveRestoreDestination].
  final String? next;

  /// Allowlist guard for the post-restore destination. Returns [next] ONLY
  /// when it is a known-safe in-app route (currently just `/admin`), else
  /// `/home`. This keeps the `next` query param from being abused as a general
  /// in-app open-redirect vector and defaults every ordinary returning user to
  /// `/home`. Pure — pinned by `test/contracts/restoring_next_destination_test.dart`.
  static const _allowedNextRoutes = {'/admin'};
  @visibleForTesting
  static String resolveRestoreDestination(String? next) =>
      _allowedNextRoutes.contains(next) ? next! : '/home';

  @override
  ConsumerState<RestoringScreen> createState() => _RestoringScreenState();
}

class _RestoringScreenState extends ConsumerState<RestoringScreen> {
  bool _showSoftHint = false;
  bool _showTimeoutCta = false;
  Timer? _softHintTimer;
  Timer? _timeoutTimer;

  // Obs#1: new signups + mid-onboarding users have NOTHING to restore, so they
  // must not see restore-flavored copy ("Loading profile & plan" / "Pulling your
  // dispatch."). Default to a neutral setup status; only a returning user
  // (GoHome) whose cloud restore is real flips _useRestoreLabel → the live
  // SyncService restore labels.
  String _statusLabel = 'Getting you ready…';
  bool _useRestoreLabel = false;

  // Theme D (diagnose 2026-05-22 4a3b08) — threshold bumped from 15s to
  // 30s based on +30 APK telemetry showing the founder's restore total
  // is 35.9s every cold start (Step A 23.8s alone exceeded the old 15s
  // gate, hitting every user every launch). Two-stage UX: a soft "Almost
  // there…" hint surfaces at 15s for users who got an old-vs-new mental
  // model of "should this take a few seconds?", and the actual escape-
  // hatch CONTINUE button surfaces at 30s. Background-restore (A5) is
  // a bigger refactor needing per-provider "loading" handling; this
  // batch ships the threshold fix and leaves A5 for the operational-
  // observability work.
  static const Duration _softHintAfter = Duration(seconds: 15);
  static const Duration _ctaAfter = Duration(seconds: 30);

  // a3f6d9 — true once _goHome is about to run; the CTA timer above is
  // wall-clock, independent of classification, so timing alone can't infer this.
  bool _committedToGoHome = false;

  @override
  void initState() {
    super.initState();
    _softHintTimer = Timer(_softHintAfter, () {
      if (mounted) setState(() => _showSoftHint = true);
    });
    _timeoutTimer = Timer(_ctaAfter, () {
      if (mounted) setState(() => _showTimeoutCta = true);
    });
    _kickoffRestore();
  }

  Future<void> _kickoffRestore() async {
    // Audit 2026-05-20 / A9 — UI no longer talks to Supabase directly.
    // Routing decision (home / resume-onboarding / mission-brief) is
    // delegated to AuthSessionBootstrapper.resolveDestination.
    final user = SupabaseService.instance.currentUser;
    if (user == null) {
      if (mounted) context.go('/');
      return;
    }

    // Parallel: destination resolution + start restore in background.
    final destinationFuture =
        AuthSessionBootstrapper.instance.resolveDestination(user.id);
    // A7 / B5 D9-D10 — canonical provider path.
    final restoreFuture =
        ref.read(syncServiceProvider).restoreFromCloudForUser();

    final destination = await destinationFuture;

    switch (destination) {
      case StartMissionBrief():
        // Brand-new user with no profile row — cancel restore, go to Mission Brief.
        // Obs#1: account-creation copy, not restore copy (nothing to restore).
        if (mounted) setState(() => _statusLabel = 'Setting up your account…');
        // A7 / B5 D9-D10 — canonical provider path.
        ref.read(syncServiceProvider).cancelInflightRestore();
        if (mounted) context.go('/onboarding/mission-brief');
        return;

      case ResumeOnboarding(:final firstMissingStep):
        // Plan A reconciliation (relocated from splash_screen during the
        // Test #4 → Test #5 merge). OBS-3 root cause: returning user has a
        // populated user_profile row (goal/experience/weight all set) but
        // onboarding_completed_at was never stamped on the cloud. Without
        // this, RestoringScreen would route them back through onboarding
        // every cold start. Self-heal-stamp instead.
        final hiveProfile = HiveService.instance.userBox.get('profile');
        final hiveProfileMap = hiveProfile is Map ? hiveProfile : null;
        // OI-46 (2026-07-29, B-pass) — renamed from hasCorePlanFields (3
        // fields) to hasAllRequiredFields, matching the 9 columns migration
        // 112 gates server-side. Also now gates the stamp ATTEMPT below: a
        // flagOnboarded=true legacy user missing one of the other 6 fields
        // would otherwise retry-and-be-rejected (P0001) forever with no way
        // to succeed. Navigation is unaffected — that cohort still goes home.
        final hasAllRequiredFields = hiveProfileMap != null &&
            hiveProfileMap['primary_goal'] != null &&
            hiveProfileMap['fitness_experience'] != null &&
            hiveProfileMap['current_weight_kg'] != null &&
            hiveProfileMap['date_of_birth'] != null &&
            hiveProfileMap['gender'] != null &&
            hiveProfileMap['height_cm'] != null &&
            hiveProfileMap['target_weight_kg'] != null &&
            hiveProfileMap['days_per_week'] != null &&
            hiveProfileMap['equipment_access'] != null;
        // audit-2026-05-16 reader-side / F3-2.1 — onboarding_completed
        // moved to userBox via MigratedKey (Test #11.1, UserConfigMigrator
        // v2). Reading from configBox directly returns the legacy/empty
        // value for any device that's run the migration → fresh-install
        // self-heal misclassifies onboarded users as new. Use MigratedKey
        // so we read whichever store the migration left the value in.
        // closes-diagnose: 2026-05-16-onboarding-triplicate-storage
        final flagOnboarded =
            MigratedKey.readWithDefault<bool>('onboarding_completed', false);

        if (flagOnboarded || hasAllRequiredFields) {
          debugPrint(
            '[RestoringScreen] self-heal: cloud onboarding_completed_at is '
            'NULL but Hive profile is populated — stamping now.',
          );
          if (hasAllRequiredFields) {
            // Only attempt the stamp when it can actually satisfy migration
            // 112's trigger. A flagOnboarded=true legacy user whose profile
            // is missing one of the 9 gated fields skips the attempt (it
            // would just be rejected every time) but still goes home below
            // — no navigation change for that cohort, just no more
            // pointless doomed-write retries on every cold start.
            unawaited(_stampOnboardingCompletedAt(user.id).catchError((e) {
              debugPrint('[RestoringScreen] self-heal stamp failed: $e');
            }));
          }
          // Treat as fully onboarded — go home (default: await restore first;
          // bg-restore flag: a returning user reaches home immediately).
          _committedToGoHome = true;
          await _goHome(user.id, restoreFuture);
          return;
        }

        // Mid-onboarding user — cancel restore, jump to first missing step.
        // Obs#1: setup copy, not restore copy.
        if (mounted) setState(() => _statusLabel = 'Setting up your account…');
        // A7 / B5 D9-D10 — canonical provider path.
        ref.read(syncServiceProvider).cancelInflightRestore();
        if (mounted) context.go('/onboarding/$firstMissingStep');
        return;

      case GoHome():
        // Fully onboarded user — go home (default: await restore first;
        // bg-restore flag: a returning user reaches home immediately).
        _committedToGoHome = true;
        await _goHome(user.id, restoreFuture);
        return;
    }
  }

  /// Navigate to /home. A RETURNING user (Hive profile already populated) takes
  /// the background-restore path: establish ownership (BLOCKING — cross-account
  /// safety, APK #15.4) + fresh-paint rollover, go to home IMMEDIATELY, and let
  /// the in-flight cloud restore finish + heal in the background. A fresh install
  /// (no local profile) OR the `disable_bg_restore` kill-switch falls through to
  /// the default path: await the full restore + ownership/heals, then go.
  ///
  /// Slow-boot guard (4e8b1d): this was an opt-IN flag (`bg_restore_enabled`,
  /// default OFF) so returning users blocked >1 min on the full 2020-history
  /// restore on every cold start. Flipped to opt-OUT — returning users default
  /// to the bg path; the kill-switch preserves the old blocking path, reachable
  /// per §4.6. The in-flight restore is NOT cancelled → single restore, no
  /// double-write race; bg heals are ref-free (singletons). The loss-sensitive
  /// restore writers are additive / local-wins (skip-if-local-exists) so a
  /// background restore never overwrites a just-logged local row; the heal's
  /// reconcileExlogIndexes repairs any index drift post-restore (c5a1f2).
  Future<void> _goHome(
      String userId, Future<RestoreResult> restoreFuture) async {
    // Obs#1: a returning user (GoHome) has real cloud data — show the live
    // SyncService restore labels instead of the neutral setup status.
    if (mounted) setState(() => _useRestoreLabel = true);
    final killSwitch =
        HiveService.instance.configBox.get('disable_bg_restore') == true;
    final localProfile = HiveService.instance.userBox.get('profile');
    final isReturning =
        localProfile is Map && localProfile['primary_goal'] != null;

    if (!killSwitch && isReturning) {
      // Ownership gate stays BLOCKING (cross-account safety, APK #15.4).
      await HiveUserSession.openForUser(userId);
      // a3f6d9 — stamp the LOCAL onboarded flag _authRedirect gates on;
      // restore only syncs the cloud onboarding_completed_at, a different key.
      if (!UserRepository.instance.isOnboarded) {
        await UserRepository.instance.setOnboarded();
      }
      // b3f9e7 — OAuth's real convergence point (not hydrateFromCloud).
      unawaited(
          AuthSessionBootstrapper.instance.ensureTermsConsentFallback(userId));
      // Fresh first paint of today-scoped providers — cheap; the in-flight
      // cloud restore keeps writing Hive in the background.
      if (mounted) {
        try {
          await DayRolloverObserver.instance.runRolloverNow(ref);
        } catch (_) {}
      }
      if (!mounted) return;
      context.go(RestoringScreen.resolveRestoreDestination(widget.next));
      // The cloud restore started in _kickoffRestore keeps running; when it
      // SUCCEEDS, run the post-restore key migrators + reconciler + refill
      // (ref-free) and bump the tick so the mounted home refreshes. Guard on
      // success so the heals never run on a cancelled/failed restore (partial
      // Hive state) — B-pass F-3.
      unawaited(restoreFuture.then((result) {
        if (result.succeeded) _healAfterRestoreInBackground();
      }));
      return;
    }

    // Default / fresh install (or flag off): await the full restore before home.
    await restoreFuture;
    if (!mounted) return;
    await _ensureOwnershipBeforeHome(userId);
    // a3f6d9 — same stamp as the bg-restore branch above.
    if (!UserRepository.instance.isOnboarded) {
      await UserRepository.instance.setOnboarded();
    }
    if (!mounted) return;
    context.go(RestoringScreen.resolveRestoreDestination(widget.next));
  }

  /// B5 + Plan A: Ownership guard — before navigating to /home, verify
  /// that the user-scoped Hive boxes are open for the current session
  /// user.id.
  ///
  /// In Test #5's namespaced Hive architecture, [HiveUserSession.openForUser]
  /// is the canonical ownership stamp — `currentOwnerFullId` reflects
  /// whichever user we last opened boxes for. If it diverges from the
  /// session user (startup ordering race, restore completed for wrong
  /// account), force-clear + re-open boxes for the correct user.
  Future<void> _ensureOwnershipBeforeHome(String sessionUserId) async {
    final ownerFullId = HiveUserSession.currentOwnerFullId;
    if (ownerFullId == null) {
      // Boxes never got opened for this user — open them now.
      await HiveUserSession.openForUser(sessionUserId);
    } else if (!ownerFullId.contains(sessionUserId)) {
      // currentOwnerFullId is namespaced; check if it tracks sessionUserId.
      debugPrint(
          '[RestoringScreen] Hive ownership mismatch '
          '(hive=$ownerFullId, session=$sessionUserId). Force-clearing.');
      await UserRepository.instance.clearAllData();
      await HiveUserSession.openForUser(sessionUserId);
      // Re-attempt restore for the correct user. Non-fatal if it fails —
      // user lands on home with empty local state which will fill on next sync.
      try {
        // A7 / B5 D9-D10 — canonical provider path.
        await ref.read(syncServiceProvider).restoreFromCloudForUser();
      } catch (e) {
        debugPrint('[RestoringScreen] re-restore after ownership fix failed: $e');
      }
    }

    // Plan A Task A-10 — One-shot migration of legacy exlog_<ts>_<hash> keys
    // to deterministic exlog_<istDateStr>_<hash(name)>. MUST run AFTER
    // openForUser (so per-user namespaced workoutBox is open) and BEFORE
    // any provider that lists exlog keys (home/train/calendar all key off
    // exercise_log_index_<date>). Idempotent — guarded by configBox.
    bool migratorDidRun = false;
    // A3 — migrators run BEFORE /home navigation, so their cost extends
    // RestoringScreen's perceived duration beyond restore_completed. Wrap
    // with Stopwatch + emit telemetry so post-mortem can include them in
    // the long-pole hunt.
    final swExlog = Stopwatch()..start();
    try {
      // Track whether the migrator actually had work to do this launch
      // so we know to ship canonical keys back up to cloud.
      final config = HiveService.instance.configBox;
      final wasAlreadyDone =
          config.get('exlog_key_migration_v8') == true;
      await ExlogKeyMigrator.runIfNeeded();
      migratorDidRun = !wasAlreadyDone;
    } catch (e) {
      debugPrint('[RestoringScreen] ExlogKeyMigrator failed (non-fatal): $e');
    }
    swExlog.stop();
    unawaited(ErrorTelemetry.logEvent(
      'restoring_screen_migrator_done',
      message: 'migrator=exlog ms=${swExlog.elapsedMilliseconds} '
          'did_run=$migratorDidRun',
    ));

    // APK Test #16.1 / Agent A — once the migrator has consolidated
    // legacy + rogue exlog keys into canonical UUID v5 keys, fire a
    // fire-and-forget syncWorkoutData() so the cloud `workout_log_exercises`
    // / `workout_log_sets` rows pick up the canonical Hive key (the cloud
    // tables key by natural columns so this just heals any divergence
    // introduced by pre-fix `_restoreExerciseLogs` rounds).
    if (migratorDidRun) {
      // A7 / B5 D9-D10 — canonical provider path.
      unawaited(ref.read(syncServiceProvider).syncWorkoutData());
    }

    // Migrate nutrition logs from `nlog_<timestamp>` to deterministic
    // `nlog_<istDateStr>_<mealType>_<hash(items)>` keys. Same guard + safety net.
    final swNlog = Stopwatch()..start();
    bool nlogRan = false;
    try {
      final wasNlogDone =
          HiveService.instance.configBox.get('nlog_key_migration_v7') == true;
      await NlogKeyMigrator.runIfNeeded();
      nlogRan = !wasNlogDone;
    } catch (e) {
      debugPrint('[RestoringScreen] NlogKeyMigrator failed (non-fatal): $e');
    }
    swNlog.stop();
    unawaited(ErrorTelemetry.logEvent(
      'restoring_screen_migrator_done',
      message: 'migrator=nlog ms=${swNlog.elapsedMilliseconds} '
          'did_run=$nlogRan',
    ));

    // Saved-meal key heal (diagnose b8d5c2) — re-key legacy `saved_meal_<ms>`
    // rows to the canonical `saved_meal_<nameHash>` shape so the writer matches
    // the restore + cloud (user_id,name) key (no more restore-duplicated meals).
    // Idempotent; runs alongside the other key migrators.
    final swSavedMeal = Stopwatch()..start();
    bool savedMealRan = false;
    try {
      final wasDone =
          HiveService.instance.configBox.get('saved_meal_key_migration_v1') ==
              true;
      await SavedMealKeyMigrator.runIfNeeded();
      savedMealRan = !wasDone;
    } catch (e) {
      debugPrint(
          '[RestoringScreen] SavedMealKeyMigrator failed (non-fatal): $e');
    }
    swSavedMeal.stop();
    unawaited(ErrorTelemetry.logEvent(
      'restoring_screen_migrator_done',
      message: 'migrator=saved_meal ms=${swSavedMeal.elapsedMilliseconds} '
          'did_run=$savedMealRan',
    ));

    // Two-Phase-1 heal (diagnose 2026-06-02) — advance current_phase to match
    // the number of completed phase blocks (founder choice: "advance, keep
    // progress"). Idempotent + monotonic → a no-op once consistent, so it is
    // safe to run on every boot and also self-heals any future duplicate.
    // Runs AFTER restore + key migrators so schedule_* + plan_start are
    // hydrated; awaited so the corrected counter lands before /home reads
    // currentPlanProvider. Never deletes/rewrites schedule rows.
    final swPhase = Stopwatch()..start();
    try {
      await PhaseProgressReconciler.reconcile(
          ref.read(workoutScheduleReadServiceProvider));
    } catch (e) {
      debugPrint(
          '[RestoringScreen] PhaseProgressReconciler failed (non-fatal): $e');
    }
    swPhase.stop();
    unawaited(ErrorTelemetry.logEvent(
      'restoring_screen_migrator_done',
      message: 'migrator=phase_reconcile ms=${swPhase.elapsedMilliseconds}',
    ));

    // Restore plan_json-skip heal (diagnose 2026-06-06) — re-applies the cloud
    // plan_json snapshot when the current window has a planned workout day that
    // lost its exercises (the exercise-less scheduled_workouts restore). Runs
    // AFTER restore + the phase reconcile so plan_start + schedule_* are
    // hydrated; symptom-gated so a healthy user is a cheap local no-op (no
    // network). Heals an already-broken install on the next sign-in.
    final swPlanIntegrity = Stopwatch()..start();
    try {
      await PlanIntegrityReconciler.reconcile(
          ref.read(workoutScheduleReadServiceProvider));
    } catch (e) {
      debugPrint(
          '[RestoringScreen] PlanIntegrityReconciler failed (non-fatal): $e');
    }
    swPlanIntegrity.stop();
    unawaited(ErrorTelemetry.logEvent(
      'restoring_screen_migrator_done',
      message:
          'migrator=plan_integrity ms=${swPlanIntegrity.elapsedMilliseconds}',
    ));

    // Bug 2026-05-22 / diagnose dc52a4 — three pieces of post-auth bootstrap
    // that used to live in splash_screen._runDeferredInit. They touch the
    // user-scoped GuardedBox (`userBox`) and so MUST run AFTER
    // HiveUserSession.openForUser, which happened above as part of
    // restoreFromCloudForUser → _ensureOwnershipBeforeHome. Splash hit a
    // pre-openForUser race that made `day_rollover_streak_freeze_refill`
    // fail on every cold start since at least 2026-05-06 — universally,
    // every user, every launch. Moving here finally lets the rollover +
    // weekly refill actually execute.

    // (1) Cold-start clear of the session-scoped `streak_freeze_just_used`
    // UI flag. Set by commitConsume(), read+cleared by
    // home_screen._checkStreakFreezeUsed. If a prior session set the flag
    // but never reached the home read (auth race, crash, signOut before
    // snackbar fired), the flag lingers in durable Hive and surfaces as a
    // spurious banner. Real consumes this session re-set it.
    try {
      final progress = UserRepository.instance.getProgress();
      if (progress != null && progress['streak_freeze_just_used'] == true) {
        await UserRepository.instance
            .updateProgress({'streak_freeze_just_used': false});
      }
    } catch (e, st) {
      debugPrint('[RestoringScreen] just_used clear failed (non-fatal): $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'restoring_just_used_clear'));
    }

    // (2) Day rollover — invalidate every "today"-scoped provider before
    // landing on /home so first paint can't show yesterday's data.
    // DayRolloverObserver.runRolloverNow is the canonical cold-start
    // path; the resume-time observer (via _checkAndRollover) handles
    // foreground-resume separately.
    if (mounted) {
      try {
        await DayRolloverObserver.instance.runRolloverNow(ref);
      } catch (e, st) {
        debugPrint('[RestoringScreen] runRolloverNow failed (non-fatal): $e\n$st');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'restoring_run_rollover_now'));
      }
    }

    // (3) Post-restore weekly refill — defence-in-depth for the obs 1+2
    // race fix. `_restoreFreezes` does a max-merge on (available,
    // last_refill); this re-call is the belt-and-braces in case local
    // last_refill got reset between splash + restore. Idempotent — no-op
    // if last_refill is already this week. Telemetry on the inside of
    // refillIfNewWeek will tell us whether it fires.
    try {
      StreakProgressService.instance.refillIfNewWeek();
    } catch (e, st) {
      debugPrint(
          '[RestoringScreen] post-restore refillIfNewWeek failed (non-fatal): $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'restoring_post_restore_refill'));
    }

    // (4) coach_memory backfill (Obs#3, dc52a4 class). Relocated from main()
    // where it ran BEFORE HiveUserSession.openForUser and threw "HiveUserSession
    // not opened — cannot wrap user-scoped box coachBox" on every launch (silent
    // fail). The user-scoped coachBox/userBox are open by now (openForUser ran
    // above). Idempotent.
    try {
      await AiCoachRepository.instance.backfillCoachMemoryIfNeeded();
    } catch (e, st) {
      debugPrint(
          '[RestoringScreen] coach_memory backfill failed (non-fatal): $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'restoring_coach_memory_backfill'));
    }

    // (5) b3f9e7 — same OAuth convergence-point reasoning as above.
    unawaited(
        AuthSessionBootstrapper.instance.ensureTermsConsentFallback(sessionUserId));
  }

  /// Plan A self-heal — stamps `onboarding_completed_at = NOW()` on both
  /// Hive and Supabase so the populated-but-NULL state can't recur.
  Future<void> _stampOnboardingCompletedAt(String userId) async {
    final stampedAt = DateTime.now().toUtc().toIso8601String();
    final profileBox = HiveService.instance.userBox;
    final existing = (profileBox.get('profile') as Map?) ?? <dynamic, dynamic>{};
    final merged = Map<String, dynamic>.from(existing.cast<String, dynamic>());
    merged['onboarding_completed_at'] = stampedAt;
    await profileBox.put('profile', merged);
    unawaited(SyncService.instance.syncProfileNow(userId));
  }

  Future<void> _onContinueAnyway() async {
    _softHintTimer?.cancel();
    _timeoutTimer?.cancel();
    // FIX-1 Part B (e2e-2026-06-21) — open the Hive session BEFORE navigating
    // so the _authRedirect owner-null guard doesn't bounce us straight back to
    // /restoring (infinite trap). On a reinstall the blocking-restore path
    // (founder's restore is ~35.9s) can exceed the 30s CONTINUE timer, so
    // openForUser may not have run yet when the user taps Continue. openForUser
    // is idempotent + _sessionLock-guarded — safe even if the in-flight restore
    // already opened the boxes.
    final userId = SupabaseService.instance.currentUser?.id;
    var ownershipOpen = false;
    if (userId != null) {
      try {
        await HiveUserSession.openForUser(userId);
        ownershipOpen = true;
      } catch (e, st) {
        // Non-fatal for navigation — the guard re-routes to /restoring which
        // re-opens — but RECORD it so a genuinely unrecoverable openForUser
        // (corrupt box) is observable instead of silently looping (B-pass F2.1).
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'restoring_continue_openforuser_failed'));
      }
    }
    // a3f6d9 — third path to /home; needs the same stamp. Gated on
    // _committedToGoHome, not just timing — the CTA can surface pre-classification.
    if (ownershipOpen &&
        _committedToGoHome &&
        !UserRepository.instance.isOnboarded) {
      await UserRepository.instance.setOnboarded();
    }
    if (mounted) {
      context.go(RestoringScreen.resolveRestoreDestination(widget.next));
    }
  }

  @override
  void dispose() {
    _softHintTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Seal mark
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.3),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Image.asset(
                  'assets/avya_icon.png',
                  width: 48,
                  height: 48,
                  errorBuilder: (context, error, stack) => Icon(
                    Icons.shield_outlined,
                    color: AppColors.accent,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(width: 80, height: 1, color: AppColors.accent),
              const SizedBox(height: 32),
              // A4 — dynamic progress text driven by SyncService restore steps.
              // Falls back to the legacy "Pulling your dispatch." label until
              // the first step boundary updates the notifier.
              // Obs#1: only a returning user (GoHome) whose cloud restore is
              // real shows the live SyncService restore labels; new signups +
              // mid-onboarding users show the neutral setup status instead.
              _useRestoreLabel
                  ? ValueListenableBuilder<String>(
                      valueListenable:
                          SyncService.instance.restoreProgressLabel,
                      builder: (context, label, _) => Text(
                        label,
                        style: AppTypography.titleL.copyWith(fontSize: 22),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Text(
                      _statusLabel,
                      style: AppTypography.titleL.copyWith(fontSize: 22),
                      textAlign: TextAlign.center,
                    ),
              const SizedBox(height: 8),
              Text(
                'Stand by, soldier.',
                style: AppTypography.bodyM.copyWith(
                  color: AppColors.accent,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 32),
              const _AnimatedDots(key: ValueKey('restoring-dots')),
              const Spacer(),
              // Theme D — soft hint between 15s and 30s (informational
              // only; restore still progressing). 36s total restore is
              // the founder's measured median per APK +30 telemetry, so
              // most users will see this for ~15s.
              if (_showSoftHint && !_showTimeoutCta)
                Padding(
                  key: const ValueKey('restoring-soft-hint'),
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Text(
                    'Almost there…',
                    style: AppTypography.bodyM.copyWith(
                      color: AppColors.textDim,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              if (_showTimeoutCta)
                Padding(
                  key: const ValueKey('restoring-timeout-cta'),
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Column(
                    children: [
                      Text(
                        'This is taking a while.',
                        style: AppTypography.bodyM.copyWith(
                          color: AppColors.textDim,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _onContinueAnyway,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.accent),
                            shape: const StadiumBorder(),
                          ),
                          child: Text(
                            'CONTINUE  →',
                            style: AppTypography.mono.copyWith(
                              fontSize: 13,
                              color: AppColors.accent,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Obs 4 (2026-06-05): post-restore heals for the background-restore path —
/// runs AFTER the in-flight cloud restore finishes (no concurrent Hive writer),
/// entirely ref-free (singletons) so it survives RestoringScreen disposal.
/// Mirrors the post-restore sequence in `_ensureOwnershipBeforeHome`: key
/// migrators → phase reconciler → weekly refill → bump the home refresh tick.
/// Every step is independently guarded.
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

// ── Animated pulsing dots ────────────────────────────────────────

class _AnimatedDots extends StatefulWidget {
  const _AnimatedDots({super.key});

  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final phase = (t + i / 3) % 1.0;
            final opacity = (0.5 + 0.5 * (1 - (2 * phase - 1).abs()))
                .clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: opacity),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
