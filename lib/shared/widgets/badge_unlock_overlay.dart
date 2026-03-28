import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/shared/models/achievement_badge.dart';

/// Full-screen overlay that celebrates a newly unlocked badge.
/// Shows each badge sequentially; auto-dismisses after 3s or on tap.
class BadgeUnlockOverlay extends StatefulWidget {
  final List<BadgeId> newBadgeIds;
  final VoidCallback onDismiss;

  const BadgeUnlockOverlay({
    super.key,
    required this.newBadgeIds,
    required this.onDismiss,
  });

  /// Show the overlay for a list of newly unlocked badges.
  static void show(BuildContext context, List<BadgeId> badgeIds) {
    if (badgeIds.isEmpty) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, _, __) => BadgeUnlockOverlay(
        newBadgeIds: badgeIds,
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  State<BadgeUnlockOverlay> createState() => _BadgeUnlockOverlayState();
}

class _BadgeUnlockOverlayState extends State<BadgeUnlockOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
    Future.delayed(const Duration(seconds: 3), _next);
  }

  void _next() {
    if (!mounted) return;
    if (_currentIndex < widget.newBadgeIds.length - 1) {
      setState(() => _currentIndex++);
      _controller.reset();
      _controller.forward();
      Future.delayed(const Duration(seconds: 3), _next);
    } else {
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badgeId = widget.newBadgeIds[_currentIndex];
    final badge = AchievementBadge.all.firstWhere((b) => b.id == badgeId);

    return GestureDetector(
      onTap: _next,
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.85),
        body: Center(
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
              decoration: BoxDecoration(
                color: const Color(0xFF0e1219),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'NEW ACHIEVEMENT',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(badge.emoji, style: const TextStyle(fontSize: 72)),
                  const SizedBox(height: 16),
                  Text(
                    badge.name,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFeef2f7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    badge.description,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 13,
                      color: const Color(0xFF6b7a8d),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Tap to continue',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 10,
                      color: const Color(0xFF6b7a8d),
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
}
