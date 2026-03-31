import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with toggle
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.monitor_heart_outlined,
                  size: 16,
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health Sync',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      isSyncEnabled
                          ? 'Google Fit / Health Connect'
                          : 'Tap to enable',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onToggleSync,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isSyncEnabled ? AppColors.accent : AppColors.border,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment: isSyncEnabled
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: isSyncEnabled
                            ? Colors.black
                            : AppColors.textSecondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (isSyncEnabled) ...[
            const SizedBox(height: 14),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 14),

            // Stats row
            Row(
              children: [
                // Steps
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
                  color: AppColors.border,
                ),
                // Sleep (with manual entry pencil)
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showSleepSheet(context),
                    child: _MetricTile(
                      icon: Icons.bedtime_outlined,
                      iconColor: AppColors.purple,
                      label: 'SLEEP',
                      value: sleepHours != null
                          ? '${sleepHours!.toStringAsFixed(1)}h'
                          : '--',
                      trailing: Icon(Icons.edit, size: 12, color: AppColors.textSecondary),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
      padding: EdgeInsets.fromLTRB(18, 14, 18, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Log Sleep',
            style: GoogleFonts.getFont('DM Sans',
                fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 14),

          // Duration
          Text('Duration (hours)', style: GoogleFonts.getFont('DM Sans',
              fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: _hoursController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.getFont('DM Sans', fontSize: 16, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. 7.5',
              hintStyle: GoogleFonts.getFont('DM Sans', color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.input,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),

          // Quality
          Text('Quality', style: GoogleFonts.getFont('DM Sans',
              fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
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
                        color: isActive ? AppColors.purple : AppColors.input,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: isActive ? AppColors.purple : AppColors.border,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          q,
                          style: GoogleFonts.getFont('DM Sans',
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: isActive ? Colors.white : AppColors.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          // Save button
          GestureDetector(
            onTap: () {
              final hours = double.tryParse(_hoursController.text);
              if (hours == null || hours <= 0 || hours > 24) return;
              widget.onSave?.call(hours, _quality.toLowerCase());
              Navigator.of(context).pop();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Center(
                child: Text(
                  'SAVE',
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black),
                ),
              ),
            ),
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
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
