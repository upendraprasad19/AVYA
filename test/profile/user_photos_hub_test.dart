// Profile "Photos" hub: one row on the Profile tab opens UserPhotosScreen,
// which routes to Progress (PRO-gated) and Saved (coach-media). The hub only
// routes; the PRO check is the Progress row's own `gateAndVerify` call, and the
// Progress screen does not check the subscription itself.
//
// WHAT IS BEHAVIORAL HERE and what is only a source pin:
//   behavioral — the hub shows exactly two rows; the Progress subtitle keeps the
//     PRO hint for a free user, drops it for a PRO user and drops it when a free
//     user upgrades with the hub open (provider override); the back stack
//     Profile -> hub -> destination unwinds one step at a time through the REAL
//     AppBar back button AND the system back path, inside a StatefulShellRoute
//     branch with the same /profile sub-route nesting the production table uses,
//     and the shell chrome (the bottom navigation's place) stays on screen for
//     the hub and for a pushed destination.
//   source pin (presence only, on COMMENT-STRIPPED source: a commented-out line
//     is not live code) — the Progress tap is built as gate -> feature constant
//     -> onPro (one push) -> onFree (one paywall); the Progress screen is named
//     exactly once in the hub (under any spelling: path, route name, class,
//     file); each gate callback OPENS with the mounted check (position, not a
//     count); and no file under lib/ except the router, the hub and the screen
//     itself names the Progress screen, so a new way in has to be added to the
//     allow-list here, next to the question of whether it is gated.
//   where the rest lives — the production route table (`/profile/photos` and
//     both destinations resolve under /profile inside the shell, to the right
//     screens): `test/router/photos_hub_route_resolution_test.dart`. The gate's
//     RUN-time behavior against the real SubscriptionService (a FREE user gets
//     the paywall, a PRO user reaches the screen, a sweep over every tappable
//     widget never builds Progress for a FREE user, leaving the hub inside the
//     server verify): `user_photos_gate_behavioral_test.dart`, which needs a
//     Hive harness this file deliberately does not carry.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/screens/user_photos_screen.dart';
import 'package:icanbefitter/features/profile/widgets/profile_row.dart';

import '../helpers/read_screen_source.dart';

class _Sub extends SubscriptionInfoNotifier {
  _Sub(this.pro);
  final bool pro;
  @override
  SubscriptionInfoData build() => SubscriptionInfoData(isPro: pro);

  /// What a completed purchase does to the provider the hub watches.
  void upgrade() => state = SubscriptionInfoData(isPro: true);
}

const _proHint = 'PRO — visual progress timeline';
const _proSubtitle = 'Track your transformation visually';
const _savedSubtitle = 'Photos you saved from AI Coach chat';
const _eyebrow = 'DOSSIER · ARCHIVE';
const _shellNav = Key('shell-nav');

/// The hub on its own (no router): enough for what it renders. [capture]
/// hands back the notifier so a test can change the subscription mid-screen.
Widget _hubOnly({required bool isPro, void Function(_Sub sub)? capture}) =>
    ProviderScope(
      overrides: [
        subscriptionInfoProvider.overrideWith(() {
          final sub = _Sub(isPro);
          capture?.call(sub);
          return sub;
        }),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/profile/photos',
          routes: [
            GoRoute(
              path: '/profile/photos',
              builder: (_, _) => const UserPhotosScreen(),
            ),
          ],
        ),
      ),
    );

