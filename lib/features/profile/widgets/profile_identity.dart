import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/pro_pill_button.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_insignia.dart';

/// Profile identity section: banner (140px per handoff, tap to view),
/// avatar overlapping banner, name, subtitle, edit button. Banner has
/// a faint diagonal-hatching overlay on placeholder gradients to match
/// the handoff `Banner` primitive.
/// Tap avatar/banner = view full screen (if exists). Small icon = replace.
///
/// The banner-overlap row hosts two elements: the 80px avatar on the left
/// and the [ProPillButton] on the right. Achievements now live in the separate
/// [SlimAchievementsCard] below the Daily Completion section.
class ProfileIdentity extends StatelessWidget {
  final String name;
  final String subtitle;
  final String? avatarUrl;
  final String? bannerUrl;
  final VoidCallback onReplaceAvatar;
  final VoidCallback onReplaceBanner;
  // Plan D D-7: nullable. When null, the EDIT PROFILE button hides
  // entirely (Profile screen now hosts Edit Profile inside SETTINGS).
  final VoidCallback? onTapEdit;
  final bool isPro;
  final VoidCallback onTapPremium;

  // Theme B · Test #8 — compact rank chip in banner-overlap row.
  // Three optional fields; chip only renders when ALL three are
  // non-null (avoids partial state during early profile load).
  final String? rankCode;
  final String? rankShortCode;
  final VoidCallback? onTapRank;

  const ProfileIdentity({
    super.key,
    required this.name,
    required this.subtitle,
    this.avatarUrl,
    this.bannerUrl,
    required this.onReplaceAvatar,
    required this.onReplaceBanner,
    this.onTapEdit,
    required this.isPro,
    required this.onTapPremium,
    this.rankCode,
    this.rankShortCode,
    this.onTapRank,
  });

