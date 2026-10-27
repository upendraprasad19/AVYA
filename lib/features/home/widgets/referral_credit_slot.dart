import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/copy/referral_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/referral_summary_provider.dart';
import 'package:icanbefitter/features/profile/screens/invite_friends_sheet.dart';
import 'package:icanbefitter/features/profile/services/referral_credit_notice_rules.dart';

/// The Home slot for the in-app referral credit notice (unit C, OI-336).
///
/// A slot OWNS its state check, so the host adds one line. It asks the notice
/// notifier for one evaluation when it mounts (the other triggers - resume, a
/// restore tick, the invite sheet opening - call the same single-flight
/// method), and renders nothing unless a credit is waiting to be announced.
/// Not a modal, no push, no sound (founder decision 2026-10-16).
class ReferralCreditSlot extends ConsumerStatefulWidget {
  const ReferralCreditSlot({super.key});

  @override
  ConsumerState<ReferralCreditSlot> createState() => _ReferralCreditSlotState();
}

class _ReferralCreditSlotState extends ConsumerState<ReferralCreditSlot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(referralCreditNoticeProvider.notifier).check());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(referralCreditNoticeProvider);
    if (notice == null) return const SizedBox.shrink();
    final text = creditNoticeText(notice.days);
    final notifier = ref.read(referralCreditNoticeProvider.notifier);
    return Container(
      key: const ValueKey('referral-credit-card'),
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.33)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: text,
              hint: ReferralCopy.noticeOpenHint,
              child: InkWell(
                onTap: () {
                  unawaited(notifier.dismiss());
                  InviteFriendsSheet.show(context);
                },
                borderRadius: BorderRadius.circular(AppRadius.cardM),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.card_giftcard,
                          size: 20, color: AppColors.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ExcludeSemantics(
                          child: Text(
                            text,
                            style: AppTypography.body.copyWith(
                                fontSize: 13,
                                color: AppColors.textDim,
                                height: 1.35),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Semantics(
            label: ReferralCopy.noticeDismissLabel,
            button: true,
            child: InkWell(
              key: const ValueKey('referral-credit-dismiss'),
              onTap: () => unawaited(notifier.dismiss()),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.close,
                    size: 18, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
