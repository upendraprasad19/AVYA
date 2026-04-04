import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/shared/models/achievement_badge.dart';

/// Redesigned achievements section for the Profile screen.
/// - Unlocked badges in a prominent 3-column grid with gold border + share icon
/// - Empty state: "Keep working out to unlock achievements"
/// - Locked badges hidden in a collapsible dropdown
class BadgesGrid extends StatefulWidget {
  const BadgesGrid({super.key});

  @override
  State<BadgesGrid> createState() => _BadgesGridState();
}

class _BadgesGridState extends State<BadgesGrid> {
  bool _showLocked = false;

  @override
  Widget build(BuildContext context) {
    final allBadges = BadgeService.instance.getAllWithStatus();
    final unlocked = allBadges.where((b) => b.isUnlocked).toList();
    final locked = allBadges.where((b) => !b.isUnlocked).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'ACHIEVEMENTS',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.proGold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.proGold.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${unlocked.length} / ${allBadges.length}',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.proGold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Unlocked badges or empty state
          if (unlocked.isEmpty)
            _buildEmptyState()
          else
            _buildUnlockedGrid(unlocked),

          // Locked section
          if (locked.isNotEmpty) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _showLocked = !_showLocked),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    '${locked.length} more to unlock',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _showLocked ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            if (_showLocked) ...[
              const SizedBox(height: 10),
              _buildLockedGrid(locked),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Text('🏆', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Complete workouts to unlock your first badge',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlockedGrid(List<AchievementBadge> badges) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: badges.length,
      itemBuilder: (context, i) => _UnlockedBadgeCard(badge: badges[i]),
    );
  }

  Widget _buildLockedGrid(List<AchievementBadge> badges) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: badges.length,
      itemBuilder: (context, i) {
        final badge = badges[i];
        return GestureDetector(
          onTap: () => _showLockedDetail(context, badge),
          child: Opacity(
            opacity: 0.3,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(badge.emoji, style: const TextStyle(fontSize: 22)),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Icon(Icons.lock, size: 10, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showLockedDetail(BuildContext context, AchievementBadge badge) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Opacity(
              opacity: 0.4,
              child: Text(badge.emoji, style: const TextStyle(fontSize: 56)),
            ),
            const SizedBox(height: 12),
            Text(
              badge.name,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              badge.description,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Keep going to unlock this!',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single unlocked badge card with emoji, name, date, and share icon.
class _UnlockedBadgeCard extends StatelessWidget {
  final AchievementBadge badge;
  const _UnlockedBadgeCard({required this.badge});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showShareSheet(context),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.proGold.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(badge.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 4),
            Text(
              badge.name,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.share, size: 10, color: AppColors.accent),
                const SizedBox(width: 3),
                Text(
                  _fmtDate(badge.unlockedAt!),
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 9,
                    fontWeight: FontWeight.w400,
                    color: AppColors.proGold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showShareSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _BadgeShareSheet(badge: badge),
    );
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}';
}

/// Bottom sheet for sharing a badge card as PNG.
class _BadgeShareSheet extends StatefulWidget {
  final AchievementBadge badge;
  const _BadgeShareSheet({required this.badge});

  @override
  State<_BadgeShareSheet> createState() => _BadgeShareSheetState();
}

class _BadgeShareSheetState extends State<_BadgeShareSheet> {
  final _repaintKey = GlobalKey();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Shareable card
          RepaintBoundary(
            key: _repaintKey,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF0e1219),
                    const Color(0xFF161d28),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppColors.proGold.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Text(widget.badge.emoji, style: const TextStyle(fontSize: 64)),
                  const SizedBox(height: 14),
                  Text(
                    widget.badge.name.toUpperCase(),
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.proGold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.badge.description,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Unlocked ${_fmtDate(widget.badge.unlockedAt!)}',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.proGold.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Branding
                  Text(
                    'ICANBEFITTER',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.accent,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Share button
          GestureDetector(
            onTap: _sharing ? null : _shareCard,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Center(
                child: _sharing
                    ? SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.black),
                        ),
                      )
                    : Text(
                        'SHARE ACHIEVEMENT',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareCard() async {
    setState(() => _sharing = true);
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();

      await Share.shareXFiles(
        [XFile.fromData(pngBytes, mimeType: 'image/png', name: 'achievement.png')],
        text: 'I just unlocked "${widget.badge.name}" on ICANBEFITTER! ${widget.badge.emoji}',
      );
    } catch (_) {
      // Sharing cancelled or failed — silent
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}';
}
