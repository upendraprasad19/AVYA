import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';

/// Settings screen — matches the handoff
/// (`design_handoff_wardroom/src/screens/utility.jsx` SettingsScreen).
///
/// * Double-rule letterhead "SETTINGS · AVYA" / "Under the hood".
/// * Subscription status hero (44-px PRO badge + "Officer's
///   Commission" + renewal meta + MANAGE link).
/// * Six setting groups (ACCOUNT / PREFERENCES / PLAN & COACHING /
///   HEALTH SYNC / NOTIFICATIONS / DATA & PRIVACY). Each row is a
///   tap target that routes to the existing settings surfaces; the
///   visual shell is presentation-only.
/// * Sign out outline button.
/// * Mono 9 ghost build-info footer.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // APK Test #12 / Task C-2 — watch subscriptionInfoProvider for
    // reactive PRO/free dossier rendering after payment success.
    final isPro = ref.watch(subscriptionInfoProvider).isPro;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: WardFrame(
        padBottom: 0,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WardLetterhead(
                  eyebrow: 'SETTINGS \u00B7 AVYA',
                  title: 'Under the hood',
                  dividerStyle: WardDivider.double,
                ),
                const SizedBox(height: AppSpacing.stackL),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: _SubscriptionStatus(isPro: isPro),
                ),
                const SizedBox(height: AppSpacing.stackL),
                _group(
                  context,
                  'ACCOUNT',
                  [
                    _Row(label: 'Profile', onTap: () => context.go('/edit-profile')),
                    _Row(label: 'Email', value: 'Manage'),
                    _Row(label: 'Password', value: 'Change'),
                  ],
                ),
                _group(
                  context,
                  'PREFERENCES',
                  [
                    _Row(label: 'Units', value: 'KG · CM'),
                    _Row(label: 'First day of week', value: 'Monday'),
                    _Row(label: 'Appearance', value: 'Wardroom'),
                    _Row(label: 'Haptics', value: 'On'),
                  ],
                ),
                _group(
                  context,
                  'PLAN & COACHING',
                  [
                    _Row(label: 'Current plan', value: 'Phase 1'),
                    _Row(label: 'Recalibrate', value: 'Review'),
                    _Row(label: 'Rest-day rule', value: 'Auto'),
                  ],
                ),
                _group(
                  context,
                  'HEALTH SYNC',
                  [
                    _Row(label: 'Health Connect', value: 'Configure'),
                    _Row(label: 'Google Fit', value: 'Configure'),
                  ],
                ),
                _group(
                  context,
                  'NOTIFICATIONS',
                  [
                    _Row(
                      label: 'Training reminders',
                      onTap: () => context.go('/notification-settings'),
                    ),
                    _Row(
                      label: 'Coach insights',
                      onTap: () => context.go('/notification-settings'),
                    ),
                    _Row(
                      label: 'Streak warnings',
                      onTap: () => context.go('/notification-settings'),
                    ),
                  ],
                ),
                _group(
                  context,
                  'DATA & PRIVACY',
                  [
                    _Row(label: 'Export my data', value: 'Request'),
                    _Row(label: 'Privacy policy', value: 'Open'),
                    _Row(
                      label: 'Delete account',
                      valueColor: AppColors.bad,
                      value: 'Irreversible',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.stackL),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: _SignOutButton(ref: ref),
                ),
                const SizedBox(height: AppSpacing.stackL),
                Center(
                  child: Text(
                    'AVYA \u00B7 WARDROOM',
                    style: AppTypography.monoXs.copyWith(
                      fontSize: 9,
                      color: AppColors.textGhost,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _group(BuildContext context, String title, List<_Row> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.stackL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Text(
              title,
              style: AppTypography.mono.copyWith(
                fontSize: 9,
                color: AppColors.textMute,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.line2),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  rows[i].build(context),
                  if (i < rows.length - 1)
                    Container(height: 1, color: AppColors.line2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row {
  const _Row({
    required this.label,
    this.value,
    this.onTap,
    this.valueColor,
  });
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Color? valueColor;

  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  color: valueColor ?? AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (value != null)
              Text(
                value!.toUpperCase(),
                style: AppTypography.monoXs.copyWith(
                  fontSize: 10,
                  color: valueColor ?? AppColors.textDim,
                  letterSpacing: 1.5,
                ),
              )
            else if (onTap != null)
              const Icon(Icons.chevron_right, size: 16, color: AppColors.textDim),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionStatus extends StatelessWidget {
  const _SubscriptionStatus({required this.isPro});
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line2),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.accent, width: 1.5),
              color: AppColors.accentSoft,
            ),
            alignment: Alignment.center,
            child: Text(
              isPro ? 'PRO' : 'FREE',
              style: AppTypography.mono.copyWith(
                fontSize: 9,
                color: AppColors.accent,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isPro ? "Officer's Commission" : 'Free tier',
                  style: AppTypography.h3.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  isPro ? 'ACTIVE \u00B7 PRO' : '30-DAY COACH TRIAL',
                  style: AppTypography.monoXs.copyWith(
                    fontSize: 9,
                    color: AppColors.textMute,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'MANAGE',
            style: AppTypography.mono.copyWith(
              fontSize: 10,
              color: AppColors.accent,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        try {
          await ref.read(authNotifierProvider.notifier).signOut();
        } catch (e) {
          debugPrint('[Settings] signOut error: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sign-out had an issue — session cleared locally.'),
              ),
            );
          }
        }
        if (context.mounted) context.go('/sign-in');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line2),
          borderRadius: BorderRadius.circular(AppRadius.sharp),
        ),
        alignment: Alignment.center,
        child: Text(
          'SIGN OUT',
          style: AppTypography.mono.copyWith(
            fontSize: 12,
            color: AppColors.textDim,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}
