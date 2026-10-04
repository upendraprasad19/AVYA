import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../models/app_notification.dart';
import '../providers/notifications_inbox_provider.dart';

/// Notifications inbox — matches the handoff
/// (`design_handoff_wardroom/src/screens/utility.jsx` NotificationsScreen).
///
/// Three-column header (BACK / INBOX + title / MARK READ) under a
/// double gold rule; four filter pills (ALL · N / COACH / PR / SYSTEM);
/// time-grouped sections (TODAY / YESTERDAY / EARLIER THIS WEEK /
/// OLDER) with category-tagged notification cards. Gold-priority items
/// (PRs and anything with `priority:'gold'` in the OneSignal payload)
/// get a 2-px accent left border and a gold category label.
///
/// Data source: [notificationsInboxProvider] — reads from
/// `HiveService.instance.notificationsBox`, populated by
/// `NotificationInboxService` from OneSignal foreground/click events.
/// See `NotificationInboxService.init()` (wired in splash_screen) for
/// the ingest hooks + welcome seed.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// `null` means "ALL"; otherwise one of the enum categories.
  AppNotificationCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(notificationsInboxProvider);
    final filtered = _filter == null
        ? all
        : all.where((n) => n.category == _filter).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: WardFrame(
        padBottom: 0,
        child: SafeArea(
          child: Column(
            children: [
              _header(context),
              _filters(all.length),
              Expanded(
                child: filtered.isEmpty
                    ? _emptyState()
                    : _list(filtered),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.accent.withValues(alpha: 0.33),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => context.go('/profile'),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  child: Text(
                    '\u2190 BACK',
                    style: AppTypography.mono.copyWith(
                      fontSize: 11,
                      color: AppColors.textDim,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'INBOX',
                        style: AppTypography.monoXs.copyWith(
                          fontSize: 8,
                          color: AppColors.textMute,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Notifications',
                        style: AppTypography.h3.copyWith(
                          fontSize: 18,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: _onMarkAllRead,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  child: Text(
                    'MARK READ',
                    style: AppTypography.monoXs.copyWith(
                      fontSize: 10,
                      color: AppColors.accent,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Container(
            height: 1,
            color: AppColors.accent.withValues(alpha: 0.22),
            margin: const EdgeInsets.only(bottom: 2),
          ),
        ],
      ),
    );
  }

  void _onMarkAllRead() {
    ref.read(notificationsInboxProvider.notifier).markAllRead();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Inbox marked as read',
          style: AppTypography.bodySm.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _filters(int total) {
    // Build filter list. `null` is the ALL sentinel.
    final options = <(AppNotificationCategory?, String)>[
      (null, 'ALL'),
      (AppNotificationCategory.coach, 'COACH'),
      (AppNotificationCategory.pr, 'PR'),
      (AppNotificationCategory.system, 'SYSTEM'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            GestureDetector(
              onTap: () => setState(() => _filter = options[i].$1),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _filter == options[i].$1
                      ? AppColors.accentSoft
                      : Colors.transparent,
                  border: Border.all(
                    color: _filter == options[i].$1
                        ? AppColors.accent.withValues(alpha: 0.33)
                        : AppColors.line2,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  options[i].$1 == null
                      ? 'ALL \u00B7 $total'
                      : options[i].$2,
                  style: AppTypography.monoXs.copyWith(
                    fontSize: 9,
                    color: _filter == options[i].$1
                        ? AppColors.accent
                        : AppColors.textDim,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
            if (i < options.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 32,
              color: AppColors.textMute,
            ),
            const SizedBox(height: 12),
            Text(
              'INBOX IS CLEAR',
              style: AppTypography.mono.copyWith(
                fontSize: 10,
                color: AppColors.textMute,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Coach nudges, PRs, and weekly reports will show up here.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textDim,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<AppNotification> items) {
    // Partition by computed group (TODAY / YESTERDAY / EARLIER / OLDER)
    // and render section headers only when a group has entries.
    final grouped = <AppNotificationGroup, List<AppNotification>>{};
    for (final n in items) {
      final g = AppNotificationGroup.fromCreatedAt(n.createdAt);
      grouped.putIfAbsent(g, () => []).add(n);
    }
    const order = <AppNotificationGroup>[
      AppNotificationGroup.today,
      AppNotificationGroup.yesterday,
      AppNotificationGroup.earlierThisWeek,
      AppNotificationGroup.older,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      children: [
        for (final group in order)
          if ((grouped[group] ?? const []).isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
              child: Text(
                group.displayLabel,
                style: AppTypography.monoXs.copyWith(
                  fontSize: 9,
                  color: AppColors.textMute,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final item in grouped[group]!)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _NotificationTile(item: item),
              ),
          ],
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});
  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    final gold = item.priority == AppNotificationPriority.gold;
    return Opacity(
      // Read notifications fade slightly — gives the user an honest
      // sense of "already seen vs. new" without another UI affordance.
      opacity: item.read ? 0.6 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(
            top: BorderSide(color: AppColors.line2),
            right: BorderSide(color: AppColors.line2),
            bottom: BorderSide(color: AppColors.line2),
            left: BorderSide(
              color: gold ? AppColors.accent : AppColors.line2,
              width: gold ? 2 : 1,
            ),
          ),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              color: AppColors.bgDeep,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              child: Text(
                item.category.displayLabel,
                style: AppTypography.monoXs.copyWith(
                  fontSize: 8,
                  color: gold ? AppColors.accent : AppColors.textMute,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: AppTypography.h3.copyWith(fontSize: 13),
                          ),
                        ),
                        Text(
                          _formatTime(item.createdAt),
                          style: AppTypography.monoXs.copyWith(
                            fontSize: 9,
                            color: AppColors.textMute,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textDim,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final today =
        DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final h = local.hour;
    final m = local.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);

    if (day == today) {
      // TODAY group: hh:mm (24-hr) for quick scan consistency
      return '${local.hour.toString().padLeft(2, '0')}:$m';
    }
    // Older entries: weekday short + time. e.g. "Sun 22:04".
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final w = weekdays[local.weekday - 1].substring(0, 3);
    return '$w $h12:$m $period';
  }
}
