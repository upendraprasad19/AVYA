// Behavioral proof that the Photos hub makes NO PRO decision about Progress, against
// the REAL SubscriptionService (OI-314, founder decision 6 of 2026-10-06).
//
// History: the Progress row moved from the Profile tab into UserPhotosScreen with
// its PRO gate (root CLAUDE.md section 4.4 rules 5 + 19) and showed a FREE user the
// paywall without opening the screen. That also locked a LAPSED user out of the
// photos they already held. Since OI-314 the hub row pushes the Progress screen
// for everyone and the SCREEN decides (progress_photos_screen_gate_test.dart and
// progress_photos_lapsed_flow_test.dart: PRO gallery + Add; lapsed gallery +
// delete, Add leads to the paywall; nobody-has-photos locked card).
//   FREE and PRO alike - tapping Progress pushes the screen (so back returns to the
//          hub), opens no paywall, and runs NO gate: zero `subscription_gate_routed`
//          events from the hub.
//   A sweep taps EVERY tappable widget on the hub, each on a fresh app, and asserts
//          the only routes reached are Progress (once per tap of that row) and
//          Saved, and that no tap opens the paywall: a stray paywall or a second
//          way in would turn it red.
// It needs no network: Supabase is not initialized in a test.
//
// HARNESS (precedent: test/widgets/swap_picker_sheet_test.dart, which also pumps
// the real PaywallSheet):
//   * the FIRST test is a typography warmup, run BEFORE setUpHiveForTests installs
//     its path_provider mock - GoogleFonts caches per family+weight and a mocked
//     path_provider makes it fail LOUDLY instead of degrading (root CLAUDE.md
//     section 4.9);
//   * Hive's real disk I/O is escaped with tester.runAsync (section 4.9: an awaited
//     disk write inside a testWidgets body hangs);
//   * @Timeout + library bound a regression of either to a failure, not a stall.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/screens/user_photos_screen.dart';
import 'package:icanbefitter/features/profile/widgets/profile_row.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

import '../helpers/hive_test_setup.dart';

class _Sub extends SubscriptionInfoNotifier {
  _Sub(this.pro);
  final bool pro;
  @override
  SubscriptionInfoData build() => SubscriptionInfoData(isPro: pro);
}

const _eyebrow = 'DOSSIER · ARCHIVE';

/// `/profile` -> `photos` (the hub) -> `progress-photos` / `saved-coach-photos`
/// (stand-ins that record the visit), with the production nesting AND the
/// production route names, so back from a destination returns to the hub and a
/// push by name reaches a stand-in too. [mounted], when given, lets a test drop
/// the whole app from the tree while the ProviderScope stays.
Widget _app(
  List<String> visited, {
  required bool displayPro,
  ValueNotifier<bool>? mounted,
}) {
  final router = GoRouter(
    initialLocation: '/profile/photos',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, _) => const Scaffold(body: Text('PROFILE')),
        routes: [
          GoRoute(
            path: 'photos',
            name: 'userPhotos',
            builder: (_, _) => const UserPhotosScreen(),
          ),
          GoRoute(
            path: 'progress-photos',
            name: 'progressPhotos',
            builder: (_, _) {
              visited.add('progress');
              return Scaffold(
                appBar: AppBar(title: const Text('PROGRESS SCREEN')),
              );
            },
          ),
          GoRoute(
            path: 'saved-coach-photos',
            name: 'savedCoachPhotos',
            builder: (_, _) {
              visited.add('saved');
              return Scaffold(
                appBar: AppBar(title: const Text('SAVED SCREEN')),
              );
            },
          ),
        ],
      ),
    ],
  );
  final app = MaterialApp.router(routerConfig: router);
  return ProviderScope(
    overrides: [subscriptionInfoProvider.overrideWith(() => _Sub(displayPro))],
    child: mounted == null
        ? app
        : ValueListenableBuilder<bool>(
            valueListenable: mounted,
            builder: (_, on, _) => on ? app : const SizedBox.shrink(),
          ),
  );
}

