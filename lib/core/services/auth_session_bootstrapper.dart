import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/injury_vocab.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';

/// Sealed-class-ish destination resolution for the post-sign-in router.
///
/// `RestoringScreen` and any silent re-auth path call
/// [AuthSessionBootstrapper.resolveDestination] to learn where to send
/// the user next — `goHome`, `resumeOnboarding('<step>')`, or
/// `startMissionBrief`.
sealed class PostSignInDestination {
  const PostSignInDestination();
}

/// Fully onboarded — sync restore can run; final stop is `/home`.
class GoHome extends PostSignInDestination {
  const GoHome();
}

/// Returning user with a `user_profile` row whose
/// `onboarding_completed_at` is still NULL. The bootstrapper inspects
/// the row's column nullness to pick the earliest missing step, and
/// the caller routes to `/onboarding/<step>`.
class ResumeOnboarding extends PostSignInDestination {
  final String firstMissingStep;
  const ResumeOnboarding(this.firstMissingStep);
}

/// Brand-new user — no `user_profile` row exists yet. Caller routes
/// to `/onboarding/mission-brief`.
class StartMissionBrief extends PostSignInDestination {
  const StartMissionBrief();
}

/// Single-owner post-sign-in hydration funnel.
///
/// Tech-debt audit 2026-05-20 finding A1 (god-provider extract) +
/// A9 (widget-layer direct Supabase): `auth_provider.dart` previously
/// did Postgres CRUD on three tables (`users`, `user_profile`,
/// `user_progress`) inline in `_ensureLocalUser`, AND
/// `restoring_screen.dart` ran its own `.from('user_profile').select()`
/// calls inside a Flutter widget. Both violations consolidated here.
///
/// Shape mirrors [WorkoutWriteService] / [HealthWriteService]:
///   - private constructor + static `instance` singleton.
///   - per-user mutex so concurrent `hydrateFromCloud(userId)` /
///     `resolveDestination(userId)` calls serialise rather than
///     racing on the read-modify-write of the local Hive profile map.
///   - all Supabase access goes through
///     [SupabaseService.instance.client] — never `Supabase.instance`
///     directly (matches §4.4 rule #4: no direct Supabase from non-
///     repository / non-service code).
///   - error reporting routed through
///     [ErrorTelemetry.recordNonFatal] (audit A11 pattern).
///
/// Public API:
///   - [resolveDestination] — pure read; the routing decision tree
///     (was `restoring_screen.dart` lines 50/59/228).
///   - [hydrateFromCloud] — writes (merge cloud → Hive, ToS sync,
///     plan regeneration). Was `_ensureLocalUser` lines 477-770.
///   - [pushOneSignalPlayerId] — extracted from `_syncOneSignalPlayerId`.
class AuthSessionBootstrapper {
  AuthSessionBootstrapper._();
  static final AuthSessionBootstrapper instance = AuthSessionBootstrapper._();

  /// Per-user mutex. Concurrent calls for the same user (RestoringScreen
  /// + token-refresh listener + manual retry) queue rather than racing.
  /// Map key is the Supabase user id.
  final Map<String, Completer<void>> _locks = {};

  SupabaseService get _supabase => SupabaseService.instance;
  HiveService get _hive => HiveService.instance;

  // ─────────────────────────────────────────────────────────────
  //  Public API
  // ─────────────────────────────────────────────────────────────

