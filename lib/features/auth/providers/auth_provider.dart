import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/user_config_migrator.dart';
import 'package:icanbefitter/core/services/logging_type_repair_migrator.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

// ── Auth State Stream ───────────────────────────────────────────

/// Streams Supabase auth state changes (sign-in, sign-out, token refresh).
/// Returns an empty stream if Supabase is not yet initialized.
final authStateProvider = StreamProvider<AuthState>((ref) {
  try {
    return SupabaseService.instance.client.auth.onAuthStateChange;
  } catch (_) {
    return const Stream.empty();
  }
});

/// Returns the currently authenticated Supabase [User], or null.
/// Returns null if Supabase is not yet initialized.
final currentUserProvider = Provider<User?>((ref) {
  try {
    return SupabaseService.instance.currentUser;
  } catch (_) {
    return null;
  }
});

// ── Auth Notifier ───────────────────────────────────────────────

/// Possible states during an auth operation.
enum AuthStatus { idle, loading, success, error }

class AuthState2 {
  final AuthStatus status;
  final String? errorMessage;
  final bool otpSent;

  const AuthState2({
    this.status = AuthStatus.idle,
    this.errorMessage,
    this.otpSent = false,
  });

  AuthState2 copyWith({
    AuthStatus? status,
    String? errorMessage,
    bool? otpSent,
  }) {
    return AuthState2(
      status: status ?? this.status,
      errorMessage: errorMessage,
      otpSent: otpSent ?? this.otpSent,
    );
  }
}

class AuthNotifier extends Notifier<AuthState2> {
  @override
  AuthState2 build() => const AuthState2();

  SupabaseService get _supabase => SupabaseService.instance;
  HiveService get _hive => HiveService.instance;

