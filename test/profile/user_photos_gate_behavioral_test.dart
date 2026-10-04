// Behavioral proof of the Progress gate on the Photos hub, against the REAL
// SubscriptionService.
//
// The Progress row moved from the Profile tab into UserPhotosScreen; its PRO gate
// (root CLAUDE.md §4.4 rules 5 + 19) must have survived the move:
//   FREE — the row opens the paywall for 'Progress Photos' and never the
//          Progress screen.
//   PRO  — the row opens the Progress screen (pushed, so back returns to the hub)
//          and no paywall.
// Both runs go through `SubscriptionService.instance.gateAndVerify` unchanged.
// It needs no network: Supabase is not initialized in a test, so for the
// high-value feature `verifyFromServer()` answers from local state
// (`subscription_service.dart`, "supabase not ready" branch) — the same local
// path `test/contracts/subscription_cqrs_behavioral_test.dart` drives.
//
// What it pins beyond the two outcomes: the feature (the gate's telemetry message
// names it, `feature=progress_photos`, so any other constant turns both cases
// red) and, for PRO, WHICH branch ran — `reason=verify_pro` is the server-verified
// (high-value) branch, so dropping `featureProgressPhotos` from
// `SubscriptionService._highValueFeatures` (root CLAUDE.md §4.4 rule 19) turns
// the PRO case red (the gate would take the `local_pro` branch instead).
//
// Two more cases exist because the Progress SCREEN has no PRO check of its own
// (the hub row is the only gate on the way in):
//   * a FREE sweep taps EVERY tappable widget on the hub, each on a fresh app,
//     and asserts the Progress screen is never built — so a second, ungated way
//     in (a shortcut button, a push by route name) turns it red;
//   * leaving the hub while a PRO user's server verify is pending must drop the
//     push quietly (the `if (!context.mounted) return;` in `onPro`). The test
//     calls the row's handler and unmounts the hub in the same synchronous
//     stretch, because `pump` flushes pending microtasks BEFORE it builds a
//     frame, which would let the gate's callback run first.
//
// What it does NOT prove (by design, stated): the server round-trip itself —
// Supabase is not initialized here, so `verifyFromServer()` answers from local
// state — and the `onFree` mounted guard: a locally-free user gets `onFree`
// synchronously inside the tap, and it runs after the await only when the SERVER
// disagrees with the local PRO flag, which no unit test can produce. For
// `onFree` the source pin in `user_photos_hub_test.dart` is the whole proof.
//
// HARNESS (precedent: test/widgets/swap_picker_sheet_test.dart, which also pumps
// the real PaywallSheet):
//   * the FIRST test is a typography warmup, run BEFORE setUpHiveForTests installs
//     its path_provider mock — GoogleFonts caches per family+weight and a mocked
//     path_provider makes it fail LOUDLY instead of degrading (root CLAUDE.md
//     §4.9);
//   * Hive's real disk I/O is escaped with tester.runAsync (§4.9: an awaited disk
//     write inside a testWidgets body hangs);
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

    testWidgets('FREE: Progress opens the paywall and never the screen',
        (tester) async {
      await tester.runAsync(() => MigratedKey.write('isPro', false));
      await tester.pumpWidget(_app(visited, displayPro: false));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();

      expect(find.text(paywallLetterheadTitle('Progress Photos')),
          findsOneWidget,
          reason: 'a free user is shown the Progress Photos paywall');
      expect(find.text('PROGRESS SCREEN'), findsNothing);
      expect(visited, isEmpty,
          reason: 'the Progress route must never be built for a free user');
      expect(routed(), hasLength(1));
      expect(routed().single, contains('feature=progress_photos'));
      expect(routed().single, contains('exit=onFree'));
      expect(routed().single, contains('reason=not_pro_local'));
      expect(nonFatals, isEmpty,
          reason: 'neither gate callback may throw (a dead context, a missing '
              'route): _runCallback would only report it as '
              'subscription_gate_callback_threw');
    });

    testWidgets('FREE: no tappable widget on the hub builds the Progress screen',
        (tester) async {
      await tester.runAsync(() => MigratedKey.write('isPro', false));
      await tester.pumpWidget(_app(visited, displayPro: false));
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
        await tester.pumpWidget(_app(visited, displayPro: false));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(GestureDetector).at(i),
            warnIfMissed: false);
        await tester.pumpAndSettle();
      }

      expect(visited, isNot(contains('progress')),
          reason: 'the Progress screen has no PRO check of its own, so a FREE '
              'user must not be able to reach it from ANY widget on the hub');
      expect(visited, contains('saved'),
          reason: 'the sweep did tap the ungated Saved row, so it taps real '
              'rows (a sweep that taps nothing would pass vacuously)');
      expect(nonFatals, isEmpty);
    });

    testWidgets('PRO: Progress opens the screen, pushed, and no paywall',
        (tester) async {
      await makePro(tester);
      await tester.pumpWidget(_app(visited, displayPro: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();

      expect(find.text('PROGRESS SCREEN'), findsOneWidget);
      expect(find.text(paywallLetterheadTitle('Progress Photos')), findsNothing);
      expect(visited, ['progress']);
      expect(routed(), hasLength(1));
      expect(routed().single, contains('feature=progress_photos'));
      expect(routed().single, contains('exit=onPro'));
      expect(routed().single, contains('reason=verify_pro'),
          reason: 'the server-verified branch: progress_photos must stay on '
              "SubscriptionService's high-value list");
      expect(nonFatals, isEmpty);

      // Pushed, so one step back is the hub again (not Profile).
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(_eyebrow), findsOneWidget);
      expect(find.text('PROFILE'), findsNothing);
    });

    testWidgets('PRO: leaving the hub inside the server verify drops the push '
        'without an error', (tester) async {
      await makePro(tester);
      final mounted = ValueNotifier<bool>(true);
      addTearDown(mounted.dispose);
      await tester.pumpWidget(_app(visited, displayPro: true, mounted: mounted));
      await tester.pumpAndSettle();

      // The row's handler, called directly: it starts the gate, which suspends
      // at `await verifyFromServer()`. Nothing is awaited from here to the
      // unmount below, so no microtask (the gate's continuation) can run yet.
      final row = tester.widget<ProfileRow>(find.ancestor(
          of: find.text('Progress'), matching: find.byType(ProfileRow)));
      row.onTap!();

      // Drop the hub from the tree and FINALIZE it (context.mounted turns
      // false) without a pump, which would flush the pending microtasks first.
      mounted.value = false;
      tester.binding.buildOwner!
        ..buildScope(tester.binding.rootElement!)
        ..finalizeTree();

      // Now the verify "answers" and the gate calls onPro on a dead context.
      await tester.pump();

      expect(routed(), hasLength(1));
      expect(routed().single, contains('exit=onPro'));
      expect(visited, isEmpty,
          reason: 'the guard must stop the push: the hub is gone');
      expect(nonFatals, isEmpty,
          reason: 'without the guard `context.push` throws on the dead context '
              'and the gate reports subscription_gate_callback_threw');
    });
  });
}
