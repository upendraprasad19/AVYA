// lib/shared/widgets/wardroom/ward_rank_pill.dart
//
// Rank pill at top of Profile. Displays [insignia] [shortCapsName]
// [chevron]. Tap toggles inline accordion expansion below the pill.
//
// Dumb in: rankCode + shortCapsName + expandedContentBuilder.
// The Profile screen owns the Service Record content via the
// builder slot — pill stays portable + testable.
//
// Animation: 200ms ease-out vertical expand. Chevron rotates 180°
// in the same window via AnimatedRotation.
//
// Source: docs/superpowers/specs/2026-05-01-apk-test-6-batch-design.md §7.2.

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_insignia.dart';

class WardRankPill extends StatefulWidget {
  const WardRankPill({
    super.key,
    required this.rankCode,
    required this.shortCapsName,
    required this.expandedContentBuilder,
  });

  final String rankCode;
  final String shortCapsName;
  final Widget Function(BuildContext) expandedContentBuilder;

  @override
  State<WardRankPill> createState() => _WardRankPillState();
}

class _WardRankPillState extends State<WardRankPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _curve;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Pill (always visible) ────────────────────────────────
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bgRaise,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.35),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WardRankInsignia(rankCode: widget.rankCode, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.shortCapsName,
                    style: AppTypography.mono.copyWith(
                      fontSize: 12,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Expanded Service Record content ──────────────────────
        SizeTransition(
          sizeFactor: _curve,
          axisAlignment: -1.0, // grow downward
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: widget.expandedContentBuilder(context),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
