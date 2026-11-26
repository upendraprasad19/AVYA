// Proof of the Progress Photos screen's OWN decision after OI-348 Landing 3c
// (founder calls of 2026-11-26: progress photos are usable by FREE users, one
// photo per IST week; PRO is uncapped), against the REAL SubscriptionService and
// the REAL screen pumped directly: no router, no hub (one test goes through the
// hub on purpose). Pumping the screen alone is the door a typed web address
// opens; the screen must decide for itself.
//
//   FREE — the first frame is the spinner (the screen has not decided yet), then
//          the empty state with the free caption and the "Add photo" button; no
//          locked card exists any more; one photo read; no capture. A free user's
//          Add tap runs the weekly slot check (`ensureFreeSlotOpen`, scripted
//          through `ProgressPhotoRepository.debugEnsureFreeSlotOverride`) BEFORE
//          the Camera / Gallery sheet (asserted with a pending slot check and
//          call counters); a used slot shows the weekly-used snackbar and picks
//          and captures nothing; two quick taps run ONE slot check and open ONE
//          sheet; leaving inside the slot check drops the continuation.
//   FREE, then the user upgrades — the gate re-runs, the caption goes and the
//          gallery state stays; a refresh that changes nothing does not re-run it,
//          nor does a write that lands while the entry gate is still pending.
//   PRO  — the first frame is the spinner (no button, no caption); then the
//          gallery state and the button through the server-verified branch
//          (`reason=verify_pro`), so dropping `featureProgressPhotos` from
//          `SubscriptionService._highValueFeatures` (rule 19) turns it red; no
//          caption; one photo read.
//   A subscription that lapses while the screen stays open — the Add tap runs the
//          gate again and takes the FREE path (slot check, sheet or the
//          weekly-used snackbar); it NEVER opens the paywall by itself.
//   Two quick taps on "Add photo" open ONE sheet; the button works again after.
//   Leaving the screen inside the entry verify, or inside the Add button's
//          verify — the `if (!mounted) return;` guards drop the callback quietly.
//   Through the hub — a PRO user passes and ends on the gallery with ONE gate.
// It needs no network: Supabase is not initialized in a test, so for the
// high-value feature `verifyFromServer()` answers from local state, and
// `ProgressPhotoRepository.list()` answers `[]` (no user).
//
// What it does NOT prove, stated: the server round trip itself (so a slow verify
// is simulated by calling the Add handler twice in ONE synchronous stretch, which
// leaves the first gate pending exactly as a stale cache plus a slow network
// does); the real weekly slot check against Storage (scripted here; the SQL side
// has its own live verify); and the `onFree` branch of a locally-PRO user whose
// SERVER answer says free, which no unit test can produce. The paywall opening
// from the snackbar's GO PRO action, and the build-mode switch for that action,
// are in progress_photos_free_flow_test.dart.
//
// HARNESS (same as test/profile/user_photos_gate_behavioral_test.dart): the FIRST
// test is a typography warmup, run BEFORE setUpHiveForTests installs its
// path_provider mock (a mocked path_provider makes GoogleFonts fail loudly;
// root CLAUDE.md §4.9); Hive's disk I/O is escaped with tester.runAsync; @Timeout +
// library bound a regression to a failure, not a stall.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/copy/progress_photo_copy.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/repositories/progress_photo_repository.dart';
import 'package:icanbefitter/features/profile/screens/progress_photos_screen.dart';
import 'package:icanbefitter/features/profile/screens/user_photos_screen.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
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
    late int slotCalls;
    // What the next weekly slot check does. Replace per test.
    late Future<void> Function() slotFn;

    setUp(() async {
      events = [];
      nonFatals = [];
      listCalls = 0;
      captureCalls = 0;
      slotCalls = 0;
      slotFn = () async {};
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
      ProgressPhotoRepository.debugEnsureFreeSlotOverride = () {
        slotCalls++;
        return slotFn();
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
      ProgressPhotoRepository.debugEnsureFreeSlotOverride = null;
      await tearDownHiveForTests(dir);
    });

    List<String> routed() =>
        events.where((e) => e.startsWith('subscription_gate_routed')).toList();

    final caption = find.byKey(const ValueKey('progress_photos_free_caption'));
    final weeklyUsed = find.text(ProgressPhotoCopy.weeklyUsed);
    final paywall =
        find.text(paywallLetterheadTitle(ProgressPhotoCopy.paywallFeature));

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

    testWidgets('FREE: the empty state with the free caption and the Add '
        'button; no locked card, one photo read, no capture', (tester) async {
      await makeFree(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('No photos yet'), findsOneWidget);
      expect(caption, findsOneWidget);
      expect(find.text(ProgressPhotoCopy.freeCaption), findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget,
          reason: 'a free user may add one photo a week');
      expect(find.text('PRO FEATURE'), findsNothing,
          reason: 'the locked card is gone');
      expect(find.text('Upgrade to PRO'), findsNothing);
      expect(listCalls, 1);
      expect(captureCalls, 0, reason: 'opening the screen writes nothing');
      expect(slotCalls, 0, reason: 'the slot is asked at the Add tap only');

      expect(routed(), hasLength(1));
      expect(routed().single, contains('feature=progress_photos'));
      expect(routed().single, contains('exit=onFree'));
      expect(routed().single, contains('reason=not_pro_local'));
      expect(nonFatals, isEmpty);
    });

    testWidgets('FREE: the first frame is the spinner (no button, no caption '
        'before the screen has decided)', (tester) async {
      await makeFree(tester);
      _firstFrame(tester, _app());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Add photo'), findsNothing);
      expect(caption, findsNothing);
      expect(find.text('No photos yet'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('Add photo'), findsOneWidget);
      expect(caption, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(listCalls, 1);
      expect(captureCalls, 0);
    });

    testWidgets('FREE: Add runs the weekly slot check BEFORE the source sheet; '
        'a slot that is open proceeds to the picker', (tester) async {
      await makeFree(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      final pending = Completer<void>();
      slotFn = () => pending.future;
      await tester.tap(find.text('Add photo'));
      await tester.pump();
      await tester.pump();

      expect(slotCalls, 1);
      expect(find.text('Camera'), findsNothing,
          reason: 'the sheet must wait for the slot check');
      expect(find.text('Gallery'), findsNothing);
      expect(captureCalls, 0);

      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(slotCalls, 1, reason: 'one intent, one slot check');
      expect(paywall, findsNothing);
      expect(nonFatals, isEmpty);
    });

    testWidgets('FREE: a used slot shows the weekly-used snackbar and picks '
        'nothing', (tester) async {
      await makeFree(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      slotFn = () async =>
          throw const PhotoQuotaException(weeklyCap: 1, message: 'used');
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();

      expect(slotCalls, 1);
      expect(weeklyUsed, findsOneWidget);
      expect(find.text('Camera'), findsNothing);
      expect(find.text('Gallery'), findsNothing);
      expect(find.text('Which angle?'), findsNothing);
      expect(captureCalls, 0);
      expect(paywall, findsNothing,
          reason: 'the paywall opens only from the snackbar action');
      expect(find.text('Add photo'), findsOneWidget,
          reason: 'the busy state clears: the button works again');
      expect(nonFatals, isEmpty);
    });

    testWidgets('FREE: two taps on Add inside one gate run ONE slot check and '
        'open ONE sheet', (tester) async {
      await makeFree(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      final add = addPhotoHandler(tester);
      add();
      add();
      await tester.pumpAndSettle();

      expect(slotCalls, 1);
      expect(find.text('Camera'), findsOneWidget);
      expect(nonFatals, isEmpty);
    });

    testWidgets('FREE: leaving the screen inside the slot check drops the '
        'continuation without an error', (tester) async {
      await makeFree(tester);
      final mounted = ValueNotifier<bool>(true);
      addTearDown(mounted.dispose);
      await tester.pumpWidget(_app(mounted: mounted));
      await tester.pumpAndSettle();

      final pending = Completer<void>();
      slotFn = () => pending.future;
      addPhotoHandler(tester)();
      await tester.pump();
      await tester.pump();
      expect(slotCalls, 1);

      _removeScreenWithoutPumping(tester, mounted);
      pending.complete();
      await tester.pump();

      expect(find.text('Camera'), findsNothing);
      expect(captureCalls, 0);
      expect(nonFatals, isEmpty);
      expect(tester.takeException(), isNull,
          reason: 'without the mounted check after the slot check the picker '
              'is opened from a dead State');
    });

    testWidgets('FREE then PRO: a purchase re-runs the gate, the caption goes '
        'and the gallery stays', (tester) async {
      late _Sub sub;
      await makeFree(tester);
      await tester.pumpWidget(_app(capture: (s) => sub = s));
      await tester.pumpAndSettle();
      expect(caption, findsOneWidget);
      final notified = countNotifications(tester);

      // A refresh that changes nothing for a still-free user is not a re-gate.
      sub.set(false);
      await tester.pumpAndSettle();
      expect(notified(), 1,
          reason: 'the refresh must reach the screen\'s listener (no == on '
              'SubscriptionInfoData); if it stops, this test proves nothing');
      expect(caption, findsOneWidget);
      expect(routed(), hasLength(1),
          reason: 'only a user who became PRO gets the gate re-run');

      // A purchase writes the local state first, then flips the provider.
      await makePro(tester);
      sub.set(true);
      await tester.pumpAndSettle();
      expect(notified(), 2);

      expect(caption, findsNothing);
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

    testWidgets('PRO, lapses, then pays again: the re-check ends as PRO, the caption '
        'goes', (tester) async {
      late _Sub sub;
      await makePro(tester);
      await tester.pumpWidget(_app(capture: (s) => sub = s));
      await tester.pumpAndSettle();
      expect(find.text('No photos yet'), findsOneWidget);
      expect(caption, findsNothing);
      expect(listCalls, 1);

      // The subscription ends; the Add tap's gate re-decides the screen as free
      // (slot open: the sheet opens; dismiss it).
      await makeFree(tester);
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(caption, findsOneWidget);

      // The user pays again: local state first, then the provider.
      await makePro(tester);
      sub.set(true);
      await tester.pumpAndSettle();
      expect(find.text('No photos yet'), findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
      expect(caption, findsNothing);
      expect(listCalls, 3,
          reason: 'entry, the lapse\'s reload, then the re-check');
    });

    // ── PRO ───────────────────────────────────────────────────────────────

    testWidgets('PRO: the gallery state and the Add button, server-verified, '
        'no caption, one photo read', (tester) async {
      await makePro(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('No photos yet'), findsOneWidget,
          reason: 'list() answers [] without a user, so a granted screen ends '
              'in the empty state');
      expect(find.text('Add photo'), findsOneWidget);
      expect(caption, findsNothing, reason: 'the free rule is not PRO\'s');
      expect(listCalls, 1);

      expect(routed(), hasLength(1));
      expect(routed().single, contains('feature=progress_photos'));
      expect(routed().single, contains('exit=onPro'));
      expect(routed().single, contains('reason=verify_pro'),
          reason: 'the server-verified branch: progress_photos must stay on '
              "SubscriptionService's high-value list (rule 19)");
      expect(nonFatals, isEmpty);
    });

    testWidgets('PRO: the very first frame is the spinner: no Add button, no '
        'caption, no photo read yet', (tester) async {
      await makePro(tester);
      _firstFrame(tester, _app());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Add photo'), findsNothing,
          reason: 'no button until the screen has verified');
      expect(caption, findsNothing,
          reason: 'a PRO user must never be shown the free caption while the '
              'screen verifies');
      expect(listCalls, 0);

      await tester.pumpAndSettle();
      expect(find.text('Add photo'), findsOneWidget);
      expect(caption, findsNothing);
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
          reason: 'only a FREE screen re-runs the gate');
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
              'already; only a FREE one re-runs it');
      expect(listCalls, 1, reason: 'the photos are read once');
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('PRO lapses while the screen is open: the Add tap takes the '
        'FREE path (slot check, then the sheet), never the paywall',
        (tester) async {
      await makePro(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(find.text('Add photo'), findsOneWidget);
      expect(caption, findsNothing);

      // The subscription ends while the screen stays open.
      await makeFree(tester);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();

      expect(slotCalls, 1, reason: 'a user who is no longer PRO owes the slot '
          'check');
      expect(find.text('Camera'), findsOneWidget);
      expect(paywall, findsNothing,
          reason: 'a lapse no longer sends anyone to the paywall by itself');
      expect(caption, findsOneWidget,
          reason: 'the verdict differed from the screen\'s, so it was '
              're-decided as free');
      expect(find.text('Add photo'), findsOneWidget);

      expect(routed(), hasLength(2));
      expect(routed().first, contains('exit=onPro'));
      expect(routed().last, contains('feature=progress_photos'));
      expect(routed().last, contains('exit=onFree'));
      expect(routed().last, contains('reason=not_pro_local'));
      expect(nonFatals, isEmpty);
    });

    testWidgets('PRO lapses and this week\'s slot is used: the weekly-used '
        'snackbar, no sheet, no paywall', (tester) async {
      await makePro(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await makeFree(tester);
      slotFn = () async =>
          throw const PhotoQuotaException(weeklyCap: 1, message: 'used');

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();

      expect(weeklyUsed, findsOneWidget);
      expect(find.text('Camera'), findsNothing);
      expect(paywall, findsNothing);
      expect(captureCalls, 0);
      expect(caption, findsOneWidget);
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
      expect(paywall, findsNothing);
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
          reason: 'a second gate would stack a second picker');
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
          reason: 'the write gate did answer; its continuation must be dropped');
      expect(find.text('Camera'), findsNothing);
      expect(nonFatals, isEmpty);
      expect(tester.takeException(), isNull,
          reason: 'without the mounted guards the picker is opened from, and '
              'setState runs on, a dead State');
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
      expect(find.text('No photos yet'), findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
      expect(caption, findsNothing);
      expect(listCalls, 1);

      final passes =
          routed().where((e) => e.contains('feature=progress_photos')).toList();
      expect(passes, hasLength(1),
          reason: 'only the screen gates; the hub row pushes for everyone');
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

    /// The text of `Future<void> _onAddPhoto(` up to its matching closing brace.
    String addBody() {
      final start = src.indexOf('Future<void> _onAddPhoto(');
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
      fail('unbalanced braces in _onAddPhoto');
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
      // `_photos` is assigned only from a non-null read; the else branch keeps
      // what is on screen and sets the error only when nothing is held.
      expect(
          RegExp(r'if \(photos != null\) \{\s*_photos = photos;\s*_error = null;'
                  r'\s*\} else \{\s*_error = held \?')
              .hasMatch(body),
          isTrue);
      expect(RegExp(r'_photos\s*=\s*photos\b').allMatches(body).length, 1);
    });

    test('the access states are exactly checking / pro / free (no locked '
        'state, no locked card)', () {
      expect(src.contains('enum _Access { checking, pro, free }'), isTrue);
      expect(src.contains('ProLockedOverlay'), isFalse);
      expect(RegExp(r'_Access\.(denied|readOnly|granted)').hasMatch(src),
          isFalse);
    });

    test('the gate callbacks only record a verdict (both gates)', () {
      expect(_has(reloadBody(), 'onPro: () => pro = true,'), isTrue);
      expect(_has(reloadBody(), 'onFree: () => pro = false,'), isTrue);
      expect(_has(addBody(), 'onPro: () => pro = true,'), isTrue);
      expect(_has(addBody(), 'onFree: () => pro = false,'), isTrue);
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

    test('the write action checks mounted after the gate and after the slot '
        'check, and only a FREE verdict asks for the slot', () {
      final b = addBody();
      expect(b.contains('if (!mounted || verdict == null) return;'), isTrue);
      expect(
          RegExp(r'if \(!verdict\) \{\s*try \{\s*await _repo\.ensureFreeSlotOpen\(\);'
                  r'\s*\} on PhotoQuotaException \{\s*_showWeeklyUsed\(\);\s*return;'
                  r'\s*\}\s*if \(!mounted\) return;')
              .hasMatch(b),
          isTrue,
          reason: 'PRO skips the slot check; a used slot returns before '
              '`proceed = true`; the continuation checks mounted');
      expect(RegExp(r'\bensureFreeSlotOpen\b').allMatches(src).length, 1);
      expect(b.indexOf('ensureFreeSlotOpen'),
          lessThan(b.indexOf('proceed = true;')),
          reason: 'nothing may proceed to the picker before the slot check');
    });

    test('the paywall is opened only from the weekly-used snackbar action, '
        'and only behind showsUpgradeAffordance()', () {
      expect(RegExp(r'showPaywallSheet\(').allMatches(src).length, 1);
      expect(
          RegExp(r'action:\s*showsUpgradeAffordance\(\)\s*\?\s*SnackBarAction\('
                  r'[\s\S]*?onPressed:\s*\(\)\s*=>\s*showPaywallSheet\(context,\s*'
                  r'feature:\s*ProgressPhotoCopy\.paywallFeature\)')
              .hasMatch(src),
          isTrue);
      expect(RegExp(r'\bshowsUpgradeAffordance\(\)').allMatches(src).length, 1);
      expect(src.contains('on ProgressPhotoProRequiredException'), isTrue,
          reason: 'a server refusal is handled, and answers with a snackbar');
      expect(RegExp(r'_showWeeklyUsed\(\)').allMatches(src).length, 3,
          reason: 'the definition, the slot-check branch and the refusal branch');
    });

    test('the Add button is offered whenever the screen has decided', () {
      expect(
          RegExp(r'floatingActionButton:\s*_access == _Access\.checking\s*\?\s*null')
              .hasMatch(src),
          isTrue);
    });

    test('every method that touches Storage has exactly one caller, and the '
        'picker is reached only from the write gate after the slot check', () {
      expect(RegExp(r'\b_pickAndCapture\b').allMatches(src).length, 2,
          reason: 'the definition and the one call');
      expect(
          src.contains('if (proceed && mounted) await _pickAndCapture();'),
          isTrue,
          reason: 'the picker opens only from the write gate, after `proceed`');
      expect(RegExp(r'\bproceed = true;').allMatches(src).length, 1);
      expect(RegExp(r'\b_capture\b').allMatches(src).length, 2,
          reason: 'the definition and the call inside _pickAndCapture');
      expect(RegExp(r'\b_delete\b').allMatches(src).length, 2,
          reason: 'the definition and the long-press on a gallery tile');
      expect(RegExp(r'\b_repo\b').allMatches(src).length, 6,
          reason: 'the field, then listStrict, ensureFreeSlotOpen, '
              'cleanupOrphanedStorage (PRO Add, unawaited), capture, delete: '
              'one use each');
      expect(src.contains('unawaited(_repo.cleanupOrphanedStorage());'), isTrue);
      expect(RegExp(r'\bProgressPhotoRepository\b').allMatches(src).length, 1,
          reason: 'the one handle on the repository is the _repo field; a second '
              'handle would skip every count above');
    });
  });
}

bool _has(String text, String needle) => text.contains(needle);
