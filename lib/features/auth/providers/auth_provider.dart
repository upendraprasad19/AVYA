import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

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

  /// Sign in with email + password.
  Future<void> signInWithEmail(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
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
        errorMessage: 'Something went wrong. Please try again.',
      );
    }
  }

  /// Create a new account with email + password.
  Future<void> signUpWithEmail(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
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
        errorMessage: 'Something went wrong. Please try again.',
      );
    }
  }

  /// Sign in with Google OAuth.
  Future<void> signInWithGoogle() async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
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
  Future<void> signOut() async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      await _supabase.client.auth.signOut();
      state = const AuthState2(status: AuthStatus.idle);
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Sign out failed.',
      );
    }
  }

  /// Reset back to idle.
  void resetState() {
    state = const AuthState2();
  }

  // ── Private ───────────────────────────────────────────────────

  Future<void> _ensureLocalUser(User user) async {
    final userBox = _hive.userBox;
    final existing = userBox.get('profile');
    if (existing == null) {
      await userBox.put('profile', {
        'id': user.id,
        'email': user.email,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }
}

/// Riverpod provider for [AuthNotifier].
final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthState2>(AuthNotifier.new);