void main() {
  testWidgets('typography warmup — GoogleFonts caches before any Hive mock',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [subscriptionInfoProvider.overrideWith(() => _Sub(false))],
      child: MaterialApp(
        home: Scaffold(
          body: Column(children: [
            const Expanded(child: UserPhotosScreen()),
            Text('a', style: AppTypography.h3),
            Text('b', style: AppTypography.bodySm),
            Text('c', style: AppTypography.monoXs),
            Text('d', style: AppTypography.body),
            // Fraunces w500 — the PaywallSheet h1 letterhead.
            Text('e', style: AppTypography.h1),
            const WardButton(label: 'x', onPressed: null),
          ]),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('Progress gate on the Photos hub (real SubscriptionService)', () {
    late Directory dir;
    late List<String> visited;
    late List<String> events;
    late List<String> nonFatals;

    setUp(() async {
      visited = [];
      events = [];
      nonFatals = [];
      // Hooks FIRST: opening the Hive user session notifies the process-wide
      // singleton registry, and once `SubscriptionService.instance` exists (from
      // the previous test) that runs its entitlement check and logs a
      // `migrated_key_read_user_box` non-fatal — which must land in the hook, not
      // in the real telemetry path. Then forget what setup itself reported.
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {message}) => events.add('$op ${message ?? ''}');
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required reason, extra}) => nonFatals.add(reason);
      dir = await setUpHiveForTests();
      events.clear();
      nonFatals.clear();
    });

    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
      await tearDownHiveForTests(dir);
    });

    List<String> routed() =>
        events.where((e) => e.startsWith('subscription_gate_routed')).toList();

    Future<void> makePro(WidgetTester tester) => tester.runAsync(() async {
          await MigratedKey.write('isPro', true);
          await MigratedKey.write(
              'expiresAt',
              DateTime.now().add(const Duration(days: 30)).toIso8601String());
        });

    testWidgets('FREE: Progress pushes the screen, with no paywall and no gate',
        (tester) async {
      await tester.runAsync(() => MigratedKey.write('isPro', false));
      await tester.pumpWidget(_app(visited, displayPro: false));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();

      expect(find.text('PROGRESS SCREEN'), findsOneWidget,
          reason: 'the screen decides what a user who is not PRO sees (a lapsed '
              'user must reach their photos)');
      expect(find.text(paywallLetterheadTitle('Progress Photos')), findsNothing,
          reason: 'the hub no longer shows the paywall');
      expect(visited, ['progress']);
      expect(routed(), isEmpty,
          reason: 'the hub runs no PRO gate: the decision belongs to the screen');
      expect(nonFatals, isEmpty);
    });

    testWidgets('PRO: Progress pushes the screen, and back returns to the hub',
        (tester) async {
      await makePro(tester);
      await tester.pumpWidget(_app(visited, displayPro: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();

      expect(find.text('PROGRESS SCREEN'), findsOneWidget);
      expect(find.text(paywallLetterheadTitle('Progress Photos')), findsNothing);
      expect(visited, ['progress']);
      expect(routed(), isEmpty);
      expect(nonFatals, isEmpty);

      // Pushed, so one step back is the hub again (not Profile).
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(_eyebrow), findsOneWidget);
      expect(find.text('PROFILE'), findsNothing);
    });

    for (final pro in [false, true]) {
      testWidgets(
          '${pro ? 'PRO' : 'FREE'}: no tappable widget on the hub opens the '
          'paywall or runs a gate', (tester) async {
        await tester.runAsync(() => MigratedKey.write('isPro', pro));
        await tester.pumpWidget(_app(visited, displayPro: pro));
        await tester.pumpAndSettle();

        // Every GestureDetector: InkWell / InkResponse / IconButton / TextButton /
        // ListTile all build one, so this covers the rows AND anything someone
        // adds beside them (a shortcut icon, a capture pill).
        final count = find.byType(GestureDetector).evaluate().length;
        expect(count, greaterThanOrEqualTo(2),
            reason: 'at least the Progress and Saved rows');

        for (var i = 0; i < count; i++) {
          // A fresh app per target: a tap can push a screen or open the paywall.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(_app(visited, displayPro: pro));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(GestureDetector).at(i),
              warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(find.text(paywallLetterheadTitle('Progress Photos')),
              findsNothing,
              reason: 'tappable #$i opened the paywall from the hub');
        }

        expect(visited.toSet(), {'progress', 'saved'},
            reason: 'the sweep reached both destinations (a sweep that taps '
                'nothing would pass vacuously) and nothing else');
        expect(routed(), isEmpty, reason: 'the hub runs no PRO gate');
        expect(nonFatals, isEmpty);
      });
    }
  });
}