  void _openFullScreen(BuildContext context, String imageUrl, String heroTag) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, anim, secondAnim) => GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Scaffold(
            backgroundColor: Colors.black87,
            body: Center(
              child: Hero(
                tag: heroTag,
                child: InteractiveViewer(
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    cacheKey: '${imageUrl}_fullres', // Separate cache key for full resolution
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Banner with overlapping avatar.
        //
        // Theme B fix · Test #8 follow-up — the outer Stack used to auto-size
        // to the 140-px banner, so the Positioned(bottom: -40) overlap row
        // (avatar / rank chip / GO PRO pill) extended 40 px below the Stack
        // and FELL OUT of the Stack's hit-test bounds. Avatar still received
        // taps because its top half stayed inside the 140-px region; the
        // rank chip and GO PRO pill — both rendered fully below banner.bottom
        // — became visually present but unclickable.
        //
        // Fix: explicit `SizedBox(height: 180)` extends the Stack to cover
        // the full overlap row. `Positioned(bottom: 0)` keeps the row's
        // bottom at the same on-screen Y. The trailing `SizedBox(height: 10)`
        // (was 50) compensates so the name row below doesn't shift.
        SizedBox(
          height: 180,
          child: Stack(
            children: [
            // Banner - tap to view, edit icon to replace
            GestureDetector(
              onTap: bannerUrl != null && bannerUrl!.isNotEmpty
                  ? () => _openFullScreen(context, bannerUrl!, 'banner_hero')
                  : onReplaceBanner,
              child: Stack(
                children: [
                  Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(AppRadius.card),
                        bottomRight: Radius.circular(AppRadius.card),
                      ),
                      gradient: bannerUrl == null
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF0a1628),
                                Color(0xFF0d2040),
                                Color(0xFF0a1628),
                              ],
                            )
                          : null,
                    ),
                    child: bannerUrl != null
                        ? Hero(
                            tag: 'banner_hero',
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(AppRadius.card),
                                bottomRight: Radius.circular(AppRadius.card),
                              ),
                              child: CachedNetworkImage(
                                imageUrl: bannerUrl!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 140,
                                memCacheWidth: (MediaQuery.of(context).size.width * MediaQuery.of(context).devicePixelRatio).toInt(),
                                memCacheHeight: (120 * MediaQuery.of(context).devicePixelRatio).toInt(),
                                placeholder: (_, url) => Container(
                                  color: AppColors.bgRaise,
                                  child: const Center(
                                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textDim)),
                                  ),
                                ),
                                errorWidget: (_, url, err) => Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [Color(0xFF0a1628), Color(0xFF0d2040), Color(0xFF0a1628)],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                  // D-9 (Plan D): floating eyebrow on banner top-left @ ~65%
                  // alpha — "DOSSIER · OFFICER" letterhead identity for the
                  // Profile tab without crowding the banner.
                  Positioned(
                    left: 16,
                    top: 12,
                    child: Text(
                      'DOSSIER · OFFICER',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.textPrimary.withValues(alpha: 0.65),
                        letterSpacing: 1.6,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // Edit icon (top-right) - always visible to replace banner
                  Positioned(
                    right: 12,
                    top: 12,
                    child: GestureDetector(
                      onTap: onReplaceBanner,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.bgDeep.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                        ),
                        child: const Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                  // Camera hint when no banner
                  if (bannerUrl == null)
                    Positioned(
                      right: 12,
                      bottom: 36,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.bgDeep.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(AppRadius.soft),
                        ),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          size: 16,
                          color: AppColors.textMute,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Banner-overlap row: avatar L · compact rank chip CENTER · PRO pill R.
            // Theme B · Test #8 — chip taps open the Rank Service Record bottom sheet.
            // Theme B fix · Test #8 follow-up — bottom: 0 (was -40); the parent
            // SizedBox(height: 180) is what now provides the +40 offset below
            // the banner. Without this fix the row's hit-test region was outside
            // the Stack's render box and the chip + GO PRO pill were unclickable.
            Positioned(
              left: 18,
              right: 18,
              bottom: 0,
              child: Row(
                children: [
                  _buildAvatar(context),
                  Expanded(
                    child: Center(
                      child: (rankCode != null &&
                              rankShortCode != null &&
                              onTapRank != null)
                          ? _buildRankChip()
                          : const SizedBox.shrink(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: ProPillButton(isPro: isPro, onTap: onTapPremium),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),

        // Theme B fix · Test #8 follow-up — was SizedBox(height: 50). The
        // SizedBox(height: 180) wrapping the Stack above already includes the
        // 40 px overlap region that this gap used to provide, so trim by 40.
        const SizedBox(height: 10),

        // Name row with edit button — Fraunces name in h2, mono subtitle
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter, 0, AppSpacing.gutter, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTypography.h2.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle.toUpperCase(),
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.textMute,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTapEdit != null)
                GestureDetector(
                  onTap: onTapEdit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.line2),
                      borderRadius: BorderRadius.circular(AppRadius.sharp),
                    ),
                    child: Text(
                      'EDIT PROFILE',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.textPrimary,
                        letterSpacing: 2.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // D-9 (Plan D): gold rule closes the Profile letterhead — eyebrow
        // (on banner) + title (name) + rule. Status strip with streak +
        // freeze + rank chip is rendered by profile_screen below this
        // widget.
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 8),
          child: Container(
            height: 1,
            width: 60,
            color: AppColors.accent,
          ),
        ),
      ],
    );
  }

  /// Theme B · Test #8 — compact rank chip rendered in the banner-overlap
  /// row. Same vertical drop as the PRO pill (top-padding 44) so all three
  /// elements (avatar / chip / PRO pill) sit on a shared baseline.
  Widget _buildRankChip() {
    return Padding(
      padding: const EdgeInsets.only(top: 44),
      child: GestureDetector(
        onTap: onTapRank,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WardRankInsignia(rankCode: rankCode!, size: 22),
              const SizedBox(width: 6),
              Text(
                rankShortCode!,
                style: AppTypography.mono.copyWith(
                  fontSize: 11,
                  color: AppColors.accent,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.expand_more,
                size: 14,
                color: AppColors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        children: [
          // Avatar circle - tap to show options (view/replace) or replace directly
          GestureDetector(
            onTap: () {
              if (avatarUrl != null && avatarUrl!.isNotEmpty) {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: AppColors.card,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
                  ),
                  builder: (_) => SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.line2, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(height: 12),
                          ListTile(
                            leading: const Icon(Icons.fullscreen, color: AppColors.accent),
                            title: Text('View Photo', style: AppTypography.body.copyWith(color: AppColors.textPrimary)),
                            onTap: () { Navigator.pop(context); _openFullScreen(context, avatarUrl!, 'avatar_hero'); },
                          ),
                          ListTile(
                            leading: const Icon(Icons.camera_alt, color: AppColors.accent),
                            title: Text('Change Photo', style: AppTypography.body.copyWith(color: AppColors.textPrimary)),
                            onTap: () { Navigator.pop(context); onReplaceAvatar(); },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              } else {
                onReplaceAvatar();
              }
            },
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: avatarUrl == null
                    ? AppColors.accent.withValues(alpha: 0.12)
                    : null,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bgDeep, width: 3),
              ),
              child: avatarUrl != null
                  ? Hero(
                      tag: 'avatar_hero',
                      child: ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: avatarUrl!,
                          fit: BoxFit.cover,
                          width: 80,
                          height: 80,
                          memCacheWidth: 240, // 80 * 3 for retina
                          memCacheHeight: 240,
                          placeholder: (_, url) => const Center(
                            child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
                          ),
                          errorWidget: (_, url, err) => _buildInitialAvatar(),
                        ),
                      ),
                    )
                  : _buildInitialAvatar(),
            ),
          ),

          // Camera button - always triggers replace (larger touch target)
          Positioned(
            bottom: -2,
            right: -2,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onReplaceAvatar,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bgDeep, width: 2.5),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 15,
                  color: AppColors.bgDeep,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialAvatar() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.camera_alt_outlined, size: 22, color: AppColors.accent),
          const SizedBox(height: 1),
          Text(
            'ADD',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.accent,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
