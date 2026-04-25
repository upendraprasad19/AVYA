import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Bottom sheet that shows the user's referral code with an EXPIRES IN N DAYS
/// countdown. After expiry, the badge changes to EXPIRED and the button
/// becomes REGENERATE → which creates a fresh 7-day code via
/// [SupabaseService.regenerateReferralCode].
class InviteFriendsSheet extends ConsumerStatefulWidget {
  const InviteFriendsSheet({super.key});

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await SupabaseService.instance.getOrCreateReferralCode();
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
                      Column(
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
                          Text(
                            'Invite a Friend',
                            style: AppTypography.h2,
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: AppColors.textDim, size: 20),
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
                        horizontal: 20, vertical: 18),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius:
                          BorderRadius.circular(AppRadius.card),
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
                    'When friends use this code within 7 days of signing up, '
                    'you both get 7 days of PRO free.',
                    style: AppTypography.bodyM
                        .copyWith(color: AppColors.textDim),
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
                          disabledBackgroundColor:
                              AppColors.accent.withValues(alpha: 0.5),
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
                    WardButton(
                      label: 'Share My Code',
                      onPressed: _share,
                    ),
                ],
              ),
      ),
    );
  }
}
