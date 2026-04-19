import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';

import '../providers/auth_provider.dart';

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
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _referralController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final _privacyTapRecognizer = TapGestureRecognizer();
  final _termsTapRecognizer = TapGestureRecognizer();

  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _consentGiven = false;
  bool _showReferralField = false;
  _SignInView _currentView = _SignInView.main;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _referralController.dispose();
    _privacyTapRecognizer.dispose();
    _termsTapRecognizer.dispose();
    super.dispose();
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

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed background image (same as splash)
          Image.asset('assets/avya_logo.png', fit: BoxFit.cover),
          // Dark overlay for text readability
          Container(color: AppColors.bg.withValues(alpha: 0.55)),
          // Content on top
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                child: _currentView == _SignInView.main
                    ? _buildMainView(authNotifier, isLoading)
                    : _currentView == _SignInView.email
                        ? _buildEmailView(authNotifier, isLoading)
                        : _buildPhoneView(authState, authNotifier, isLoading),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Main View ──────────────────────────────────────────────────

  Widget _buildMainView(AuthNotifier authNotifier, bool isLoading) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),

        // Tagline (logo is now the full-screen background)
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

        // ── Consent checkbox (DPDP compliance) ─────────────
        GestureDetector(
          onTap: () => setState(() => _consentGiven = !_consentGiven),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: _consentGiven,
                  onChanged: (v) => setState(() => _consentGiven = v ?? false),
                  activeColor: AppColors.accent,
                  checkColor: Colors.black,
                  side: BorderSide(
                    color: _consentGiven ? AppColors.accent : AppColors.textSecondary,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textDim,
                    ),
                    children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                        recognizer: _privacyTapRecognizer
                          ..onTap = () => launchUrl(
                                Uri.parse('https://icanbefitter.vercel.app/privacy'),
                                mode: LaunchMode.externalApplication,
                              ),
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                        recognizer: _termsTapRecognizer
                          ..onTap = () => launchUrl(
                                Uri.parse('https://icanbefitter.vercel.app/terms'),
                                mode: LaunchMode.externalApplication,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Continue with Google — PRIMARY ──────────────────
        _buildSharpButton(
          label: 'CONTINUE WITH GOOGLE',
          icon: Icons.g_mobiledata,
          iconSize: 28,
          background: Colors.white,
          foreground: Colors.black,
          border: Colors.white,
          onPressed: isLoading || !_consentGiven
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
          onPressed: isLoading || !_consentGiven
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
          onPressed: isLoading || !_consentGiven
              ? null
              : () => setState(() => _currentView = _SignInView.email),
          isLoading: false,
        ),
        const SizedBox(height: 32),

        // ── Social proof ────────────────────────────────────
        Text(
          'JOIN 10,000+ INDIANS ON THEIR FITNESS JOURNEY',
          style: AppTypography.monoXs.copyWith(
            color: AppColors.textMute,
            letterSpacing: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        // ── Referral code (optional) ────────────────────────
        GestureDetector(
          onTap: () => setState(() => _showReferralField = !_showReferralField),
          child: Text(
            _showReferralField ? 'HIDE REFERRAL CODE' : 'HAVE A REFERRAL CODE?',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.accent,
              letterSpacing: 1.5,
            ),
          ),
        ),
        if (_showReferralField) ...[
          const SizedBox(height: 10),
          _buildTextField(
            controller: _referralController,
            hintText: 'Enter referral code (e.g. AVYA-XXXX1234)',
            prefixIcon: Icons.card_giftcard,
            maxLength: 20,
          ),
        ],

        const SizedBox(height: 40),
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
                      _otpController.clear();
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

        const SizedBox(height: 32),

        // Phone input / OTP section
        if (!authState.otpSent) ...[
          _buildTextField(
            controller: _phoneController,
            hintText: 'Phone number (+91...)',
            keyboardType: TextInputType.phone,
            prefixIcon: Icons.phone_outlined,
          ),
          const SizedBox(height: 24),
          _buildPrimaryButton(
            label: 'SEND OTP',
            isLoading: isLoading,
            onPressed: () {
              final phone = _phoneController.text.trim();
              if (phone.isEmpty) return;
              authNotifier.signInWithPhone(phone);
            },
          ),
        ] else ...[
          Text(
            'Enter the OTP sent to ${_phoneController.text.trim()}',
            style: AppTypography.body.copyWith(
              color: AppColors.textDim,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _otpController,
            hintText: '6-digit OTP',
            keyboardType: TextInputType.number,
            prefixIcon: Icons.pin_outlined,
          ),
          const SizedBox(height: 24),
          _buildPrimaryButton(
            label: 'VERIFY OTP',
            isLoading: isLoading,
            onPressed: () {
              final phone = _phoneController.text.trim();
              final otp = _otpController.text.trim();
              if (otp.isEmpty) return;
              authNotifier.verifyOtp(phone, otp);
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