  /// Decision tree for "where do we send the user after sign-in?"
  ///
  /// Single live SELECT on `user_profile` for the current user:
  ///   - no row             → [StartMissionBrief]
  ///   - row + completed_at IS NOT NULL → [GoHome]
  ///   - row + completed_at IS NULL     → [ResumeOnboarding(firstMissingStep)]
  ///
  /// `firstMissingStep` is computed by scanning the row's columns in
  /// onboarding order — `identity` < `goal` < `stats` < `details` <
  /// `plan` (same order the screens are wired into the router).
  ///
  /// On Supabase error: returns [StartMissionBrief] as the conservative
  /// fallback — same behavior the legacy `_resolveOnboardingResumeRoute`
  /// catch-block had at `restoring_screen.dart:239`.
  Future<PostSignInDestination> resolveDestination(String userId) async {
    return _withLock(userId, () async {
      try {
        // NOTE: identity-step completion is detected via `date_of_birth`
        // (a real `user_profile` column written by the onboarding identity
        // screen → sync_profile.dart). Do NOT select `full_name` here — that
        // column lives on the `users` table, NOT `user_profile`; selecting it
        // raises PostgREST 42703 and the catch below silently degrades EVERY
        // user to StartMissionBrief. See diagnose 2026-05-30-resolve-
        // destination-full-name-drift.
        final row = await _supabase.client
            .from('user_profile')
            .select('user_id, onboarding_completed_at, date_of_birth, '
                'primary_goal, current_weight_kg, fitness_experience')
            .eq('user_id', userId)
            .maybeSingle();
        return classifyDestination(row);
      } catch (e, st) {
        debugPrint('[AuthSessionBootstrapper.resolveDestination] $e');
        unawaited(ErrorTelemetry.recordNonFatal(
          e,
          st,
          reason: 'auth_session_bootstrapper_resolve_destination',
          extra: {'user_id': userId},
        ));
        // Conservative fallback (matches legacy behaviour at
        // restoring_screen.dart:239 catch-block).
        return const StartMissionBrief();
      }
    });
  }

  /// Pure decision function. Visible-for-testing — given a
  /// `user_profile` row payload (or null for "no row"), returns the
  /// canonical destination. Has no side effects and no Supabase
  /// dependency, so unit tests can pin every branch without spinning
  /// up the SDK.
  ///
  /// Field-order is `identity → goal → stats → details → plan`,
  /// matching the order the onboarding screens are wired into the
  /// router.
  @visibleForTesting
  static PostSignInDestination classifyDestination(
      Map<String, dynamic>? row) {
    if (row == null) return const StartMissionBrief();
    if (row['onboarding_completed_at'] != null) return const GoHome();

    // Row exists but onboarding_completed_at IS NULL → resume.
    // `date_of_birth` is the identity-step sentinel (full_name is on the
    // `users` table, not user_profile — see diagnose 2026-05-30-resolve-
    // destination-full-name-drift).
    if (row['date_of_birth'] == null) {
      return const ResumeOnboarding('identity');
    }
    if (row['primary_goal'] == null) {
      return const ResumeOnboarding('goal');
    }
    if (row['current_weight_kg'] == null) {
      return const ResumeOnboarding('stats');
    }
    if (row['fitness_experience'] == null) {
      return const ResumeOnboarding('details');
    }
    return const ResumeOnboarding('plan');
  }

