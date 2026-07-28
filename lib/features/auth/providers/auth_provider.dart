// AUTH_INVALIDATION_EXEMPT: the auth provider IS the source of truth
// for auth state. It produces the signal that `authUserIdTokenProvider`
// derives from — it can't self-watch without creating a circular
// rebuild loop.

import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:icanbefitter/core/services/auth_session_bootstrapper.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/streak_freeze_clamp_migrator.dart';
import 'package:icanbefitter/core/services/user_config_migrator.dart';
import 'package:icanbefitter/core/services/body_fat_default_healer.dart';
import 'package:icanbefitter/core/services/logging_type_repair_migrator.dart';
import 'package:icanbefitter/core/services/wlog_type_backfill_migrator.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// Releases every per-user identity this DEVICE holds outside Hive.
///
/// TOP-LEVEL, not a method on [AuthNotifier], because sign-out is not the only
/// path that ends a session. Review round 1 (2026-07-27) found two others that
/// clear Hive + Supabase directly and never touch the notifier:
///
///   - `main.dart`'s `runZonedGuarded` HiveOwnershipException recovery — which
///     fires exactly when the cross-account guard trips, i.e. precisely the
///     "this device may be carrying a stale identity" case.
///   - `delete_account_screen.dart`'s DPDP hard-delete — and "a handset the
///     user sold or handed on" is the scenario this whole fix describes, so
///     leaving account deletion uncovered inverted the intent. Crashlytics
///     would keep tagging crashes with the deleted user's id.
///
/// Guards mirror the BIND sites in `_ensureLocalUser` exactly (`!kIsWeb`,
/// `!kDebugMode`): an unbind running where the bind never did is a new failure
/// mode, not a fix. Each step is individually try/caught so a throwing SDK
/// cannot block the rest — and so this is safe to call from a zone handler.
///
/// Does NOT touch the static `onStateChanged` callbacks; see the note in
/// [AuthNotifier.unbindSessionIdentity] for why clearing those is a regression.
Future<void> releaseDeviceSessionIdentity() async {
  if (!kIsWeb) {
    try {
      await OneSignal.logout();
    } catch (e) {
      debugPrint('[auth/releaseIdentity] OneSignal.logout failed: $e');
    }
  }
  if (!kDebugMode) {
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier('');
    } catch (e) {
      debugPrint('[auth/releaseIdentity] Crashlytics clear failed: $e');
    }
  }
}

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
  ///
  /// `@visibleForTesting` non-private so a test subclass can override it to
  /// short-circuit to `true` (real `_supabase.initialize()` fails in a pure
  /// VM test) — see `test/contracts/check_email_registered_behavioral_test.dart`.
  @visibleForTesting
  Future<bool> ensureSupabaseReady() async {
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

  /// Checks whether [email] already belongs to a registered account, via the
  /// server-side `email_is_registered` RPC (SECURITY DEFINER — public.users
  /// RLS is owner-only and there's no auth.uid() yet at this point in the
  /// flow). Returns true/false, or null on error (the error is also
  /// surfaced through `state` for the screen's existing SnackBar listener).
  ///
  /// Never sets `AuthStatus.success` — the screen's `ref.listen` navigates
  /// to `/restoring` on success, and this check happens with no real session.
  Future<bool?> checkEmailRegistered(String email) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    if (!await ensureSupabaseReady()) return null;
    try {
      final result = await rpcEmailIsRegistered(email.trim());
      state = state.copyWith(status: AuthStatus.idle);
      return result;
    } catch (e) {
      unawaited(ErrorTelemetry.logEvent('auth_email_check_failed',
          message: '[${e.runtimeType}] ${e.toString().split('\n').first}'));
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Could not verify email. Please try again.',
      );
      return null;
    }
  }

  /// The network leaf of [checkEmailRegistered], extracted so a test
  /// subclass can override just this and inherit the real state-machine
  /// (loading/idle/error transitions, telemetry on failure) for a genuine
  /// behavioral test — see
  /// `test/contracts/check_email_registered_behavioral_test.dart`.
  @visibleForTesting
  Future<bool> rpcEmailIsRegistered(String trimmedEmail) async {
    final result = await _supabase.client.rpc(
      'email_is_registered',
      params: {'p_email': trimmedEmail},
    );
    return result as bool;
  }

  /// Sign in with email + password.
  Future<void> signInWithEmail(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    if (!await ensureSupabaseReady()) return;
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
      // APK Test #12.8 — auth lifecycle event so we can correlate
      // post-auth bug reports (PRO pill stuck, profile name "USER")
      // with the exact sign-in instant.
      unawaited(ErrorTelemetry.logEvent('auth_signed_in',
          message:
              'method=email userId=${response.user!.id.substring(0, 8)}'));
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
    if (!await ensureSupabaseReady()) return;
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
      // APK Test #12.8 — distinct sign-up event vs sign-in.
      unawaited(ErrorTelemetry.logEvent('auth_signed_up',
          message:
              'method=email userId=${response.user!.id.substring(0, 8)}'));
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
    if (!await ensureSupabaseReady()) return;
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
    if (!await ensureSupabaseReady()) return;
    try {
      await _supabase.client.auth.signInWithOtp(phone: phone);
      state = state.copyWith(status: AuthStatus.idle, otpSent: true);
    } on AuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.message,
      );
    } catch (e) {
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('auth_send_phone_otp_failed',
          message: clipped));
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
      // APK Test #12.8 — phone OTP success event.
      unawaited(ErrorTelemetry.logEvent('auth_signed_in',
          message:
              'method=phone_otp userId=${response.user!.id.substring(0, 8)}'));
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
    // APK Test #12.8 — capture sign-out before any Hive clear so the
    // event makes it to cloud even if a subsequent step throws.
    final signedOutId = _supabase.currentUser?.id;
    if (signedOutId != null) {
      unawaited(ErrorTelemetry.logEvent('auth_signed_out',
          message: 'userId=${signedOutId.substring(0, 8)}'));
    }
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

    await unbindSessionIdentity();

    state = const AuthState2(status: AuthStatus.idle);
  }

  /// OI-51 — releases every per-user identity this device holds outside Hive.
  ///
  /// `_ensureLocalUser` BINDS the device to a user at sign-in (`OneSignal.login`
  /// + Crashlytics `setUserIdentifier`). Until 2026-07-27 nothing ever unbound
  /// it, and `signOut` cleared only Hive + Supabase.
  ///
  /// The exposure is the SIGNED-OUT WINDOW, not the next user: when B signs in,
  /// `_ensureLocalUser` overwrites both bindings, so B is attributed correctly.
  /// But between A signing out and anyone signing in, the device remains
  /// `external_id = A` — so **A's push notifications keep arriving**, carrying
  /// A's fitness data (calories, streaks, coach messages), on a handset A may
  /// have sold, returned, or handed to someone else. Crashes in that window are
  /// likewise tagged with A's id.
  ///
  /// Extracted from [signOut] so it is directly callable in tests: `signOut()`
  /// itself needs Supabase + Hive + GoRouter and is not unit-testable (the same
  /// reason `profile_signout_routes_through_auth_notifier_test.dart` is
  /// source-grep). The static-callback clearing below IS verified behaviourally
  /// against this method; the two plugin calls are platform channels and are
  /// pinned by source-grep + channel mocking.
  ///
  /// Guards mirror the BIND sites exactly (`!kIsWeb` / `!kDebugMode`) — an
  /// unbind running where the bind never did would be a new failure mode. Each
  /// step keeps [signOut]'s per-step try/catch shape: sign-out must complete
  /// even if a third-party SDK throws.
  @visibleForTesting
  Future<void> unbindSessionIdentity() async {
    await releaseDeviceSessionIdentity();

    // THE STATIC onStateChanged CALLBACKS ARE DELIBERATELY *NOT* CLEARED HERE.
    //
    // The first version of this method nulled all three. Review round 1
    // (2026-07-27) showed that is a REGRESSION, not a fix, and the reasoning is
    // worth keeping because OI-51's own sub-finding 4 asks for it:
    //
    //   `app.dart:45/59/76` (initState) is the ONLY place in `lib/` that
    //   installs them — verified by `grep -rn "onStateChanged = " lib/`. And
    //   `ICanBeFitterApp` is constructed exactly once per process
    //   (`main.dart:123`, `main_dev.dart:36`, `main_prod.dart:33`), so
    //   initState runs once for the app's lifetime. `_ensureLocalUser` never
    //   re-installs them. Nulling them on sign-out therefore kills provider
    //   invalidation PERMANENTLY for every later sign-in in the same process —
    //   and every call site uses `onStateChanged?.call()`, so nothing throws;
    //   the invalidation just silently stops.
    //
    //   That reintroduces three already-fixed, founder-observed bugs for the
    //   rest of the session: APK Test #12.2 (PRO pill stuck on FREE),
    //   #12.4 ("I logged breakfast … nothing got updated in UI"), and OI-37
    //   (stale rank after promotion).
    //
    // OI-51 SUB-FINDING 4 IS WRONG ON ITS PREMISE. It says the closure
    // "captures Riverpod state" and so needs a reset path. It captures the
    // ConsumerState's `ref`, which is bound to the process-lived ProviderScope,
    // NOT to a user. After B signs in, invalidating those providers is exactly
    // the correct behaviour — they re-read from B's Hive boxes through the
    // `wrapUserScopedBox` guard. There is no cross-account leak to close here,
    // so the right number of clears on the sign-out path is zero.
    //
    // The genuine half of that sub-finding — that `RankService` had no clear
    // site ANYWHERE, not even at teardown — is fixed where it belongs, in
    // `app.dart:dispose()` alongside the other two.
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
    // APK Test #12.8 — entry-point trace. Most lifecycle bugs (PRO pill
    // stuck, profile name "USER") manifest after this method runs;
    // having a per-call event lets us correlate downstream failures with
    // the exact ensureLocalUser invocation.
    unawaited(ErrorTelemetry.logEvent('auth_user_ensured',
        message: 'userId=${user.id.substring(0, 8)}'));

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
        // OI-51 round 2: this is the cross-account guard firing -- the single
        // moment the device is MOST likely to be carrying the wrong user's
        // identity -- and it force-signs-out without going through signOut().
        await releaseDeviceSessionIdentity();
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

    // Unit C (bug c) — drop `notification_preferences` from the SHARED
    // configBox. Delete-only, never copied: configBox has no owner, so a copy
    // would hand the previous user's preferences to this one. Losing the value
    // is safe (absent ⇒ server SENDS, decision N2); inheriting a stranger's
    // "off" is silent and unfixable by the affected user. Own flag, so this
    // does not re-run the completed 31-key copy sweep.
    try {
      await UserConfigMigrator.purgeDeleteOnlyKeys();
    } catch (e) {
      debugPrint('[auth/_ensureLocalUser] delete-only purge failed: $e');
    }

    // Unit 4 (d-bf) — heal the fabricated onboarding body-fat 18.0 (clears the
    // cloud column FIRST, then local) so the profile-edit Katch recompute stops
    // consuming a made-up value. Idempotent + kill-switched (disable_bodyfat_heal).
    try {
      await BodyFatDefaultHealer.runIfNeeded();
    } catch (e) {
      debugPrint('[auth/_ensureLocalUser] body-fat default heal failed: $e');
      // Non-fatal — retries next session (cloud + local stay consistent 18.0).
    }

    // Bug f8c1a5 (APK Test #16.2) Layer 2 — one-shot clamp of any
    // corrupted streak_freezes_available value in userBox['progress']
    // down to the tier cap, plus clear of streak_freezes_last_refill so
    // a fresh refill can run. Idempotent, gated by migrationBox flag.
    // Read-side clamp in StreakFreezeNotifier.build is Layer 1 and is
    // already in effect; this migrator is the durable Hive repair.
    try {
      await StreakFreezeClampMigrator.runIfNeeded();
    } catch (e) {
      debugPrint('[auth/_ensureLocalUser] streak freeze clamp failed: $e');
      // Non-fatal — read-side clamp still hides the corrupted display.
    }

    // APK Test #15.4 / B2 backfill — one-shot mirror of pre-bridge muster
    // answers into userBox['profile']. Gated by migrationBox flag.
    try {
      await InductionService.instance.backfillMusterToProfileIfNeeded();
    } catch (e) {
      debugPrint('[auth/_ensureLocalUser] muster backfill failed: $e');
      // Non-fatal — backfill is idempotent and retries on next launch.
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

    // Bug f1c8e4 — one-shot backfill of `type: 'workout_log'` (+ ISO
    // `completed_at`) onto legacy `wlog_*` rows the pre-fix markCompleted wrote
    // without them. Without it the count/history readers (getWeeklyWorkoutCounts,
    // getWorkoutLogs, badge total, AI snapshot) miss every workout completed on
    // this install before the fix. Idempotent (gated by migrationBox flag),
    // local-only (no cloud re-sync — `type` is a Hive-only field). Non-fatal.
    try {
      await WlogTypeBackfillMigrator.runIfNeeded();
    } catch (e) {
      debugPrint('[auth/_ensureLocalUser] wlog type backfill failed: $e');
    }

    // ── Cloud hydration ────────────────────────────────────────
    //
    // Audit 2026-05-20 / A1 + A9 (AuthSessionBootstrapper extract).
    // Previously this block did Postgres CRUD on `users`,
    // `user_profile`, `user_progress` inline (formerly lines 480-770).
    // All of that now lives in [AuthSessionBootstrapper.hydrateFromCloud]
    // which owns the same shape (users upsert + ignoreDuplicates,
    // last_active_at, ToS sync, H-3 full_name self-heal, F2/F3 cloud →
    // Hive merge, plan regen, gap-closer push).
    //
    // We wrap the call in a try/catch here so the silent-swallow
    // defense (Bug A, 2026-04-26: orphan public.users row blocked sync
    // for 48h) survives at the orchestration layer — same explicit
    // detection of Postgres codes 23505 (unique_violation) and 23503
    // (foreign_key_violation), same canonical ErrorTelemetry sink
    // (audit A11). The bootstrapper has its own inner telemetry too;
    // this outer guard catches any escape-hatch path.
    try {
      await AuthSessionBootstrapper.instance.hydrateFromCloud(user);
    } catch (e) {
      debugPrint('[_ensureLocalUser] hydrateFromCloud failed: $e');
      String errorType = 'users_upsert_failed';
      final eStr = e.toString();
      if (eStr.contains('23505')) errorType = 'users_unique_violation_23505';
      if (eStr.contains('23503')) errorType = 'users_fk_violation_23503';
      unawaited(ErrorTelemetry.recordNonFatal(
        e,
        StackTrace.current,
        reason: errorType,
        extra: {
          'user_id': user.id,
          'platform': 'android',
          'error_message_preview':
              eStr.length > 1000 ? eStr.substring(0, 1000) : eStr,
        },
      ));
    }

    // APK Test #12.6 — Crashlytics user identifier (first 8 chars of UUID
    // for privacy; enough to correlate crashes back to a user without
    // logging the full PII-bearing UUID). Fire-and-forget; failure must
    // never block the auth flow.
    if (!kDebugMode) {
      try {
        unawaited(FirebaseCrashlytics.instance.setUserIdentifier(
          user.id.length >= 8 ? user.id.substring(0, 8) : user.id,
        ));
      } catch (e) {
        debugPrint('[auth/_ensureLocalUser] Crashlytics setUserIdentifier failed: $e');
      }
    }

    // Bind OneSignal external_id to Supabase user UUID for push targeting.
    // Test #11.1: persist OneSignal player_id (subscription id) to
    // `user_progress.onesignal_player_id` so the `delete-account` Edge
    // Function can unsubscribe pushes when the user erases their account.
    // Without this, deleted accounts may keep receiving push notifications
    // until the OS uninstalls the app (migration 049 added the column but
    // no client-side write existed).
    //
    // Audit 2026-05-20 / A1 — player_id push is now owned by
    // AuthSessionBootstrapper.syncCurrentOneSignalPlayerId.
    if (!kIsWeb) {
      try {
        await OneSignal.login(user.id);
        unawaited(AuthSessionBootstrapper.instance
            .syncCurrentOneSignalPlayerId(user.id));
      } catch (_) {
        // Non-critical — push notifications will still work on next launch.
      }
    }
  }
}

/// Riverpod provider for [AuthNotifier].
final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthState2>(AuthNotifier.new);
