import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';
import 'package:icanbefitter/core/services/stat_snapshot_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Plan F F-13 — Promotion Day celebration overlay.
///
/// Full-screen modal shown once per rank promotion. Insignia paints on via
/// AnimationController over 1.5s. Side-by-side stats baseline → today.
/// Ceremonial "By order of the Captain" line. Tap-to-dismiss + 30s auto-
/// dismiss safety. Share button uses share_plus.
///
/// MVP placeholder insignia (text-bordered ribbon) — Plan D D-1 will swap
/// to `WardRankInsignia` CustomPaint when that lands.
///
/// F-14 image generation is deferred to Test #7 — share currently sends
/// text-only "I just ranked up to <rank>!" message via share_plus.
class PromotionCelebrationScreen extends StatefulWidget {
  final String newRankCode;
  final UserStatSnapshot? baseline;
  final UserStatSnapshot? now;

  const PromotionCelebrationScreen({
    super.key,
    required this.newRankCode,
    this.baseline,
    this.now,
  });

  @override
  State<PromotionCelebrationScreen> createState() =>
      _PromotionCelebrationScreenState();
}

class _PromotionCelebrationScreenState extends State<PromotionCelebrationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeIn;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    // 30-second auto-dismiss safety. Stored in a Timer so dispose() can
    // cancel it — without this, widget tests crash with "A Timer is still
    // pending even after the widget tree was disposed".
    _autoDismissTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rank = rankByCode(widget.newRankCode) ?? kRankLadder.first;
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'PROMOTION DAY',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.accent,
                    letterSpacing: 4,
                    fontSize: 14,
                  ),
                ),
                Container(
                  height: 1,
                  width: 100,
                  color: AppColors.accent,
                  margin: const EdgeInsets.symmetric(vertical: 16),
                ),
                AnimatedBuilder(
                  animation: _fadeIn,
                  builder: (ctx, _) => Opacity(
                    opacity: _fadeIn.value,
                    child: _buildPlaceholderInsignia(rank.code),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  rank.displayName,
                  style: AppTypography.h2.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'By order of the Captain — you are promoted to ${rank.displayName}.',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (widget.baseline != null && widget.now != null)
                  _buildStatsRow(),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _shareThisMoment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Share this moment'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tap anywhere to dismiss',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderInsignia(String code) {
    // MVP placeholder. Plan D D-1 will replace with WardRankInsignia CustomPaint.
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.accent, width: 3),
        borderRadius: BorderRadius.circular(48),
      ),
      alignment: Alignment.center,
      child: Text(
        code,
        style: AppTypography.mono.copyWith(
          color: AppColors.accent,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final w0 = widget.baseline?.weightKg;
    final w1 = widget.now?.weightKg;
    final wDelta = (w0 != null && w1 != null) ? w1 - w0 : null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _statTile(
          'WEIGHT',
          '${w0?.toStringAsFixed(1) ?? "—"} → ${w1?.toStringAsFixed(1) ?? "—"} kg',
          wDelta != null
              ? '${wDelta >= 0 ? "+" : ""}${wDelta.toStringAsFixed(1)} kg'
              : null,
        ),
        _statTile(
          'PROTEIN',
          '${widget.baseline?.avgProtein7d ?? "—"} → ${widget.now?.avgProtein7d ?? "—"} g',
          null,
        ),
        _statTile('STREAK', 'PEAK', null),
      ],
    );
  }

  Widget _statTile(String label, String value, String? delta) {
    return Column(
      children: [
        Text(
          label,
          style: AppTypography.mono.copyWith(
            color: AppColors.textDim,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.body.copyWith(color: AppColors.textPrimary),
        ),
        if (delta != null)
          Text(
            delta,
            style: AppTypography.bodySm.copyWith(color: AppColors.accent),
          ),
      ],
    );
  }

  Future<void> _shareThisMoment() async {
    // F-14 MVP — text share. Image generation deferred to Test #7.
    final rank = rankByCode(widget.newRankCode) ?? kRankLadder.first;
    await Share.share(
      'I just ranked up to ${rank.displayName} on AVYA! 🎖️',
      subject: 'Promotion Day — ${rank.displayName}',
    );
  }
}
