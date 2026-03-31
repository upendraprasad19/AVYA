import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import '../widgets/profile_row.dart';

/// Dedicated screen for managing notification preferences.
/// Receives current prefs from ProfileScreen and calls [onSave] on changes.
class NotificationSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> notifPrefs;
  final bool isPro;
  final ValueChanged<Map<String, dynamic>> onSave;

  const NotificationSettingsScreen({
    super.key,
    required this.notifPrefs,
    required this.isPro,
    required this.onSave,
  });

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late Map<String, dynamic> _prefs;

  @override
  void initState() {
    super.initState();
    // Deep copy so mutations don't affect parent until onSave
    _prefs = {};
    for (final entry in widget.notifPrefs.entries) {
      if (entry.value is Map) {
        _prefs[entry.key] = Map<String, dynamic>.from(entry.value as Map);
      } else {
        _prefs[entry.key] = entry.value;
      }
    }
  }

  bool _getEnabled(String key) {
    final pref = _prefs[key];
    if (pref is Map) return pref['enabled'] == true;
    return true;
  }

  String _getTime(String key) {
    final pref = _prefs[key];
    if (pref is Map && pref['time'] is String) return pref['time'] as String;
    return '07:00';
  }

  String _getDay(String key) {
    final pref = _prefs[key];
    if (pref is Map && pref['day'] is String) return pref['day'] as String;
    return 'sunday';
  }

  void _toggle(String key, bool value) {
    setState(() {
      final pref = Map<String, dynamic>.from((_prefs[key] as Map?) ?? {});
      pref['enabled'] = value;
      _prefs[key] = pref;
    });
    widget.onSave(_prefs);
  }

  void _setTime(String key, String time) {
    setState(() {
      final pref = Map<String, dynamic>.from((_prefs[key] as Map?) ?? {});
      pref['time'] = time;
      _prefs[key] = pref;
    });
    widget.onSave(_prefs);
  }

  void _setDay(String key, String day) {
    setState(() {
      final pref = Map<String, dynamic>.from((_prefs[key] as Map?) ?? {});
      pref['day'] = day;
      _prefs[key] = pref;
    });
    widget.onSave(_prefs);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.getFont('DM Sans',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _NotificationRow(
                  icon: Icons.wb_sunny_outlined,
                  title: 'Morning Check-in',
                  enabled: _getEnabled('morning_checkin'),
                  onToggle: (v) => _toggle('morning_checkin', v),
                  isPro: widget.isPro,
                  timeValue: _getTime('morning_checkin'),
                  timeOptions: const [
                    '05:00', '05:30', '06:00', '06:30', '07:00',
                    '07:30', '08:00', '08:30', '09:00',
                  ],
                  onTimeChanged: (t) => _setTime('morning_checkin', t),
                ),
                _NotificationRow(
                  icon: Icons.fitness_center,
                  title: 'Workout Reminder',
                  enabled: _getEnabled('workout_reminder'),
                  onToggle: (v) => _toggle('workout_reminder', v),
                  timeValue: _getTime('workout_reminder'),
                  timeOptions: const [
                    '06:00', '07:00', '08:00', '09:00', '10:00',
                    '16:00', '17:00', '18:00', '18:30', '19:00',
                    '20:00', '21:00',
                  ],
                  onTimeChanged: (t) => _setTime('workout_reminder', t),
                ),
                _NotificationRow(
                  icon: Icons.local_fire_department_outlined,
                  title: 'Streak Alerts',
                  enabled: _getEnabled('streak_alerts'),
                  onToggle: (v) => _toggle('streak_alerts', v),
                ),
                _NotificationRow(
                  icon: Icons.bar_chart_rounded,
                  title: 'Weekly Recap',
                  enabled: _getEnabled('weekly_recap'),
                  onToggle: (v) => _toggle('weekly_recap', v),
                  dayValue: _getDay('weekly_recap'),
                  dayOptions: const [
                    'monday', 'tuesday', 'wednesday', 'thursday',
                    'friday', 'saturday', 'sunday',
                  ],
                  onDayChanged: (d) => _setDay('weekly_recap', d),
                ),
                _NotificationRow(
                  icon: Icons.diamond_outlined,
                  title: 'Subscription Reminders',
                  enabled: _getEnabled('subscription_reminders'),
                  onToggle: (v) => _toggle('subscription_reminders', v),
                  showBorder: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Notifications help you stay consistent. We\'ll never spam you.',
            style: GoogleFonts.getFont('DM Sans',
                fontSize: 11, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Notification Row ──────────────────────────────────────────────────

class _NotificationRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final bool isPro;
  final bool showBorder;
  final String? timeValue;
  final List<String>? timeOptions;
  final ValueChanged<String>? onTimeChanged;
  final String? dayValue;
  final List<String>? dayOptions;
  final ValueChanged<String>? onDayChanged;

  const _NotificationRow({
    required this.icon,
    required this.title,
    required this.enabled,
    required this.onToggle,
    this.isPro = false,
    this.showBorder = true,
    this.timeValue,
    this.timeOptions,
    this.onTimeChanged,
    this.dayValue,
    this.dayOptions,
    this.onDayChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: showBorder
            ? const Border(
                bottom: BorderSide(color: AppColors.border, width: 1),
              )
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: GoogleFonts.getFont('DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isPro) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.proGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'PRO',
                      style: GoogleFonts.getFont('DM Sans',
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: AppColors.proGold),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (timeOptions != null && timeValue != null && enabled)
            _TimePicker(
              value: timeValue!,
              options: timeOptions!,
              onChanged: onTimeChanged!,
            ),
          if (dayOptions != null && dayValue != null && enabled)
            _DayPicker(
              value: dayValue!,
              options: dayOptions!,
              onChanged: onDayChanged!,
            ),
          const SizedBox(width: 8),
          ProfileToggle(value: enabled, onChanged: onToggle),
        ],
      ),
    );
  }
}

// ── Time Picker ───────────────────────────────────────────────────────

class _TimePicker extends StatelessWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _TimePicker({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  String _formatTime(String time24) {
    final parts = time24.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts.length > 1 ? parts[1] : '00';
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      itemBuilder: (ctx) => options
          .map((t) => PopupMenuItem(
                value: t,
                child: Text(
                  _formatTime(t),
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 12,
                      fontWeight: t == value ? FontWeight.w700 : FontWeight.w400,
                      color: t == value ? AppColors.accent : AppColors.textPrimary),
                ),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatTime(value),
              style: GoogleFonts.getFont('DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 14, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}

// ── Day Picker ────────────────────────────────────────────────────────

class _DayPicker extends StatelessWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _DayPicker({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  String _formatDay(String day) {
    if (day.isEmpty) return day;
    return day[0].toUpperCase() + day.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      itemBuilder: (ctx) => options
          .map((d) => PopupMenuItem(
                value: d,
                child: Text(
                  _formatDay(d),
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 12,
                      fontWeight: d == value ? FontWeight.w700 : FontWeight.w400,
                      color: d == value ? AppColors.accent : AppColors.textPrimary),
                ),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatDay(value),
              style: GoogleFonts.getFont('DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 14, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
