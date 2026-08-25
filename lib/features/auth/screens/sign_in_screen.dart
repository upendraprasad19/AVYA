import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../providers/auth_provider.dart';
import '../widgets/auth_header.dart';
import '../widgets/forgot_password_sheet.dart';

/// Enum for the current sign-in view.
enum _SignInView { main, email, phone }

// Phone OTP disabled — Twilio not wired to Supabase Auth (AUTH-04). Flip true once wired.
const bool _kEnablePhoneEnlist = false;

// Google's official multicolor "G" mark (same paths as the approved mockup,
// docs/mockups/2026-08-03-sign-in-google-card-v1.html) — Google's brand
// guidelines require the mark to render unmodified, not recolored to match
// the app's own palette.
const String _googleGSvg = '''
<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
  <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.9-2.26 5.36-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
  <path fill="#FBBC05" d="M10.53 28.59a14.5 14.5 0 0 1-.76-4.59c0-1.59.27-3.13.76-4.59l-7.98-6.19A24 24 0 0 0 0 24c0 3.87.92 7.53 2.56 10.78z"/>
  <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.9l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>
''';

/// Steps within the email sub-view, reached once the merged main view's
/// CONTINUE button has run the server-side registration check
/// (`AuthNotifier.checkEmailRegistered`) and branched automatically — no
/// manual toggle. (Sign-in redesign, 2026-08: email entry used to be its
/// own `enterEmail` step here; it now lives inline on the main view so the
/// funnel is 2 screens instead of 3.)
enum _EmailStep { signIn, signUp }

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

  // Overwritten by the main view's CONTINUE handler before _currentView
  // ever switches to .email — the initial value is never read.
  _EmailStep _emailStep = _EmailStep.signIn;
  bool _obscurePassword = true;
  _SignInView _currentView = _SignInView.main;

  /// Synchronous reentrancy guard for the main view's CONTINUE button.
  /// `isLoading` (derived from provider state) only disables the button on
  /// the NEXT frame after `checkEmailRegistered` sets AuthStatus.loading, so
  /// a same-frame double-tap can start the RPC twice. This field is set
  /// before the first `await` so a second tap in the same frame is rejected
  /// immediately (B-pass finding 4, 96afd825-review.md).
  bool _checkingEmail = false;

  /// Starts UNCHECKED — the user's tick is the clear affirmative action.
  ///
  /// ⚠ THIS REVERSES THE EARLIER Q2 DECISION, which pre-checked the box to
  /// reduce signup friction on the grounds that "tapping CREATE ACCOUNT with
  /// the checkbox checked is the affirmative action", citing the common Indian
  /// fintech pattern (CRED, Zerodha, Razorpay).
  ///
  /// Changed for the Play Store launch. DPDP §6(1) requires consent given by a
  /// "clear affirmative action", and a pre-ticked box is the textbook example
  /// of what does NOT qualify (the GDPR equivalent was settled in Planet49).
  /// The button-press argument is arguable, but this app processes HEALTH data
  /// and is going through Play review with a Data Safety declaration — the
  /// weaker reading is not worth defending there.
  ///
  /// COST, stated plainly: CREATE ACCOUNT is now disabled until the user ticks,
  /// which will cost some signup conversion. That is a product trade-off, not a
  /// pure compliance win. Reverting is a one-word change back to `true`.
  bool _privacyAccepted = false;

  @override
  void initState() {
    super.initState();
    // OBS-A fix (Test #4 batch): TermsModal trigger REMOVED on sign-in screen mount.
    //
    // The Q2 design (APK Test #2) covers ToS/Privacy via:
    //   (a) inline footer on welcome screen
    //   (b) UNCHECKED consent checkbox above SIGN UP (gates the button) —
    //       un-ticked 2026-08-25; the tick is the DPDP affirmative action
    //   (c) returning users have users.terms_accepted_at synced from cloud
    //       to Hive on _ensureLocalUser (auth_provider.dart:466)
    //
    // The modal call here was a pre-Q2 leftover that fired on every sign-in
    // screen mount, including the gap between sign-out and sign-in completion
    // (before cloud sync rehydrates Hive). Returning users hit it incorrectly.
    // Q2 design fully replaces it; the modal is no longer needed on this path.
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
            final configBox = HiveService.instance.configBox;
            configBox.put('pending_referral_code', code);
          } catch (_) {}
          SupabaseService.instance
              .callFunction('redeem-referral', body: {'code': code})
              .then((_) {
                debugPrint('[SignIn] Referral code redeemed: $code');
                // Clear pending code on success
                try {
                  HiveService.instance.configBox.delete(
                    'pending_referral_code',
                  );
                } catch (_) {}
              })
              .catchError((e) {
                debugPrint(
                  '[SignIn] Referral redemption failed (will retry on next launch): $e',
                );
              });
        }
        // Q1: Route through RestoringScreen instead of /splash.
        // RestoringScreen runs the post-auth decision tree:
        //   onboarded → restore + /home
        //   mid-onboarding → resume at correct step
        //   no profile row → /onboarding/mission-brief
        context.go('/restoring');
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
        child: switch (_currentView) {
          _SignInView.main => _buildRootWithHero(authNotifier, isLoading),
          _SignInView.email => _buildEmailRoot(authNotifier, isLoading),
          _SignInView.phone => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            child: _buildPhoneView(authState, authNotifier, isLoading),
          ),
        },
      ),
    );
  }

  /// Root for the email sub-view — unlike the shared `SingleChildScrollView`
  /// the phone view still uses, this centers short content vertically while
  /// still scrolling (not clipping) when the on-screen keyboard opens or the
  /// form grows past the viewport.
  Widget _buildEmailRoot(AuthNotifier authNotifier, bool isLoading) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: _buildEmailView(authNotifier, isLoading)),
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

  // ── Main View — Direction B redesign (U9, APK Test #4) ───────────
  //
  // Changes vs previous version:
  // - All 3 auth buttons unified to dark+gold-outline style
  // - 'CONTINUE WITH' → 'ENLIST VIA' (Captain voice)
  // - 'OR' divider → 'AUX' with thin gold rules
  // - 'AI-POWERED FITNESS & NUTRITION' → 'FITNESS · NUTRITION · DISCIPLINE'
  // - Manifesto line: 'Discipline. Honest data. Twelve months. We change the man.'
  // - 'JOIN 10,000+...' → 'ENLISTED · 18,866 SAILORS ACTIVE'
  // - Mil-stamp footer: 'AVYA · v1.0.0+3 · ISSUED 2026'
  // - 'Forgot password?' → 'RESET ACCESS'
  // - Vertical spacing tightened ~20%

  Widget _buildMainView(AuthNotifier authNotifier, bool isLoading) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 18),

          // Tagline — Direction B: discipline-first
          Text(
            'FITNESS · NUTRITION · DISCIPLINE',
            style: AppTypography.mono.copyWith(
              color: AppColors.accent,
              letterSpacing: 2.0,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'BUILT FOR INDIAN LIFESTYLES',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),

          // Captain-voice manifesto
          Text(
            'Discipline. Honest data.\nTwelve months. We change the man.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(
              fontSize: 13,
              height: 1.5,
              fontStyle: FontStyle.italic,
              color: AppColors.textDim,
            ),
          ),
          const SizedBox(height: 18),

          // ── Sign-in card (Google-primary redesign, 2026-08) ──────────
          // Enclosed Wardroom card holding Google sign-in (primary CTA,
          // styled per Google's own brand spec — NOT reskinned gold, so it
          // reads unmistakably as Google), an OR divider, the email field,
          // and a visually-secondary CONTINUE button. Approved mockup:
          // docs/mockups/2026-08-03-sign-in-google-card-v1.html. Phone OTP
          // stays out of scope — still flagged off (_kEnablePhoneEnlist),
          // left exactly as it was, structurally unmoved.
          WardCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Gated on _checkingEmail too (B-pass finding, 03a8ce7c088d-review.md
                // #2): pre-redesign, Google and the email-check button lived on
                // separate _SignInView states and could never be interacted with
                // concurrently. Merging them onto one view opened a same-frame
                // window (isLoading only reflects AuthStatus.loading on the NEXT
                // frame) where Google could fire while checkEmailRegistered is
                // still in flight, racing two auth operations against the same
                // AuthNotifier. The `isLoading || _checkingEmail` ternary below
                // only disables the button on the NEXT build — it doesn't stop a
                // tap that lands in the same frame as CONTINUE's tap, before that
                // rebuild runs (plan-review round 1, Finding 1). The `if
                // (_checkingEmail) return;` guard inside the callback itself reads
                // the field live at call time, so it closes that window too.
                _buildGoogleSignInButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          if (_checkingEmail) return;
                          authNotifier.signInWithGoogle();
                        },
                  isLoading: isLoading,
                ),

                if (_kEnablePhoneEnlist) ...[
                  const SizedBox(height: 10),
                  // ── ENLIST VIA PHONE ─────────────────────────────────
                  // Same guard as Google above, same reason.
                  _buildEnlistButton(
                    label: 'ENLIST VIA PHONE',
                    icon: Icons.phone_outlined,
                    iconSize: 18,
                    onPressed: isLoading
                        ? null
                        : () {
                            if (_checkingEmail) return;
                            setState(() => _currentView = _SignInView.phone);
                          },
                    isLoading: false,
                  ),
                ],

                const SizedBox(height: 14),
                _buildOrDivider(),
                const SizedBox(height: 14),

                // ── Email entry, inline (sign-in redesign 2026-08) ───
                // Was its own "ENLIST VIA EMAIL" → tap → separate screen with just
                // this field. Now the field lives directly on the entry screen so
                // Google-or-email is a single step; CONTINUE runs the same
                // server-side registration check as before and branches straight
                // to the sign-in or sign-up step.
                _buildTextField(
                  controller: _emailController,
                  hintText: 'Email address',
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.email_outlined,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!RegExp(
                      r'^[^@]+@[^@]+\.[^@]+$',
                    ).hasMatch(value.trim())) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                // CONTINUE reads as visually secondary to the Google button
                // above (smaller height/radius/type-scale via `compact:
                // true`) so hierarchy is unambiguously Google-first — the
                // shared _buildPrimaryButton widget is otherwise unchanged
                // and still used verbatim by the email sign-in/sign-up and
                // phone OTP sub-views below.
                _buildPrimaryButton(
                  label: 'CONTINUE',
                  compact: true,
                  isLoading: isLoading || _checkingEmail,
                  onPressed: () async {
                    if (_checkingEmail) return;
                    if (!_formKey.currentState!.validate()) return;
                    _checkingEmail = true;
                    try {
                      final email = _emailController.text.trim();
                      final registered = await authNotifier
                          .checkEmailRegistered(email);
                      if (!mounted || registered == null) return;
                      setState(() {
                        _emailStep = registered
                            ? _EmailStep.signIn
                            : _EmailStep.signUp;
                        _currentView = _SignInView.email;
                      });
                    } finally {
                      if (mounted) setState(() => _checkingEmail = false);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "We'll take you to sign-in or enlistment.",
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
          ),
          const SizedBox(height: 12),

          // ── RESET ACCESS (formerly Forgot password?) ────────
          GestureDetector(
            onTap: isLoading ? null : () => ForgotPasswordSheet.show(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'RESET ACCESS',
                style: AppTypography.mono.copyWith(
                  color: AppColors.accent,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // U8 fix (Test #4 hotfix): referral code input REMOVED from welcome
          // landing view. Referral entry now lives in sign-up form + Profile.

          // ── Honest belonging cue (F21) ───────────────────────
          // No fabricated head-count: the app is pre-public-launch, so "18,866
          // sailors active" was invented. An integrity-led brand never fakes
          // social proof (psychology-pass ethical line). "Founding cohort /
          // enlistment open" is true (early enrolment) and still confers honest
          // belonging + honest scarcity.
          Text(
            'FOUNDING COHORT · ENLISTMENT OPEN',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textDim,
              letterSpacing: 1.6,
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // ── Mil-stamp footer ─────────────────────────────────
          Text(
            'AVYA · v${AppConstants.appVersion} · ISSUED 2026',
            textAlign: TextAlign.center,
            style: AppTypography.mono.copyWith(
              fontSize: 8,
              letterSpacing: 1.4,
              color: AppColors.textMute,
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  /// Direction B auth button — uniform dark+gold-outline for all 3 providers.
  /// Replaces the old white Google / dim Phone / accent Email trio.
  Widget _buildEnlistButton({
    required String label,
    required IconData icon,
    required double iconSize,
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
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            onTap: onPressed,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.4),
                  width: 1.4,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
              child: isLoading
                  ? Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.accent,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: iconSize, color: AppColors.accent),
                        const SizedBox(width: 12),
                        Text(
                          label,
                          style: AppTypography.mono.copyWith(
                            fontSize: 13,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w800,
                            color: AppColors.accent,
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

  /// "Sign in with Google" — styled per Google's own brand button spec
  /// (white pill, official multicolor "G" mark, dark-grey text) so it reads
  /// unmistakably as Google against the dark Wardroom card, rather than
  /// being reskinned into Campaign Gold like the other auth buttons. This
  /// intentionally does NOT reuse `_buildEnlistButton`'s dark+gold-outline
  /// treatment — Google's brand guidelines are the constraint here, not
  /// the app's own visual system. Embeds the official Google "G" SVG
  /// inline (flutter_svg, already a project dependency) rather than
  /// shipping a new asset file.
  Widget _buildGoogleSignInButton({
    required VoidCallback? onPressed,
    required bool isLoading,
  }) {
    final disabled = onPressed == null;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: Opacity(
        opacity: disabled ? 0.6 : 1,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onPressed,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.googleButtonBorder),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.googleButtonText,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.string(_googleGSvg, width: 18, height: 18),
                        const SizedBox(width: 10),
                        Text(
                          'Sign in with Google',
                          style: AppTypography.body.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.googleButtonText,
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

  /// "OR" divider inside the sign-in card, separating the Google button
  /// from the email flow. Replaces the loose "AUX" divider this card
  /// consolidated — AUX made sense between two identically-styled dark
  /// buttons; inside the card the visual weight difference between the
  /// Google button and the email flow already tells that story, and "AUX"
  /// read as unexplained jargon here. Border-tinted rather than
  /// accent-tinted so it doesn't compete with the card's own edge.
  Widget _buildOrDivider() {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: AppColors.border)),
        const SizedBox(width: 10),
        Text(
          'OR',
          style: AppTypography.mono.copyWith(
            fontSize: 9,
            letterSpacing: 2.0,
            color: AppColors.textGhost,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: AppColors.border)),
      ],
    );
  }

  // ── Email Sub-View ─────────────────────────────────────────────

  Widget _buildEmailView(AuthNotifier authNotifier, bool isLoading) {
    switch (_emailStep) {
      case _EmailStep.signIn:
        return _buildEmailStepSignIn(authNotifier, isLoading);
      case _EmailStep.signUp:
        return _buildEmailStepSignUp(authNotifier, isLoading);
    }
  }

  /// Returns to the merged main view (Google button + email entry),
  /// clearing the password and any stale auth error — mirrors the same
  /// reset `_buildPhoneView`'s back handler already does when backing out
  /// of OTP entry. Pre-redesign this returned to a separate `enterEmail`
  /// step; that step no longer exists, so this now targets `.main` directly.
  void _backToMain(AuthNotifier authNotifier) {
    setState(() {
      _currentView = _SignInView.main;
      _passwordController.clear();
    });
    authNotifier.resetState();
  }

  /// Read-only display of the already-entered, already-checked email.
  /// Deliberately not a live TextFormField — editing it here would let a
  /// user swap emails post-check without re-triggering the registration
  /// check, bypassing the whole gate. Changing email routes through
  /// [_backToMain] instead.
  Widget _buildEmailDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        border: Border.all(color: AppColors.line2, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.email_outlined, color: AppColors.textDim, size: 20),
          const SizedBox(width: AppSpacing.cardPadding),
          Expanded(
            child: Text(
              _emailController.text.trim(),
              style: AppTypography.body.copyWith(color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangeEmailLink(AuthNotifier authNotifier, bool isLoading) {
    return TextButton(
      onPressed: isLoading ? null : () => _backToMain(authNotifier),
      child: Text(
        'CHANGE EMAIL',
        style: AppTypography.monoXs.copyWith(
          color: AppColors.accent,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  /// Centered brand-mark header shared by the three email steps. Echoes
  /// [_HeroLogoBand]'s centered-logo language (lighter — no radial glow — so
  /// it stays subordinate to the welcome hero) and shares the form's vertical
  /// axis, so the title gets full width and never wraps. Replaces the
  /// bespoke left-aligned [AuthHeader] on the email path only; [AuthHeader]
  /// stays in use by the (currently hidden) phone view.
  Widget _buildEmailBrandMark({required String title, VoidCallback? onBack}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Standalone top-left back arrow, in a fixed slot (no layout shift);
        // non-interactive when onBack == null (i.e. during loading), matching
        // AuthHeader's isLoading→null gating at the call sites.
        Align(
          alignment: Alignment.centerLeft,
          child: Opacity(
            opacity: onBack == null ? 0.35 : 1,
            child: GestureDetector(
              key: const ValueKey('auth-header-back'),
              onTap: onBack,
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
                title,
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

  /// Step 2a — password-only sign-in for an already-registered email.
  Widget _buildEmailStepSignIn(AuthNotifier authNotifier, bool isLoading) {
    return Column(
      children: [
        _buildEmailBrandMark(
          title: 'Sign in',
          onBack: isLoading ? null : () => _backToMain(authNotifier),
        ),
        Form(
          key: _formKey,
          child: Column(
            children: [
              _buildEmailDisplay(),
              const SizedBox(height: AppSpacing.sectionGap),
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
              _buildPrimaryButton(
                label: 'SIGN IN WITH EMAIL',
                isLoading: isLoading,
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  final email = _emailController.text.trim();
                  final password = _passwordController.text;
                  authNotifier.signInWithEmail(email, password);
                },
              ),

              // Forgot password — only relevant on the sign-in variant,
              // never during sign-up. Pre-2026-04-24 the link lived only
              // on the welcome view (pre-email) where users who already
              // committed to email couldn't see it.
              const SizedBox(height: 10),
              GestureDetector(
                onTap: isLoading
                    ? null
                    : () => ForgotPasswordSheet.show(context),
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
              const SizedBox(height: 12),
              _buildChangeEmailLink(authNotifier, isLoading),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  /// Step 2b — password + referral + privacy for a not-yet-registered email.
  Widget _buildEmailStepSignUp(AuthNotifier authNotifier, bool isLoading) {
    return Column(
      children: [
        _buildEmailBrandMark(
          title: 'Sign up',
          onBack: isLoading ? null : () => _backToMain(authNotifier),
        ),
        Form(
          key: _formKey,
          child: Column(
            children: [
              _buildEmailDisplay(),
              const SizedBox(height: AppSpacing.sectionGap),
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

              // U8 fix: Referral code field. The existing redemption flow
              // in the success listener (_referralController.text.trim())
              // is already wired up and reused here — no new handler needed.
              const SizedBox(height: 16),
              Text(
                'REFERRAL CODE (OPTIONAL)',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textDim,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _referralController,
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                ),
                cursorColor: AppColors.accent,
                maxLength: 20,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: AppConstants.referralCodeHint,
                  hintStyle: AppTypography.body.copyWith(
                    color: AppColors.textMute,
                    fontSize: 15,
                  ),
                  prefixIcon: const Icon(
                    Icons.card_giftcard_outlined,
                    color: AppColors.textDim,
                    size: 18,
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.input,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: BorderSide(color: AppColors.border),
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
              const SizedBox(height: 4),
              Text(
                'Have a referral code? Apply for +7 days PRO.',
                style: AppTypography.bodySm.copyWith(
                  fontSize: 12,
                  color: AppColors.textDim,
                ),
              ),
              const SizedBox(height: 12),

              // Privacy/Terms checkbox. Starts UNCHECKED — the tick is the
              // DPDP §6(1) "clear affirmative action". See `_privacyAccepted`.
              _PrivacyCheckboxRow(
                value: _privacyAccepted,
                onChanged: (v) => setState(() => _privacyAccepted = v ?? false),
              ),
              const SizedBox(height: 12),

              _buildPrimaryButton(
                label: 'CREATE ACCOUNT',
                isLoading: isLoading,
                // Gate the CREATE ACCOUNT button on checkbox acceptance.
                enabled: _privacyAccepted,
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  final email = _emailController.text.trim();
                  final password = _passwordController.text;
                  // closes-diagnose: b3f9e7
                  // The user's own TICK on the (unchecked-by-default) consent
                  // box is the affirmative-action signal — DPDP §6(1), a clear
                  // affirmative action. Corrected 2026-08-25: this said
                  // "pre-checked … per DPDP §11", which stopped being true when
                  // `_privacyAccepted` was flipped to false, and cited a
                  // different section than the field's own docstring. The original E.3 fix
                  // (audit 2026-05-16, F3-1.2) wrote ToS/Privacy acceptance
                  // straight to `HiveService.instance.userBox` HERE, before
                  // signUp — but no Supabase session (and therefore no open
                  // user-scoped Hive box) exists yet at this point, so that
                  // write threw `HiveOwnershipException`/`StateError` every
                  // single time and was silently swallowed. Passing the
                  // captured values through instead — `_ensureLocalUser`
                  // (auth_provider.dart) writes them to Hive AFTER
                  // `HiveUserSession.openForUser` has actually opened the box,
                  // where the write can succeed. UTC ISO8601 because the cloud
                  // column is `timestamptz` (IST applies to date-keys only,
                  // not timestamps — see docs/architecture/sync.md IST contract).
                  authNotifier.signUpWithEmail(
                    email,
                    password,
                    termsAcceptedAt: DateTime.now().toUtc().toIso8601String(),
                    termsVersion: AppConstants.termsVersion,
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildChangeEmailLink(authNotifier, isLoading),
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
        AuthHeader(
          eyebrow: 'RECRUIT REGISTRY',
          title: authState.otpSent ? 'Enter the code' : 'Phone sign in',
          onBack: isLoading
              ? null
              : () => setState(() {
                  _currentView = _SignInView.main;
                  _otpController.clear();
                  _resendTimer?.cancel();
                  _resendSecondsRemaining = 0;
                  authNotifier.resetState();
                }),
        ),

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
            style: AppTypography.body.copyWith(color: AppColors.textDim),
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
        hintStyle: AppTypography.body.copyWith(color: AppColors.textDisabled),
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

  // <diagnose-id> — `compact` is opt-in only, used solely by the new
  // in-card CONTINUE button (email-secondary in the sign-in card mockup,
  // approved 2026-08-03). It must not change the default appearance at
  // this method's other 4 call sites (email sign-in/sign-up, phone SEND/
  // VERIFY OTP), so every visual delta below is gated behind the flag
  // rather than changing the shared defaults.
  Widget _buildPrimaryButton({
    required String label,
    required bool isLoading,
    required VoidCallback onPressed,
    bool enabled = true,
    bool compact = false,
  }) {
    final isDisabled = !enabled || isLoading;
    final radius = compact ? AppRadius.card : AppRadius.sharp;
    return SizedBox(
      width: double.infinity,
      height: compact ? 44 : 52,
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Material(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: isDisabled ? null : onPressed,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.accent,
                  width: compact ? 1 : 2,
                ),
                borderRadius: BorderRadius.circular(radius),
              ),
              padding: EdgeInsets.symmetric(
                vertical: compact ? 12 : 14,
                horizontal: 28,
              ),
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
                          fontSize: compact ? 11 : 12,
                          color: AppColors.bgDeep,
                          letterSpacing: compact ? 2.0 : 2.5,
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

/// Privacy/Terms checkbox row shown above the CREATE ACCOUNT button
/// during email sign-up. Pre-checked; links open Privacy Policy and Terms
/// in the external browser. The tappable link areas are handled by
/// [TapGestureRecognizer] to avoid nesting [GestureDetector] inside the row.
class _PrivacyCheckboxRow extends StatefulWidget {
  const _PrivacyCheckboxRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  State<_PrivacyCheckboxRow> createState() => _PrivacyCheckboxRowState();
}

class _PrivacyCheckboxRowState extends State<_PrivacyCheckboxRow> {
  final _privacyRecognizer = TapGestureRecognizer();
  final _termsRecognizer = TapGestureRecognizer();

  @override
  void initState() {
    super.initState();
    _privacyRecognizer.onTap = () => launchUrl(
      Uri.parse('https://icanbefitter.com/privacy'),
      mode: LaunchMode.externalApplication,
    );
    _termsRecognizer.onTap = () => launchUrl(
      Uri.parse('https://icanbefitter.com/terms'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  void dispose() {
    _privacyRecognizer.dispose();
    _termsRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: widget.value,
            activeColor: AppColors.accent,
            checkColor: AppColors.bgDeep,
            side: const BorderSide(color: AppColors.border, width: 1.5),
            onChanged: widget.onChanged,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: AppTypography.bodyS.copyWith(
                color: AppColors.textPrimary,
                height: 1.4,
              ),
              children: [
                const TextSpan(text: 'I agree to the '),
                TextSpan(
                  text: 'Privacy Policy',
                  style: const TextStyle(
                    color: AppColors.accent,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.accent,
                  ),
                  recognizer: _privacyRecognizer,
                ),
                const TextSpan(text: ' and '),
                TextSpan(
                  text: 'Terms',
                  style: const TextStyle(
                    color: AppColors.accent,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.accent,
                  ),
                  recognizer: _termsRecognizer,
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
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
                  // gold glow. The "A" italic-serif placeholder used here
                  // until the APK-test-1-batch (2026-04-24) is replaced
                  // with the canonical AVYA icon asset for a more crafted
                  // premium feel. Icon sized to 54% of the ring diameter.
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.accent, width: 2),
                      gradient: RadialGradient(
                        colors: [
                          AppColors.accent.withValues(alpha: 0.15),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: ClipOval(
                      child: Image.asset(
                        'assets/avya_icon.png',
                        width: 44,
                        height: 44,
                        fit: BoxFit.contain,
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
                  const SizedBox(height: 4),
                  // Direction B (U9): serial-number arc below wordmark.
                  Text(
                    '· REGISTRATION OPEN · 2026 ·',
                    textAlign: TextAlign.center,
                    style: AppTypography.mono.copyWith(
                      fontSize: 8,
                      letterSpacing: 1.6,
                      color: AppColors.accent.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
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
