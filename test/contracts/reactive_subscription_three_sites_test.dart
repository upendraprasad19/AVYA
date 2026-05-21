// H-1 / H-2 / H-2b (audit-2026-05-11) — regression test that 3
// surfaces watch the canonical `subscriptionInfoProvider` instead of
// snapshotting `SubscriptionService.instance.isPro()` at build/init
// time. Stale-pro class APK Test #12 / C-2 — a free user who upgrades
// mid-session would see "free" UI on all three until the next
// rebuild.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/read_screen_source.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('H-1/H-2/H-2b reactive subscriptionInfoProvider', () {
    test(
      'H-1 — userStatsProvider build() reads subscriptionInfoProvider',
      () {
        final src = _src('lib/features/profile/providers/profile_provider.dart');
        final idx = src.indexOf('class UserStatsNotifier');
        expect(idx, greaterThan(0));
        // Slice to the end of the class — next `class ` declaration
        // or next `final ...Provider` at top level.
        final endA = src.indexOf('\nclass ', idx + 10);
        final endB = src.indexOf('\nfinal userStatsProvider', idx + 10);
        final candidateEnds =
            [endA, endB].where((i) => i > idx).toList()..sort();
        final endIdx = candidateEnds.isEmpty ? src.length : candidateEnds.first;
        final body = src.substring(idx, endIdx);

        expect(
          body,
          contains('ref.watch(subscriptionInfoProvider)'),
          reason:
              'UserStatsNotifier.build() must watch '
              'subscriptionInfoProvider so the stats card reactively '
              'rebuilds on PRO upgrade. Pre-fix it snapshotted '
              'SubscriptionService.isPro() at build time → stayed on '
              '"free" until the user manually triggered a rebuild.',
        );
        expect(
          body.contains('SubscriptionService.instance.isPro()'),
          isFalse,
          reason:
              'UserStatsNotifier must not call SubscriptionService.isPro() '
              'directly — that snapshot is what stale-pro fixes are '
              'replacing across the codebase.',
        );
      },
    );

    test(
      'H-2 — train_screen WeekSelector.onSelect reads subscriptionInfoProvider',
      () {
        final src = readScreenSource('train');
        final idx = src.indexOf('WeekSelector(');
        expect(idx, greaterThan(0));
        // Slice to the closing `),` of the WeekSelector — find the
        // next top-level widget. Use the comment 'Week selector tabs'
        // / 'Compact week rows' anchor: onSelect body is between them.
        final endIdx = src.indexOf('// Compact week rows', idx);
        final body = src.substring(idx, endIdx > idx ? endIdx : src.length);

        expect(
          body,
          contains('ref.read(subscriptionInfoProvider)'),
          reason:
              'WeekSelector.onSelect must read subscriptionInfoProvider '
              'so the PRO/free routing decision reflects the latest '
              'subscription state. Pre-fix it called '
              'SubscriptionService.isPro() directly → free user who '
              'upgrades mid-session still routed to preview screen.',
        );
      },
    );

    test(
      'H-2b — swap_sheet does NOT cache isPro at initState',
      () {
        final src = _src('lib/features/home/widgets/swap_sheet.dart');
        // The original bug pattern: `late final bool _isPro;` field
        // plus an assignment in initState. Both must be absent.
        expect(
          src.contains('late final bool _isPro'),
          isFalse,
          reason:
              'swap_sheet must not declare `late final bool _isPro`. '
              'Cached at initState time → stays stale if user upgrades '
              'while the sheet is open.',
        );
        expect(
          src.contains('_isPro = _subscriptionService.isPro()'),
          isFalse,
          reason:
              'swap_sheet must not assign _isPro from a cached snapshot. '
              'Use ref.read(subscriptionInfoProvider) inside _onConfirm '
              'instead.',
        );
        expect(
          src,
          contains('ref.read(subscriptionInfoProvider)'),
          reason:
              'swap_sheet must read subscriptionInfoProvider at the '
              'moment of confirmation so the PRO branch reflects '
              'mid-session upgrades.',
        );
      },
    );

    test(
      'swap_sheet upgraded to ConsumerStatefulWidget for ref access',
      () {
        final src = _src('lib/features/home/widgets/swap_sheet.dart');
        expect(
          src,
          contains('class SwapSheet extends ConsumerStatefulWidget'),
          reason:
              'swap_sheet must be a ConsumerStatefulWidget so the state '
              'class has ref access for the H-2b reactive read.',
        );
        expect(
          src,
          contains('extends ConsumerState<SwapSheet>'),
          reason:
              'State class must extend ConsumerState for ref access.',
        );
      },
    );
  });
}
