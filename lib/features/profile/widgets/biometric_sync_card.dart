import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Biometric sync card displaying steps and sleep from Health Connect.
///
/// FREE for all users. Display-only for now — adaptive workouts = Phase 2.
class BiometricSyncCard extends StatelessWidget {
  final int? stepsToday;
  final double? sleepHours;
  final bool isSyncEnabled;
  final VoidCallback onToggleSync;
  final void Function(double hours, String quality)? onLogSleep;

  const BiometricSyncCard({
    super.key,
    this.stepsToday,
    this.sleepHours,
    required this.isSyncEnabled,
    required this.onToggleSync,
    this.onLogSleep,
  });

  @override
  Widget build(BuildContext context) {
    return WardCard(
      variant: WardCardVariant.inset,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Status dot
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isSyncEnabled ? AppColors.ok : AppColors.textMute,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HEALTH CONNECT',
                      style: AppTypography.mono.copyWith(
                        color: AppColors.textMute,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isSyncEnabled
                          ? 'Google Fit / Health Connect'
                          : 'Tap to enable',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              // Sharp slab CONNECT / SYNCED toggle
              GestureDetector(
                onTap: onToggleSync,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSyncEnabled ? Colors.transparent : AppColors.accent,
                    border: Border.all(color: AppColors.accent),
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                  ),
                  child: Text(
                    isSyncEnabled ? 'SYNCED' : 'CONNECT',
                    style: AppTypography.monoXs.copyWith(
                      color: isSyncEnabled ? AppColors.accent : AppColors.bgDeep,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (isSyncEnabled) ...[
            const SizedBox(height: 14),
            const WardRule(margin: EdgeInsets.zero),
            const SizedBox(height: 14),

            // Stats row
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    icon: Icons.directions_walk,
                    iconColor: AppColors.accent,
                    label: 'STEPS TODAY',
                    value: stepsToday != null
                        ? _formatNumber(stepsToday!)
                        : '--',
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: AppColors.line2,
                ),
                // Sleep (with manual entry pencil)
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showSleepSheet(context),
                    child: _MetricTile(
                      icon: Icons.bedtime_outlined,
                      iconColor: AppColors.info,
                      label: 'SLEEP',
                      value: sleepHours != null
                          ? '${sleepHours!.toStringAsFixed(1)}h'
                          : '--',
                      trailing: const Icon(Icons.edit,
                          size: 12, color: AppColors.textMute),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1)}k';
    }
    return n.toString();
  }

  void _showSleepSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (_) => _ManualSleepSheet(
        initialHours: sleepHours,
        onSave: onLogSleep,
      ),
    );
  }
}

/// Bottom sheet for manual sleep entry.
class _ManualSleepSheet extends StatefulWidget {
  final double? initialHours;
  final void Function(double hours, String quality)? onSave;

  const _ManualSleepSheet({this.initialHours, this.onSave});

  @override
  State<_ManualSleepSheet> createState() => _ManualSleepSheetState();
}

class _ManualSleepSheetState extends State<_ManualSleepSheet> {
  late TextEditingController _hoursController;
  String _quality = 'Good';
  static const _qualities = ['Poor', 'Fair', 'Good', 'Excellent'];

  @override
  void initState() {
    super.initState();
    _hoursController = TextEditingController(
      text: widget.initialHours?.toStringAsFixed(1) ?? '',
    );
  }

  @override
  void dispose() {
    _hoursController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(18, 14, 18, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'LOG SLEEP',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Log Sleep',
            style: AppTypography.h2,
          ),
          const SizedBox(height: 14),

          // Duration
          Text(
            'Duration (hours)',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _hoursController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTypography.body
                .copyWith(fontSize: 16, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. 7.5',
              hintStyle: AppTypography.body.copyWith(color: AppColors.textDim),
              filled: true,
              fillColor: AppColors.bgRaise,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide: const BorderSide(color: AppColors.line2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide: const BorderSide(color: AppColors.line2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),

          // Quality
          Text(
            'Quality',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: _qualities.map((q) {
              final isActive = _quality == q;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: q != _qualities.last ? 6 : 0),
                  child: GestureDetector(
                    onTap: () => setState(() => _quality = q),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.info : AppColors.bgRaise,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: isActive ? AppColors.info : AppColors.line2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          q,
                          style: AppTypography.bodySm.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? AppColors.bgDeep
                                : AppColors.textDim,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          // Save button — sharp 2-px gold slab
          WardButton(
            label: 'Save',
            onPressed: () {
              final hours = double.tryParse(_hoursController.text);
              if (hours == null || hours <= 0 || hours > 24) return;
              widget.onSave?.call(hours, _quality.toLowerCase());
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Widget? trailing;

  const _MetricTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 20),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: AppTypography.h3.copyWith(
            color: AppColors.textPrimary,
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTypography.monoXs.copyWith(
            color: AppColors.textMute,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}