  /// Long-running post-sign-in cloud hydration.
  ///
  /// Extracted verbatim from the inline block at
  /// `auth_provider.dart._ensureLocalUser` lines 477-770. Owns:
  ///
  ///   - public.users upsert (id, email, full_name, created_at) with
  ///     `ignoreDuplicates: true` so the email-prefix seed is set only
  ///     on first signup.
  ///   - `last_active_at` update.
  ///   - H-3 (audit 2026-05-11) full_name self-heal: if local Hive
  ///     profile carries a real name, push it up — overwrites the
  ///     email-prefix seed.
  ///   - ToS/Privacy acceptance sync (Hive → cloud).
  ///   - F2/F3 user_profile cloud → Hive merge (always pulls, even
  ///     for same-user re-login — fixes stale avatar/banner).
  ///   - user_progress restore.
  ///   - ai_chat_started_at + terms_accepted_at hydration.
  ///   - Local workout schedule regeneration if missing.
  ///   - Last-ditch gap-closer: pushes Hive profile if cloud row
  ///     missing.
  ///   - Early-stage SubscriptionService.refreshFromSupabase fast path.
  ///
  /// All exceptions are caught + routed to ErrorTelemetry. Callers
  /// (the `_ensureLocalUser` orchestrator in auth_provider) wrap this
  /// in their own outer catch so the cross-account guard + verify-
  /// after-clear semantics are preserved at the orchestration layer.
  Future<void> hydrateFromCloud(User user) async {
    final userId = user.id;
    await _withLock(userId, () async {
      final userBox = _hive.userBox;
      final existing = userBox.get('profile');

      // ─── public.users upsert + last_active + ToS sync ──────────
      try {
        await _supabase.client.from('users').upsert({
          'id': user.id,
          'email': user.email ?? '',
          'full_name': user.userMetadata?['full_name'] ??
              ((user.email?.isNotEmpty == true)
                  ? user.email!.split('@').first
                  : 'User'),
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'id', ignoreDuplicates: true);

        // Always update last_active_at (safe — doesn't touch full_name).
        await _supabase.client.from('users').update({
          'last_active_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', user.id);

        // H-3 (audit-2026-05-11) full_name self-heal.
        final localProfile = userBox.get('profile');
        if (localProfile is Map) {
          final localName = (localProfile['full_name'] as String?)?.trim();
          final emailPrefix = (user.email?.contains('@') == true)
              ? user.email!.split('@').first
              : null;
          final looksReal = localName != null &&
              localName.isNotEmpty &&
              RegExp(r'[A-Za-z]').hasMatch(localName) &&
              localName != emailPrefix;
          if (looksReal) {
            await _supabase.client
                .from('users')
                .update({'full_name': localName}).eq('id', user.id);
          }
        }

        // Sync ToS/Privacy acceptance from Hive (stamped by TermsModal).
        final termsAcceptedAt = userBox.get('terms_accepted_at');
        final termsVersion = userBox.get('terms_version');
        if (termsAcceptedAt is String && termsAcceptedAt.isNotEmpty) {
          await _supabase.client.from('users').update({
            'terms_accepted_at': termsAcceptedAt,
            if (termsVersion is String && termsVersion.isNotEmpty)
              'terms_version': termsVersion,
          }).eq('id', user.id);
        }
      } catch (e, st) {
        // Bug A defense (2026-04-26): silent-swallow let an orphan
        // public.users row block sync for 48h. Route through canonical
        // ErrorTelemetry so 23505/23503 violations surface (audit A11).
        String errorType = 'users_upsert_failed';
        final eStr = e.toString();
        if (eStr.contains('23505')) {
          errorType = 'users_unique_violation_23505';
        }
        if (eStr.contains('23503')) {
          errorType = 'users_fk_violation_23503';
        }
        debugPrint('[AuthSessionBootstrapper.hydrateFromCloud] '
            'users upsert failed: $e');
        unawaited(ErrorTelemetry.recordNonFatal(
          e,
          st,
          reason: errorType,
          extra: {
            'user_id': user.id,
            'platform': 'android',
            'error_message_preview':
                eStr.length > 1000 ? eStr.substring(0, 1000) : eStr,
          },
        ));
      }

      // ─── user_profile cloud → Hive merge (F2/F3) ───────────────
      try {
        final supabase = _supabase.client;
        final profileRows = await supabase
            .from('user_profile')
            .select()
            .eq('user_id', user.id)
            .limit(1);

        final cloudHasRealData = profileRows.isNotEmpty &&
            (profileRows.first['primary_goal'] != null ||
                profileRows.first['height_cm'] != null);

        final existingMap =
            existing is Map ? Map<String, dynamic>.from(existing) : null;
        final hiveHasRealData = existingMap != null &&
            (existingMap['primary_goal'] != null ||
                existingMap['height_cm'] != null);

        if (cloudHasRealData) {
          // Merge cloud → Hive. Cloud wins for non-null fields; Hive
          // values survive for fields the cloud left null (F2).
          final cloud = Map<String, dynamic>.from(profileRows.first);
          final merged = <String, dynamic>{
            ...?existingMap,
            for (final e in cloud.entries)
              if (e.value != null) e.key: e.value,
          };
          merged['id'] = user.id;
          merged['email'] = user.email;
          // Restore-class hydration → skipSync (audit A4).
          await ProfileWriteService.instance
              .updateProfile(merged, skipSync: true);
          await MigratedKey.write('onboarding_completed', true);

          // Also pull progress (rare to have local progress before login).
          try {
            final progressRows = await supabase
                .from('user_progress')
                .select()
                .eq('user_id', user.id)
                .limit(1);
            if (progressRows.isNotEmpty) {
              final existingProgress = userBox.get('progress');
              final existingProgressMap = existingProgress is Map
                  ? Map<String, dynamic>.from(existingProgress)
                  : <String, dynamic>{};
              final cloudProgress =
                  Map<String, dynamic>.from(progressRows.first);
              final mergedProgress = <String, dynamic>{
                ...existingProgressMap,
                for (final e in cloudProgress.entries)
                  if (e.value != null) e.key: e.value,
              };
              await userBox.put('progress', mergedProgress);
            }

            // Hydrate terms acceptance.
            final userRows = await supabase
                .from('users')
                .select('terms_accepted_at, terms_version')
                .eq('id', user.id)
                .limit(1);
            if (userRows.isNotEmpty) {
              final serverTermsAt =
                  userRows.first['terms_accepted_at'] as String?;
              final serverTermsVersion =
                  userRows.first['terms_version'] as String?;
              if (serverTermsAt != null && serverTermsAt.isNotEmpty) {
                final localTermsAt = userBox.get('terms_accepted_at');
                if (localTermsAt == null) {
                  await userBox.put('terms_accepted_at', serverTermsAt);
                  if (serverTermsVersion != null) {
                    await userBox.put('terms_version', serverTermsVersion);
                  }
                }
              }
            }

            // Regenerate workout schedule locally if plan is missing.
            if (!WorkoutScheduleService.instance.hasPlan() &&
                MigratedKey.read<bool>('onboarding_completed') == true) {
              final goal =
                  merged['primary_goal'] as String? ?? 'general_fitness';
              final equipment =
                  merged['equipment_access'] as String? ?? 'basic_gym';
              final daysPerWeek =
                  (merged['days_per_week'] as num?)?.toInt() ?? 4;
              final experience =
                  merged['fitness_experience'] as String? ?? 'beginner';
              final phase = progressRows.isNotEmpty
                  ? ((progressRows.first['current_phase'] as int?) ?? 1)
                  : 1;
              // U4: thread injuries so the login-restore plan regen excludes
              // contraindicated exercises (vocab canonicalized in generateV4).
              final injuries = InjuryVocab.fromProfile(merged['injuries']);

              DateTime startDate;
              if (progressRows.isNotEmpty) {
                final genStr =
                    progressRows.first['phase_started_at'] as String?;
                startDate = genStr != null
                    ? DateTime.tryParse(genStr) ?? DateTime.now()
                    : DateTime.now();
              } else {
                startDate = DateTime.now();
              }

              try {
                await WorkoutScheduleService.instance.generateAndSchedule(
                  goal: goal,
                  equipment: equipment,
                  daysPerWeek: daysPerWeek,
                  startDate: startDate,
                  experienceLevel: experience,
                  phase: phase,
                  injuries: injuries, // U4
                );
              } catch (genErr, genSt) {
                debugPrint(
                    'Plan generation failed on login restore: $genErr');
                unawaited(ErrorTelemetry.recordNonFatal(
                  genErr,
                  genSt,
                  reason: 'auth_session_bootstrapper_login_plan_gen_failed',
                ));
              }
            }
          } catch (e, st) {
            debugPrint(
                '[AuthSessionBootstrapper] Progress/trial restore failed: $e');
            unawaited(ErrorTelemetry.recordNonFatal(
              e,
              st,
              reason: 'auth_session_bootstrapper_progress_trial_restore',
            ));
          }
        } else if (hiveHasRealData) {
          // F3 · Hive is the source of truth; cloud is stale/empty.
          // Push Hive → cloud to repair instead of routing to onboarding.
          await MigratedKey.write('onboarding_completed', true);
          unawaited(SyncService.instance.syncProfileNow(user.id));
        } else {
          // Neither has real data → genuine new user.
          if (profileRows.isNotEmpty) {
            // Delete empty cloud row so onboarding's upsert creates fresh.
            try {
              await supabase
                  .from('user_profile')
                  .delete()
                  .eq('user_id', user.id);
            } catch (_) {}
          }
          // Edge case: users.onboarding_completed=true but user_profile wiped.
          final userRows = await supabase
              .from('users')
              .select('onboarding_completed')
              .eq('id', user.id)
              .limit(1);
          if (userRows.isNotEmpty &&
              (userRows.first['onboarding_completed'] as bool?) == true) {
            await MigratedKey.write('onboarding_completed', true);
          }
        }
      } catch (e, st) {
        debugPrint(
            '[AuthSessionBootstrapper.hydrateFromCloud] restore query failed: $e');
        unawaited(ErrorTelemetry.recordNonFatal(
          e,
          st,
          reason: 'auth_session_bootstrapper_restore_query_failed',
          extra: {'user_id': user.id},
        ));
      }

      // ─── Minimal local profile stub for brand-new users ────────
      // Audit 2026-05-20 A4 — routed through canonical write service.
      // skipSync: true because the user_profile cloud row is created
      // by the onboarding sync path; the minimal stub here doesn't yet
      // have the foreign-key fields the upsert would need.
      if (userBox.get('profile') == null) {
        await ProfileWriteService.instance.updateProfile(
          {
            'id': user.id,
            'email': user.email,
            'created_at': DateTime.now().toIso8601String(),
          },
          skipSync: true,
        );
      }

      // Last-ditch gap closer: if cloud still has no user_profile row,
      // push Hive now. Rare — F3 branch above already handled the main case.
      _pushProfileToSupabaseIfMissing(user.id);

      // F1 · Early-stage subscription refresh.
      unawaited(SubscriptionService.instance.refreshFromSupabase());
    });
  }

  /// Reads OneSignal's current push subscription id and upserts it onto
  /// `user_progress.onesignal_player_id`. Fire-and-forget — failure
  /// must never block auth. Idempotent: same id → upsert is a no-op.
  ///
  /// Extracted from `auth_provider._syncOneSignalPlayerId` (Test #11.1
  /// requirement: persist player_id so delete-account Edge Function
  /// can unsubscribe pushes when the user erases their account).
  Future<void> pushOneSignalPlayerId(String userId, String playerId) async {
    if (playerId.isEmpty) return;
    try {
      await _supabase.client.from('user_progress').upsert({
        'user_id': userId,
        'onesignal_player_id': playerId,
      }, onConflict: 'user_id');
    } catch (e, st) {
      debugPrint('[AuthSessionBootstrapper.pushOneSignalPlayerId] $e');
      unawaited(ErrorTelemetry.recordNonFatal(
        e,
        st,
        reason: 'auth_session_bootstrapper_push_onesignal_player_id',
        extra: {'user_id': userId},
      ));
    }
  }

  /// Convenience wrapper: read OneSignal's push subscription id at the
  /// call site (only available on non-web) and forward to
  /// [pushOneSignalPlayerId]. Used by `auth_provider._ensureLocalUser`.
  Future<void> syncCurrentOneSignalPlayerId(String userId) async {
    if (kIsWeb) return;
    try {
      final playerId = OneSignal.User.pushSubscription.id;
      if (playerId == null || playerId.isEmpty) return;
      await pushOneSignalPlayerId(userId, playerId);
    } catch (e, st) {
      debugPrint('[AuthSessionBootstrapper.syncCurrentOneSignalPlayerId] $e');
      unawaited(ErrorTelemetry.recordNonFatal(
        e,
        st,
        reason: 'auth_session_bootstrapper_sync_current_player_id',
      ));
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Internals
  // ─────────────────────────────────────────────────────────────

  /// Checks if `user_profile` row is missing in Supabase and pushes
  /// local Hive profile if so. Fire-and-forget — never blocks sign-in.
  void _pushProfileToSupabaseIfMissing(String userId) async {
    try {
      final rows = await _supabase.client
          .from('user_profile')
          .select('user_id')
          .eq('user_id', userId)
          .limit(1);
      if (rows.isEmpty) {
        await SyncService.instance.syncProfileNow(userId);
        debugPrint(
            '[AuthSessionBootstrapper] Gap detected — pushed missing user_profile.');
      }
    } catch (_) {
      // Offline — SyncService.checkAndSync() will handle on next launch.
    }
  }

  /// Per-user mutex helper. Concurrent calls for the same userId queue;
  /// calls for different users run independently.
  Future<T> _withLock<T>(String userId, Future<T> Function() op) async {
    while (_locks[userId] != null) {
      try {
        await _locks[userId]!.future;
      } catch (_) {/* swallowed; holder will release */}
    }
    final c = Completer<void>();
    _locks[userId] = c;
    try {
      return await op();
    } finally {
      _locks.remove(userId);
      if (!c.isCompleted) c.complete();
    }
  }
}
