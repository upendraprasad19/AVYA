import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:icanbefitter/core/copy/referral_copy.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/features/profile/providers/referral_eligibility_provider.dart';
import 'package:icanbefitter/features/profile/providers/referral_summary_provider.dart';
import 'package:icanbefitter/features/profile/repositories/referral_repository.dart';
import 'package:icanbefitter/features/profile/widgets/referrer_counters_block.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Bottom sheet that shows the user's referral code with an EXPIRES IN N DAYS
/// countdown. After expiry, the badge changes to EXPIRED and the button
/// becomes REGENERATE → which creates a fresh 7-day code via
/// [SupabaseService.regenerateReferralCode].
class InviteFriendsSheet extends ConsumerStatefulWidget {
  const InviteFriendsSheet({super.key, this.loadCodeForTest});

  /// Test seam: replaces the referral-code load (the sheet's widget tests have
  /// no Supabase client, so without it only the REGENERATE state renders).
  /// Always null in production.
  @visibleForTesting
  final Future<({String code, DateTime expiresAt})?> Function()?
  loadCodeForTest;

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
      ),
      builder: (_) => const InviteFriendsSheet(),
    );
  }

  @override
  ConsumerState<InviteFriendsSheet> createState() => _InviteFriendsSheetState();
}

class _InviteFriendsSheetState extends ConsumerState<InviteFriendsSheet> {
  String? _code;
  DateTime? _expiresAt;
  bool _loading = true;
  bool _regenerating = false;

  // U8 fix: "Apply someone else's code" section
  final _applyController = TextEditingController();
  bool _applying = false;
  String? _applyError;
  String? _applySuccess;

