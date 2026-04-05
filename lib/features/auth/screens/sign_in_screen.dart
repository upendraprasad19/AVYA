import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

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
  final _formKey = GlobalKey<FormState>();

  bool _isSignUp = false;
  bool _obscurePassword = true;
  _SignInView _currentView = _SignInView.main;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
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
              style: AppTypography.bodyM.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.row),
            ),
          ),
        );
        authNotifier.resetState();
      }
      if (next.status == AuthStatus.success) {
        context.go('/splash');
      }
    });

    final isLoading = authState.status == AuthStatus.loading;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
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
    );
  }

  // ── Main View ──────────────────────────────────────────────────

  Widget _buildMainView(AuthNotifier authNotifier, bool isLoading) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),

        // AVYA logo
        _buildLogo(),
        const SizedBox(height: 12),

        // Tagline
        Text(
          'AI-powered fitness & nutrition',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          'built for Indian lifestyles',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),

        // ── Continue with Google — PRIMARY ──────────────────
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: isLoading ? null : () => authNotifier.signInWithGoogle(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white.withAlpha(150),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              elevation: 2,
              shadowColor: Colors.black.withAlpha(40),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.black,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.g_mobiledata,
                        size: 28,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Continue with Google',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Continue with Phone — SECONDARY ─────────────────
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: isLoading
                ? null
                : () => setState(() => _currentView = _SignInView.phone),
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.card,
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border, width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.phone_outlined,
                  size: 20,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 10),
                Text(
                  'Continue with Phone',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Divider ─────────────────────────────────────────
        _buildDivider(),
        const SizedBox(height: 20),

        // ── Continue with Email — TERTIARY ──────────────────
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: isLoading
                ? null
                : () => setState(() => _currentView = _SignInView.email),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: AppColors.accent,
              side: BorderSide(
                color: AppColors.accent.withAlpha(77),
                width: 1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.email_outlined,
                  size: 20,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 10),
                Text(
                  'Continue with Email',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),

        // ── Social proof ────────────────────────────────────
        Text(
          'Join 10,000+ Indians on their fitness journey',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        // ── Legal text ──────────────────────────────────────
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary.withAlpha(128),
            ),
            children: [
              const TextSpan(text: 'By continuing, you agree to our '),
              TextSpan(
                text: 'Terms of Service',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: AppColors.accent,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => launchUrl(
                        Uri.parse('https://icanbefitter.vercel.app'),
                        mode: LaunchMode.externalApplication,
                      ),
              ),
              const TextSpan(text: ' & '),
              TextSpan(
                text: 'Privacy Policy',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: AppColors.accent,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => launchUrl(
                        Uri.parse('https://icanbefitter.vercel.app'),
                        mode: LaunchMode.externalApplication,
                      ),
              ),
            ],
          ),
        ),
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

        // Logo (smaller)
        _buildLogo(),
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
                label: _isSignUp ? 'Create Account' : 'Sign In with Email',
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
                      ? 'Already have an account? Sign In'
                      : "Don't have an account? Sign Up",
                  style: AppTypography.bodyM.copyWith(
                    color: AppColors.accent,
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

        // Logo (smaller)
        _buildLogo(),
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
            label: 'Send OTP',
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
            style: AppTypography.bodyM.copyWith(
              color: AppColors.textSecondary,
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
            label: 'Verify OTP',
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

  // ── Logo ────────────────────────────────────────────────────────

  Widget _buildLogo() {
    return Image.asset(
      'assets/avya_logo.png',
      width: 160,
      fit: BoxFit.contain,
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
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: AppTypography.bodyL.copyWith(color: AppColors.textPrimary),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: AppTypography.bodyL.copyWith(
          color: AppColors.textDisabled,
        ),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppColors.textSecondary, size: 20)
            : null,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.input,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
          borderSide: const BorderSide(color: AppColors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
          borderSide: const BorderSide(color: AppColors.red, width: 1.5),
        ),
        errorStyle: AppTypography.bodyS.copyWith(color: AppColors.red),
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
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.accent.withAlpha(100),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          elevation: 4,
          shadowColor: AppColors.accent.withAlpha(60),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
        ),
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
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.border, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or',
            style: AppTypography.bodyM.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.border, thickness: 1)),
      ],
    );
  }
}
