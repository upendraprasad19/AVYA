import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:icanbefitter/core/router/app_router.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
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
  }

  @override
  void dispose() {
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

      if (!mounted) return;

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

      // Sign out so GoRouter redirects to /sign-in.
      await Supabase.instance.client.auth.signOut();
      // Reset the recovery flag so the guard on next mount works.
      AppRouter.isPasswordRecovery = false;
      // The router's _authRedirect handles the navigation automatically.
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

  @override
  Widget build(BuildContext context) {
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
