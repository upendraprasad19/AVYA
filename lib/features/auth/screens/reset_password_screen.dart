import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:icanbefitter/core/router/app_router.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Full-screen password reset form. Reachable only from a password-recovery
/// email link — the user lands on the web SPA, Supabase processes the
/// recovery token from the URL hash, and [SplashScreen] routes here.
///
/// The form collects a new password + confirmation, calls
/// [GoTrueClient.updateUser] to set it, then signs out and redirects to
/// the sign-in screen so the user can log in with the new password.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Guard: if the user arrived here without a legitimate recovery flow,
    // redirect to sign-in. The flag is set by SplashScreen after detecting
    // `type=recovery` in the URL fragment.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!AppRouter.isPasswordRecovery && mounted) {
        context.go('/sign-in');
      }
    });
    // See [_authSub]: the legacy link path can produce the session AFTER this
    // screen has already built and decided it has none.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPwCtrl.text),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Password updated. Sign in with your new password.',
              style: AppTypography.bodySm.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.ok,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sharp),
            ),
          ),
        );
      }

      // Sign out — the user re-authenticates with the new password. Runs
      // even if the widget already unmounted (plan-review round 1, Finding
      // 3) and swallows its own failure (Finding 2): updateUser above
      // already succeeded, so a transient signOut error must not surface as
      // "password update failed" nor block the navigation below.
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (e) {
        unawaited(
          ErrorTelemetry.logEvent(
            'auth_password_reset_cleanup_failed',
            message: '$e',
          ),
        );
      }
      // OI-51 round 2: a password reset ends the session too. Same user
      // re-authenticates seconds later, but leaving the binding set means a
      // push aimed at the old session can still land in the gap. Called
      // UNCONDITIONALLY, outside signOut()'s try — plan-review round 2,
      // Finding 1: nesting it inside that try meant a signOut() throw
      // skipped the release too, same shape as the sibling call sites this
      // mirrors (auth_provider.dart:573-579, perform_sign_out.dart,
      // settings_screen.dart, main.dart) which all call it unconditionally
      // after a swallowed signOut() failure. releaseDeviceSessionIdentity()
      // has no Supabase session dependency and try/catches its own two
      // steps internally, so it's always safe to call here.
      await releaseDeviceSessionIdentity();
      // Reset the recovery flag so the guard on next mount works.
      AppRouter.isPasswordRecovery = false;
      // Navigate explicitly. GoRouter has no refreshListenable tied to
      // Supabase auth state, and /reset is deliberately exempt from
      // _authRedirect (recovery has no normal session) — nothing
      // re-evaluates the route on sign-out, so without this the screen
      // sits on /reset forever after a successful reset (stuck-screen bug).
      // Mirrors the explicit-navigation pattern SignInScreen already uses
      // on success (sign_in_screen.dart, ref.listen → context.go).
      if (mounted) context.go('/sign-in');
    } on AuthException catch (e) {
      setState(() {
        _sending = false;
        _error = e.message;
      });
    } catch (e) {
      unawaited(
        ErrorTelemetry.logEvent('auth_password_update_failed', message: '$e'),
      );
      setState(() {
        _sending = false;
        _error = 'Could not update password. Try again.';
      });
    }
  }

  /// Whether a real recovery session exists.
  ///
  /// The `initState` guard above checks `AppRouter.isPasswordRecovery`, which
  /// is only a claim about the URL SHAPE — it is set from the link/OTP
  /// detector and says nothing about whether a session was ever obtained. That
  /// gap is diagnose c9e2b7: under PKCE the emailed code can only be exchanged
  /// by the client that requested the reset, so opening the mail anywhere else
  /// left this screen rendering a perfectly normal form that could only ever
  /// fail at submit with GoTrue's "Auth session missing!".
  ///
  /// Checking the session itself is the difference between "this looks like a
  /// recovery" and "we can actually change a password".
  bool get _hasSession =>
      Supabase.instance.client.auth.currentSession != null;

  /// Rebuilds this screen when a session arrives AFTER first build.
  ///
  /// `_hasSession` is read during `build`, and on the legacy link path the
  /// session is produced ASYNCHRONOUSLY by `detectSessionInUrl` during
  /// `Supabase.initialize`. Build first, session second, and the screen would
  /// have shown "this reset session has expired" permanently, with nothing to
  /// trigger a rebuild — turning a recoverable wait into a dead end
  /// (round-1 review, P2-7). Not needed for the new code path, where
  /// `verifyOTP` completes before we navigate; needed for every email already
  /// in flight.
  StreamSubscription<AuthState>? _authSub;

  @override
  Widget build(BuildContext context) {
    if (!_hasSession) return _buildNoSessionState(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(),
                    // WHOSE password is being set. Founder observation
                    // 2026-08-06: the screen named no account at all, so there
                    // was no way to tell a wrong-account reset from a right
                    // one. This is only knowable because a session now exists
                    // by the time we get here — with the old link flow there
                    // was no `currentUser` to read.
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.stackM),
                      child: Text(
                        Supabase.instance.client.auth.currentUser?.email ?? '',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _buildPasswordField(
                            controller: _newPwCtrl,
                            hintText: 'New password',
                            obscure: _obscureNew,
                            onToggle: () =>
                                setState(() => _obscureNew = !_obscureNew),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Enter a new password';
                              }
                              if (v.length < 6) {
                                return 'At least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpacing.stackM),
                          _buildPasswordField(
                            controller: _confirmPwCtrl,
                            hintText: 'Confirm new password',
                            obscure: _obscureConfirm,
                            onToggle: () => setState(
                              () => _obscureConfirm = !_obscureConfirm,
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Confirm your new password';
                              }
                              if (v != _newPwCtrl.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Minimum 6 characters',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.textDim,
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.bad,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sectionGap),
                          _buildUpdateButton(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shown when we reached `/reset` with no recovery session (c9e2b7).
  ///
  /// Replaces the old behaviour of rendering the form anyway and failing at
  /// submit with a raw "Auth session missing!" — a message that names an
  /// internal concept and gives the user nothing to act on. §4.4 rule 13: a
  /// screen handles its empty/error state, and "we cannot do this here" IS a
  /// state, not an exception.
  Widget _buildNoSessionState(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                Text(
                  'This reset session has expired, or the link was opened on a '
                  'different device from the one that requested it.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
                const SizedBox(height: AppSpacing.stackM),
                Text(
                  'Start again and we will email you a 6-digit code you can '
                  'enter right here.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textMute,
                  ),
                ),
                const SizedBox(height: AppSpacing.stackL),
                GestureDetector(
                  onTap: () => context.go('/sign-in'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Center(
                      child: Text(
                        'REQUEST A NEW CODE',
                        // Matches _buildUpdateButton's label treatment exactly
                        // so the two primary actions on this screen read as
                        // one system.
                        style: AppTypography.h3.copyWith(
                          fontSize: 12,
                          color: AppColors.bgDeep,
                          letterSpacing: 2.5,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Back to sign-in
        Align(
          alignment: Alignment.centerLeft,
          child: Opacity(
            opacity: _sending ? 0.35 : 1,
            child: GestureDetector(
              onTap: _sending ? null : () => context.go('/sign-in'),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Icon(
                  Icons.arrow_back,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent, width: 1.5),
                  color: AppColors.bgDeep,
                ),
                alignment: Alignment.center,
                child: Image.asset(
                  'assets/avya_icon.png',
                  width: 32,
                  height: 32,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'RECRUIT REGISTRY',
                textAlign: TextAlign.center,
                style: AppTypography.mono.copyWith(
                  fontSize: 10,
                  letterSpacing: 2.0,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 64,
                height: 1,
                color: AppColors.accent.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 12),
              Text(
                'SET NEW PASSWORD',
                textAlign: TextAlign.center,
                style: AppTypography.h2.copyWith(
                  fontSize: 24,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.stackXL),
      ],
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hintText,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      style: AppTypography.body.copyWith(color: AppColors.textPrimary),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: AppTypography.body.copyWith(color: AppColors.textDisabled),
        prefixIcon: const Icon(
          Icons.lock_outline,
          color: AppColors.textDim,
          size: 20,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppColors.textSecondary,
            size: 20,
          ),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: AppColors.input,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          borderSide: const BorderSide(color: AppColors.line2, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          borderSide: const BorderSide(color: AppColors.line2, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          borderSide: const BorderSide(color: AppColors.bad, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          borderSide: const BorderSide(color: AppColors.bad, width: 2),
        ),
        errorStyle: AppTypography.bodySm.copyWith(color: AppColors.bad),
      ),
    );
  }

  Widget _buildUpdateButton() {
    final disabled = _sending;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: Material(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            onTap: disabled ? null : _updatePassword,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 2),
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
              child: Center(
                child: _sending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.black,
                        ),
                      )
                    : Text(
                        'UPDATE PASSWORD',
                        style: AppTypography.h3.copyWith(
                          fontSize: 12,
                          color: AppColors.bgDeep,
                          letterSpacing: 2.5,
                          height: 1,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
