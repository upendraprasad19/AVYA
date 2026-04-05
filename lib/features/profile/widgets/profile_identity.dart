import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';

/// Profile identity section: banner (120px, tap to view), avatar overlapping banner,
/// name, subtitle, edit button.
/// Tap avatar/banner = view full screen (if exists). Small icon = replace.
class ProfileIdentity extends StatelessWidget {
  final String name;
  final String subtitle;
  final String? avatarUrl;
  final String? bannerUrl;
  final VoidCallback onReplaceAvatar;
  final VoidCallback onReplaceBanner;
  final VoidCallback onTapEdit;

  const ProfileIdentity({
    super.key,
    required this.name,
    required this.subtitle,
    this.avatarUrl,
    this.bannerUrl,
    required this.onReplaceAvatar,
    required this.onReplaceBanner,
    required this.onTapEdit,
  });

  void _openFullScreen(BuildContext context, String imageUrl, String heroTag) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Scaffold(
            backgroundColor: Colors.black87,
            body: Center(
              child: Hero(
                tag: heroTag,
                child: InteractiveViewer(
                  child: CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain),
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
        // Banner with overlapping avatar
        Stack(
          clipBehavior: Clip.none,
          children: [
            // Banner - tap to view, edit icon to replace
            GestureDetector(
              onTap: bannerUrl != null && bannerUrl!.isNotEmpty
                  ? () => _openFullScreen(context, bannerUrl!, 'banner_hero')
                  : onReplaceBanner,
              child: Stack(
                children: [
                  Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
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
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              ),
                              child: CachedNetworkImage(
                                imageUrl: bannerUrl!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 120,
                                placeholder: (_, __) => Container(
                                  color: AppColors.input,
                                  child: const Center(
                                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary)),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Container(
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
                  // Edit icon (top-right) - always visible to replace banner
                  Positioned(
                    right: 12,
                    top: 12,
                    child: GestureDetector(
                      onTap: onReplaceBanner,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.bg.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(10),
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
                          color: AppColors.bg.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Avatar positioned to overlap banner
            Positioned(
              left: 18,
              bottom: -31,
              child: _buildAvatar(context),
            ),
          ],
        ),

        const SizedBox(height: 40), // Space for avatar overlap

        // Name row with edit button
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.toUpperCase(),
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onTapEdit,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'EDIT PROFILE',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        children: [
          // Avatar circle - tap to view (if exists) or replace (if null)
          GestureDetector(
            onTap: avatarUrl != null && avatarUrl!.isNotEmpty
                ? () => _openFullScreen(context, avatarUrl!, 'avatar_hero')
                : onReplaceAvatar,
            child: Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: avatarUrl == null
                    ? AppColors.accent.withValues(alpha: 0.12)
                    : null,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 3),
              ),
              child: avatarUrl != null
                  ? Hero(
                      tag: 'avatar_hero',
                      child: ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: avatarUrl!,
                          fit: BoxFit.cover,
                          width: 62,
                          height: 62,
                          placeholder: (_, __) => const Center(
                            child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
                          ),
                          errorWidget: (_, __, ___) => _buildInitialAvatar(),
                        ),
                      ),
                    )
                  : _buildInitialAvatar(),
            ),
          ),

          // Camera button - always triggers replace
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: onReplaceAvatar,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bg, width: 2.5),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 13,
                  color: Colors.black,
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
            'Add',
            style: GoogleFonts.getFont('DM Sans', fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}