  /// Ensures Supabase is initialized, attempting initialization if needed.
  /// Returns false and sets an error state if it cannot be initialized.
  Future<bool> _ensureSupabaseReady() async {
    if (_supabase.isInitialized) return true;
    try {
      await _supabase.initialize();
      return true;
    } catch (e) {
      // Surface build-config errors clearly; everything else is a connectivity issue.
      final msg = e is StateError
          ? e.message
          : 'Connection failed. Please check your internet and try again.';
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: msg,
      );
      return false;
    }
  }

  /// Sign in with email + password.
  Future<void> signInWithEmail(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    if (!await _ensureSupabaseReady()) return;
    try {
      final response = await _supabase.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Sign in failed. Please check your credentials.',
        );
        return;
      }

      await _ensureLocalUser(response.user!);
      state = state.copyWith(status: AuthStatus.success);
    } on AuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: '[${e.runtimeType}] ${e.toString().split('\n').first}',
      );
    }
  }

  /// Create a new account with email + password.
  Future<void> signUpWithEmail(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    if (!await _ensureSupabaseReady()) return;
    try {
      final response = await _supabase.client.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user == null) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Sign up failed. Please try again.',
        );
        return;
      }

      // If identities is empty, the user already exists but hasn't confirmed
      // their email — Supabase returns a fake success to prevent user enumeration.
      if (response.user!.identities != null &&
          response.user!.identities!.isEmpty) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage:
              'An account with this email already exists. Please sign in.',
        );
        return;
      }

      // Email confirmation enabled → session is null, user must confirm email.
      if (response.session == null) {
        // Still try to set up local state, but don't require it to succeed.
        try {
          await _ensureLocalUser(response.user!);
        } catch (_) {}
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage:
              'Check your email for a confirmation link, then sign in.',
        );
        return;
      }

      // Session present → signed in immediately (email confirmation off).
      try {
        await _ensureLocalUser(response.user!);
      } on StateError catch (e) {
        // Test #10.1 — cross-account guard's verify-after-clear failed
        // (poisoned local state would leak into this session). The
        // guard already force-signed-out; surface the failure to UI.
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage:
              'Couldn’t clean up the previous session. Please sign in again.',
        );
        debugPrint('[signUpWithEmail] poisoned-clear escalation: $e');
        return;
      } catch (_) {
        // Other local setup failures are non-fatal — auth succeeded.
      }
      state = state.copyWith(status: AuthStatus.success);
    } on AuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Sign up failed: ${e.toString().split('\n').first}',
      );
    }
  }

  /// Sign in with Google OAuth.
  Future<void> signInWithGoogle() async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    if (!await _ensureSupabaseReady()) return;
    try {
      await _supabase.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.icanbefitter://login-callback/',
      );
    } on AuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Google sign-in failed. Please try again.',
      );
    }
  }

  /// Send OTP to the given phone number (E.164 format).
  Future<void> signInWithPhone(String phone) async {
    state = state.copyWith(
      status: AuthStatus.loading,
      errorMessage: null,
      otpSent: false,
    );
    if (!await _ensureSupabaseReady()) return;
    try {
      await _supabase.client.auth.signInWithOtp(phone: phone);
      state = state.copyWith(status: AuthStatus.idle, otpSent: true);
    } on AuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Failed to send OTP. Please try again.',
      );
    }
  }

  /// Verify the OTP sent to [phone].
  Future<void> verifyOtp(String phone, String otp) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      final response = await _supabase.client.auth.verifyOTP(
        phone: phone,
        token: otp,
        type: OtpType.sms,
      );

      if (response.user == null) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Invalid OTP. Please try again.',
        );
        return;
      }

      await _ensureLocalUser(response.user!);
      state = state.copyWith(status: AuthStatus.success);
    } on AuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'OTP verification failed. Please try again.',
      );
    }
  }

  /// Sign the user out of Supabase.
  ///
  /// Sign out BEFORE clearing Hive so the router never sees
  /// authenticated + !onboarded which would redirect to /onboarding.
  Future<void> signOut() async {
    try {
      await UserRepository.instance.clearAllData();
    } catch (e) {
      debugPrint('[auth/signOut] clearAllData failed: $e');
    }
    try {
      await HiveUserSession.deleteAllFilesForCurrentUser();
    } catch (e) {
      debugPrint('[auth/signOut] deleteAllFilesForCurrentUser failed: $e');
    }
    try {
      await _supabase.client.auth.signOut();
    } catch (e) {
      debugPrint('[auth/signOut] supabase signOut failed: $e');
    }
    state = const AuthState2(status: AuthStatus.idle);
  }

  /// Reset back to idle.
  void resetState() {
    state = const AuthState2();
  }

  /// Back out of the OTP step to the phone-input step (keeps other state
  /// idle, so the UI re-renders the phone entry view and lets the user
  /// edit their number instead of being stuck on OTP entry).
  void resetPhoneFlow() {
    state = state.copyWith(
      status: AuthStatus.idle,
      otpSent: false,
    );
  }

  // ── Private ───────────────────────────────────────────────────

  /// Ensures local Hive state is correct after sign-in.
  ///
  /// If the user previously completed onboarding (has a profile in Supabase),
  /// restores the onboarding flag so they skip onboarding on re-login.
  Future<void> _ensureLocalUser(User user) async {
    // Layer 2.3 — open per-user namespaced boxes FIRST, before any code
    // reads user-scoped Hive. Idempotent — re-running for same user is a no-op.
    // Different user → previous boxes closed first.
    await HiveUserSession.openForUser(user.id);

    final userBox = _hive.userBox;
    final existing = userBox.get('profile');

    // B1 layer 2/3: Cross-account safety net — checks if existing profile id
    // mismatches new user.id (leftover from failed/incomplete sign-out).
    // Test #5 Plan A: removed the second arm via 'last_authenticated_user_id'
    // because HiveUserSession.openForUser (called above) provides the same
    // isolation guarantee for per-user namespaced boxes.
    bool needsClear = false;
    String? clearReason;

    if (existing != null) {
      final existingId = (existing as Map<dynamic, dynamic>?)?['id'] as String?;
      if (existingId == null || existingId != user.id) {
        needsClear = true;
        clearReason = 'profile id mismatch (had=$existingId, now=${user.id})';
      }
    }
    // Test #5 Plan A note: the second arm of the guard ('last_authenticated_user_id'
    // mismatch via syncBox) is no longer needed because HiveUserSession.openForUser
    // (called above on line 317) opens per-user namespaced boxes, providing the
    // same isolation guarantee. Stamping last_authenticated_user_id is also
    // unnecessary — HiveUserSession.currentOwnerFullId is now the canonical
    // ownership marker, set by openForUser itself.
    if (needsClear) {
      debugPrint('[auth/_ensureLocalUser] Cross-account guard fired: $clearReason. Clearing Hive.');
      final clearResult = await UserRepository.instance.clearAllData();

      // Test #10.1 — verify-after-clear. Pre-fix, `clearAllData()` could
      // silently partial-fail (one GuardedBox throw aborted the chain),
      // leaving stale `userBox['profile']` and configBox flags behind →
      // the next user inherited the previous user's data.
      // Now: re-read the keys that define the leak and force-signOut
      // if either survived.
      final reCheckProfile = userBox.get('profile');
      final reCheckOnboarded = userBox.get('onboarding_completed');
      final reCheckConfigOnboarded =
          MigratedKey.read<bool>('onboarding_completed') == true;
      if (reCheckProfile != null ||
          reCheckOnboarded == true ||
          reCheckConfigOnboarded ||
          clearResult.hasFailures) {
        debugPrint(
            '[auth/_ensureLocalUser] CRITICAL: clearAllData partial-failed. '
            'profile=$reCheckProfile, onboarded=$reCheckOnboarded, '
            'configOnboarded=$reCheckConfigOnboarded, '
            'clearFailures=${clearResult.failures}');
        // Force-signOut so user lands on /sign-in instead of a poisoned
        // home screen. Throws so signUpWithEmail/signInWithEmail can
        // surface the failure.
        try {
          await _supabase.client.auth.signOut();
        } catch (_) {}
        throw StateError(
            'Cross-account clear partial-failed; signed out for safety.');
      }
    }

    // Test #10.1 — Move user-specific keys from shared `configBox` into
    // per-user `userBox` (one-shot per device, gated by migrationBox).
    // MUST run AFTER the cross-account guard so we don't migrate stale
    // keys from a previous session into the new user's box.
    try {
      await UserConfigMigrator.runIfNeeded();
    } catch (e) {
      debugPrint('[auth/_ensureLocalUser] config→user migration failed: $e');
      // Non-fatal — readers will see legacy configBox values until next
      // launch. Cross-account guard would still clear them if needed.
    }

    // APK Test #12.2 / Task #2b — one-shot self-repair migration that
    // walks every `exlog_*` row and corrects `logging_type` drift left
    // by pre-Test-#12 swap state retention. Idempotent (gated by
    // migrationBox flag). Non-fatal on failure — next launch retries.
    try {
      await LoggingTypeRepairMigrator.runIfNeeded();
    } catch (e) {
      debugPrint('[auth/_ensureLocalUser] logging_type repair failed: $e');
    }

    // Ensure user exists in public.users table (Edge Functions need this).
    // Uses ignoreDuplicates so full_name + created_at are only set once
    // (on first sign-up) and never overwritten on subsequent sign-ins.
    try {
      await _supabase.client.from('users').upsert({
        'id': user.id,
        'email': user.email ?? '',
        'full_name': user.userMetadata?['full_name'] ?? ((user.email?.isNotEmpty == true) ? user.email!.split('@').first : 'User'),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'id', ignoreDuplicates: true);

      // Always update last_active_at (safe — doesn't touch full_name)
      await _supabase.client.from('users').update({
        'last_active_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', user.id);

      // Sync ToS/Privacy acceptance from Hive (stamped by TermsModal).
      // Only writes if Hive has a value — never overwrites a server-side
      // timestamp with null.
      final termsAcceptedAt = userBox.get('terms_accepted_at');
      final termsVersion = userBox.get('terms_version');
      if (termsAcceptedAt is String && termsAcceptedAt.isNotEmpty) {
        await _supabase.client.from('users').update({
          'terms_accepted_at': termsAcceptedAt,
          if (termsVersion is String && termsVersion.isNotEmpty)
            'terms_version': termsVersion,
        }).eq('id', user.id);
      }
    } catch (e) {
      debugPrint('[_ensureLocalUser] users table upsert failed: $e');
      // Bug A defense (2026-04-26): silent-swallow let an orphan public.users
      // row block sync for 48h. Surface PostgrestException codes 23505 / 23503
      // to the cloud so future failures are auditable across devices.
      String errorType = 'users_upsert_failed';
      final eStr = e.toString();
      if (eStr.contains('23505')) errorType = 'users_unique_violation_23505';
      if (eStr.contains('23503')) errorType = 'users_fk_violation_23503';
      // Posts to the `log-client-error` Edge Function (see _logClientError).
      unawaited(_logClientError(user.id, errorType, eStr));
      // Non-fatal for sign-in flow, but AI chat / sync may fail until
      // resolved. Now visible in client_errors instead of only debugPrint.
    }

    // F2/F3 · Always pull the cloud profile on sign-in and merge into Hive.
    // Previously guarded by `if (existing == null)` — which meant a same-user
    // re-login kept stale Hive data (avatar_url/banner_url etc.) and never
    // refreshed. Now we always pull; merge logic below picks the right source
    // per field.
    try {
      final supabase = _supabase.client;
      final profileRows = await supabase
          .from('user_profile')
          .select()
          .eq('user_id', user.id)
          .limit(1);

      // Does the cloud row have any real onboarding-provided data? An all-null
      // row can exist because an old sync mapped only 12 fields or a failed
      // write created an empty row. "Real data" = goal set OR height known.
      final cloudHasRealData = profileRows.isNotEmpty &&
          (profileRows.first['primary_goal'] != null ||
              profileRows.first['height_cm'] != null);

      // Does Hive already have real data? (email-only stubs don't count.)
      final existingMap =
          existing is Map ? Map<String, dynamic>.from(existing) : null;
      final hiveHasRealData = existingMap != null &&
          (existingMap['primary_goal'] != null ||
              existingMap['height_cm'] != null);

      if (cloudHasRealData) {
        // Merge cloud → Hive. Cloud wins for every non-null field it provides;
        // Hive values survive for fields the cloud left null (covers mid-flight
        // local edits that haven't synced back up yet). F2 behaviour.
        final cloud = Map<String, dynamic>.from(profileRows.first);
        final merged = <String, dynamic>{
          ...?existingMap,
          for (final e in cloud.entries)
            if (e.value != null) e.key: e.value,
        };
        merged['id'] = user.id;
        merged['email'] = user.email;
        await userBox.put('profile', merged);
        await MigratedKey.write('onboarding_completed', true);

        // Also pull progress (same merge semantics — rare to have local
        // progress before login anyway).
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

          // Hydrate AI trial start + terms acceptance from server.
          // terms_accepted_at is synced so TermsModal never re-fires on a
          // new device when the user already accepted on another device.
          final userRows = await supabase
              .from('users')
              .select('ai_chat_started_at, terms_accepted_at, terms_version')
              .eq('id', user.id)
              .limit(1);
          if (userRows.isNotEmpty) {
            final serverTrialStart =
                userRows.first['ai_chat_started_at'] as String?;
            if (serverTrialStart != null) {
              await MigratedKey.write('ai_trial_start', serverTrialStart);
            }
            // Restore terms acceptance so TermsModal skips on new devices.
            final serverTermsAt =
                userRows.first['terms_accepted_at'] as String?;
            final serverTermsVersion =
                userRows.first['terms_version'] as String?;
            if (serverTermsAt != null && serverTermsAt.isNotEmpty) {
              // Only write if Hive doesn't already have a stamp — local
              // timestamp is more precise (it came from this device's user
              // interaction) and should not be overwritten by a cloud value.
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
            final goal = merged['primary_goal'] as String? ?? 'general_fitness';
            final equipment =
                merged['equipment_access'] as String? ?? 'basic_gym';
            final daysPerWeek =
                (merged['days_per_week'] as num?)?.toInt() ?? 4;
            final experience =
                merged['fitness_experience'] as String? ?? 'beginner';
            final phase = progressRows.isNotEmpty
                ? ((progressRows.first['current_phase'] as int?) ?? 1)
                : 1;

            DateTime startDate;
            if (progressRows.isNotEmpty) {
              final genStr = progressRows.first['phase_started_at'] as String?;
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
              );
            } catch (genErr) {
              debugPrint('Plan generation failed on login restore: $genErr');
            }
          }
        } catch (e) {
          debugPrint('Progress/trial restore failed: $e');
        }
      } else if (hiveHasRealData) {
        // F3 · Hive is the source of truth; cloud is stale or empty. Push
        // Hive → cloud to repair the row instead of falsely routing the user
        // to onboarding. Treat as onboarded since Hive has real data.
        await MigratedKey.write('onboarding_completed', true);
        unawaited(SyncService.instance.syncProfileNow(user.id));
      } else {
        // Neither Hive nor cloud has real data → genuine new user.
        // Fall through: minimal profile creation below will run.
        if (profileRows.isNotEmpty) {
          // Delete the empty cloud row so onboarding's upsert creates fresh.
          try {
            await supabase
                .from('user_profile')
                .delete()
                .eq('user_id', user.id);
          } catch (_) {}
        }
        // Also read users.onboarding_completed to handle edge cases where
        // the users row has the flag but user_profile got wiped.
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
    } catch (e) {
      // Supabase query failed (offline or table missing). Proceed with
      // whatever Hive has; next sync cycle will reconcile.
      debugPrint('[Auth] Supabase restore query failed: $e');
    }

    // Create minimal local profile if nothing was restored and Hive is still
    // empty (genuine new user, or offline with no prior local data).
    if (userBox.get('profile') == null) {
      await userBox.put('profile', {
        'id': user.id,
        'email': user.email,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    // Last-ditch gap closer: if cloud still has no user_profile row, push
    // Hive now. Rare — the F3 branch above already handled the main case.
    _pushProfileToSupabaseIfMissing(user.id);

    // F1 · Early-stage subscription refresh — fires immediately on sign-in
    // so the UI gets PRO state before RestoringScreen starts the full
    // restore. The canonical subscription refresh is now ALSO folded into
    // SyncService.restoreFromCloudForUser (Theme A3, APK Test #11) as the
    // last restore step, making it atomic with freeze/inbox/rank pulls.
    // This call is kept as a fast-path fallback for any sign-in flow that
    // does not go through RestoringScreen (e.g. silent re-auth on token
    // refresh). Both calls are idempotent — refreshFromSupabase has its
    // own grace-period guard so a double-call within the same session is
    // cheap.
    unawaited(SubscriptionService.instance.refreshFromSupabase());

    // Bind OneSignal external_id to Supabase user UUID for push targeting.
    // Test #11.1: also persist the OneSignal player_id (subscription id)
    // to `user_progress.onesignal_player_id` so the `delete-account` Edge
    // Function can unsubscribe pushes when the user erases their account.
    // Without this, deleted accounts may keep receiving push notifications
    // until the OS uninstalls the app (migration 049 added the column but
    // no client-side write existed).
    if (!kIsWeb) {
      try {
        await OneSignal.login(user.id);
        unawaited(_syncOneSignalPlayerId(user.id));
      } catch (_) {
        // Non-critical — push notifications will still work on next launch.
      }
    }
  }

  /// Reads OneSignal's current push subscription id and upserts it onto
  /// `user_progress.onesignal_player_id`. Fire-and-forget — failure here
  /// must never block auth. Idempotent: same id → upsert is a no-op.
  Future<void> _syncOneSignalPlayerId(String userId) async {
    try {
      final playerId = OneSignal.User.pushSubscription.id;
      if (playerId == null || playerId.isEmpty) return;
      await _supabase.client.from('user_progress').upsert({
        'user_id': userId,
        'onesignal_player_id': playerId,
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('[auth_provider._syncOneSignalPlayerId] $e');
    }
  }

  /// Posts a single error event to the `log-client-error` Edge Function.
  /// Fire-and-forget. Catches its own errors so logging never throws.
  Future<void> _logClientError(
    String userId,
    String errorType,
    String message,
  ) async {
    try {
      await _supabase.client.functions.invoke(
        'log-client-error',
        body: {
          'user_id': userId,
          'error_type': errorType,
          'message': message.length > 1000
              ? message.substring(0, 1000)
              : message,
          'source': 'auth_provider._ensureLocalUser',
        },
      );
    } catch (_) {
      // Swallow — error logging must never break the host flow.
    }
  }

  /// Checks if user_profile row is missing in Supabase and pushes local
  /// Hive profile if so. Fire-and-forget — never blocks sign-in.
  void _pushProfileToSupabaseIfMissing(String userId) async {
    try {
      final rows = await _supabase.client
          .from('user_profile')
          .select('user_id')
          .eq('user_id', userId)
          .limit(1);
      if (rows.isEmpty) {
        await SyncService.instance.syncProfileNow(userId);
        debugPrint('[Auth] Gap detected — pushed missing user_profile to Supabase.');
      }
    } catch (_) {
      // Offline — SyncService.checkAndSync() will handle on next launch.
    }
  }
}

/// Riverpod provider for [AuthNotifier].
final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthState2>(AuthNotifier.new);
