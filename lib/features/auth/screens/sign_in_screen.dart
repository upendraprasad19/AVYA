import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

import '../providers/auth_provider.dart';

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
  bool _showPhoneInput = false;
  bool _obscurePassword = true;

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
        context.go('/onboarding');
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),

                // ── Logo / App Name ─────────────────────────────
                _buildLogo(),
                const SizedBox(height: 8),
                Text(
                  'Your AI Fitness Coach',
                  style: AppTypography.bodyL.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 48),

                // ── Phone OTP flow OR Email flow ────────────────
                if (_showPhoneInput) ...[
                  _buildPhoneSection(authState, authNotifier, isLoading),
                ] else ...[
                  _buildEmailSection(authNotifier, isLoading),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Logo ────────────────────────────────────────────────────────

  Widget _buildLogo() {
    return Column(
      children: [
        // Icon placeholder
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.accentTint,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.accent.withAlpha(77),
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.fitness_center,
            color: AppColors.accent,
            size: 40,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'ICANBEFITTER',
          style: AppTypography.displayL.copyWith(
            color: AppColors.accent,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  // ── Email Section ───────────────────────────────────────────────

  Widget _buildEmailSection(AuthNotifier authNotifier, bool isLoading) {
    return Form(
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
              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value.trim())) {
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
          const SizedBox(height: 24),

          // ── Divider ─────────────────────────────────────────
          _buildDivider(),
          const SizedBox(height: 24),

          // ── Continue with Google ────────────────────────────
          _buildSecondaryButton(
            label: 'Continue with Google',
            icon: Icons.g_mobiledata,
            isLoading: isLoading,
            onPressed: () => authNotifier.signInWithGoogle(),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          // ── Sign in with Phone ─────────────────────────────
          TextButton.icon(
            onPressed: isLoading
                ? null
                : () => setState(() => _showPhoneInput = true),
            icon: Icon(
              Icons.phone_outlined,
              color: AppColors.textSecondary,
              size: 18,
            ),
            label: Text(
              'Sign in with Phone',
              style: AppTypography.bodyM.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Phone Section ───────────────────────────────────────────────

  Widget _buildPhoneSection(
    AuthState2 authState,
    AuthNotifier authNotifier,
    bool isLoading,
  ) {
    return Column(
      children: [
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
        const SizedBox(height: 16),
        TextButton(
          onPressed: isLoading
              ? null
              : () => setState(() {
                    _showPhoneInput = false;
                    _otpController.clear();
                    ref.read(authNotifierProvider.notifier).resetState();
                  }),
          child: Text(
            'Back to Email sign in',
            style: AppTypography.bodyM.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
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

  Widget _buildSecondaryButton({
    required String label,
    required IconData icon,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: Icon(icon, size: 24),
        label: Text(
          label,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.accent,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          backgroundColor: AppColors.accentTint,
          side: BorderSide(
            color: AppColors.accent.withAlpha(77),
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
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
