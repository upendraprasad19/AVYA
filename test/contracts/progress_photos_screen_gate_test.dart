// Proof that the Progress Photos screen enforces PRO ITSELF (ledger row R1-04 of
// the Photos-hub batch; founder decision 2026-10-05), against the REAL
// SubscriptionService and the REAL screen pumped directly: no router, no hub
// (one test goes through the hub on purpose, to prove the two locks compose).
// That is the point: before this change the hub row was the only PRO check, so
// the web address `#/profile/progress-photos` (a door that never touches the hub)
// reached a working screen. It works only in an app that is already open: a fresh
// load goes through `/restoring` and lands on Home (app_router.dart, restoring
// _screen.dart). Pumping the screen alone IS that door.
//
//   FREE — the locked card with its label, already on the very first frame (no
//          spinner flash); no photo read (`ProgressPhotoRepository
//          .debugOnListForTests` counts `list()` calls: zero); no "Add photo"
//          button; Upgrade opens the paywall, by tap and by keyboard (Tab
//          reaches it); tapping EVERY tappable widget on the locked screen, one
//          at a time, reads no photo and opens no Camera / Gallery / angle sheet;
//          the card is announced as a button, centred while it fits, with a pill
//          that hugs its label, and fits a short window and a large text scale.
//   FREE, then the user upgrades (a purchase from the card) — the gate re-runs and
//          the card gives way to the gallery; an unrelated provider refresh does
//          not re-run it; neither does a subscription write that lands while the
//          entry gate is still pending (only a LOCKED screen re-gates).
//   PRO  — the first frame is the spinner (no card, no button); then the gallery
//          state and the button, through the server-verified branch
//          (`reason=verify_pro`), so dropping `featureProgressPhotos` from
//          `SubscriptionService._highValueFeatures` (rule 19) turns it red; one
//          photo read.
//   A subscription that lapses while the screen stays open — the write action
//          runs the gate again: paywall, never the Camera/Gallery sheet.
//   Two quick taps on "Add photo" open ONE sheet; the button works again after.
//   Leaving the screen inside the entry verify, or inside the Add button's
//          verify — the `if (!mounted) return;` guards drop the callback quietly.
//   Through the hub — a PRO user passes both locks and ends on the gallery.
// It needs no network: Supabase is not initialized in a test, so for the
// high-value feature `verifyFromServer()` answers from local state, and
// `ProgressPhotoRepository.list()` answers `[]` (no user).
//
// What it does NOT prove, stated: the server round trip itself (so a slow verify
// is simulated by calling the Add handler twice in ONE synchronous stretch, which
// leaves the first gate pending exactly as a stale cache plus a slow network
// does); and the `onFree` mounted guards: a locally-free user gets `onFree`
// synchronously, and it runs after the await only when the SERVER disagrees with
// the local PRO flag, which no unit test can produce — for those the source pins
// below are the whole proof. Also not proven here: the WEB keyboard map (a VM
// test runs the non-web shortcut map, Enter -> ActivateIntent; the web map, Enter
// -> ButtonActivateIntent, is handled by InkWell too, read from the Flutter
// source, not run); the desktop-platform case proves "no exception" only; and of
// the five window / text-scale cases only the two 320x240 ones overflow when the
// card does not scroll (the other three pin that ordinary sizes keep working).
//
// HARNESS (same as test/profile/user_photos_gate_behavioral_test.dart): the FIRST
// test is a typography warmup, run BEFORE setUpHiveForTests installs its
// path_provider mock (a mocked path_provider makes GoogleFonts fail loudly;
// root CLAUDE.md §4.9); Hive's disk I/O is escaped with tester.runAsync; @Timeout +
// library bound a regression to a failure, not a stall.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/repositories/progress_photo_repository.dart';
import 'package:icanbefitter/features/profile/screens/progress_photos_screen.dart';
import 'package:icanbefitter/features/profile/screens/user_photos_screen.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/pro_locked_overlay.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/read_screen_source.dart';

class _Sub extends SubscriptionInfoNotifier {
  _Sub(this.pro);
  final bool pro;
  @override
  SubscriptionInfoData build() => SubscriptionInfoData(isPro: pro);

  /// What the provider does when the subscription state changes: a completed
  /// purchase (`true`) or a refresh that changes nothing (the current value).
  void set(bool value) => state = SubscriptionInfoData(isPro: value);
}