/// The production nesting: a StatefulShellRoute branch whose `/profile` route
/// has `photos`, `progress-photos` and `saved-coach-photos` as sub-routes
/// (`lib/core/router/app_router.dart`). The shell builder wraps the branch in a
/// Scaffold with a keyed bottom bar, as `_MainShell` wraps it in its
/// NavigationBar, so "the bottom navigation stays" is asserted rather than
/// assumed. The destination stand-ins carry an AppBar, as the real screens do,
/// so the automatic back arrow exists exactly when the navigator can pop.
Widget _shellApp(List<String> visited) {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => Scaffold(
          body: shell,
          bottomNavigationBar: const SizedBox(key: _shellNav, height: 56),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, _) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => context.go('/profile/photos'),
                      child: const Text('OPEN PHOTOS'),
                    ),
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'photos',
                    builder: (_, _) => const UserPhotosScreen(),
                  ),
                  GoRoute(
                    path: 'progress-photos',
                    builder: (_, _) {
                      visited.add('progress');
                      return Scaffold(
                        appBar: AppBar(title: const Text('PROGRESS SCREEN')),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'saved-coach-photos',
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
          ),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [subscriptionInfoProvider.overrideWith(() => _Sub(false))],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Every spelling under which code can name the Progress screen as a
/// destination: the route path, the route name, the class and its file. The
/// storage bucket `'progress-photos'` and the feature constant are not on this
/// list (they are not navigation).
final _progressDestination = RegExp(
  r'''profile/progress-photos|['"]progressPhotos['"]|ProgressPhotosScreen|progress_photos_screen''',
);

void main() {
  group('the hub itself', () {
    testWidgets('shows exactly two rows: Progress and Saved', (tester) async {
      await tester.pumpWidget(_hubOnly(isPro: true));
      await tester.pump();
      expect(find.byType(ProfileRow), findsNWidgets(2));
      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text(_eyebrow), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget, reason: 'the AppBar title');
    });

    testWidgets('a FREE user still sees the PRO hint on Progress',
        (tester) async {
      await tester.pumpWidget(_hubOnly(isPro: false));
      await tester.pump();
      expect(find.text(_proHint), findsOneWidget,
          reason: 'the old Profile row told free users this is a PRO feature; '
              'moving it behind a hub must not drop that hint');
      expect(find.text(_proSubtitle), findsNothing);
    });

    testWidgets('a PRO user sees the plain Progress subtitle', (tester) async {
      await tester.pumpWidget(_hubOnly(isPro: true));
      await tester.pump();
      expect(find.text(_proSubtitle), findsOneWidget);
      expect(find.text(_proHint), findsNothing);
    });

    testWidgets('the PRO hint goes away when the user upgrades with the hub open',
        (tester) async {
      // The Progress row opens the paywall for a free user; the purchase flips
      // the provider while this screen is still mounted underneath it.
      late _Sub sub;
      await tester.pumpWidget(_hubOnly(isPro: false, capture: (s) => sub = s));
      await tester.pump();
      expect(find.text(_proHint), findsOneWidget);

      sub.upgrade();
      await tester.pump();
      expect(find.text(_proSubtitle), findsOneWidget,
          reason: 'the hub must rebuild from the provider, not read it once');
      expect(find.text(_proHint), findsNothing);
    });

    // One test per tier, NOT a loop inside one test: a second pumpWidget in the
    // same test updates the existing ProviderScope, and an overrideWith that
    // changed between the two pumps is not applied there, so the second
    // iteration would still render FREE and its "PRO" half could never fail.
    // The Progress subtitle is asserted too, which proves the tier of each run.
    for (final pro in [false, true]) {
      testWidgets('Saved keeps its own subtitle for a ${pro ? 'PRO' : 'FREE'} user',
          (tester) async {
        await tester.pumpWidget(_hubOnly(isPro: pro));
        await tester.pump();
        expect(find.text(pro ? _proSubtitle : _proHint), findsOneWidget,
            reason: 'this run really renders the ${pro ? 'PRO' : 'FREE'} tier');
        expect(find.text(_savedSubtitle), findsOneWidget);
      });
    }
  });

  group('the back stack, inside a shell branch like production', () {
    testWidgets('Profile -> hub (go) and the back arrow returns to Profile',
        (tester) async {
      await tester.pumpWidget(_shellApp([]));
      await tester.pumpAndSettle();
      expect(find.text('OPEN PHOTOS'), findsOneWidget);
      expect(find.byKey(_shellNav), findsOneWidget);

      await tester.tap(find.text('OPEN PHOTOS'));
      await tester.pumpAndSettle();
      expect(find.text(_eyebrow), findsOneWidget);
      expect(find.byKey(_shellNav), findsOneWidget,
          reason: 'the hub is inside the shell, so the bottom bar stays');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('OPEN PHOTOS'), findsOneWidget,
          reason: 'one step back from the hub is the Profile screen');
    });

    testWidgets('Saved is pushed: the shell stays and back returns to the HUB',
        (tester) async {
      final visited = <String>[];
      await tester.pumpWidget(_shellApp(visited));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OPEN PHOTOS'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      expect(find.text('SAVED SCREEN'), findsOneWidget);
      expect(visited, contains('saved'));
      expect(visited, isNot(contains('progress')));
      expect(find.byKey(_shellNav), findsOneWidget,
          reason: 'a pushed /profile sub-route stays inside the shell branch');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(_eyebrow), findsOneWidget,
          reason: 'go() would have replaced the stack and dropped the hub');
      expect(find.text('OPEN PHOTOS'), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('OPEN PHOTOS'), findsOneWidget);
    });

    testWidgets('the SYSTEM back path unwinds destination -> hub -> Profile',
        (tester) async {
      await tester.pumpWidget(_shellApp([]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OPEN PHOTOS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      expect(find.text('SAVED SCREEN'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(_eyebrow), findsOneWidget,
          reason: 'Android back / browser back from a destination lands on the hub');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('OPEN PHOTOS'), findsOneWidget,
          reason: 'and one more lands on Profile, not on a blank shell');
    });
  });

  group('source pins (presence only; the behavior above is the proof)', () {
    late String hub;
    setUpAll(() {
      hub = readSourceFileStripped(
          'lib/features/profile/screens/user_photos_screen.dart');
    });

    test('Progress is built as gate -> feature -> onPro (one push) -> onFree '
        '(one paywall)', () {
      final gate = hub.indexOf('gateAndVerify(');
      final feature = hub.indexOf('AppConstants.featureProgressPhotos');
      final onPro = hub.indexOf('onPro:');
      final push = hub.indexOf("context.push('/profile/progress-photos')");
      final onFree = hub.indexOf('onFree:');
      final paywall =
          hub.indexOf("showPaywallSheet(context, feature: 'Progress Photos')");
      expect(gate, greaterThan(-1));
      expect(feature, greaterThan(gate));
      expect(onPro, greaterThan(feature));
      expect(push, greaterThan(onPro), reason: 'navigation only inside onPro');
      expect(onFree, greaterThan(push));
      expect(paywall, greaterThan(onFree), reason: 'free users get the paywall');

      // First-occurrence indexes cannot see a SECOND, ungated navigation, so
      // count them: one gate call, one paywall, and ONE mention of the Progress
      // screen under any spelling (a `pushNamed('progressPhotos')`, a
      // `MaterialPageRoute(... ProgressPhotosScreen ...)` or a second path
      // string all add a match).
      expect('gateAndVerify('.allMatches(hub).length, 1);
      expect('showPaywallSheet('.allMatches(hub).length, 1);
      expect(_progressDestination.allMatches(hub).length, 1,
          reason: 'a second way into the Progress screen beside the gate would '
              'bypass it (the screen does not check the subscription itself)');
      expect("context.push('/profile/progress-photos')".allMatches(hub).length, 1);
      expect(
          RegExp(r'gateAndVerify\(\s*AppConstants\.featureProgressPhotos,')
              .hasMatch(hub),
          isTrue,
          reason: 'the constant is what puts the feature on the server-verified '
              '(high-value) list in SubscriptionService');
    });

    test('each gate callback OPENS with the mounted check', () {
      // gateAndVerify awaits a server verify (up to 10 s) before it calls the
      // callbacks for a locally-PRO user; the user can leave the hub in that
      // window. A count of `if (!context.mounted) return;` cannot tell a guard
      // that opens the callback from one placed after the push, or moved onto
      // a different row, so the check is anchored to the callback it protects.
      // (onPro is also proven at runtime in the gate test; onFree only runs
      // late when the SERVER disagrees with the local PRO flag, which no unit
      // test can produce, so for onFree this is the whole proof.)
      for (final cb in ['onPro', 'onFree']) {
        expect(
            RegExp('$cb:\\s*\\(\\)\\s*\\{\\s*'
                    r'if\s*\(\s*!context\.mounted\s*\)\s*return;')
                .hasMatch(hub),
            isTrue,
            reason: '$cb must start with `if (!context.mounted) return;`');
      }
    });

    test('both destinations are pushed, never go()', () {
      expect(hub.contains("context.push('/profile/saved-coach-photos')"), isTrue);
      expect(hub.contains("context.go('/profile/progress-photos')"), isFalse,
          reason: 'go() would drop the hub from the back stack');
      expect(hub.contains("context.go('/profile/saved-coach-photos')"), isFalse);
    });
  });

  group('who may name the Progress screen (source scan of lib/)', () {
    test('only the router, the hub and the screen itself do', () {
      // The Progress screen has no PRO check of its own; the hub row is the
      // only gate on the way in (founder decision pending: ledger row R1-04).
      // So a new entry point anywhere in lib/ (a Home shortcut, a notification
      // route, a deep link) must be added HERE on purpose, and be gated.
      final hits = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        // Cheap raw check first; strip comments only for the few that match.
        if (!_progressDestination.hasMatch(f.readAsStringSync())) continue;
        if (_progressDestination.hasMatch(readSourceFileStripped(f.path))) {
          hits.add(f.path.replaceAll(r'\', '/'));
        }
      }
      hits.sort();
      expect(hits, [
        'lib/core/router/app_router.dart',
        'lib/features/profile/screens/progress_photos_screen.dart',
        'lib/features/profile/screens/user_photos_screen.dart',
      ]);
    });
  });
}
