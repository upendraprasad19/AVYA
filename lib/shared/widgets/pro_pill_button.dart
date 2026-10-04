import 'package:flutter/material.dart';

import '../../core/theme/typography.dart';

/// Bug #22 — Brushed metallic PRO pill. Gold for PRO, silver for free.
/// Both tiers share the same shape/size/shadow/padding. Only the gradient,
/// borders, and label change, so side-by-side they read as two members of
/// the same design family — visual tier comparison at a glance.
///
/// Tap behaviour is delegated to [onTap] (parent decides whether to open
/// the subscription detail sheet or the paywall).
class ProPillButton extends StatelessWidget {
  final bool isPro;
  final VoidCallback onTap;

  const ProPillButton({
    super.key,
    required this.isPro,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Gold — PRO state
    const goldFill = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFBBF24), Color(0xFFD97706)],
    );
    const goldTopEdge = Color(0xFFFCD34D);
    const goldBottomEdge = Color(0xFF92400E);

    // Silver — free state
    const silverFill = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFE5E7EB), Color(0xFF9CA3AF)],
    );
    const silverTopEdge = Color(0xFFF3F4F6);
    const silverBottomEdge = Color(0xFF4B5563);

    final fill = isPro ? goldFill : silverFill;
    final topEdge = isPro ? goldTopEdge : silverTopEdge;
    final bottomEdge = isPro ? goldBottomEdge : silverBottomEdge;
    final label = isPro ? 'PRO' : 'GO PRO';

    // Double-border technique implemented via two stacked containers:
    // outer Container provides the shadow + top-edge highlight border,
    // inner Container provides the gradient fill + bottom-edge shadow border.
    // Flutter requires uniform border colors when borderRadius is used, so
    // we achieve the two-tone metal edge by nesting two 1-pixel borders.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: topEdge, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x61000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            gradient: fill,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: bottomEdge, width: 1),
          ),
          child: Text(
            label,
            style: AppTypography.bodySm.copyWith(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 0.5),
          ),
        ),
      ),
    );
  }
}
