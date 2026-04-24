import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Forgot-password entry sheet. User enters their email, we call Supabase
/// [GoTrueClient.resetPasswordForEmail] which sends a reset link to that
/// email. On success, the sheet closes and shows a snackbar on the parent
/// scaffold.
class ForgotPasswordSheet extends StatefulWidget {
  const ForgotPasswordSheet._();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ForgotPasswordSheet._(),
    );
  }

  @override
  State<ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<ForgotPasswordSheet> {
  final _emailCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'https://icanbefitter.vercel.app/reset',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reset link sent to $email. Check your inbox.',
            style: AppTypography.bodySm.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.ok,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sharp),
          ),
        ),
      );
    } on AuthException catch (e) {
      setState(() {
        _sending = false;
        _error = e.message;
      });
    } catch (_) {
      setState(() {
        _sending = false;
        _error = 'Could not send reset link. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle.
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'RESET YOUR PASSWORD',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'We\'ll email you a link.',
              style: AppTypography.h3.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                hintText: 'you@example.com',
                hintStyle: AppTypography.body.copyWith(
                  color: AppColors.textMute,
                  fontSize: 16,
                ),
                prefixIcon: const Icon(
                  Icons.email_outlined,
                  color: AppColors.accent,
                  size: 20,
                ),
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
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: AppTypography.bodySm.copyWith(color: AppColors.bad),
              ),
            ],
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _sending ? null : _send,
              child: Opacity(
                opacity: _sending ? 0.6 : 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Center(
                    child: Text(
                      _sending ? 'SENDING…' : 'SEND RESET LINK',
                      style: AppTypography.mono.copyWith(
                        color: AppColors.bgDeep,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _sending ? null : () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
