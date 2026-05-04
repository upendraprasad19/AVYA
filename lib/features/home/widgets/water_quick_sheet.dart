import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/water_target_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Bottom sheet for quickly adding water intake from the home screen.
///
/// Shows current intake vs personal target (from WaterTargetService).
/// Includes quick-add buttons and an EDIT TARGET affordance.
class WaterQuickSheet extends ConsumerStatefulWidget {
  const WaterQuickSheet({super.key});

  @override
  ConsumerState<WaterQuickSheet> createState() => _WaterQuickSheetState();
}

class _WaterQuickSheetState extends ConsumerState<WaterQuickSheet> {
  String? _addedLabel;

  void _addWater(int ml, String label) async {
    await ref.read(waterIntakeProvider.notifier).addWater(ml);
    setState(() => _addedLabel = label);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _addedLabel = null);
    });
  }

  Future<void> _openEditTarget() async {
    // Capture messenger before the await so it's safe to use after async gap.
    final messenger = ScaffoldMessenger.of(context);
    final result = await showModalBottomSheet<({bool reset, int? newMl})>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _EditWaterTargetSheet(
        currentMl: WaterTargetService.instance.currentTargetMl(),
        hasOverride: WaterTargetService.instance.hasUserOverride(),
      ),
    );
    if (result == null) return; // sheet dismissed
    if (result.reset) {
      await WaterTargetService.instance.setUserOverride(null);
    } else if (result.newMl != null) {
      await WaterTargetService.instance.setUserOverride(result.newMl);
    }
    if (!mounted) return;
    ref.invalidate(waterTargetProvider);
    messenger.showSnackBar(SnackBar(
      content: Text('Target updated ✓', style: AppTypography.body),
      backgroundColor: AppColors.ok,
      duration: const Duration(seconds: 1),
    ));
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final currentMl = ref.watch(waterIntakeProvider);
    final targetMl = ref.watch(waterTargetProvider);
    final progress = (currentMl / targetMl).clamp(0.0, 1.0);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        12,
        AppSpacing.gutter,
        24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.line2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title row — mono caps eyebrow + EDIT TARGET link
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              Text(
                'LOG WATER',
                style: AppTypography.mono.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 3,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _openEditTarget,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  child: Text(
                    'EDIT TARGET',
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Current progress — Fraunces numeric
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _formatMl(currentMl),
                  style: AppTypography.h1.copyWith(
                    color: AppColors.accent,
                  ),
                ),
                TextSpan(
                  text: ' / ${_formatMl(targetMl)} ML',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Progress bar — WardBar
          WardBar(
            pct: progress,
            height: 6,
            color: AppColors.info,
          ),
          const SizedBox(height: 10),

          // Feedback text
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _addedLabel != null
                ? Text(
                    '✓ ADDED $_addedLabel',
                    key: ValueKey(_addedLabel),
                    style: AppTypography.mono.copyWith(
                      color: AppColors.ok,
                      letterSpacing: 2,
                    ),
                  )
                : const SizedBox(height: 16, key: ValueKey('empty')),
          ),
          const SizedBox(height: 12),

          // Quick-add buttons row — sharp 2-px outline tiles
          Row(
            children: [
              _WaterButton(
                label: '150ML',
                subtitle: 'SMALL GLASS',
                icon: Icons.local_cafe_outlined,
                onTap: () => _addWater(150, '150ml'),
              ),
              const SizedBox(width: 8),
              _WaterButton(
                label: '250ML',
                subtitle: 'GLASS',
                icon: Icons.local_drink_outlined,
                onTap: () => _addWater(250, '250ml'),
              ),
              const SizedBox(width: 8),
              _WaterButton(
                label: '500ML',
                subtitle: 'BOTTLE',
                icon: Icons.water_drop_outlined,
                onTap: () => _addWater(500, '500ml'),
              ),
              const SizedBox(width: 8),
              _WaterButton(
                label: '750ML',
                subtitle: 'LARGE',
                icon: Icons.sports_bar_outlined,
                onTap: () => _addWater(750, '750ml'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _formatMl(int ml) {
    if (ml >= 1000) {
      final thousands = ml ~/ 1000;
      final hundreds = (ml % 1000).toString().padLeft(3, '0');
      return '$thousands,$hundreds';
    }
    return ml.toString();
  }
}

class _WaterButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _WaterButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: AppColors.bgRaise,
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            border: Border.all(color: AppColors.line2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(height: 6),
              Text(
                label,
                style: AppTypography.mono.copyWith(
                  color: AppColors.textPrimary,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Edit Water Target Sheet ───────────────────────────────────────
//
// Allows the user to override their computed daily water target.
// Min 2500 ml (WaterTargetService.floorMl), max 4000 ml (ceilingMl).
// Stepping in 100 ml increments via +/- buttons or direct text entry.
// Returns ({reset: true, newMl: null}) to clear override,
//         ({reset: false, newMl: <value>}) to apply a new one.
class _EditWaterTargetSheet extends StatefulWidget {
  const _EditWaterTargetSheet({
    required this.currentMl,
    required this.hasOverride,
  });

  final int currentMl;
  final bool hasOverride;

  @override
  State<_EditWaterTargetSheet> createState() => _EditWaterTargetSheetState();
}

class _EditWaterTargetSheetState extends State<_EditWaterTargetSheet> {
  late int _selectedMl;
  late TextEditingController _controller;

  static const _step = 100;

  @override
  void initState() {
    super.initState();
    _selectedMl = widget.currentMl;
    _controller = TextEditingController(text: _selectedMl.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _increment() {
    final next = (_selectedMl + _step)
        .clamp(WaterTargetService.floorMl, WaterTargetService.ceilingMl);
    _setMl(next.toInt());
  }

  void _decrement() {
    final next = (_selectedMl - _step)
        .clamp(WaterTargetService.floorMl, WaterTargetService.ceilingMl);
    _setMl(next.toInt());
  }

  void _setMl(int ml) {
    setState(() {
      _selectedMl = ml;
      _controller.text = ml.toString();
      _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length);
    });
  }

  void _onTextChanged(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    final clamped = parsed
        .clamp(WaterTargetService.floorMl, WaterTargetService.ceilingMl)
        .toInt();
    if (clamped != _selectedMl) setState(() => _selectedMl = clamped);
    // Resync controller text if clamping changed the value, to prevent stale
    // display (e.g. user types "9999" → display corrects to "4000").
    if (clamped != parsed) {
      _controller.value = TextEditingValue(
        text: clamped.toString(),
        selection: TextSelection.collapsed(offset: clamped.toString().length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final atFloor = _selectedMl <= WaterTargetService.floorMl;
    final atCeiling = _selectedMl >= WaterTargetService.ceilingMl;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter, 12, AppSpacing.gutter, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),

            // Eyebrow
            Text(
              'SET WATER TARGET',
              style: AppTypography.mono.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${WaterTargetService.floorMl ~/ 1000}.${(WaterTargetService.floorMl % 1000) ~/ 100} – '
              '${WaterTargetService.ceilingMl ~/ 1000}.${(WaterTargetService.ceilingMl % 1000) ~/ 100} L range',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textGhost,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 20),

            // Stepper row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Decrement
                _StepButton(
                  icon: Icons.remove,
                  onTap: atFloor ? null : _decrement,
                ),
                const SizedBox(width: 16),

                // Editable numeric input
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _controller,
                    onChanged: _onTextChanged,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    textAlign: TextAlign.center,
                    style: AppTypography.h2.copyWith(
                      color: AppColors.accent,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                      filled: true,
                      fillColor: AppColors.input,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.sharp),
                        borderSide: BorderSide(
                            color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.sharp),
                        borderSide: BorderSide(
                            color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.sharp),
                        borderSide: BorderSide(
                            color: AppColors.accent),
                      ),
                      suffixText: 'ML',
                      suffixStyle: AppTypography.monoXs.copyWith(
                        color: AppColors.textMute,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 16),
                // Increment
                _StepButton(
                  icon: Icons.add,
                  onTap: atCeiling ? null : _increment,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // SAVE button
            WardButton(
              label: 'SAVE TARGET',
              variant: WardButtonVariant.primary,
              onPressed: () => Navigator.of(context)
                  .pop((reset: false, newMl: _selectedMl)),
            ),

            // Reset link — only shown when user has an active override
            if (widget.hasOverride) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () =>
                    Navigator.of(context).pop((reset: true, newMl: null)),
                child: Text(
                  'Reset to recommended',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textDim,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.textGhost,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: enabled ? AppColors.input : AppColors.bgDeep,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(
            color: enabled
                ? AppColors.accent.withValues(alpha: 0.4)
                : AppColors.border,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 20,
          color: enabled ? AppColors.accent : AppColors.textGhost,
        ),
      ),
    );
  }
}
