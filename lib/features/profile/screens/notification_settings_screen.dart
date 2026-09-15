import 'dart:async';
import 'package:flutter/material.dart';
import 'package:icanbefitter/features/profile/services/notification_prefs_repository.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import '../widgets/profile_row.dart';

/// Dedicated screen for managing notification preferences.
/// Receives current prefs from ProfileScreen and calls [onSave] on changes.
class NotificationSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> notifPrefs;
  final bool isPro;

  /// Opens the paywall when a free user taps a locked PRO row. Optional so the
  /// screen stays usable from a test or a preview harness.
  ///
  /// Receives the tapped row's display title so the paywall names the feature
  /// the user actually reached for (OI-76). A single no-arg callback could only
  /// ever show one feature's copy for both locked rows.
  final ValueChanged<String>? onProLockedTap;
  final ValueChanged<Map<String, dynamic>> onSave;

  const NotificationSettingsScreen({
    super.key,
    required this.notifPrefs,
    required this.isPro,
    this.onProLockedTap,
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
    // Self-sufficient fallback (B-pass P1). The Settings entry point pushes
    // this route WITHOUT `extra`, so widget.notifPrefs arrives empty, isPro
    // false and onSave a no-op. Rendering that would show every toggle ON,
    // silently discard every change, and show a paying PRO user a lock. Read
    // the real values instead when the caller supplied none.
    final source = widget.notifPrefs.isNotEmpty
        ? widget.notifPrefs
        : NotificationPrefsRepository.read();
    _prefs = {};
    for (final entry in source.entries) {
      if (entry.value is Map) {
        _prefs[entry.key] = Map<String, dynamic>.from(entry.value as Map);
      } else {
        _prefs[entry.key] = entry.value;
      }
    }
  }

  /// Legacy key aliases — the client historically stored `workout_reminder`
  /// (singular). Reading only the plural would show the row as ON for a user
  /// who deliberately turned it OFF, and their next save would overwrite the
  /// stored choice. Mirrors NotificationPrefsRepository._legacyAliases.
  static const Map<String, String> _legacyAliases = {
    'workout_reminders': 'workout_reminder',
  };

  dynamic _pref(String key) => _prefs[key] ?? _prefs[_legacyAliases[key] ?? ''];

  /// Persists a change.
  ///
  /// Prefers the caller's [onSave] (ProfileScreen owns the in-memory copy and
  /// needs to stay in sync). Falls back to writing through the repository
  /// directly when the caller supplied the router's no-op default — otherwise
  /// every change made via the Settings entry point is silently discarded
  /// (B-pass P1).
  void _persist() {
    widget.onSave(_prefs);
    if (widget.notifPrefs.isEmpty) {
      // Reached without `extra` — the caller's onSave is the router default,
      // which throws the value away. Write it ourselves.
      unawaited(NotificationPrefsRepository.write(_prefs));
    }
  }

  bool _getEnabled(String key) {
    final pref = _pref(key);
    // `!= false`, never `== true`. A map that carries only {time: '20:00'} —
    // which is exactly what _setTime writes for a key the user has never
    // toggled — must still read as ENABLED. The old `== true` flipped the
    // toggle off the moment someone changed a time (B-pass P1).
    if (pref is Map) return pref['enabled'] == true;
    return true;
  }

  String _getTime(String key) {
    final pref = _pref(key);
    if (pref is Map && pref['time'] is String) return pref['time'] as String;
    return '07:00';
  }

  String _getDay(String key) {
    final pref = _pref(key);
    if (pref is Map && pref['day'] is String) return pref['day'] as String;
    return 'sunday';
  }

  void _toggle(String key, bool value) {
    setState(() {
      final pref = Map<String, dynamic>.from((_prefs[key] as Map?) ?? {});
      pref['enabled'] = value;
      _prefs[key] = pref;
    });
    _persist();
  }

  void _setTime(String key, String time) {
    setState(() {
      final pref = Map<String, dynamic>.from((_prefs[key] as Map?) ?? {});
      pref['time'] = time;
      _prefs[key] = pref;
    });
    _persist();
  }

  void _setDay(String key, String day) {
    setState(() {
      final pref = Map<String, dynamic>.from((_prefs[key] as Map?) ?? {});
      pref['day'] = day;
      _prefs[key] = pref;
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DISPATCH \u00B7 SIGNALS',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 2.5,
              ),
            ),
            const SizedBox(height: 2),
            Text('Notifications', style: AppTypography.h3),
          ],
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
                  enabled: _getEnabled('workout_reminders'),
                  onToggle: (v) => _toggle('workout_reminders', v),
                  timeValue: _getTime('workout_reminders'),
                  timeOptions: const [
                    '06:00', '07:00', '08:00', '09:00', '10:00',
                    '16:00', '17:00', '18:00', '18:30', '19:00',
                    '20:00', '21:00',
                  ],
                  onTimeChanged: (t) => _setTime('workout_reminders', t),
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
                ),
                _NotificationRow(
                  icon: Icons.egg_outlined,
                  title: 'Protein Alerts',
                  enabled: _getEnabled('protein_alerts'),
                  onToggle: (v) => _toggle('protein_alerts', v),
                  isProFeature: NotificationPrefsRepository.proOnlyKeys
                      .contains('protein_alerts'),
                  userIsPro: widget.isPro,
                  onLockedTap: widget.onProLockedTap,
                ),
                _NotificationRow(
                  icon: Icons.trending_flat_rounded,
                  title: 'Plateau Check',
                  enabled: _getEnabled('plateau_alert'),
                  onToggle: (v) => _toggle('plateau_alert', v),
                  isProFeature: NotificationPrefsRepository.proOnlyKeys
                      .contains('plateau_alert'),
                  userIsPro: widget.isPro,
                  onLockedTap: widget.onProLockedTap,
                ),
                _NotificationRow(
                  icon: Icons.emoji_events_outlined,
                  title: 'PR Celebrations',
                  enabled: _getEnabled('pr_celebration'),
                  onToggle: (v) => _toggle('pr_celebration', v),
                ),
                _NotificationRow(
                  icon: Icons.military_tech_outlined,
                  title: 'Promotion Day',
                  enabled: _getEnabled('rank_promotion'),
                  onToggle: (v) => _toggle('rank_promotion', v),
                ),
                _NotificationRow(
                  icon: Icons.waving_hand_outlined,
                  title: 'Check-ins When Away',
                  enabled: _getEnabled('re_engagement'),
                  onToggle: (v) => _toggle('re_engagement', v),
                  showBorder: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Notifications help you stay consistent. We\'ll never spam you.',
            style: AppTypography.bodySm.copyWith(fontSize: 11, color: AppColors.textDim),
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
  /// TRUE when THIS ROW is a PRO feature — not when the user is PRO.
  ///
  /// The old semantic was inverted: `isPro: widget.isPro` showed the gold
  /// chip only to users who ALREADY had PRO, i.e. the one audience that did
  /// not need telling. A PRO badge is a signal to free users.
  final bool isProFeature;

  /// Whether the signed-in user actually has PRO. Combined with
  /// [isProFeature] this decides LOCKED vs interactive.
  final bool userIsPro;

  /// Invoked with this row's [title] when a free user taps a locked PRO row
  /// (opens the paywall).
  final ValueChanged<String>? onLockedTap;
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
    this.isProFeature = false,
    this.userIsPro = false,
    this.onLockedTap,
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
                    style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isProFeature) ...[
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
                      style: AppTypography.monoXs.copyWith(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.proGold),
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
          // A locked PRO row shows a lock, not a dead toggle. A toggle the
          // user can flip but that never persists is the exact "settings lie"
          // this whole batch exists to remove.
          if (isProFeature && !userIsPro)
            GestureDetector(
              onTap: onLockedTap == null ? null : () => onLockedTap!(title),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Icon(Icons.lock_outline,
                    size: 18, color: AppColors.proGold),
              ),
            )
          else
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
                  style: AppTypography.bodySm.copyWith(fontWeight: t == value ? FontWeight.w700 : FontWeight.w400, color: t == value ? AppColors.accent : AppColors.textPrimary),
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
              style: AppTypography.monoXs.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.accent),
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
                  style: AppTypography.bodySm.copyWith(fontWeight: d == value ? FontWeight.w700 : FontWeight.w400, color: d == value ? AppColors.accent : AppColors.textPrimary),
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
              style: AppTypography.monoXs.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.accent),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 14, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
