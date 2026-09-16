import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

/// Landing screen for a signup-confirmation link
/// (`/confirm?token_hash=...`), reached either via the web SPA or — on
/// Android — via App Link straight into the app.
///
/// [tokenHash] is extracted by the router from the query string; a missing
/// or empty value means the link was malformed/stripped and is shown as an
/// error immediately, with no Supabase call attempted. Verification runs
/// once via [AuthNotifier.confirmEmail]; success routes into `/restoring`
/// (the same post-auth convergence point every other sign-in path uses),
/// failure shows a persistent error state — there is no form here to retry
/// from, so a snackbar that could go unread is the wrong shape.
class ConfirmEmailScreen extends ConsumerStatefulWidget {
  const ConfirmEmailScreen({super.key, this.tokenHash});

  final String? tokenHash;

  @override
  ConsumerState<ConfirmEmailScreen> createState() =>
      _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends ConsumerState<ConfirmEmailScreen> {
  // Tracks WHICH token_hash verification has already been triggered for —
  // not just whether any verification has started. A bare bool would
  // permanently block a second, different token_hash delivered to this same
  // mounted State: go_router's pageKey is path-only (`ValueKey('/confirm')`,
  // no query string — go_router-17.2.3 match.dart:227-251), and Android's
  // singleTop launch mode (AndroidManifest.xml, shared with the OAuth
  // callback) delivers a second `/confirm?token_hash=...` intent to the
  // already-running Activity via onNewIntent while the first is still the
  // matched location — e.g. two confirmation-link taps in quick succession.
  // Flutter then reuses the Element/State and calls didUpdateWidget, not
  // initState, so both arms must be guarded.
  String? _startedFor;

  @override
  void initState() {
    super.initState();
    _maybeStartVerification(widget.tokenHash);
  }

  @override
  void didUpdateWidget(covariant ConfirmEmailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tokenHash != oldWidget.tokenHash) {
      _maybeStartVerification(widget.tokenHash);
    }
  }

  void _maybeStartVerification(String? tokenHash) {
    if (tokenHash == null || tokenHash.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_startedFor == tokenHash || !mounted) return;
      _startedFor = tokenHash;
      ref.read(authNotifierProvider.notifier).confirmEmail(tokenHash);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokenHash = widget.tokenHash;
    if (tokenHash == null || tokenHash.isEmpty) {
      return _buildErrorState(
        context,
        'This confirmation link is missing its token. Copy the full link '
        'from your email, or request a new one from the sign-in screen.',
      );
    }

    ref.listen<AuthState2>(authNotifierProvider, (previous, next) {
      if (next.status == AuthStatus.success) {
        // Same convergence point every other sign-in path uses — see
        // sign_in_screen.dart's identical ref.listen.
        context.go('/restoring');
      }
    });

    final authState = ref.watch(authNotifierProvider);
    if (authState.status == AuthStatus.error) {
      // Distinct from the generic error CTA (round 2 finding): navigating to
      // /sign-in while still authenticated is a silent no-op — _authRedirect
      // bounces straight back to /home before SignInScreen ever renders — so
      // this specific message needs an action that actually signs out first.
      if (authState.errorMessage ==
          AuthNotifier.alreadyAuthenticatedConfirmMessage) {
        return _buildAlreadySignedInState(context);
      }
      return _buildErrorState(
        context,
        authState.errorMessage ??
            'This confirmation link is invalid or has expired.',
      );
    }

    return _buildLoadingState(context);
  }

  Widget _buildLoadingState(BuildContext context) {
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
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.stackM),
                Text(
                  'Confirming your account...',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(color: AppColors.textDim),
                ),
                const SizedBox(height: AppSpacing.stackL),
                // Escape hatch: confirmEmail is bounded by signInTimeout, but
                // that still leaves up to that long with nothing tappable —
                // this fires automatically on mount with no prior user
                // gesture, unlike a hung sign-in the user can at least
                // correlate with their own tap. Always visible, not staged
                // behind a delay, so there is never a moment with no way out.
                _buildSignInLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
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
                  message,
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(color: AppColors.textDim),
                ),
                const SizedBox(height: AppSpacing.stackL),
                _buildSignInLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Distinct from [_buildErrorState]: the CTA here actually signs the user
  /// out before navigating, rather than merely calling `context.go`, which
  /// `_authRedirect` would otherwise bounce straight back to `/home` for an
  /// authenticated, onboarded user before `SignInScreen` ever rendered
  /// (round-2 finding — the same class as `reset_password_screen.dart`'s
  /// diagnose c8f1d3: a screen that signs out in place must navigate
  /// explicitly afterward, since GoRouter has no `refreshListenable` tied to
  /// auth state).
  Widget _buildAlreadySignedInState(BuildContext context) {
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
                  AuthNotifier.alreadyAuthenticatedConfirmMessage,
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(color: AppColors.textDim),
                ),
                const SizedBox(height: AppSpacing.stackL),
                GestureDetector(
                  onTap: () async {
                    await ref.read(authNotifierProvider.notifier).signOut();
                    if (context.mounted) context.go('/sign-in');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Center(
                      child: Text(
                        'SIGN OUT',
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

  Widget _buildSignInLink() {
    return GestureDetector(
      onTap: () => context.go('/sign-in'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Center(
          child: Text(
            'GO TO SIGN IN',
            style: AppTypography.h3.copyWith(
              fontSize: 12,
              color: AppColors.bgDeep,
              letterSpacing: 2.5,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
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
          child: Image.asset('assets/avya_icon.png', width: 32, height: 32),
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
          'CONFIRM ACCOUNT',
          textAlign: TextAlign.center,
          style: AppTypography.h2.copyWith(
            fontSize: 24,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.stackXL),
      ],
    );
  }
}
