// lib/features/profile/screens/delete_account_screen.dart
//
// DPDP-compliant hard-delete flow (Task H1, APK Test #11).
//
// Two-step confirm:
//   Step 1 — Blast-radius page. Lists exactly what is deleted and what
//             stays (DPDP §6 disclosure requirement). Gold "KEEP MY
//             ACCOUNT" is the safe-path CTA. Ghost "CONTINUE" advances
//             to step 2.
//   Step 2 — Type-to-confirm. User must enter their first name (case-
//             insensitive) followed by the word DELETE (case-sensitive,
//             uppercase only). Enables the final "IRREVERSIBLE — DELETE
//             MY ACCOUNT" button (AppColors.bad background).
//
// On confirm:
//   1. Invokes delete-account Edge Function with confirmation token
//      'DELETE-MY-ACCOUNT-<userId.substring(0,8)>'.
//   2. On 200: UserRepository.instance.clearAllData() + auth.signOut()
//              + navigate to '/sign-in'.
//   3. On error: error-code-aware snackbar, no Hive wipe.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show SignOutScope, FunctionException;

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  // 1 = blast-radius page, 2 = type-to-confirm
  int _step = 1;
  bool _loading = false;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  // Validation state
  bool get _confirmValid {
    final profile = ref.read(userProfileProvider);
    final fullName = (profile['full_name'] as String?) ?? '';
    final firstName = fullName.split(' ').first;
    if (firstName.isEmpty) return false;

    final text = _controller.text.trim();
    // Split on first space only — anything after first word is the suffix
    final spaceIdx = text.indexOf(' ');
    if (spaceIdx < 0) return false;
    final enteredFirst = text.substring(0, spaceIdx);
    final enteredSuffix = text.substring(spaceIdx + 1);

    // First name: case-insensitive match
    final firstNameOk =
        enteredFirst.toLowerCase() == firstName.toLowerCase();
    // DELETE: case-sensitive (must be uppercase)
    final deleteSuffixOk = enteredSuffix == 'DELETE';
    return firstNameOk && deleteSuffixOk;
  }

  // ── Placeholder for tests — overridable ──────────────────────────
  @visibleForTesting
  Future<Map<String, dynamic>> invokeDeleteFunction(
      String confirmationToken) async {
    // §2.31 / Obs#9: callFunction refreshes the JWT before the authed invoke.
    // The raw invoke sent whatever (possibly stale, backgrounded-web) token
    // supabase-js held → delete-account 401'd → "Couldn't delete account".
    final response = await SupabaseService.instance.callFunction(
      'delete-account',
      body: {'confirmation_token': confirmationToken},
    );
    return response.data as Map<String, dynamic>? ?? {};
  }

  Future<void> _onConfirmDelete() async {
    if (!_confirmValid || _loading) return;
    setState(() => _loading = true);

    final userId = SupabaseService.instance.currentUser?.id ?? '';
    final token =
        'DELETE-MY-ACCOUNT-${userId.substring(0, userId.length >= 8 ? 8 : userId.length)}';

    try {
      final result = await invokeDeleteFunction(token);
      // Treat an explicit 'error' field as failure even if no exception
      if (result.containsKey('error') &&
          result['error'] != null &&
          result['error'] != '') {
        throw _DeleteAccountException(
            code: result['error'] as String? ?? 'unknown');
      }

      // ── Success path ──────────────────────────────────────────────
      // Clear all local Hive data, then sign out server-side.
      await UserRepository.instance.clearAllData();
      await SupabaseService.instance.client.auth
          .signOut(scope: SignOutScope.global);

      if (mounted) {
        context.go('/sign-in');
      }
    } on _DeleteAccountException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showError(e.code);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        // Attempt to decode a structured error from FunctionException.
        final msg = e.toString();
        if (e is FunctionException && e.status == 401) {
          // Stale/expired session token — callFunction's refresh couldn't
          // recover (user effectively logged out). Obs#9: this used to fall
          // through to the opaque "generic" error on every backgrounded-web tap.
          _showError('session_expired');
        } else if (msg.contains('razorpay_cancel_failed')) {
          _showError('razorpay_cancel_failed');
        } else if (msg.contains('confirmation_token_mismatch')) {
          _showError('confirmation_token_mismatch');
        } else {
          _showError('generic');
        }
      }
    }
  }

  void _showError(String code) {
    String message;
    switch (code) {
      case 'session_expired':
        message =
            "Your session expired. Sign out, sign back in, then try again.";
        break;
      case 'razorpay_cancel_failed':
        message =
            "Couldn't cancel your subscription. Contact support@icanbefitter.com.";
        break;
      case 'confirmation_token_mismatch':
        message = "Confirmation didn't match. Please try again.";
        break;
      default:
        message =
            "Couldn't delete account. Try again or contact support.";
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AppTypography.body),
        backgroundColor: AppColors.bad,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppColors.textPrimary, size: 20),
          onPressed: () {
            if (_step == 2) {
              // Back from step 2 goes to step 1
              setState(() {
                _step = 1;
                _controller.clear();
              });
            } else {
              context.pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _step == 1 ? _buildStep1() : _buildStep2(),
        ),
      ),
    );
  }

  // ── Step 1 — blast radius ─────────────────────────────────────────

  Widget _buildStep1() {
    return SingleChildScrollView(
      key: const ValueKey('step1'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        12,
        AppSpacing.gutter,
        AppSpacing.stackXL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow
          Text(
            '⊙  ACCOUNT ERASURE  ·  DPDP',
            style: AppTypography.mono.copyWith(
              fontSize: 10,
              letterSpacing: 1.2,
              color: AppColors.bad,
            ),
          ),
          const SizedBox(height: 8),
          Container(width: 60, height: 1, color: AppColors.bad),
          const SizedBox(height: 20),

          // Title
          Text(
            'Permanent deletion.',
            style: AppTypography.h1,
          ),
          const SizedBox(height: 24),

          // ── What will be deleted ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                  color: AppColors.bad.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'THIS WILL PERMANENTLY:',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.bad,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                ..._bullets([
                  'Delete your profile, workouts, meals, weight history, photos.',
                  'Cancel your active subscription (no refund — request via support if applicable).',
                  'Sign you out on every device.',
                ], color: AppColors.bad),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── What stays ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border:
                  Border.all(color: AppColors.line2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WHAT STAYS:',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                ..._bullets([
                  'Your Razorpay payment receipts (Razorpay retains these per Indian tax law).',
                  'Anonymous community contributions you\'ve made (custom exercises/foods you submitted to the public library — your name is removed but the entry remains).',
                  'Backups will purge within 30 days.',
                ], color: AppColors.textDim),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Cannot be undone note
          Center(
            child: Text(
              'This cannot be undone.',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textMute,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ── Primary CTA: keep account ─────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => context.pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                ),
                elevation: 0,
              ),
              child: Text(
                'KEEP MY ACCOUNT',
                style: AppTypography.mono.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                  fontSize: 11,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Ghost CTA: continue to step 2 ────────────────────────
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () => setState(() => _step = 2),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textMute,
                side: BorderSide(
                    color: AppColors.textMute.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                ),
              ),
              child: Text(
                'CONTINUE',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2.5,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2 — type-to-confirm ──────────────────────────────────────

  Widget _buildStep2() {
    final profile = ref.watch(userProfileProvider);
    final fullName = (profile['full_name'] as String?) ?? '';
    final firstName = fullName.split(' ').first;
    final hintName = firstName.isNotEmpty ? firstName : 'Avyaansh';

    return SingleChildScrollView(
      key: const ValueKey('step2'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        12,
        AppSpacing.gutter,
        AppSpacing.stackXL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow
          Text(
            '⊙  CONFIRM ERASURE',
            style: AppTypography.mono.copyWith(
              fontSize: 10,
              letterSpacing: 1.2,
              color: AppColors.bad,
            ),
          ),
          const SizedBox(height: 8),
          Container(width: 60, height: 1, color: AppColors.bad),
          const SizedBox(height: 20),

          // Title
          Text(
            'Type to confirm.',
            style: AppTypography.h1,
          ),
          const SizedBox(height: 8),

          Text(
            'This is irreversible. We need to be sure.',
            style: AppTypography.body.copyWith(
              color: AppColors.textDim,
            ),
          ),

          const SizedBox(height: 28),

          // Field label
          Text(
            'TYPE YOUR FIRST NAME + THE WORD DELETE',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),

          // Text field
          TextFormField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            style: AppTypography.body.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: '$hintName DELETE',
              hintStyle: AppTypography.body.copyWith(
                color: AppColors.textGhost,
              ),
              filled: true,
              fillColor: AppColors.input,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide:
                    const BorderSide(color: AppColors.line2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide:
                    const BorderSide(color: AppColors.line2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide:
                    BorderSide(color: AppColors.bad.withValues(alpha: 0.6)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
            ),
          ),

          const SizedBox(height: 8),

          // Inline hint
          Text(
            'e.g. "$hintName DELETE"  (DELETE must be uppercase)',
            style: AppTypography.bodySm.copyWith(color: AppColors.textMute),
          ),

          const SizedBox(height: 32),

          // Final delete button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _confirmValid && !_loading
                  ? _onConfirmDelete
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.bad,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.bad.withValues(alpha: 0.25),
                disabledForegroundColor:
                    Colors.white.withValues(alpha: 0.38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'IRREVERSIBLE — DELETE MY ACCOUNT',
                      style: AppTypography.mono.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.8,
                        fontSize: 10,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 16),

          // Back link
          Center(
            child: TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                        _step = 1;
                        _controller.clear();
                      }),
              child: Text(
                'BACK',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helper ────────────────────────────────────────────────────────

  List<Widget> _bullets(List<String> texts, {required Color color}) {
    return texts
        .map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 8),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    t,
                    style: AppTypography.body
                        .copyWith(color: AppColors.textDim),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }
}

// ── Internal exception type ───────────────────────────────────────────

class _DeleteAccountException implements Exception {
  const _DeleteAccountException({required this.code});
  final String code;
}
