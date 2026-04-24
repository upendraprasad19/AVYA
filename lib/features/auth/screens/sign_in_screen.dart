import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';

import '../providers/auth_provider.dart';
import '../widgets/forgot_password_sheet.dart';
import '../widgets/terms_modal.dart';

/// Enum for the current sign-in view.
enum _SignInView { main, email, phone }

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  final _referralController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// Full E.164-formatted phone number emitted by [IntlPhoneField]
  /// (e.g. `+919876543210`). This is what Supabase's `signInWithOtp`
  /// expects. Kept in sync via the `onChanged` callback.
  String _phoneE164 = '';

  /// Local mirror of whatever the user typed (for the "change number" back
  /// link to pre-fill — [IntlPhoneField] doesn't expose its controller).
  String _phoneLocal = '';

  /// Countdown timer for the "Resend OTP" link on the OTP view.
  /// Runs for 30 seconds after a successful SEND OTP / RESEND OTP tap,
  /// then the link becomes tappable.
  Timer? _resendTimer;
  int _resendSecondsRemaining = 0;
  static const int _resendCooldownSeconds = 30;

  bool _isSignUp = false;
  bool _obscurePassword = true;
  _SignInView _currentView = _SignInView.main;

  @override
  void initState() {
    super.initState();
    // On first launch, gate the screen behind a blocking ToS/Privacy modal.
    // Once accepted, [TermsModal.maybeShow] records the acceptance timestamp
    // in Hive (userBox['terms_accepted_at']) so it doesn't re-appear. On
    // sign-in completion, the stored timestamp is synced up to Supabase's
    // `users.terms_accepted_at` column.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) TermsModal.maybeShow(context);
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsRemaining = _resendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendSecondsRemaining <= 1) {
        t.cancel();
        setState(() => _resendSecondsRemaining = 0);
      } else {
        setState(() => _resendSecondsRemaining -= 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final authNotifier = ref.read(authNotifierProvider.notifier);

    // Listen for auth state changes to navigate.
    ref.listen<AuthState2>(authNotifierProvider, (prev, next) {
      if (next.status == AuthStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              next.errorMessage!,
              style: AppTypography.bodySm.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.bad,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sharp),
            ),
          ),
        );
        authNotifier.resetState();
      }
      if (next.status == AuthStatus.success) {
        // Save referral code to Hive so it can be retried if redemption fails
        final code = _referralController.text.trim();
        if (code.isNotEmpty) {
          // Store pending referral in configBox for retry on next launch
          try {
            final configBox = Hive.box('configBox');
            configBox.put('pending_referral_code', code);
          } catch (_) {}
          SupabaseService.instance.callFunction(
            'redeem-referral',
            body: {'code': code},
          ).then((_) {
            debugPrint('[SignIn] Referral code redeemed: $code');
            // Clear pending code on success
            try { Hive.box('configBox').delete('pending_referral_code'); } catch (_) {}
          }).catchError((e) {
            debugPrint('[SignIn] Referral redemption failed (will retry on next launch): $e');
          });
        }
        context.go('/splash');
      }
    });

    final isLoading = authState.status == AuthStatus.loading;

    // Option 1 background layout (locked 2026-04-24):
    // * Top 45% of viewport: hero band on solid `bgDeep` with a circular
    //   gold logo mark, a parchment "AVYA" wordmark, and a double gold rule
    //   at the bottom edge — separates the identity moment from the form.
    // * Bottom 55%: solid `bg`, scrollable, houses tagline + auth stack +
    //   forgot-password + referral + social proof. Zero text-over-image.
    // The hero band is rendered for the main view only; phone/email
    // sub-views get their own full-canvas layout (back button at top).
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _currentView == _SignInView.main
            ? _buildRootWithHero(authNotifier, isLoading)
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                child: _currentView == _SignInView.email
                    ? _buildEmailView(authNotifier, isLoading)
                    : _buildPhoneView(authState, authNotifier, isLoading),
              ),
      ),
    );
  }

  /// Main sign-in view with Option 1's hero-logo band on top.
  Widget _buildRootWithHero(AuthNotifier authNotifier, bool isLoading) {
    final heroHeight = MediaQuery.of(context).size.height * 0.38;
    return Column(
      children: [
        _HeroLogoBand(height: heroHeight),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            child: _buildMainView(authNotifier, isLoading),
          ),
        ),
      ],
    );
  }

  // ── Main View ──────────────────────────────────────────────────

  Widget _buildMainView(AuthNotifier authNotifier, bool isLoading) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 22),

        // Tagline — sits on the solid bg below the hero band.
        Text(
          'AI-POWERED FITNESS & NUTRITION',
          style: AppTypography.mono.copyWith(
            color: AppColors.textDim,
            letterSpacing: 2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'BUILT FOR INDIAN LIFESTYLES',
          style: AppTypography.mono.copyWith(
            color: AppColors.textMute,
            letterSpacing: 2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // ── Continue with Google — PRIMARY ──────────────────
        _buildSharpButton(
          label: 'CONTINUE WITH GOOGLE',
          icon: Icons.g_mobiledata,
          iconSize: 28,
          background: Colors.white,
          foreground: Colors.black,
          border: Colors.white,
          onPressed: isLoading
              ? null
              : () => authNotifier.signInWithGoogle(),
          isLoading: isLoading,
        ),
        const SizedBox(height: 12),

        // ── Continue with Phone — SECONDARY ─────────────────
        _buildSharpButton(
          label: 'CONTINUE WITH PHONE',
          icon: Icons.phone_outlined,
          iconSize: 20,
          background: AppColors.card,
          foreground: AppColors.textPrimary,
          border: AppColors.line2,
          onPressed: isLoading
              ? null
              : () => setState(() => _currentView = _SignInView.phone),
          isLoading: false,
        ),
        const SizedBox(height: 20),

        // ── Divider ─────────────────────────────────────────
        _buildDivider(),
        const SizedBox(height: 20),

        // ── Continue with Email — TERTIARY ──────────────────
        _buildSharpButton(
          label: 'CONTINUE WITH EMAIL',
          icon: Icons.email_outlined,
          iconSize: 20,
          background: Colors.transparent,
          foreground: AppColors.accent,
          border: AppColors.accent,
          onPressed: isLoading
              ? null
              : () => setState(() => _currentView = _SignInView.email),
          isLoading: false,
        ),
        const SizedBox(height: 10),

        // ── Forgot password link ────────────────────────────
        GestureDetector(
          onTap: isLoading ? null : () => ForgotPasswordSheet.show(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Forgot password?',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 22),

        // ── Referral code (always visible, prominent) ───────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'REFERRAL CODE (OPTIONAL)',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _referralController,
          style: AppTypography.body.copyWith(
            color: AppColors.textPrimary,
            fontSize: 16,
          ),
          cursorColor: AppColors.accent,
          maxLength: 20,
          decoration: InputDecoration(
            hintText: 'AVYA-XXXX1234',
            hintStyle: AppTypography.body.copyWith(
              color: AppColors.textMute,
              fontSize: 16,
            ),
            prefixIcon: const Icon(
              Icons.card_giftcard,
              color: AppColors.accent,
              size: 20,
            ),
            counterText: '',
            filled: true,
            fillColor: AppColors.input,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide(
                color: AppColors.accent.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide(
                color: AppColors.accent.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: const BorderSide(
                color: AppColors.accent,
                width: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Social proof ────────────────────────────────────
        Text(
          'JOIN 10,000+ INDIANS ON THEIR FITNESS JOURNEY',
          style: AppTypography.monoXs.copyWith(
            color: AppColors.textMute,
            letterSpacing: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Email Sub-View ─────────────────────────────────────────────

  Widget _buildEmailView(AuthNotifier authNotifier, bool isLoading) {
    return Column(
      children: [
        const SizedBox(height: 20),

        // Back button
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: isLoading
                ? null
                : () => setState(() {
                      _currentView = _SignInView.main;
                      _isSignUp = false;
                    }),
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: AppColors.textPrimary,
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 12),

        const SizedBox(height: 32),

        // Email form
        Form(
          key: _formKey,
          child: Column(
            children: [
              // Email field
              _buildTextField(
                controller: _emailController,
                hintText: 'Email address',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.email_outlined,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$')
                      .hasMatch(value.trim())) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.sectionGap),

              // Password field
              _buildTextField(
                controller: _passwordController,
                hintText: 'Password',
                obscureText: _obscurePassword,
                prefixIcon: Icons.lock_outline,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your password';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Sign In / Sign Up button
              _buildPrimaryButton(
                label: _isSignUp ? 'CREATE ACCOUNT' : 'SIGN IN WITH EMAIL',
                isLoading: isLoading,
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  final email = _emailController.text.trim();
                  final password = _passwordController.text;
                  if (_isSignUp) {
                    authNotifier.signUpWithEmail(email, password);
                  } else {
                    authNotifier.signInWithEmail(email, password);
                  }
                },
              ),
              const SizedBox(height: 12),

              // Toggle sign-in / sign-up
              TextButton(
                onPressed: isLoading
                    ? null
                    : () => setState(() => _isSignUp = !_isSignUp),
                child: Text(
                  _isSignUp
                      ? 'ALREADY HAVE AN ACCOUNT? SIGN IN'
                      : "DON'T HAVE AN ACCOUNT? SIGN UP",
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.accent,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ── Phone Sub-View ─────────────────────────────────────────────

  Widget _buildPhoneView(
    AuthState2 authState,
    AuthNotifier authNotifier,
    bool isLoading,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),

        // Back to main (discards any pending OTP state).
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: isLoading
                ? null
                : () => setState(() {
                      _currentView = _SignInView.main;
                      _otpController.clear();
                      _resendTimer?.cancel();
                      _resendSecondsRemaining = 0;
                      authNotifier.resetState();
                    }),
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: AppColors.textPrimary,
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Phone input / OTP section.
        if (!authState.otpSent) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              'PHONE NUMBER',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IntlPhoneField(
            initialCountryCode: 'IN',
            initialValue: _phoneLocal,
            disableLengthCheck: false,
            invalidNumberMessage: 'Invalid phone number',
            style: AppTypography.body.copyWith(
              color: AppColors.textPrimary,
              fontSize: 16,
            ),
            cursorColor: AppColors.accent,
            dropdownTextStyle: AppTypography.body.copyWith(
              color: AppColors.textPrimary,
            ),
            flagsButtonPadding: const EdgeInsets.symmetric(horizontal: 10),
            dropdownIcon: const Icon(
              Icons.arrow_drop_down,
              color: AppColors.accent,
            ),
            decoration: InputDecoration(
              hintText: '98765 43210',
              hintStyle: AppTypography.body.copyWith(
                color: AppColors.textMute,
                fontSize: 16,
              ),
              filled: true,
              fillColor: AppColors.input,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide: const BorderSide(
                  color: AppColors.accent,
                  width: 1.5,
                ),
              ),
            ),
            onChanged: (phone) {
              // Strip a leading 0 if users muscle-type "09876…" —
              // IntlPhoneField's raw `number` keeps the leading zero
              // verbatim but Supabase expects a clean E.164 without it.
              final cleaned = phone.number.startsWith('0')
                  ? phone.number.substring(1)
                  : phone.number;
              _phoneE164 = '${phone.countryCode}$cleaned';
              _phoneLocal = cleaned;
            },
          ),
          const SizedBox(height: 20),
          _buildPrimaryButton(
            label: 'SEND OTP',
            isLoading: isLoading,
            onPressed: () {
              if (_phoneE164.length < 8) return;
              authNotifier.signInWithPhone(_phoneE164);
              // Start the resend cooldown immediately — avoids racing the
              // state update from the notifier (user should always see the
              // countdown kick in on SEND tap).
              _startResendCooldown();
            },
          ),
        ] else ...[
          Text(
            'Enter the OTP sent to $_phoneE164',
            style: AppTypography.body.copyWith(
              color: AppColors.textDim,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          // Change-number link — backs out of OTP entry to phone input
          // without fully resetting the main sign-in view, and keeps the
          // phone number pre-filled so the user can edit just the digits.
          GestureDetector(
            onTap: isLoading
                ? null
                : () {
                    _resendTimer?.cancel();
                    _otpController.clear();
                    authNotifier.resetPhoneFlow();
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.arrow_back,
                    size: 14,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Change number',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _otpController,
            hintText: '6-digit OTP',
            keyboardType: TextInputType.number,
            prefixIcon: Icons.pin_outlined,
          ),
          const SizedBox(height: 14),
          // Resend OTP — disabled during cooldown, tappable once the
          // countdown hits 0. Cooldown resets on every resend tap so users
          // can't spam SMS while still getting a clear path back to resend.
          Center(
            child: _resendSecondsRemaining > 0
                ? Text(
                    "Didn't receive it?  Resend in ${_resendSecondsRemaining}s",
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textMute,
                    ),
                  )
                : GestureDetector(
                    onTap: isLoading
                        ? null
                        : () {
                            authNotifier.signInWithPhone(_phoneE164);
                            _startResendCooldown();
                          },
                    child: Text(
                      "Didn't receive it?  Resend OTP",
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          _buildPrimaryButton(
            label: 'VERIFY OTP',
            isLoading: isLoading,
            onPressed: () {
              final otp = _otpController.text.trim();
              if (otp.isEmpty) return;
              authNotifier.verifyOtp(_phoneE164, otp);
            },
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  // ── Reusable Widgets ────────────────────────────────────────────

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    IconData? prefixIcon,
    Widget? suffixIcon,
    bool obscureText = false,
    String? Function(String?)? validator,
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      maxLength: maxLength,
      style: AppTypography.body.copyWith(color: AppColors.textPrimary),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: AppTypography.body.copyWith(
          color: AppColors.textDisabled,
        ),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppColors.textDim, size: 20)
            : null,
        suffixIcon: suffixIcon,
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

  Widget _buildSharpButton({
    required String label,
    required IconData icon,
    required double iconSize,
    required Color background,
    required Color foreground,
    required Color border,
    required VoidCallback? onPressed,
    required bool isLoading,
  }) {
    final disabled = onPressed == null;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            onTap: onPressed,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: border, width: 2),
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
              child: isLoading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: foreground,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: iconSize, color: foreground),
                        const SizedBox(width: 10),
                        Text(
                          label,
                          style: AppTypography.h3.copyWith(
                            fontSize: 12,
                            color: foreground,
                            letterSpacing: 2.5,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          onTap: isLoading ? null : onPressed,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.accent, width: 2),
              borderRadius: BorderRadius.circular(AppRadius.sharp),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      label,
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
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.line2, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.line2, thickness: 1)),
      ],
    );
  }
}

/// Option 1 background hero band: circular gold logo mark + "AVYA"
/// wordmark + double gold rule at the bottom edge, all on solid
/// [AppColors.bgDeep]. Fills the top ~38% of the viewport.
class _HeroLogoBand extends StatelessWidget {
  const _HeroLogoBand({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Container(
        color: AppColors.bgDeep,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo mark — 82dp circle, 2px gold border, faint radial
                  // gold glow. Placeholder "A" glyph in italic serif; can
                  // be swapped later for an SVG/PNG asset without touching
                  // the layout math.
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.accent,
                        width: 2,
                      ),
                      gradient: RadialGradient(
                        colors: [
                          AppColors.accent.withValues(alpha: 0.15),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'A',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 38,
                        fontWeight: FontWeight.w400,
                        color: AppColors.accent,
                        fontStyle: FontStyle.italic,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Wordmark.
                  Text(
                    'AVYA',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.textPrimary,
                      letterSpacing: 8,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'ICANBEFITTER',
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.textMute,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            // Double gold rule at the bottom — same eyebrow language as
            // WardDispatchHeader elsewhere in the app.
            Positioned(
              bottom: 4,
              left: 32,
              right: 32,
              child: Column(
                children: [
                  Container(height: 1, color: AppColors.accent),
                  const SizedBox(height: 3),
                  Container(
                    height: 1,
                    color: AppColors.accent.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
