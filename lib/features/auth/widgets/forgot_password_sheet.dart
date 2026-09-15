import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:icanbefitter/core/router/app_router.dart';

import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/widgets/auth_header.dart';

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

/// The sheet is a two-step flow in ONE surface: ask for the email, then ask
/// for the 6-digit code that lands in the inbox.
///
/// Deliberately not a new route (diagnose c9e2b7). Keeping both steps inside
/// the sheet means the whole recovery entry stays on `/sign-in`, which is
/// already reachable signed-out and already exempt from `_authRedirect` — so
/// there is no new redirect-exemption to get wrong, and `/reset` is reached
/// only AFTER `verifyOTP` has produced a real session, which is precisely what
/// that screen always assumed and never checked.
enum _Step { email, code }

class _ForgotPasswordSheetState extends State<ForgotPasswordSheet> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _sending = false;
  String? _error;
  _Step _step = _Step.email;

  /// The address the code was actually sent to. Held separately from the
  /// controller so the confirmation copy can't drift if the field is edited.
  String _sentTo = '';

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
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
        redirectTo: 'https://app.icanbefitter.com/reset',
      );
      if (!mounted) return;
      // Advance in place rather than popping. The email now carries a 6-digit
      // code, not a link — so the user finishes here, on the device they are
      // already holding.
      setState(() {
        _sending = false;
        _sentTo = email;
        _step = _Step.code;
        _error = null;
      });
    } on AuthException catch (e) {
      setState(() {
        _sending = false;
        _error = e.message;
      });
    } catch (e) {
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('auth_forgot_password_send_failed',
          message: clipped));
      setState(() {
        _sending = false;
        // Rule 17: the real cause in debug, the generic line in release.
        // Until b6e4f2 the generic line was ALL we ever got — the telemetry
        // call above could not land a row (signed-out), so a founder-reported
        // failure on 2026-08-06 left literally zero evidence of what threw.
        // The pre-auth lane now records it; this only helps a debug build.
        _error = kDebugMode
            ? 'Could not send reset link: $clipped'
            : 'Could not send reset link. Try again.';
      });
    }
  }

  /// Exchanges the emailed 6-digit code for a real session.
  ///
  /// This is the whole point of the redesign (diagnose c9e2b7). The old flow
  /// emailed a PKCE link, and PKCE binds that code to the client that REQUESTED
  /// it — the verifier is written to *that* client's storage
  /// (`gotrue_client.dart:1118`). Request the reset in the Android app, open
  /// the mail in a browser, and the exchange has nothing to verify against: no
  /// session is created, and `updateUser` on the reset screen reports the
  /// literal truth, "Auth session missing!". A typed code carries no such
  /// binding, so it works from whatever device happens to be in hand — which
  /// includes the single most common real pattern, request on a laptop and open
  /// the mail on a phone.
  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.client.auth.verifyOTP(
        email: _sentTo,
        token: code,
        type: OtpType.recovery,
      );
      if (!mounted) return;
      // Capture the router BEFORE popping — this element is defunct after.
      final router = GoRouter.of(context);
      // `/reset`'s own guard reads this flag (reset_password_screen.dart:44).
      AppRouter.isPasswordRecovery = true;
      Navigator.of(context).pop();
      router.go('/reset');
    } on AuthException catch (e) {
      setState(() {
        _sending = false;
        // GoTrue's own wording is genuinely useful here — "Token has expired
        // or is invalid" tells the user exactly what to do next.
        _error = e.message;
      });
    } catch (e) {
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent(
          'auth_password_recovery_verify_failed',
          message: clipped));
      setState(() {
        _sending = false;
        _error = kDebugMode
            ? 'Could not verify that code: $clipped'
            : 'Could not verify that code. Try again.';
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
            AuthHeader(
              eyebrow: 'RECRUIT REGISTRY',
              title: _step == _Step.email ? 'Reset password' : 'Enter code',
              // On the code step, back returns to the email field instead of
              // closing — a mistyped address shouldn't cost the whole flow.
              onBack: _sending
                  ? null
                  : () {
                      if (_step == _Step.code) {
                        setState(() {
                          _step = _Step.email;
                          _codeCtrl.clear();
                          _error = null;
                        });
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
            ),
            const SizedBox(height: 6),
            if (_step == _Step.code) ...[
              Text(
                'We sent a 6-digit code to $_sentTo. Enter it here — it works '
                'on this device even if you opened the email elsewhere.',
                style: AppTypography.bodySm.copyWith(color: AppColors.textMute),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              // Distinct key per step so Flutter rebuilds the field instead of
              // reusing the element (which would keep the old controller's
              // selection and re-run autofocus against stale state).
              key: ValueKey(_step),
              controller: _step == _Step.email ? _emailCtrl : _codeCtrl,
              keyboardType: _step == _Step.email
                  ? TextInputType.emailAddress
                  : TextInputType.number,
              maxLength: _step == _Step.email ? null : 6,
              buildCounter: (_,
                      {required int currentLength,
                      required bool isFocused,
                      int? maxLength}) =>
                  null,
              autofocus: true,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                hintText: _step == _Step.email ? 'you@example.com' : '123456',
                hintStyle: AppTypography.body.copyWith(
                  color: AppColors.textMute,
                  fontSize: 16,
                ),
                prefixIcon: Icon(
                  _step == _Step.email
                      ? Icons.email_outlined
                      : Icons.pin_outlined,
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
              onTap: _sending
                  ? null
                  : (_step == _Step.email ? _send : _verifyCode),
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
                      // No longer "SEND RESET LINK" — there is no link any
                      // more, and copy that promises one would be a lie.
                      _step == _Step.email
                          ? (_sending ? 'SENDING…' : 'SEND CODE')
                          : (_sending ? 'VERIFYING…' : 'VERIFY CODE'),
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
