import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/exlog_key_migrator.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/nlog_key_migrator.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

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
  const RestoringScreen({super.key});

  @override
  ConsumerState<RestoringScreen> createState() => _RestoringScreenState();
}

class _RestoringScreenState extends ConsumerState<RestoringScreen> {
  bool _showTimeoutCta = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _showTimeoutCta = true);
    });
    _kickoffRestore();
  }

  Future<void> _kickoffRestore() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/');
      return;
    }

    // Parallel: profile lookup + start restore in background
    final profileFuture = supabase
        .from('user_profile')
        .select('user_id, onboarding_completed_at')
        .eq('user_id', user.id)
        .maybeSingle();

    final restoreFuture = SyncService.instance.restoreFromCloudForUser();

    final profile = await profileFuture;

    if (profile == null) {
      // Brand-new user with no profile row — cancel restore, go to Mission Brief
      SyncService.instance.cancelInflightRestore();
      if (mounted) context.go('/onboarding/mission-brief');
      return;
    }

    if (profile['onboarding_completed_at'] == null) {
      // Plan A reconciliation (relocated from splash_screen during the
      // Test #4 → Test #5 merge). OBS-3 root cause: returning user has a
      // populated user_profile row (goal/experience/weight all set) but
      // onboarding_completed_at was never stamped on the cloud. Without
      // this, RestoringScreen would route them back through onboarding
      // every cold start. Self-heal-stamp instead.
      final hiveProfile = HiveService.instance.userBox.get('profile');
      final hiveProfileMap = hiveProfile is Map ? hiveProfile : null;
      final hasCorePlanFields = hiveProfileMap != null &&
          hiveProfileMap['primary_goal'] != null &&
          hiveProfileMap['fitness_experience'] != null &&
          hiveProfileMap['current_weight_kg'] != null;
      // audit-2026-05-16 reader-side / F3-2.1 — onboarding_completed
      // moved to userBox via MigratedKey (Test #11.1, UserConfigMigrator
      // v2). Reading from configBox directly returns the legacy/empty
      // value for any device that's run the migration → fresh-install
      // self-heal misclassifies onboarded users as new. Use MigratedKey
      // so we read whichever store the migration left the value in.
      // closes-diagnose: 2026-05-16-onboarding-triplicate-storage
      final flagOnboarded =
          MigratedKey.readWithDefault<bool>('onboarding_completed', false);

      if (flagOnboarded || hasCorePlanFields) {
        debugPrint(
          '[RestoringScreen] self-heal: cloud onboarding_completed_at is '
          'NULL but Hive profile is populated — stamping now.',
        );
        // Fire-and-forget — non-fatal if it fails; next launch retries.
        unawaited(_stampOnboardingCompletedAt(user.id).catchError((e) {
          debugPrint('[RestoringScreen] self-heal stamp failed: $e');
        }));
        // Treat as fully onboarded — await restore + go home.
        await restoreFuture;
        if (!mounted) return;
        await _ensureOwnershipBeforeHome(user.id);
        if (!mounted) return;
        context.go('/home');
        return;
      }

      // Mid-onboarding user — cancel restore, jump to first missing step
      SyncService.instance.cancelInflightRestore();
      if (mounted) {
        final route = await _resolveOnboardingResumeRoute(user.id);
        if (mounted) context.go(route);
      }
      return;
    }

    // Fully onboarded user — await restore then go home
    await restoreFuture;
    if (!mounted) return;
    await _ensureOwnershipBeforeHome(user.id);
    if (!mounted) return;
    context.go('/home');
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
        await SyncService.instance.restoreFromCloudForUser();
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
      unawaited(SyncService.instance.syncWorkoutData());
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
  }

  /// Looks at the user_profile row and returns the earliest missing onboarding
  /// step so the user can pick up where they left off.
  Future<String> _resolveOnboardingResumeRoute(String userId) async {
    try {
      final supabase = Supabase.instance.client;
      final profile = await supabase
          .from('user_profile')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (profile == null) return '/onboarding/mission-brief';
      if (profile['full_name'] == null) return '/onboarding/identity';
      if (profile['primary_goal'] == null) return '/onboarding/goal';
      if (profile['current_weight_kg'] == null) return '/onboarding/stats';
      if (profile['fitness_experience'] == null) return '/onboarding/details';
      return '/onboarding/plan';
    } catch (_) {
      return '/onboarding';
    }
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

  void _onContinueAnyway() {
    _timeoutTimer?.cancel();
    if (mounted) context.go('/home');
  }

  @override
  void dispose() {
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
              ValueListenableBuilder<String>(
                valueListenable: SyncService.instance.restoreProgressLabel,
                builder: (context, label, _) => Text(
                  label,
                  style: AppTypography.titleL.copyWith(fontSize: 22),
                  textAlign: TextAlign.center,
                ),
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
