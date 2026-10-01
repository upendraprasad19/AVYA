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
import 'package:icanbefitter/core/services/local_onboarding_evidence.dart';
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

// Single-library `part` split (2026-08-10) — same shape as
// `lib/features/train/screens/active_workout/`, except the head file keeps its
// `*_screen.dart` name so it stays inside Gate 43's filename regex. Parts share
// this file's imports and its private namespace, so nothing was renamed.
part 'restoring/animated_dots.dart';
part 'restoring/heal_after_restore.dart';

/// Gate screen shown immediately after sign-in success. Runs
/// [AuthSessionBootstrapper.resolveDestination] + [SyncService.restoreFromCloudForUser]
/// in parallel, then routes to /home, resume-onboarding, or mission-brief.
/// Full decision tree + timeout UX (15s soft hint, 30s escape CTA):
/// `lib/features/auth/CLAUDE.md` "Post-auth flow".
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

  // Theme D two-stage timeout UX (soft hint at 15s, CONTINUE at 30s).
  // Full reasoning + telemetry: docs/diagnoses/2026-05-22-restoring-timeout-threshold-4a3b08.md.
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
        // closes-diagnose: c2e9f4 — this branch is reached both when the user
        // genuinely has no profile row AND when the cloud read returned zero
        // rows because RLS filtered a stale-token request (HTTP 200, null,
        // indistinguishable from "no such user"). Consult local evidence
        // before condemning anyone to onboarding: a returning user whose Hive
        // profile is populated goes home instead.
        //
        // A genuinely new user has neither the flag nor a profile map, so
        // this changes nothing for them — pinned by the behavioral test.
        if (await _hasLocalOnboardedEvidence()) {
          debugPrint('[RestoringScreen] StartMissionBrief overridden by local '
              'evidence — cloud read returned no row but Hive says onboarded.');
          unawaited(ErrorTelemetry.logEvent(
              'restoring_missionbrief_overridden_by_local_evidence',
              message: 'userId=${user.id.substring(0, 8)}'));
          _committedToGoHome = true;
          await _goHome(user.id, restoreFuture);
          return;
        }
        // Brand-new user with no profile row — cancel restore, go to Mission Brief.
        // Obs#1: account-creation copy, not restore copy (nothing to restore).
        if (mounted) setState(() => _statusLabel = 'Setting up your account…');
        // A7 / B5 D9-D10 — canonical provider path.
        ref.read(syncServiceProvider).cancelInflightRestore();
        if (mounted) context.go('/onboarding/mission-brief');
        return;

      case DestinationUnknown(:final reason):
        // closes-diagnose: c2e9f4 — the read did not answer. Local evidence
        // first; failing that, DO NOT route into onboarding. Staying put keeps
        // the restore running and leaves the 15s hint / 30s CONTINUE escape
        // in place, whereas guessing "new user" is the one wrong answer that
        // destroys data if the user completes the flow.
        debugPrint('[RestoringScreen] destination unknown ($reason)');
        unawaited(ErrorTelemetry.logEvent('restoring_destination_unknown',
            message: 'userId=${user.id.substring(0, 8)} reason=$reason'));
        if (await _hasLocalOnboardedEvidence()) {
          _committedToGoHome = true;
          await _goHome(user.id, restoreFuture);
          return;
        }
        if (mounted) {
          setState(() => _statusLabel = 'Still connecting…');
        }
        return;

      case ResumeOnboarding(:final firstMissingStep):
        // Plan A reconciliation (relocated from splash_screen during the
        // Test #4 → Test #5 merge). OBS-3 root cause: returning user has a
        // populated user_profile row (goal/experience/weight all set) but
        // onboarding_completed_at was never stamped on the cloud. Without
        // this, RestoringScreen would route them back through onboarding
        // every cold start. Self-heal-stamp instead.
        // closes-diagnose: c2e9f4 — routed through the shared helper so all
        // THREE not-onboarded branches consult the same evidence, and so the
        // Hive session is guaranteed open before the read (it previously was
        // not — see _hasLocalOnboardedEvidence's doc comment).
        await _ensureHiveSessionOpenForEvidence();
        final hiveProfile = HiveService.instance.userBox.get('profile');
        // OI-46 (2026-07-29, B-pass) — the 9 columns migration 112 gates
        // server-side. Gates the stamp ATTEMPT below: a flagOnboarded=true
        // legacy user missing one of the other 6 fields would otherwise
        // retry-and-be-rejected (P0001) forever with no way to succeed.
        // Navigation is unaffected — that cohort still goes home.
        final hasAllRequiredFields = hasAllRequiredProfileFields(hiveProfile);
        // audit-2026-05-16 reader-side / F3-2.1 — onboarding_completed
        // moved to userBox via MigratedKey (Test #11.1, UserConfigMigrator
        // v2). Reading from configBox directly returns the legacy/empty
        // value for any device that's run the migration → fresh-install
        // self-heal misclassifies onboarded users as new. Use MigratedKey
        // so we read whichever store the migration left the value in.
        // closes-diagnose: 2026-05-16-onboarding-triplicate-storage
        final flagOnboarded =
            MigratedKey.readWithDefault<bool>('onboarding_completed', false);

        if (hasLocalOnboardedEvidence(
            hiveProfile: hiveProfile, flagOnboarded: flagOnboarded)) {
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

  /// Opens the user-scoped Hive session so a local-evidence read cannot be
  /// silently served an empty box.
  ///
  /// closes-diagnose: c2e9f4. Under authenticated-but-owner-null
  /// `wrapUserScopedBox` serves `GuardedBox.empty` (guarded_box.dart:333) —
  /// every read yields null and the evidence check concludes "no evidence",
  /// SILENTLY (the loud `StateError` at :335 fires only when UNAUTHENTICATED).
  /// The pre-fix code relied on `restoreFromCloudForUser` having opened the
  /// session, but that call (sync_service.dart:454) is fire-and-forget, so it
  /// was a RACE — likely why a3f6d9's self-heal passed tests and still let this
  /// through in the field. `openForUser` is idempotent + `_sessionLock`-guarded
  /// and `_goHome` opens it moments later anyway, so this only moves the
  /// existing call earlier; no new ownership transition.
  Future<void> _ensureHiveSessionOpenForEvidence() async {
    try {
      await HiveUserSession.ensureOpenedForCurrentSession();
    } catch (e, st) {
      // Non-fatal: the evidence read below just returns empty, which is the
      // pre-fix behaviour. Recorded so a genuinely unopenable session is
      // observable rather than silently degrading every boot.
      debugPrint('[RestoringScreen] evidence session open failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'restoring_evidence_session_open_failed'));
    }
  }

  /// Local-evidence check for the [StartMissionBrief] / [DestinationUnknown]
  /// branches (closes-diagnose c2e9f4). Opens the Hive session first, then
  /// delegates to the pure predicate in `local_onboarding_evidence.dart`.
  /// Kill-switch `disable_local_onboarded_evidence` (§4.6) restores the pre-fix
  /// behaviour, where neither branch consulted local state at all.
  Future<bool> _hasLocalOnboardedEvidence() async {
    try {
      if (HiveService.instance.configBox.get('disable_local_onboarded_evidence') ==
          true) {
        return false;
      }
    } catch (_) {
      // configBox unavailable — keep the FIX on (safe direction).
    }
    await _ensureHiveSessionOpenForEvidence();
    try {
      return hasLocalOnboardedEvidence(
        hiveProfile: HiveService.instance.userBox.get('profile'),
        flagOnboarded:
            MigratedKey.readWithDefault<bool>('onboarding_completed', false),
      );
    } catch (e, st) {
      debugPrint('[RestoringScreen] local evidence read failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'restoring_local_evidence_read_failed'));
      return false;
    }
  }

  /// Navigate to /home. Returning users (Hive profile populated) take the
  /// background-restore path (home immediately, restore/heal continues in
  /// background); fresh installs or `disable_bg_restore` await the full
  /// restore first. Full reasoning: `lib/features/auth/CLAUDE.md` "Post-auth
  /// flow" + "Returning user waits >1 min" pitfall row; diagnoses 4e8b1d, c5a1f2.
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

    // Relocated from splash_screen._runDeferredInit (diagnose dc52a4) --
    // touches userBox, so MUST run AFTER HiveUserSession.openForUser above.

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
    // closes-diagnose: c2e9f4 — B-pass Finding 1 (P0). CONTINUE used to go to
    // /home unconditionally; with classification unresolved the stamp below was
    // skipped, so `_authRedirect` bounced /home → bare /onboarding, re-opening
    // this batch's own misroute through the escape hatch — for precisely its
    // target cohort (returning user, fresh reinstall, read failing the whole
    // 30s). `completeOnboarding`'s guard cannot save them either: it re-runs the
    // SAME SELECT under the SAME broken token and FAILS OPEN by design. A
    // wall-clock timer is not evidence that /home is safe — re-ask instead.
    if (!_committedToGoHome && userId != null) {
      if (await _hasLocalOnboardedEvidence()) {
        _committedToGoHome = true;
      } else {
        final retry =
            await AuthSessionBootstrapper.instance.resolveDestination(userId);
        switch (retry) {
          case GoHome():
            _committedToGoHome = true;
          case ResumeOnboarding(:final firstMissingStep):
            if (mounted) context.go('/onboarding/$firstMissingStep');
            return;
          case StartMissionBrief():
            // A genuine new user — unchanged destination for them.
            if (mounted) context.go('/onboarding/mission-brief');
            return;
          case DestinationUnknown(:final reason):
            // STILL unknown → stay. /home bounces to onboarding, and onboarding
            // is what destroys a real profile. CTA stays live so a tap retries.
            unawaited(ErrorTelemetry.logEvent(
                'restoring_continue_still_unknown',
                message: 'userId=${userId.substring(0, 8)} reason=$reason'));
            if (mounted) {
              setState(() {
                _statusLabel = 'Still connecting — tap again to retry.';
                _showTimeoutCta = true;
              });
            }
            return;
        }
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
