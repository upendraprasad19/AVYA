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
      'H-2b successor — SwapPickerSheet/SwapConfirmSheet read '
      'subscriptionInfoProvider reactively, never cached at initState',
      () {
        // swap_sheet.dart (the original H-2b fix site) was deleted in the
        // day-swapper batch. Home's long-press now opens the shared
        // SwapPickerSheet (Task 24), and every swap ultimately runs through
        // DaySwapController (lib/features/train/providers/day_swap_provider.dart,
        // Task 12), which reads isPro FRESH on every call, never cached:
        //
        //   bool get _isPro => _ref.read(subscriptionInfoProvider).isPro;
        //
        //   Future<DaySwapResult> swap({...}) async {
        //     final result = await _ref.read(swapServiceProvider).swapDays(
        //           ..., isPro: _isPro, ...);
        //     ...
        //   }
        //
        // `_isPro` is a GETTER (re-evaluated on every read), and `swap()`
        // reads it at call time, not in a constructor/initState — so a
        // subscription change between opening the sheet and confirming the
        // swap is picked up. This test pins the STRUCTURAL half (no cached
        // field on the widgets themselves, consistent with H-2b's original
        // fix); the FRESH-READ half is the controller code quoted above,
        // verified by reading day_swap_provider.dart directly (Task 12).
        for (final path in const [
          'lib/features/train/widgets/swap_picker_sheet.dart',
          'lib/features/train/widgets/swap_confirm_sheet.dart',
        ]) {
          final src = _src(path);
          expect(
            src.contains('late final bool _isPro'),
            isFalse,
            reason: '$path must not cache isPro at initState (H-2b class).',
          );
          expect(
            src,
            contains('subscriptionInfoProvider'),
            reason: '$path must read subscriptionInfoProvider.',
          );
          expect(
            src,
            contains('extends ConsumerState'),
            reason: '$path must be a ConsumerStatefulWidget for ref access.',
          );
        }
        final controllerSrc =
            _src('lib/features/train/providers/day_swap_provider.dart');
        expect(
          controllerSrc,
          contains('bool get _isPro => _ref.read(subscriptionInfoProvider).isPro;'),
          reason: 'DaySwapController must read isPro as a fresh getter, not '
              'cache it, so every swap sees the current tier.',
        );
      },
    );

    test(
      'H-3a — streakFreezeMaxProvider watches subscriptionInfoProvider',
      () {
        // Phase 2 (discipline-overhaul, 2026-06-18) — the freeze
        // denominator must flip 1→3 the instant a mid-session PRO grant
        // lands without an auth change or app relaunch.
        //
        // Pre-fix: `ref.read(subscriptionServiceProvider).isPro()` was a
        // snapshot — the Provider body only rebuilt on authUserIdTokenProvider
        // change (i.e. sign-out/sign-in), so a fresh payment that wrote
        // isPro=true kept showing "1/1" until relaunch. Same stale-pro
        // class as APK Test #12 / C-2.
        final src =
            _src('lib/features/home/providers/home_provider.dart');
        final idx = src.indexOf('final streakFreezeMaxProvider');
        expect(idx, greaterThan(0));
        final endIdx = src.indexOf('\n})', idx + 10);
        final body = src.substring(idx, endIdx > idx ? endIdx : src.length);

        expect(
          body,
          contains('ref.watch(subscriptionInfoProvider).isPro'),
          reason:
              'streakFreezeMaxProvider must watch subscriptionInfoProvider '
              'so a mid-session PRO grant (onStateChanged → invalidate) '
              'immediately rebuilds the provider and flips the max 1→3.',
        );
        expect(
          body.contains('ref.read(subscriptionServiceProvider).isPro()'),
          isFalse,
          reason:
              'streakFreezeMaxProvider must not call '
              'subscriptionServiceProvider.isPro() directly — that '
              'snapshot does not rebuild on onStateChanged (only on '
              'authUserIdTokenProvider change).',
        );
      },
    );

    test(
      'H-3b — StreakFreezeNotifier.build() watches subscriptionInfoProvider',
      () {
        // Phase 2 (discipline-overhaul, 2026-06-18) — the cap inside
        // StreakFreezeNotifier must also be reactive so that the stored
        // clamp immediately applies the PRO cap=3 when PRO is granted
        // mid-session.
        final src =
            _src('lib/features/home/providers/home_provider.dart');
        final idx = src.indexOf('class StreakFreezeNotifier');
        expect(idx, greaterThan(0));
        final endIdx = src.indexOf('\nfinal streakFreezeProvider', idx + 10);
        final body = src.substring(idx, endIdx > idx ? endIdx : src.length);

        expect(
          body,
          contains('ref.watch(subscriptionInfoProvider).isPro'),
          reason:
              'StreakFreezeNotifier.build() must watch '
              'subscriptionInfoProvider for the cap computation so that '
              'the stored value is clamped reactively on PRO upgrade '
              '(not only at next auth change).',
        );
        expect(
          body.contains('ref.read(subscriptionServiceProvider).isPro()'),
          isFalse,
          reason:
              'StreakFreezeNotifier must not call '
              'subscriptionServiceProvider.isPro() directly — stale-pro '
              'class fix.',
        );
      },
    );

    test(
      'H-3c — home_screen invalidateOnRetry includes streakFreezeProvider',
      () {
        // Phase 2 (discipline-overhaul, 2026-06-18) — invalidateOnRetry
        // is the bg-restore heal path. Without streakFreezeProvider, a
        // restored freeze count that changed Hive during the bg-restore
        // would not reflect until the next render cycle.
        final src = _src('lib/features/home/screens/home_screen.dart');
        final idx = src.indexOf('void invalidateOnRetry(WidgetRef ref)');
        expect(idx, greaterThan(0));
        final endIdx = src.indexOf('\n  }', idx + 10);
        final body = src.substring(idx, endIdx > idx ? endIdx : src.length);

        expect(
          body,
          contains('ref.invalidate(streakFreezeProvider)'),
          reason:
              'invalidateOnRetry must invalidate streakFreezeProvider so '
              'a bg-restore that modifies streak_freezes_available triggers '
              'a rebuild of the streak badge denominator.',
        );
      },
    );
  });
}
