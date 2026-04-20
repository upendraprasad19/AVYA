import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Notifications inbox — matches the handoff
/// (`design_handoff_wardroom/src/screens/utility.jsx` NotificationsScreen).
///
/// Three-column header (BACK / INBOX + title / MARK READ) under a
/// double gold rule; four filter pills (ALL · N / COACH / PR / SYSTEM);
/// three grouped sections (TODAY / YESTERDAY / EARLIER THIS WEEK) with
/// category-tagged notification cards. Gold-flagged items get a 2-px
/// accent left border and a gold category label.
///
/// This is a presentation shell; inbox content is seeded from
/// `_sampleItems` until the OneSignal + local notifications Hive box
/// reader wiring lands in a follow-up PR.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _filter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final items = _sampleItems
        .where((e) => _filter == 'ALL' || e.category == _filter)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: WardFrame(
        padBottom: 0,
        child: SafeArea(
          child: Column(
            children: [
              _header(context),
              _filters(items.length),
              Expanded(child: _list(items)),
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
              Padding(
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

  Widget _filters(int total) {
    const options = ['ALL', 'COACH', 'PR', 'SYSTEM'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
      child: Row(
        children: [
          for (final opt in options) ...[
            GestureDetector(
              onTap: () => setState(() => _filter = opt),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _filter == opt
                      ? AppColors.accentSoft
                      : Colors.transparent,
                  border: Border.all(
                    color: _filter == opt
                        ? AppColors.accent.withValues(alpha: 0.33)
                        : AppColors.line2,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  opt == 'ALL' ? 'ALL \u00B7 $total' : opt,
                  style: AppTypography.monoXs.copyWith(
                    fontSize: 9,
                    color: _filter == opt
                        ? AppColors.accent
                        : AppColors.textDim,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
            if (opt != options.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _list(List<_InboxItem> items) {
    final grouped = <String, List<_InboxItem>>{};
    for (final it in items) {
      grouped.putIfAbsent(it.group, () => []).add(it);
    }
    const order = ['TODAY', 'YESTERDAY', 'EARLIER THIS WEEK'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      children: [
        for (final group in order)
          if (grouped[group] != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
              child: Text(
                group,
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
  final _InboxItem item;

  @override
  Widget build(BuildContext context) {
    final gold = item.gold;
    return Container(
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
              item.category,
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
                        item.time,
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
    );
  }
}

class _InboxItem {
  const _InboxItem({
    required this.category,
    required this.title,
    required this.body,
    required this.time,
    required this.group,
    this.gold = false,
  });
  final String category;
  final String title;
  final String body;
  final String time;
  final String group;
  final bool gold;
}

const _sampleItems = <_InboxItem>[
  _InboxItem(
    category: 'COACH',
    title: "Today's dispatch is ready",
    body:
        "Your Leg Day is scheduled \u2014 6 exercises, ~55 min. Ready when you are.",
    time: '09:12',
    group: 'TODAY',
    gold: true,
  ),
  _InboxItem(
    category: 'PR',
    title: 'New PR on Incline Dumbbell Press',
    body: '70 kg \u00D7 6 reps \u2014 up 7.5 kg since Phase 1 start.',
    time: '07:48',
    group: 'TODAY',
    gold: true,
  ),
  _InboxItem(
    category: 'SYSTEM',
    title: 'Weekly report generated',
    body:
        'Your W·15 report is ready. 4 workouts, 48.2 t volume, 4-day streak.',
    time: 'Sun 22:04',
    group: 'YESTERDAY',
  ),
  _InboxItem(
    category: 'COACH',
    title: 'Protein target missed yesterday',
    body:
        "Fell 38g short on protein. Try 180g salmon + quinoa for an easy hit.",
    time: 'Sun 21:00',
    group: 'YESTERDAY',
  ),
  _InboxItem(
    category: 'COACH',
    title: 'Your streak is 3 days strong',
    body: 'Another 4 and the freeze unlocks. Keep the momentum.',
    time: 'Sat 18:22',
    group: 'EARLIER THIS WEEK',
  ),
];
