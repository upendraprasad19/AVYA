import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
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

    // If Hive has a profile for a DIFFERENT user (e.g. incomplete sign-out),
    // clear all user-specific boxes before restoring the new user's data.
    if (existing != null) {
      final existingId = (existing as Map<dynamic, dynamic>?)?['id'] as String?;
      if (existingId != null && existingId != user.id) {
        await UserRepository.instance.clearAllData();
      }
    }

    // Ensure user exists in public.users table (Edge Functions need this).
    // Awaited — AI chat returns 404 if this row is missing.
    try {
      await _supabase.client.from('users').upsert({
        'id': user.id,
        'email': user.email ?? '',
        'full_name': user.userMetadata?['full_name'] ?? user.email?.split('@').first ?? 'User',
        'last_active_at': DateTime.now().toUtc().toIso8601String(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'id');
    } catch (e) {
      debugPrint('users table upsert failed: $e');
      // Non-fatal for sign-in, but AI chat may fail if row is missing.
    }

    if (existing == null) {
      // No local profile — could be first login OR re-login after sign-out.
      // Check Supabase for existing user data.
      try {
        final supabase = _supabase.client;
        final profileRows = await supabase
            .from('user_profile')
            .select()
            .eq('user_id', user.id)
            .limit(1);

        if (profileRows.isNotEmpty) {
          // Verify the remote profile has real onboarding data.
          // An empty row (all NULLs) can be created by sync errors and
          // should NOT be treated as a valid returning-user profile.
          final remoteProfile = Map<String, dynamic>.from(profileRows.first);
          final hasRealData = remoteProfile['primary_goal'] != null ||
              remoteProfile['height_cm'] != null;
          if (!hasRealData) {
            // Empty row — delete it and proceed as a new user.
            try {
              await supabase
                  .from('user_profile')
                  .delete()
                  .eq('user_id', user.id);
            } catch (_) {}
          }
        }
        if (profileRows.isNotEmpty &&
            (profileRows.first['primary_goal'] != null ||
             profileRows.first['height_cm'] != null)) {
          // Returning user — restore profile and onboarding flag.
          final remoteProfile = Map<String, dynamic>.from(profileRows.first);
          remoteProfile['id'] = user.id;
          remoteProfile['email'] = user.email;
          await userBox.put('profile', remoteProfile);
          await configBox.put('onboarding_completed', true);

          // Also try to restore progress data.
          final progressRows = await supabase
              .from('user_progress')
              .select()
              .eq('user_id', user.id)
              .limit(1);
          if (progressRows.isNotEmpty) {
            await userBox.put(
                'progress', Map<String, dynamic>.from(progressRows.first));
          }

          // Regenerate workout schedule locally only if plan is missing AND
          // user has completed onboarding. This avoids overwriting progress
          // for returning users and avoids generating before onboarding
          // for new users (onboarding_provider handles that case).
          if (!WorkoutScheduleService.instance.hasPlan() &&
              configBox.get('onboarding_completed') == true) {
            final goal = remoteProfile['primary_goal'] as String? ?? 'general_fitness';
            final equipment = remoteProfile['equipment_access'] as String? ?? 'basic_gym';
            final daysPerWeek = (remoteProfile['days_per_week'] as num?)?.toInt() ?? 4;
            final experience = remoteProfile['fitness_experience'] as String? ?? 'beginner';
            final phase = progressRows.isNotEmpty
                ? ((progressRows.first['current_phase'] as int?) ?? 1)
                : 1;

            // Determine start date: use plan_generated_at from progress if
            // available, otherwise start from this Monday.
            DateTime startDate;
            if (progressRows.isNotEmpty) {
              final genStr = progressRows.first['phase_started_at'] as String?;
              startDate = genStr != null
                  ? DateTime.tryParse(genStr) ?? DateTime.now()
                  : DateTime.now();
            } else {
              startDate = DateTime.now();
            }

            // Use a separate try-catch so plan generation failures are NOT
            // swallowed by the outer Supabase-offline catch block.
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
              // Non-fatal — train screen will show "generating" state and
              // retry plan generation on first load.
            }
          }

          return;
        }

        // Also check users table for onboarding flag.
        final userRows = await supabase
            .from('users')
            .select('onboarding_completed')
            .eq('id', user.id)
            .limit(1);

        if (userRows.isNotEmpty) {
          final onboarded =
              (userRows.first['onboarding_completed'] as bool?) ?? false;
          if (onboarded) {
            await configBox.put('onboarding_completed', true);
          }
        }
      } catch (_) {
        // Supabase query failed (offline or table doesn't exist yet).
        // Fall through to create minimal local profile.
      }

      // Create minimal local profile if nothing was restored.
      if (userBox.get('profile') == null) {
        await userBox.put('profile', {
          'id': user.id,
          'email': user.email,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    }

    // Gap detection: if local profile exists but Supabase user_profile is
    // missing, push immediately. Recovers from a failed onboarding sync
    // without requiring a 7-day wait for the weekly full sync.
    if (existing != null) {
      _pushProfileToSupabaseIfMissing(user.id);
    }

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
