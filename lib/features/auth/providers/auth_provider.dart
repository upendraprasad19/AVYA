import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
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
      } catch (_) {
        // Local setup failure is non-fatal — auth succeeded.
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
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);

    // Atomic logout (F16): set a marker BEFORE wiping Hive. If the app is
    // force-killed mid-clear (OS eviction, power loss), `main.dart` will
    // detect the marker on next launch and re-run `clearAllData` before any
    // other code reads a half-wiped box.
    final hive = HiveService.instance;
    try {
      await hive.configBox.put('logout_in_progress', true);
    } catch (_) {/* configBox not open yet / unavailable — best effort */}

    // 1. Terminate session (local scope always works offline).
    try {
      await _supabase.client.auth.signOut(scope: SignOutScope.global);
    } catch (_) {
      try {
        await _supabase.client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
    }
    // 2. Clear all user data after session is gone.
    await UserRepository.instance.clearAllData();

    // 3. Atomic logout complete — clear the marker.
    try {
      await hive.configBox.delete('logout_in_progress');
    } catch (_) {/* configBox was just cleared; flag is already gone */}

    state = const AuthState2(status: AuthStatus.idle);
  }

  /// Reset back to idle.
  void resetState() {
    state = const AuthState2();
  }

  // ── Private ───────────────────────────────────────────────────

  /// Ensures local Hive state is correct after sign-in.
  ///
  /// If the user previously completed onboarding (has a profile in Supabase),
  /// restores the onboarding flag so they skip onboarding on re-login.
  Future<void> _ensureLocalUser(User user) async {
    final userBox = _hive.userBox;
    final configBox = _hive.configBox;
    final existing = userBox.get('profile');

    // If Hive has a profile that isn't provably this user's, wipe it.
    // Covers three cases:
    //   1. Different user was logged in (existingId != user.id)
    //   2. Old profile has no 'id' field (set via onboarding without id) —
    //      we can't confirm it belongs to the new user, so clear it.
    //   3. Incomplete sign-out left stale data behind.
    if (existing != null) {
      final existingId = (existing as Map<dynamic, dynamic>?)?['id'] as String?;
      if (existingId == null || existingId != user.id) {
        await UserRepository.instance.clearAllData();
      }
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
    } catch (e) {
      debugPrint('users table upsert failed: $e');
      // Non-fatal for sign-in, but AI chat may fail if row is missing.
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
        await configBox.put('onboarding_completed', true);

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

          // Hydrate AI trial start from server (preserves trial across devices).
          final userRows = await supabase
              .from('users')
              .select('ai_chat_started_at')
              .eq('id', user.id)
              .limit(1);
          if (userRows.isNotEmpty) {
            final serverTrialStart =
                userRows.first['ai_chat_started_at'] as String?;
            if (serverTrialStart != null) {
              await configBox.put('ai_trial_start', serverTrialStart);
            }
          }

          // Regenerate workout schedule locally if plan is missing.
          if (!WorkoutScheduleService.instance.hasPlan() &&
              configBox.get('onboarding_completed') == true) {
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
        await configBox.put('onboarding_completed', true);
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
          await configBox.put('onboarding_completed', true);
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

    // F1 · Refresh subscription state from server after every sign-in.
    // Without this, a user who bought PRO on a previous session and then
    // logs out/in sees themselves as free until they tap a PRO feature
    // that happens to call `verifyFromServer()`. Fire-and-forget — UI
    // reads Hive cache until the refresh lands.
    unawaited(SubscriptionService.instance.refreshFromSupabase());

    // Bind OneSignal external_id to Supabase user UUID for push targeting.
    if (!kIsWeb) {
      try {
        await OneSignal.login(user.id);
      } catch (_) {
        // Non-critical — push notifications will still work on next launch.
      }
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
