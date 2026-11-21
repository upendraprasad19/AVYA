import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
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
/// Progress is NOT gated here. The row pushes `ProgressPhotosScreen` for every
/// user, and that screen decides what each one sees (OI-314, founder decision 6 of
/// 2026-10-06): PRO gets the gallery and the Add button; a lapsed user who holds
/// photos gets the gallery to view and delete (no new uploads: the database
/// refuses them, migration 154); a user with no photos who is not PRO gets the
/// locked card with the Upgrade button. Before OI-314 this row ran the PRO gate
/// itself and showed a free user the paywall without opening the screen, which
/// also locked a lapsed user out of their own photos. Saved is ungated by design.
/// `user_photos_hub_test.dart` fails on a second door from this hub that names
/// the Progress screen.
///
/// The ONE subscription read in the build is display-only: the Progress subtitle
/// keeps the "PRO — visual progress timeline" hint for a user who is not PRO.
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
                  // No gate here: the screen decides (see the class doc).
                  onTap: () => context.push('/profile/progress-photos'),
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