  @override
  void initState() {
    super.initState();
    _load();
    // The sheet opening is one of the credit-notice triggers. The network call
    // is single-flight only while two calls OVERLAP: the counters block mounts
    // after the code loads, so a completed first call can be followed by a
    // second one (one extra RPC, no correctness impact).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(referralCreditNoticeProvider.notifier).check();
      }
    });
  }

  @override
  void dispose() {
    _applyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result =
        await (widget.loadCodeForTest?.call() ??
            SupabaseService.instance.getOrCreateReferralCode());
    if (mounted) {
      setState(() {
        _code = result?.code;
        _expiresAt = result?.expiresAt;
        _loading = false;
      });
    }
  }

  Future<void> _regenerate() async {
    setState(() => _regenerating = true);
    try {
      final result = await SupabaseService.instance.regenerateReferralCode();
      if (mounted && result != null) {
        setState(() {
          _code = result.code;
          _expiresAt = result.expiresAt;
        });
      }
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<void> _applyCode() async {
    final code = _applyController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _applying = true;
      _applyError = null;
      _applySuccess = null;
    });
    final result = await ReferralRepository.instance.redeem(code);
    if (!mounted) return;
    if (result.success) {
      if (!result.alreadyRedeemed) {
        // The plain verify is cached for 5 minutes and would return the stale
        // local state right after a grant; the eligibility CTA is stale too.
        try {
          await ref
              .read(subscriptionServiceProvider)
              .verifyFromServer(force: true);
        } catch (_) {
          // The grant is real; the entitlement catches up on its own path.
        }
        if (!mounted) return;
        ref.invalidate(referralEligibilityProvider);
      }
      if (!mounted) return;
      setState(() {
        _applying = false;
        _applySuccess = result.alreadyRedeemed
            ? ReferralCopy.codeAlreadyApplied
            : ReferralCopy.codeApplied;
        _applyController.clear();
      });
    } else {
      setState(() {
        _applying = false;
        _applyError = result.errorMessage ?? ReferralCopy.codeApplyFailed;
      });
    }
  }

  Future<void> _share() async {
    if (_code == null) return;
    const playStore =
        'https://play.google.com/store/apps/details?id=com.icanbefitter.avya';
    final message =
        '🎯 Try AVYA — premium fitness coaching with an AI coach who actually knows you.\n\n'
        'Use my code $_code within 7 days → 7 days of PRO, free.\n\n'
        '📲 $playStore';
    await Share.share(message);
  }

  bool get _isExpired =>
      _expiresAt == null || _expiresAt!.isBefore(DateTime.now());

  int get _daysRemaining {
    if (_expiresAt == null) return 0;
    final diff = _expiresAt!.difference(DateTime.now()).inDays;
    return diff.clamp(0, 7);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            20,
            AppSpacing.gutter,
            28,
          ),
          child: _loading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: CircularProgressIndicator(),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      children: [
                        // Expanded so the title wraps instead of overflowing at
                        // large text sizes (unit C added the 2x-text fit test).
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SHARE & GROW',
                                style: AppTypography.mono.copyWith(
                                  color: AppColors.accent,
                                  letterSpacing: 2.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text('Invite a Friend', style: AppTypography.h2),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.textDim,
                            size: 20,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(width: 48, height: 1.5, color: AppColors.accent),
                    const SizedBox(height: 20),

                    // Code card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.33),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _code ?? '—',
                            style: AppTypography.h2.copyWith(
                              color: AppColors.accent,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isExpired
                                ? 'EXPIRED'
                                : 'EXPIRES IN $_daysRemaining DAY${_daysRemaining == 1 ? '' : 'S'}',
                            style: AppTypography.mono.copyWith(
                              fontSize: 10,
                              letterSpacing: 1.4,
                              color: _isExpired
                                  ? AppColors.bad
                                  : AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description
                    Text(
                      ReferralCopy.inviteDescription,
                      style: AppTypography.bodyM.copyWith(
                        color: AppColors.textDim,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // CTA button — REGENERATE when expired, SHARE when valid
                    if (_isExpired)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _regenerating ? null : _regenerate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.bg,
                            disabledBackgroundColor: AppColors.accent
                                .withValues(alpha: 0.5),
                            shape: const StadiumBorder(),
                          ),
                          child: _regenerating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.bg,
                                  ),
                                )
                              : Text(
                                  'REGENERATE  →',
                                  style: AppTypography.mono.copyWith(
                                    fontSize: 13,
                                    letterSpacing: 1.4,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.bg,
                                  ),
                                ),
                        ),
                      )
                    else
                      WardButton(label: 'Share My Code', onPressed: _share),

                    // Unit C (OI-336): the referrer's aggregates, BELOW the Share
                    // action so a late-arriving block never shifts the code.
                    const ReferrerCountersBlock(),

                    // U8 fix: Apply someone else's referral code
                    const SizedBox(height: 28),
                    Container(
                      width: double.infinity,
                      height: 1,
                      color: AppColors.border,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'GOT A CODE?',
                      style: AppTypography.mono.copyWith(
                        fontSize: 10,
                        letterSpacing: 2,
                        color: AppColors.textDim,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _applyController,
                            style: AppTypography.bodyM.copyWith(
                              color: AppColors.textPrimary,
                            ),
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 20,
                            decoration: InputDecoration(
                              hintText: AppConstants.referralCodeHint,
                              hintStyle: AppTypography.bodyM.copyWith(
                                color: AppColors.textMute,
                              ),
                              counterText: '',
                              filled: true,
                              fillColor: AppColors.input,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.card,
                                ),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.card,
                                ),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.card,
                                ),
                                borderSide: const BorderSide(
                                  color: AppColors.accent,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _applying ? null : _applyCode,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentSoft,
                              foregroundColor: AppColors.accent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.card,
                                ),
                                side: BorderSide(
                                  color: AppColors.accent.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                            ),
                            child: _applying
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.accent,
                                    ),
                                  )
                                : Text(
                                    'APPLY',
                                    style: AppTypography.mono.copyWith(
                                      fontSize: 11,
                                      letterSpacing: 1.4,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.accent,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    if (_applySuccess != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _applySuccess!,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.ok,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (_applyError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _applyError!,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.bad,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      ReferralCopy.friendDisclosure,
                      key: const ValueKey('referral-friend-disclosure'),
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textDim,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
        ),
      ),
    );
  }
}
