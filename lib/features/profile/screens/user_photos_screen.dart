import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../providers/profile_provider.dart';
import '../widgets/profile_row.dart';

/// Hub behind the single "Photos" row on the Profile tab.
///
/// Two destinations, deliberately NOT merged: Progress Photos (PRO-gated,
/// daily-capped, dated body-progress timeline in the `progress-photos` bucket)
/// and Saved Photos (photos the user consented to keep from AI Coach chat, in
/// the `coach-media` bucket). The hub only routes; each destination keeps its
/// own data source and delete behaviour. Both are pushed (not `go`) so back
/// returns here.
///
/// Progress has TWO PRO locks. The row below gives a free user the paywall
/// without ever opening `ProgressPhotosScreen`; the screen also runs the same
/// `gateAndVerify` on entry (`progress_photos_screen_gate_test.dart`), so a way
/// in that never touches this hub (the web address `#/profile/progress-photos`,
/// a shortcut, a named-route push) is stopped there and shows a locked card.
/// Saved is ungated by design. `user_photos_hub_test.dart` and
/// `user_photos_gate_behavioral_test.dart` still fail on a second ungated door
/// from this hub, because a free user should get the paywall, not the card.
///
/// The ONLY subscription read in the build is display-only: the Progress
/// subtitle keeps the "PRO — visual progress timeline" hint the old Profile row
/// carried for free users. The gate itself is `gateAndVerify` below, with the
/// same feature constant the old row used.
///
/// Both gate callbacks check `context.mounted` first. For a user who is PRO
/// locally, `gateAndVerify` awaits a server verify (up to 10 s) before it calls
/// either callback (a locally-free user gets `onFree` synchronously; `onFree`
/// also runs after the await when the server disagrees with the local PRO
/// flag), and the user can leave the hub in that window; without the check the
/// push / paywall would throw on a dead context and only surface as a
/// `subscription_gate_callback_threw` telemetry record.
///
/// Known trade-offs, accepted (the old Profile row had the same timing):
///  * a second tap on Progress while that verify is still running stacks a
///    second Progress screen (the old row used `go`, which was idempotent;
///    every other `push` row in the app behaves like this). Both screens are
///    read-only views on open, so nothing is written twice.
///  * the guard asks "is the hub still mounted", not "is it still on top": a
///    user who taps Saved while the verify is pending ends up on Saved with
///    Progress pushed above it, and back returns to Saved, then the hub.
///  * the gate logs `exit=onPro` before it runs the callback, so a push the
///    guard drops still shows up in telemetry as a routed user.
class UserPhotosScreen extends ConsumerWidget {
  const UserPhotosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(subscriptionInfoProvider).isPro;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DOSSIER · ARCHIVE',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 2.5,
              ),
            ),
            const SizedBox(height: 2),
            Text('Photos', style: AppTypography.h3),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: 8,
        ),
        children: [
          WardCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ProfileRow(
                  icon: Icons.timeline_outlined,
                  title: 'Progress',
                  subtitle: isPro
                      ? 'Track your transformation visually'
                      : 'PRO — visual progress timeline',
                  trailing: const ProfileRowChevron(),
                  // The first of two PRO locks on the way to
                  // ProgressPhotosScreen (the screen gates itself too).
                  onTap: () => SubscriptionService.instance.gateAndVerify(
                    AppConstants.featureProgressPhotos,
                    onPro: () {
                      if (!context.mounted) return;
                      context.push('/profile/progress-photos');
                    },
                    onFree: () {
                      if (!context.mounted) return;
                      showPaywallSheet(context, feature: 'Progress Photos');
                    },
                  ),
                ),
                // Saved is deliberately not gated: the screen lists only photos
                // this user chose to keep from an AI Coach chat, so a user who
                // never saved one just sees an empty screen, which is harmless.
                ProfileRow(
                  icon: Icons.bookmark_border,
                  title: 'Saved',
                  subtitle: 'Photos you saved from AI Coach chat',
                  trailing: const ProfileRowChevron(),
                  showBorder: false,
                  onTap: () => context.push('/profile/saved-coach-photos'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