/// The screen alone, as the typed web address builds it. [mounted], when given,
/// lets a test drop the whole app from the tree while the ProviderScope stays;
/// [capture] hands back the notifier so a test can change the subscription.
Widget _app({
  ValueNotifier<bool>? mounted,
  void Function(_Sub sub)? capture,
}) {
  const app = MaterialApp(home: ProgressPhotosScreen());
  return ProviderScope(
    overrides: [
      subscriptionInfoProvider.overrideWith(() {
        final sub = _Sub(false);
        capture?.call(sub);
        return sub;
      }),
    ],
    child: mounted == null
        ? app
        : ValueListenableBuilder<bool>(
            valueListenable: mounted,
            builder: (_, on, _) => on ? app : const SizedBox.shrink(),
          ),
  );
}

/// The hub, then the REAL Progress screen behind it, with the production route
/// names and nesting (`/profile` -> `photos` -> `progress-photos`).
Widget _throughTheHub() {
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
            builder: (_, _) => const ProgressPhotosScreen(),
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

/// Builds the first frame BY HAND. `pumpWidget` flushes microtasks after the
/// frame, which would let a pending gate answer before a test can look at (or
/// remove) the screen. The gate starts in `initState` during the build inside
/// `handleDrawFrame`; for a locally-PRO user it suspends at
/// `await verifyFromServer()`, for a locally-free user `onFree` has already run.
void _firstFrame(WidgetTester tester, Widget app) {
  tester.binding
      .attachRootWidget(tester.binding.wrapWithDefaultView(app));
  tester.binding.scheduleFrame();
  tester.binding.handleBeginFrame(Duration.zero);
  tester.binding.handleDrawFrame();
}

/// Drops the app (see [_app]'s `mounted`) and FINALIZES the tree (`mounted` turns
/// false) without a pump, which would flush the pending microtasks first.
void _removeScreenWithoutPumping(
    WidgetTester tester, ValueNotifier<bool> mounted) {
  mounted.value = false;
  tester.binding.buildOwner!
    ..buildScope(tester.binding.rootElement!)
    ..finalizeTree();
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
            Expanded(
              child: ProLockedOverlay(
                featureLabel: 'Progress Photos',
                description: 'x',
                onUpgradeTap: () {},
                child: const SizedBox.shrink(),
              ),
            ),
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

  group('Progress screen gate (real SubscriptionService, screen pumped alone)',
      () {
    late Directory dir;
    late List<String> events;
    late List<String> nonFatals;
    late int listCalls;
    late int captureCalls;

    setUp(() async {
      events = [];
      nonFatals = [];
      listCalls = 0;
      captureCalls = 0;
      // Hooks FIRST (see user_photos_gate_behavioral_test.dart): opening the Hive
      // user session notifies the singleton registry, and a stray non-fatal must
      // land in the hook, not in the real telemetry path.
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {message}) => events.add('$op ${message ?? ''}');
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required reason, extra}) => nonFatals.add(reason);
      ProgressPhotoRepository.debugOnListForTests = () => listCalls++;
      ProgressPhotoRepository.debugCaptureOverride = (_, _) async {
        captureCalls++;
        return null;
      };
      dir = await setUpHiveForTests();
      events.clear();
      nonFatals.clear();
    });

    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
      ProgressPhotoRepository.debugOnListForTests = null;
      ProgressPhotoRepository.debugCaptureOverride = null;
      await tearDownHiveForTests(dir);
    });

    List<String> routed() =>
        events.where((e) => e.startsWith('subscription_gate_routed')).toList();

    /// Counts what the subscription provider tells its listeners. The "a refresh
    /// that changes nothing" assertions below mean something only if that refresh
    /// DID notify: `SubscriptionInfoData` has no `==`, so every write does. If it
    /// ever gets one, those writes go quiet, the screen's listener never runs, and
    /// the assertions would pass for ANY listener; this probe turns that into a
    /// failure here instead. Call it after the first frame (the scope must exist).
    int Function() countNotifications(WidgetTester tester) {
      var n = 0;
      final container = ProviderScope.containerOf(
          tester.element(find.byType(ProgressPhotosScreen)));
      final sub = container.listen(subscriptionInfoProvider, (_, _) => n++);
      addTearDown(sub.close);
      return () => n;
    }

    Future<void> makePro(WidgetTester tester) => tester.runAsync(() async {
          await MigratedKey.write('isPro', true);
          await MigratedKey.write(
              'expiresAt',
              DateTime.now().add(const Duration(days: 30)).toIso8601String());
        });

    Future<void> makeFree(WidgetTester tester) =>
        tester.runAsync(() => MigratedKey.write('isPro', false));

    VoidCallback addPhotoHandler(WidgetTester tester) => tester
        .widget<FloatingActionButton>(find.byType(FloatingActionButton))
        .onPressed!;

    // ── FREE ──────────────────────────────────────────────────────────────

    testWidgets('FREE: the locked card with its label, no photo read, no Add '
        'button', (tester) async {
      await makeFree(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.byType(ProLockedOverlay), findsOneWidget);
      expect(find.text('PRO FEATURE'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(ProLockedOverlay),
              matching: find.text('Progress Photos')),
          findsOneWidget,
          reason: 'the card names the feature');
      expect(find.text('Track your transformation visually'), findsOneWidget);
      expect(find.text('Upgrade to PRO'), findsOneWidget);
      expect(find.text('Add photo'), findsNothing,
          reason: 'a free user must not be offered a Storage write');
      expect(listCalls, 1,
          reason: 'one read of the user\'s OWN photos, to tell a never-PRO user '
              'from a lapsed one (OI-314); it found none, hence the locked card');
      expect(captureCalls, 0,
          reason: 'a free user must trigger no Storage write');

      expect(routed(), hasLength(1));
      expect(routed().single, contains('feature=progress_photos'));
      expect(routed().single, contains('exit=onFree'));
      expect(routed().single, contains('reason=not_pro_local'));
      expect(nonFatals, isEmpty);
    });

    testWidgets('FREE: the first frame is the spinner (the screen cannot yet '
        'tell never-PRO from lapsed), then the locked card', (tester) async {
      await makeFree(tester);
      _firstFrame(tester, _app());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ProLockedOverlay), findsNothing,
          reason: 'a lapsed user\'s photos must not be hidden behind the card '
              'before the read answers');
      expect(find.text('Add photo'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byType(ProLockedOverlay), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(listCalls, 1);
      expect(captureCalls, 0);
    });

    testWidgets('FREE: the card\'s Upgrade button opens the paywall',
        (tester) async {
      await makeFree(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Upgrade to PRO'));
      await tester.pumpAndSettle();

      expect(find.text(paywallLetterheadTitle('Progress Photos')),
          findsOneWidget);
      expect(nonFatals, isEmpty);
    });

    testWidgets('FREE: the Upgrade button is a real button: 44 dp tall and '
        'operable from the keyboard (web)', (tester) async {
      await makeFree(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      final target = find.ancestor(
          of: find.text('Upgrade to PRO'), matching: find.byType(InkWell));
      expect(target, findsOneWidget);
      expect(tester.getSize(target).height, greaterThanOrEqualTo(44));

      // Tab until the Upgrade button holds the focus (a few stops at most: nothing
      // else on this screen takes focus today, but a future AppBar action would),
      // then Enter. A bare GestureDetector never takes focus, so it fails here.
      // The focus must sit INSIDE the button's InkWell: the route's own focus
      // scope also contains the button's text, so "contains the text" would be
      // true before any Tab.
      bool upgradeHasFocus() {
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused == null) return false;
        return find
            .descendant(
                of: find.ancestor(
                    of: find.text('Upgrade to PRO'),
                    matching: find.byType(InkWell)),
                matching: find.byElementPredicate((e) => e == focused))
            .evaluate()
            .isNotEmpty;
      }

      for (var i = 0; i < 6 && !upgradeHasFocus(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(upgradeHasFocus(), isTrue,
          reason: 'the Upgrade button must be reachable with Tab');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text(paywallLetterheadTitle('Progress Photos')),
          findsOneWidget,
          reason: 'Tab then Enter must activate the Upgrade button');
    });

    testWidgets('FREE: no tappable widget on the locked screen reads photos or '
        'opens a picker', (tester) async {
      await makeFree(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      // Every GestureDetector: InkWell / InkResponse / IconButton / TextButton /
      // ListTile / FloatingActionButton all build one, so this covers the card's
      // Upgrade button AND anything someone adds beside it (an AppBar action, a
      // refresh icon, a retry button). The source pins below count references;
      // this is the behaviour.
      final count = find.byType(GestureDetector).evaluate().length;
      expect(count, greaterThanOrEqualTo(1),
          reason: 'at least the Upgrade button');

      var paywalls = 0;
      for (var i = 0; i < count; i++) {
        // A fresh app per target: a tap can open the paywall or a sheet.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(_app());
        await tester.pumpAndSettle();
        await tester.tap(find.byType(GestureDetector).at(i),
            warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.text('Camera'), findsNothing,
            reason: 'tappable #$i opened the picker for a free user');
        expect(find.text('Gallery'), findsNothing);
        expect(find.text('Which angle?'), findsNothing);
        if (find
            .text(paywallLetterheadTitle('Progress Photos'))
            .evaluate()
            .isNotEmpty) {
          paywalls++;
        }
      }

      // One entry read per app built: the first one above plus one per target; a
      // tap adds none.
      expect(listCalls, count + 1,
          reason: 'no tap on the locked screen may read photos again');
      expect(captureCalls, 0, reason: 'no tap may reach a Storage write');
      expect(paywalls, greaterThanOrEqualTo(1),
          reason: 'the sweep did tap the Upgrade button (a sweep that taps '
              'nothing would pass vacuously)');
      expect(nonFatals, isEmpty);
    });

    testWidgets('FREE: the Upgrade button is announced as a button',
        (tester) async {
      // Disposed inside the test: the framework verifies it before any tearDown.
      final handle = tester.ensureSemantics();
      try {
        await makeFree(tester);
        await tester.pumpWidget(_app());
        await tester.pumpAndSettle();

        expect(
            tester.getSemantics(find.text('Upgrade to PRO')),
            containsSemantics(
                isButton: true, hasTapAction: true, label: 'Upgrade to PRO'),
            reason: 'a screen reader must hear a button with an action');
      } finally {
        handle.dispose();
      }
    });

    testWidgets('FREE: the card\'s content is centred while it fits',
        (tester) async {
      await makeFree(tester);
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      final card = tester.getRect(find.byType(ProLockedOverlay));
      final lock = tester.getRect(find.byIcon(Icons.lock_rounded));
      final cta = tester.getRect(find.ancestor(
          of: find.text('Upgrade to PRO'), matching: find.byType(InkWell)));
      // The column runs from the lock badge (a 40 dp circle round the 20 dp icon)
      // to the bottom of the button.
      final gapAbove = (lock.center.dy - 20) - card.top;
      final gapBelow = card.bottom - cta.bottom;
      expect(gapAbove, greaterThan(100),
          reason: 'the card is tall here: content hugging its top is not centred');
      expect((gapAbove - gapBelow).abs(), lessThan(2),
          reason: 'equal space above and below the column');
      expect((lock.center.dx - card.center.dx).abs(), lessThan(1));
      expect((cta.center.dx - card.center.dx).abs(), lessThan(1));
    });

    testWidgets('FREE: the Upgrade pill hugs its label (not stretched to the '
        'card\'s width)', (tester) async {
      await makeFree(tester);
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      final pill = tester.getSize(find.ancestor(
          of: find.text('Upgrade to PRO'), matching: find.byType(InkWell)));
      final label = tester.getSize(find.text('Upgrade to PRO'));
      expect(pill.width, closeTo(label.width + 40, 1),
          reason: 'the label plus the two 20 dp paddings; a full-width pill is '
              'a different look');
    });

    // The card must fit wherever the web address can be opened: a short browser
    // window, a landscape phone, a large text scale. One test per case, so a
    // failure names the case. A RenderFlex overflow surfaces as an exception.
    const cases = <(String, Size, double)>[
      ('a desktop window', Size(1200, 800), 1.0),
      ('a phone', Size(360, 640), 1.0),
      ('a short window', Size(320, 240), 1.0),
      ('a phone at 2x text', Size(360, 640), 2.0),
      ('a short window at 2x text', Size(320, 240), 2.0),
    ];
    for (final (name, size, scale) in cases) {
      testWidgets('FREE: the locked card fits $name; the Upgrade button stays '
          'reachable', (tester) async {
        await makeFree(tester);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(_app());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'the card overflowed at ${size.width}x${size.height}, '
                '${scale}x text');

        final cta = find.text('Upgrade to PRO');
        await tester.ensureVisible(cta);
        await tester.pumpAndSettle();
        final rect = tester.getRect(cta);
        final window = Offset.zero & size;
        expect(window.contains(rect.topLeft), isTrue,
            reason: 'the Upgrade button must be on screen once scrolled to');
        expect(window.contains(rect.bottomRight - const Offset(1, 1)), isTrue,
            reason: 'the Upgrade button must be on screen once scrolled to');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('FREE: the card also lays out on a desktop platform (the '
        'scroll view gets a desktop scrollbar there)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await makeFree(tester);
        tester.view.physicalSize = const Size(320, 240);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_app());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Upgrade to PRO'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('FREE then PRO: a purchase from the card re-runs the gate and '
        'the card gives way to the gallery', (tester) async {
      late _Sub sub;
      await makeFree(tester);
      await tester.pumpWidget(_app(capture: (s) => sub = s));
      await tester.pumpAndSettle();
      expect(find.byType(ProLockedOverlay), findsOneWidget);
      final notified = countNotifications(tester);

      // A refresh that changes nothing for a still-free user is not a re-gate.
      sub.set(false);
      await tester.pumpAndSettle();
      expect(notified(), 1,
          reason: 'the refresh must reach the screen\'s listener (no == on '
              'SubscriptionInfoData); if it stops, this test proves nothing');
      expect(find.byType(ProLockedOverlay), findsOneWidget);
      expect(routed(), hasLength(1),
          reason: 'only a user who became PRO gets the gate re-run');

      // A purchase writes the local state first, then flips the provider.
      await makePro(tester);
      sub.set(true);
      await tester.pumpAndSettle();
      expect(notified(), 2);

      expect(find.byType(ProLockedOverlay), findsNothing);
      expect(find.text('No photos yet'), findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
      expect(listCalls, 2,
          reason: 'the free entry\'s read, then the post-upgrade read');
      expect(routed(), hasLength(2));
      expect(routed().last, contains('feature=progress_photos'));
      expect(routed().last, contains('exit=onPro'));
      expect(routed().last, contains('reason=verify_pro'),
          reason: 'the re-run is the server-verified gate, same as on entry');
      expect(nonFatals, isEmpty);
    });

    testWidgets('PRO, lapses, then pays again: the re-check shows the spinner, '
        'not the gallery state of the earlier PRO period', (tester) async {
      late _Sub sub;
      await makePro(tester);
      await tester.pumpWidget(_app(capture: (s) => sub = s));
      await tester.pumpAndSettle();
      expect(find.text('No photos yet'), findsOneWidget);
      expect(listCalls, 1);

      // The subscription ends; the Add button's gate locks the screen.
      await makeFree(tester);
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      expect(find.byType(ProLockedOverlay), findsOneWidget);

      // The user pays again from the card: local state first, then the provider.
      await makePro(tester);
      sub.set(true);
      // A frame BY HAND before any microtask runs: the gate is re-checking.
      tester.binding.scheduleFrame();
      tester.binding.handleBeginFrame(Duration.zero);
      tester.binding.handleDrawFrame();
      expect(find.byType(ProLockedOverlay), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('No photos yet'), findsNothing,
          reason: 'what an earlier PRO period loaded must not show while the '
              'gate re-checks');
      expect(find.text('Add photo'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('No photos yet'), findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
      expect(listCalls, 3,
          reason: 'entry, the refused Add tap\'s reload, then the re-check');
    });

    // ── PRO ───────────────────────────────────────────────────────────────

    testWidgets('PRO: the gallery state and the Add button, server-verified, '
        'one photo read', (tester) async {
      await makePro(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.byType(ProLockedOverlay), findsNothing);
      expect(find.text('No photos yet'), findsOneWidget,
          reason: 'list() answers [] without a user, so a granted screen ends '
              'in the empty state');
      expect(find.text('Add photo'), findsOneWidget);
      expect(listCalls, 1);

      expect(routed(), hasLength(1));
      expect(routed().single, contains('feature=progress_photos'));
      expect(routed().single, contains('exit=onPro'));
      expect(routed().single, contains('reason=verify_pro'),
          reason: 'the server-verified branch: progress_photos must stay on '
              "SubscriptionService's high-value list (rule 19)");
      expect(nonFatals, isEmpty);
    });

    testWidgets('PRO: the very first frame is the spinner: no locked card, no '
        'Add button, no photo read yet', (tester) async {
      await makePro(tester);
      _firstFrame(tester, _app());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ProLockedOverlay), findsNothing,
          reason: 'a PRO user must never be shown the lock while it verifies');
      expect(find.text('Add photo'), findsNothing,
          reason: 'no button until the screen has verified PRO');
      expect(listCalls, 0);

      await tester.pumpAndSettle();
      expect(find.text('Add photo'), findsOneWidget);
      expect(listCalls, 1);
    });

    testWidgets('PRO: a provider refresh does not re-run the gate or re-read '
        'the photos', (tester) async {
      late _Sub sub;
      await makePro(tester);
      await tester.pumpWidget(_app(capture: (s) => sub = s));
      await tester.pumpAndSettle();
      expect(routed(), hasLength(1));
      expect(listCalls, 1);
      final notified = countNotifications(tester);

      sub.set(true);
      await tester.pumpAndSettle();

      expect(notified(), 1,
          reason: 'the refresh must reach the screen\'s listener (no == on '
              'SubscriptionInfoData); if it stops, this test proves nothing');
      expect(routed(), hasLength(1),
          reason: 'only a screen that is LOCKED re-runs the gate');
      expect(listCalls, 1);
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('PRO: a subscription write while the entry gate is still '
        'pending starts no second gate', (tester) async {
      late _Sub sub;
      await makePro(tester);
      // The first frame by hand: the entry gate is pending, the screen is checking.
      _firstFrame(tester, _app(capture: (s) => sub = s));
      final notified = countNotifications(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // A purchase writes the subscription state several times (a local write,
      // then refreshFromSupabase). One such write lands now, and the next frame,
      // built BY HAND so that no microtask (the pending gate's answer) runs
      // first, delivers it to the screen's listener while the screen is still
      // checking.
      sub.set(true);
      tester.binding.scheduleFrame();
      tester.binding.handleBeginFrame(Duration.zero);
      tester.binding.handleDrawFrame();
      expect(notified(), 1,
          reason: 'the write must reach the listeners while the gate is '
              'pending, or this test proves nothing');

      await tester.pumpAndSettle();
      expect(routed(), hasLength(1),
          reason: 'a screen that is still checking has a gate in flight '
              'already; only a LOCKED one re-runs it');
      expect(listCalls, 1, reason: 'the photos are read once');
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('PRO lapses while the screen is open: Add photo shows the '
        'paywall, never the Camera / Gallery sheet', (tester) async {
      await makePro(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(find.text('Add photo'), findsOneWidget);

      // The subscription ends while the screen stays open.
      await makeFree(tester);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();

      expect(find.text(paywallLetterheadTitle('Progress Photos')),
          findsOneWidget);
      expect(find.text('Camera'), findsNothing);
      expect(find.text('Gallery'), findsNothing);
      expect(find.byType(ProLockedOverlay), findsOneWidget,
          reason: 'the refused write puts the screen in its locked state');
      expect(find.text('Add photo'), findsNothing);

      expect(routed(), hasLength(2));
      expect(routed().first, contains('exit=onPro'));
      expect(routed().last, contains('feature=progress_photos'));
      expect(routed().last, contains('exit=onFree'));
      expect(routed().last, contains('reason=not_pro_local'));
      expect(nonFatals, isEmpty);
    });

    testWidgets('PRO: Add photo opens the Camera / Gallery sheet, through the '
        'server-verified gate', (tester) async {
      await makePro(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text(paywallLetterheadTitle('Progress Photos')), findsNothing);
      expect(routed(), hasLength(2));
      expect(routed().last, contains('feature=progress_photos'));
      expect(routed().last, contains('exit=onPro'));
      expect(routed().last, contains('reason=verify_pro'),
          reason: 'the second gate is the server-verified one too (rule 19)');
      expect(nonFatals, isEmpty);
    });

    testWidgets('PRO: two taps on Add photo inside one gate open ONE sheet',
        (tester) async {
      await makePro(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      // Two taps in one synchronous stretch: the first gate is still pending when
      // the second arrives, as it is on a slow network with a stale verify cache
      // (`verifyFromServer` stamps the cache only after a 200 answer). `pump`
      // would flush the microtasks between them.
      final add = addPhotoHandler(tester);
      add();
      add();
      await tester.pumpAndSettle();

      expect(find.text('Camera'), findsOneWidget,
          reason: 'a second gate would stack a second picker, and one intent '
              'could burn two of the 5 photos a day');
      expect(
          routed().where((e) => e.contains('exit=onPro')), hasLength(2),
          reason: 'the entry gate plus exactly ONE write gate');
      expect(nonFatals, isEmpty);
    });

    testWidgets('PRO: the Add button is the busy spinner while its own gate is '
        'pending, and works again afterwards', (tester) async {
      await makePro(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      // Start the write gate and build a frame BY HAND before any microtask runs:
      // the gate is still pending (a slow verify), so the button must say so.
      addPhotoHandler(tester)();
      tester.binding.scheduleFrame();
      tester.binding.handleBeginFrame(Duration.zero);
      tester.binding.handleDrawFrame();
      expect(find.text('Add photo'), findsNothing,
          reason: 'no tappable Add button while the gate is pending');
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'the busy spinner tells the user the tap was received');
      expect(
          tester
              .widget<FloatingActionButton>(find.byType(FloatingActionButton))
              .onPressed,
          isNull);

      // The gate answers: the picker opens.
      await tester.pumpAndSettle();
      expect(find.text('Camera'), findsOneWidget);

      // Dismiss the sheet by tapping the barrier; the button must be usable again.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Camera'), findsNothing);
      expect(find.text('Add photo'), findsOneWidget,
          reason: 'the busy state must clear once the gate has answered');

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      expect(find.text('Camera'), findsOneWidget);
      expect(nonFatals, isEmpty);
    });

    testWidgets('PRO: leaving the screen inside the server verify drops the '
        'callback without an error', (tester) async {
      await makePro(tester);
      final mounted = ValueNotifier<bool>(true);
      addTearDown(mounted.dispose);

      _firstFrame(tester, _app(mounted: mounted));
      _removeScreenWithoutPumping(tester, mounted);

      // Now the verify "answers" and the gate calls onPro on a dead State.
      await tester.pump();

      expect(routed(), hasLength(1));
      expect(routed().single, contains('exit=onPro'));
      expect(listCalls, 0, reason: 'a dead screen must not read photos');
      expect(nonFatals, isEmpty,
          reason: 'without the guard setState runs on a disposed State and the '
              'gate reports subscription_gate_callback_threw');
      expect(tester.takeException(), isNull);
    });

    testWidgets('PRO: leaving the screen inside the Add button\'s verify drops '
        'the callback without an error', (tester) async {
      await makePro(tester);
      final mounted = ValueNotifier<bool>(true);
      addTearDown(mounted.dispose);
      await tester.pumpWidget(_app(mounted: mounted));
      await tester.pumpAndSettle();

      // The write gate starts and suspends at the verify; the screen goes away.
      addPhotoHandler(tester)();
      _removeScreenWithoutPumping(tester, mounted);
      await tester.pump();

      expect(routed().where((e) => e.contains('exit=onPro')), hasLength(2),
          reason: 'the write gate did answer; its callback must be dropped');
      expect(find.text('Camera'), findsNothing);
      expect(nonFatals, isEmpty);
      expect(tester.takeException(), isNull,
          reason: 'without the mounted guards the picker is opened from, and '
              'setState runs on, a dead State; those throw from a dropped future '
              '(the gate\'s callback runner only reports a SYNCHRONOUS throw, as '
              'subscription_gate_callback_threw), so the failure shows up here, '
              'or as an uncaught async error of the test');
    });

    // ── Through the hub ───────────────────────────────────────────────────

    testWidgets('through the hub: a PRO user passes the screen\'s gate and ends '
        'on the gallery', (tester) async {
      await makePro(tester);
      await tester.pumpWidget(_throughTheHub());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();

      expect(find.byType(ProgressPhotosScreen), findsOneWidget);
      expect(find.byType(ProLockedOverlay), findsNothing,
          reason: 'the screen\'s own gate must not refuse a PRO user the hub '
              'let through');
      expect(find.text('No photos yet'), findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
      expect(listCalls, 1);

      final passes =
          routed().where((e) => e.contains('feature=progress_photos')).toList();
      expect(passes, hasLength(1),
          reason: 'only the screen gates now; the hub row pushes for everyone');
      for (final p in passes) {
        expect(p, contains('exit=onPro'));
        expect(p, contains('reason=verify_pro'));
      }
      expect(nonFatals, isEmpty);
    });
  });

  group('source pins (comment-stripped; PRESENCE only, the tests above are the '
      'behaviour)', () {
    late String src;
    setUpAll(() {
      src = readSourceFileStripped(
          'lib/features/profile/screens/progress_photos_screen.dart');
    });

    /// The text of `Future<void> _reload(` up to its matching closing brace.
    String reloadBody() {
      final start = src.indexOf('Future<void> _reload(');
      expect(start, greaterThanOrEqualTo(0));
      final open = src.indexOf('{', src.indexOf(') async', start));
      var depth = 0;
      for (var i = open; i < src.length; i++) {
        if (src[i] == '{') depth++;
        if (src[i] == '}') {
          depth--;
          if (depth == 0) return src.substring(start, i + 1);
        }
      }
      fail('unbalanced braces in _reload');
    }

    test('initState starts the reload and does nothing else', () {
      expect(
          RegExp(r'void initState\(\) \{\s*super\.initState\(\);\s*'
                  r'_reload\(keepGallery: true\);\s*\}')
              .hasMatch(src),
          isTrue,
          reason: 'initState must be super.initState() + _reload(...): a photo '
              'read there, outside the single writer, would race it');
    });

    test('_reload is the ONLY code that assigns _access, _photos and _error '
        '(bar the field initialisers and the optimistic tile removal)', () {
      final body = reloadBody();
      final outside = src.replaceFirst(body, '');
      expect(RegExp(r'\b_access\s*=(?!=)').allMatches(outside).length, 1,
          reason: 'only the field initialiser `_Access _access = ...` may assign '
              '_access outside _reload');
      expect(RegExp(r'\b_error\s*=(?!=)').allMatches(outside).length, 0);
      // `_photos =` outside: the field is `_photos;` (no assignment) and the one '
      // optimistic removal in _delete.
      expect(RegExp(r'\b_photos\s*=(?!=)').allMatches(outside).length, 1,
          reason: 'only _delete\'s optimistic removal may assign _photos');
      expect(outside.contains('_photos = ['), isTrue);
      expect(RegExp(r'\b_access\s*=(?!=)').allMatches(body).length, greaterThan(2));
    });

    test('_reload checks mounted and the sequence after EVERY await', () {
      final body = reloadBody();
      final awaits = RegExp(r'\bawait\b').allMatches(body).length;
      final checks = RegExp(r'if \(!mounted \|\| gen != _seq\) return;')
          .allMatches(body)
          .length;
      expect(awaits, 2, reason: 'the gate and the read');
      expect(checks, greaterThanOrEqualTo(awaits),
          reason: 'one check after each await, plus the one in the catch');
      expect(body.contains('final gen = ++_seq;'), isTrue);
      expect(body.contains('finally'), isTrue,
          reason: 'the in-flight counter is released in a finally');
    });

    test('a failed read is never treated as an empty gallery', () {
      final body = reloadBody();
      // `denied` is reachable only from a non-null read result.
      expect(
          RegExp(r'if \(photos != null\) \{[\s\S]*?photos\.isEmpty \? _Access\.denied')
              .hasMatch(body),
          isTrue);
      expect(RegExp(r'_Access\.denied').allMatches(body).length, 1);
    });

    test('the gate callbacks in _reload only record a verdict', () {
      final body = reloadBody();
      expect(body.contains('onPro: () => pro = true,'), isTrue);
      expect(body.contains('onFree: () => pro = false,'), isTrue);
    });

    test('exactly two gates, both on the progress_photos feature', () {
      expect(RegExp(r'gateAndVerify\(').allMatches(src).length, 2,
          reason: 'the reload (entry) + the write action (_onAddPhoto)');
      expect(
          RegExp(r'gateAndVerify\(\s*AppConstants\.featureProgressPhotos,')
              .allMatches(src)
              .length,
          2);
    });

    test('the write gate\'s callbacks open with the mounted check', () {
      for (final cb in const ['onPro', 'onFree']) {
        expect(
            RegExp('$cb:\\s*\\(\\)\\s*\\{\\s*if\\s*\\(\\s*!mounted\\s*\\)\\s*return;')
                .allMatches(src)
                .length,
            1,
            reason: '$cb of _onAddPhoto must open with the guard');
      }
    });

    test('the paywall is shown by the locked card, the Add gate\'s onFree and '
        'the refusal branch only; the quota branch shows none', () {
      expect(RegExp(r'showPaywallSheet\(').allMatches(src).length, 3);
      expect(src.contains('on PhotoQuotaException'), isTrue);
      expect(src.contains('on ProgressPhotoProRequiredException'), isTrue);
    });

    test('the Add button is offered only to PRO, or to a lapsed user who holds '
        'photos', () {
      expect(
          src.contains('!(_access == _Access.granted ||'), isTrue);
      expect(
          RegExp(r'_access == _Access\.readOnly && \(_photos\?\.isNotEmpty \?\? false\)')
              .hasMatch(src),
          isTrue);
    });

    test('every method that touches Storage has exactly one caller, and the '
        'picker is reached only from the write gate', () {
      expect(RegExp(r'\b_pickAndCapture\b').allMatches(src).length, 2,
          reason: 'the definition and the one call');
      expect(
          RegExp(r'onPro:\s*\(\)\s*\{\s*if\s*\(\s*!mounted\s*\)\s*return;\s*'
                  r'_pickAndCapture\(\);')
              .hasMatch(src),
          isTrue,
          reason: 'the picker opens only from the write gate\'s onPro');
      expect(RegExp(r'\b_capture\b').allMatches(src).length, 2,
          reason: 'the definition and the call inside _pickAndCapture');
      expect(RegExp(r'\b_delete\b').allMatches(src).length, 2,
          reason: 'the definition and the long-press on a gallery tile');
      expect(RegExp(r'\b_repo\b').allMatches(src).length, 4,
          reason: 'the field, then listStrict, capture, delete: one use each');
      expect(RegExp(r'\bProgressPhotoRepository\b').allMatches(src).length, 1,
          reason: 'the one handle on the repository is the _repo field; a second '
              'handle would skip every count above');
    });
  });
}
