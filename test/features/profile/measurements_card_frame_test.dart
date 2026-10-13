// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md section 4.9): the first test
// is a typography warmup before any path_provider mock; Hive is set up per
// group. History is a FAKE notifier (no Hive write in the fake-async zone).
@Timeout(Duration(minutes: 6))
library;

// L2b Landing C (E3): the frame that pins the card above a screen's body.
// Plan: docs/plans/coach-measurement-surfaces.md (C2, section 4).
//
// GEOMETRY: every edge row is a LITERAL body height (never computed from the
// constants), laid out in a tight box of exactly that height. The production
// rows lay the frame out the way the app does: an outer Scaffold with an 80 dp
// bottom bar, a 24 dp top inset, and the screen's own 56 dp AppBar, which makes
// a 640 dp window a 480 dp body and a 568 dp window a 408 dp body.
//
// FONT: `flutter test` renders Ahem (every glyph one em wide, one em of line
// height). The header's real face is JetBrains Mono (not DM Sans): 0.6 em wide
// and 1.32 em of line height, measured from the font file. So Ahem is the WIDEST
// possible font, which makes the header wrap to its two-run worst case at 320 and
// 360 dp, but it is NOT the tallest: its lines are shorter than the real ones.
// The plan's 0.6 em fixture is replaced by (a) a 700 dp host in which the header
// is one run, (b) the header rows in measurements_card_test.dart that give Ahem
// the real advance with a text scale of 0.6, and (c) the floor row below, which
// adds the line height Ahem lacks (0.32 em of each text line) to the real card's
// measured height.
//
// CLOCKS: the clock is pinned to 2031-06-15 20:00 UTC (2031-06-16 01:30 IST);
// entries are dated 2031. No row turns red on the day the real clock reaches
// 2031; from then on a frame that asked the device clock cannot be told apart by
// these literals (the card's New Year row carries that check).
//
// THE 286-301 ROWS: the card is COMPACT there (the header alone, not stretched to
// the cap), so they cannot see the cap's value; the `available - kMinListHeight`
// term of the cap binds only if the header grows past what kMinCardCap allows,
// and the floor row below is the tripwire for that day.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';
import 'package:icanbefitter/features/profile/widgets/body_measurements_sheet.dart';
import 'package:icanbefitter/features/profile/widgets/measurements_card.dart';
import 'package:icanbefitter/features/profile/widgets/measurements_card_frame.dart';

import '../../helpers/flutter_error_capture.dart';
import '../../helpers/hive_test_setup.dart';

class _FakeHistory extends BodyMeasurementsNotifier {
  _FakeHistory(this.state0);

  final BodyMeasurementsState state0;

  @override
  BodyMeasurementsState build() => state0;
}

class _FakeWrite extends MeasurementWriteNotifier {
  @override
  bool? lastUnitInches() => false;
}

MeasurementEntry e(String date, Map<String, double> sites) =>
    MeasurementEntry(date: date, sites: sites);

BodyMeasurementsState hist(List<MeasurementEntry> entries) =>
    BodyMeasurementsState(
      loaded: true,
      latest: HealthReadService.latestBySiteOf(entries),
      lastEntryDate: entries.isEmpty ? null : entries.first.date,
      entries: entries,
    );

// Four sites, each with a change line: the tiles are the tallest content the
// card can have, so at 2x text they overflow every cap and fill it exactly.
final _fullHistory = hist([
  e('2031-06-10', {'chest': 97.5, 'waist': 79.5, 'hips': 100.5, 'arms': 33.0}),
  e('2031-05-20', {'chest': 96.0, 'waist': 81.0, 'hips': 100.0, 'arms': 32.0}),
]);

// Waist alone, no change line: short content, below every cap.
final _shortHistory = hist([
  e('2031-06-10', {'waist': 79.5}),
]);

final class _Created extends ProviderObserver {
  final List<ProviderBase<Object?>> providers = [];

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    providers.add(context.provider);
  }

  bool saw(ProviderBase<Object?> p) => providers.contains(p);
}

const _childKey = ValueKey('frame-child');

/// A tight box of exactly [height] dp holding the frame over a keyed child.
Widget tightBox(double height, {double width = 360, Widget? child}) => Align(
  alignment: Alignment.topCenter,
  child: SizedBox(
    width: width,
    height: height,
    child: MeasurementsCardFrame(
      child: child ?? Container(key: _childKey, color: Colors.black),
    ),
  ),
);

void main() {
  testWidgets('typography warmup - GoogleFonts caches before any Hive mock', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Text('a', style: AppTypography.body),
              Text('b', style: AppTypography.bodyS),
              Text('c', style: AppTypography.titleS),
              Text('d', style: AppTypography.mono),
              Text('e', style: AppTypography.monoXs),
              Text('f', style: AppTypography.label),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('MeasurementsCardFrame', () {
    late Directory dir;

    setUp(() async {
      dir = await setUpHiveForTests();
      setTestClockTo(DateTime.utc(2031, 6, 15, 20)); // 2031-06-16 01:30 IST
    });

    tearDown(() async {
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    Widget app({
      required Widget home,
      bool flag = true,
      BodyMeasurementsState? history,
      double textScale = 1.0,
      ProviderObserver? observer,
      bool shell = false,
      String token = kTestUserId,
    }) {
      return ProviderScope(
        observers: [?observer],
        overrides: [
          authUserIdTokenProvider.overrideWithValue(token),
          measurementsEnabledProvider.overrideWithValue(flag),
          bodyMeasurementsProvider.overrideWith(
            () => _FakeHistory(history ?? _fullHistory),
          ),
          measurementWriteProvider.overrideWith(_FakeWrite.new),
        ],
        child: MaterialApp(
          builder: (ctx, child) {
            var mq = MediaQuery.of(
              ctx,
            ).copyWith(textScaler: TextScaler.linear(textScale));
            if (shell) {
              mq = mq.copyWith(
                padding: const EdgeInsets.only(top: 24),
                viewPadding: const EdgeInsets.only(top: 24),
              );
            }
            return MediaQuery(data: mq, child: child!);
          },
          home: home,
        ),
      );
    }

    /// The app's own nesting: shell Scaffold with an 80 dp bottom bar, the
    /// screen's Scaffold with a 56 dp AppBar, the frame in its body.
    Widget shellHome(Widget body) => Scaffold(
      bottomNavigationBar: const SizedBox(height: 80),
      body: Scaffold(
        appBar: AppBar(toolbarHeight: 56, title: const Text('P')),
        body: body,
      ),
    );

    void window(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Rect cardRect(WidgetTester tester) =>
        tester.getRect(find.byType(MeasurementsCard));

    // ── OFF ────────────────────────────────────────────────────────────

    testWidgets('OFF returns the identical child and creates no measurements '
        'provider; ON (non-empty history) creates both', (tester) async {
      const child = SizedBox(key: _childKey, height: 10);
      final off = _Created();
      await tester.pumpWidget(
        app(
          flag: false,
          observer: off,
          home: const Scaffold(body: MeasurementsCardFrame(child: child)),
        ),
      );
      await tester.pump();
      final frame = tester.element(find.byType(MeasurementsCardFrame));
      Widget? direct;
      frame.visitChildren((c) => direct = c.widget);
      expect(identical(direct, child), isTrue);
      expect(find.byType(MeasurementsCard), findsNothing);
      expect(off.saw(bodyMeasurementsProvider), isFalse);
      expect(off.saw(measurementWriteProvider), isFalse);

      // Positive control on the same installation path.
      final on = _Created();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(
          observer: on,
          home: Scaffold(body: tightBox(480)),
        ),
      );
      await tester.pump();
      expect(find.byType(MeasurementsCard), findsOneWidget);
      expect(on.saw(bodyMeasurementsProvider), isTrue);
      expect(on.saw(measurementWriteProvider), isTrue);
    });

    // ── the cap, at literal body heights ───────────────────────────────

    testWidgets('285.9 dp: the child alone, no card', (tester) async {
      await tester.pumpWidget(app(home: Scaffold(body: tightBox(285.9))));
      await tester.pump();
      expect(find.byType(MeasurementsCard), findsNothing);
      expect(
        tester.getSize(find.byKey(_childKey)).height,
        closeTo(285.9, 0.01),
      );
    });

    // The threshold's own neighbourhood: a boundary moved by a few hundredths
    // of a dp is invisible to the two rows at 285.9 and 286.0.
    testWidgets('285.99 dp: still the child alone, no card', (tester) async {
      await tester.pumpWidget(
        app(
          home: Scaffold(body: tightBox(285.99)),
        ),
      );
      await tester.pump();
      expect(find.byType(MeasurementsCard), findsNothing);
    });

    for (final h in [286.0, 299.0, 300.0, 301.0]) {
      testWidgets('$h dp: the card is there (header only) and the list keeps '
          'at least 150 dp', (tester) async {
        await tester.pumpWidget(app(home: Scaffold(body: tightBox(h))));
        await tester.pump();
        expect(find.byType(MeasurementsCard), findsOneWidget);
        expect(find.text('BODY MEASUREMENTS'), findsOneWidget);
        expect(find.text('Add measurements'), findsOneWidget);
        expect(find.text('79.5 cm'), findsNothing, reason: 'compact: no tiles');
        expect(
          tester.getSize(find.byKey(_childKey)).height,
          greaterThanOrEqualTo(150),
        );
      });
    }

    testWidgets('399.96 dp: the cap is 199.98, still compact', (tester) async {
      await tester.pumpWidget(
        app(
          textScale: 2.0,
          home: Scaffold(body: tightBox(399.96)),
        ),
      );
      await tester.pump();
      expect(find.byType(MeasurementsCard), findsOneWidget);
      expect(find.textContaining('WAIST'), findsNothing);
    });

    testWidgets('399.9 dp: still compact (header only)', (tester) async {
      await tester.pumpWidget(
        app(textScale: 2.0, home: Scaffold(body: tightBox(399.9))),
      );
      await tester.pump();
      expect(find.byType(MeasurementsCard), findsOneWidget);
      expect(find.textContaining('WAIST'), findsNothing);
    });

    // Cap-binding fixture: four change lines at 2x text always overflow the
    // window the cap leaves, so the card fills its cap exactly and the list
    // gets the rest.
    for (final row in <({double body, double cap, double list})>[
      (body: 400, cap: 200, list: 200),
      (body: 408, cap: 204, list: 204),
      (body: 480, cap: 240, list: 240),
      (body: 584, cap: 292, list: 292),
    ]) {
      testWidgets('${row.body} dp: the card box is ${row.cap} dp, the list '
          '${row.list} dp, and the tiles show', (tester) async {
        await tester.pumpWidget(
          app(textScale: 2.0, home: Scaffold(body: tightBox(row.body))),
        );
        await tester.pump();
        expect(find.textContaining('WAIST'), findsOneWidget);
        final card = cardRect(tester);
        // The card box is the card plus the 12 dp above and the 8 dp below.
        expect(card.height + 12 + 8, closeTo(row.cap, 0.01));
        expect(card.top, closeTo(12, 0.01));
        expect(
          tester.getSize(find.byKey(_childKey)).height,
          closeTo(row.list, 0.01),
        );
      });
    }

    testWidgets(
      'a short history is below the cap (the card is not stretched)',
      (tester) async {
        await tester.pumpWidget(
          app(
            history: _shortHistory,
            home: Scaffold(body: tightBox(480)),
          ),
        );
        await tester.pump();
        expect(find.text('79.5 cm'), findsOneWidget);
        expect(cardRect(tester).height + 20, lessThan(240));
        expect(tester.getSize(find.byKey(_childKey)).height, greaterThan(240));
      },
    );

    testWidgets('the card spans the body width inside the 22 dp gutter', (
      tester,
    ) async {
      await tester.pumpWidget(app(home: Scaffold(body: tightBox(480))));
      await tester.pump();
      final card = cardRect(tester);
      final body = tester.getRect(find.byType(MeasurementsCardFrame));
      expect(card.left - body.left, closeTo(22, 0.01));
      expect(body.right - card.right, closeTo(22, 0.01));
      expect(card.width, closeTo(360 - 44, 0.01));
    });

    testWidgets('the account-swap window (token <anon>): no card and no blank '
        'band, the list keeps the whole body', (tester) async {
      await tester.pumpWidget(
        app(
          token: '<anon>',
          home: Scaffold(body: tightBox(480)),
        ),
      );
      await tester.pump();
      expect(find.byType(MeasurementsCard), findsNothing);
      expect(tester.getSize(find.byKey(_childKey)).height, closeTo(480, 0.01));
    });

    testWidgets('the child gets the whole remainder even when it asks for '
        'less (Expanded, not Flexible)', (tester) async {
      await tester.pumpWidget(
        app(
          home: Scaffold(
            body: tightBox(
              480,
              child: const SizedBox(key: _childKey, height: 10),
            ),
          ),
        ),
      );
      await tester.pump();
      final card = cardRect(tester);
      expect(
        tester.getSize(find.byKey(_childKey)).height,
        closeTo(480 - (card.height + 20), 0.01),
      );
    });

    // `watch` over `read`: the flag flips while the frame is mounted (the
    // remote-config refresh) and the card must follow, both ways.
    testWidgets('the flag flipping under a mounted frame adds and removes the '
        'card', (tester) async {
      final flag = NotifierProvider<_Flag, bool>(_Flag.new);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserIdTokenProvider.overrideWithValue(kTestUserId),
            measurementsEnabledProvider.overrideWith((ref) => ref.watch(flag)),
            bodyMeasurementsProvider.overrideWith(
              () => _FakeHistory(_fullHistory),
            ),
            measurementWriteProvider.overrideWith(_FakeWrite.new),
          ],
          child: MaterialApp(home: Scaffold(body: tightBox(480))),
        ),
      );
      await tester.pump();
      expect(find.byType(MeasurementsCard), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MeasurementsCardFrame)),
      );
      container.read(flag.notifier).set(true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(MeasurementsCard), findsOneWidget);
      container.read(flag.notifier).set(false);
      await tester.pump();
      expect(find.byType(MeasurementsCard), findsNothing);
      expect(tester.getSize(find.byKey(_childKey)).height, closeTo(480, 0.01));
    });

    // ── production-like hosts ──────────────────────────────────────────

    testWidgets('production host: a 640 dp window gives the frame a 480 dp '
        'body', (tester) async {
      window(tester, const Size(360, 640));
      await tester.pumpWidget(
        app(
          shell: true,
          flag: false,
          home: shellHome(
            const MeasurementsCardFrame(child: SizedBox.expand(key: _childKey)),
          ),
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byKey(_childKey)).height, closeTo(480, 0.01));
    });

    testWidgets('production host: a 568 dp window gives a 408 dp body, the '
        'card box is 204 dp and the list 204 dp', (tester) async {
      window(tester, const Size(320, 568));
      await tester.pumpWidget(
        app(
          shell: true,
          textScale: 2.0,
          home: shellHome(
            MeasurementsCardFrame(
              child: Container(key: _childKey, color: Colors.black),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(cardRect(tester).height + 20, closeTo(204, 0.01));
      expect(tester.getSize(find.byKey(_childKey)).height, closeTo(204, 0.01));
    });

    // ── the header ─────────────────────────────────────────────────────

    // At 320 dp (two runs in the widest font) and at 700 dp (one run), at every
    // text scale: the header, the card's chrome and the frame's margin fit the
    // derived floor, and the button label is fully visible.
    for (final width in [320.0, 360.0, 700.0]) {
      for (final scale in [1.0, 1.5, 2.0, 3.0]) {
        testWidgets('header at ${width.toInt()} dp, text x$scale: within the '
            'derived floor, label fully visible, no overflow', (tester) async {
          final capture = FlutterErrorCapture()..start();
          addTearDown(capture.stop);
          await tester.pumpWidget(
            app(
              textScale: scale,
              history: hist(const []),
              home: Scaffold(body: tightBox(400, width: width)),
            ),
          );
          await tester.pump();
          capture.stop(); // before any expect that can fail
          final wrap = find
              .descendant(
                of: find.byType(MeasurementsCard),
                matching: find.byType(Wrap),
              )
              .first;
          expect(wrap, findsOneWidget);
          // The REAL card (its padding, border and header, whatever they are
          // today) plus the frame's margin, plus the line height Ahem lacks:
          // JetBrains Mono's 1.32 em against Ahem's 1.0 em, on the 10 sp text
          // of the header at the header's clamped scale (at most x2.0).
          final cardHeight = tester
              .getSize(find.byType(MeasurementsCard))
              .height;
          final lineHeightAhemLacks =
              0.32 * AppTypography.mono.fontSize! * math.min(scale, 2.0);
          expect(
            cardHeight +
                kCardMarginTop +
                kCardMarginBottom +
                lineHeightAhemLacks,
            lessThanOrEqualTo(kMinCardCap),
            reason: 'the header at x$scale in a real face outgrew kMinCardCap',
          );
          final label = tester.getRect(find.text('Add measurements'));
          final button = tester.getRect(
            find
                .ancestor(
                  of: find.text('Add measurements'),
                  matching: find.byType(InkWell),
                )
                .first,
          );
          expect(button.height, greaterThanOrEqualTo(48));
          expect(label.left, greaterThanOrEqualTo(button.left - 0.01));
          expect(label.right, lessThanOrEqualTo(button.right + 0.01));
          expect(capture.overflows, isEmpty);
          expect(capture.others, isEmpty);
        });
      }
    }

    testWidgets('the header button stays put while the tiles scroll, and a tap '
        'on it opens the sheet', (tester) async {
      await tester.pumpWidget(
        app(textScale: 2.0, home: Scaffold(body: tightBox(400))),
      );
      await tester.pump();
      final scrollable = find.descendant(
        of: find.byType(MeasurementsCard),
        matching: find.byType(Scrollable),
      );
      expect(
        tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        greaterThan(0),
        reason: 'precondition: there is something to scroll',
      );
      final button = find.text('Add measurements');
      final before = tester.getRect(button);
      final box = cardRect(tester);
      expect(box.contains(before.center), isTrue);
      await tester.drag(scrollable, const Offset(0, -60));
      await tester.pump();
      expect(tester.getRect(button), before);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(BodyMeasurementsSheet), findsOneWidget);
    });

    testWidgets('an opaque overlay in front of the button swallows the tap '
        '(the door is not the card, it is the button)', (tester) async {
      await tester.pumpWidget(
        app(
          history: hist(const []),
          home: Scaffold(
            body: Stack(
              children: [
                tightBox(400),
                Positioned.fill(
                  child: Container(color: const Color(0x01000000)),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Add measurements'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(BodyMeasurementsSheet), findsNothing);
    });

    // ── what the card does to its neighbours ───────────────────────────

    for (final scale in [1.0, 1.5, 2.0, 3.0]) {
      for (final shell in [false, true]) {
        for (final flag in [true, false]) {
          final stubs = <String, Widget Function()>{
            'loading': () => const Center(child: CircularProgressIndicator()),
            'error': () => const Center(child: Text('error')),
            'empty': () => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [Text('none'), SizedBox(height: 8), Text('yet')],
              ),
            ),
            'list': () => ListView.builder(
              itemCount: 30,
              itemBuilder: (_, i) => SizedBox(height: 60, child: Text('r$i')),
            ),
          };
          for (final stub in stubs.entries) {
            testWidgets('${stub.key} child, flag ${flag ? 'ON' : 'OFF'}, '
                '${shell ? 'production' : 'full'} host, text x$scale: no '
                'exception', (tester) async {
              final capture = FlutterErrorCapture()..start();
              addTearDown(capture.stop);
              window(tester, const Size(360, 640));
              // The stubs are plain widgets; an animation in one (the
              // spinner) never settles, so pump a fixed number of frames.
              await tester.pumpWidget(
                app(
                  shell: shell,
                  flag: flag,
                  textScale: scale,
                  home: shell
                      ? shellHome(MeasurementsCardFrame(child: stub.value()))
                      : Scaffold(
                          body: MeasurementsCardFrame(child: stub.value()),
                        ),
                ),
              );
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 100));
              capture.stop(); // before any expect that can fail
              expect(capture.messages, isEmpty);
            });
          }
        }
      }
    }

    testWidgets('the list can still be scrolled to its last item, by rect', (
      tester,
    ) async {
      window(tester, const Size(360, 640));
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          shell: true,
          textScale: 2.0,
          home: shellHome(
            MeasurementsCardFrame(
              child: ListView.builder(
                controller: controller,
                itemCount: 30,
                itemBuilder: (_, i) => SizedBox(
                  height: 60,
                  child: Text('row $i', key: ValueKey('row-$i')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pump();
      final last = tester.getRect(find.byKey(const ValueKey('row-29')));
      final list = tester.getRect(find.byType(ListView));
      expect(last.bottom, lessThanOrEqualTo(list.bottom + 0.01));
      expect(last.top, greaterThanOrEqualTo(list.top - 0.01));
    });

    testWidgets('an unbounded host gets the child alone and no exception', (
      tester,
    ) async {
      final capture = FlutterErrorCapture()..start();
      addTearDown(capture.stop);
      await tester.pumpWidget(
        app(
          home: const Scaffold(
            body: SingleChildScrollView(
              child: MeasurementsCardFrame(
                child: SizedBox(key: _childKey, height: 100),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      capture.stop(); // before any expect that can fail
      expect(find.byType(MeasurementsCard), findsNothing);
      expect(find.byKey(_childKey), findsOneWidget);
      expect(capture.messages, isEmpty);
    });

    testWidgets('the child keeps its scroll offset when the body height '
        'crosses the card threshold (the shape never changes)', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      Widget at(double height) => app(
        history: hist(const []),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 360,
              height: height,
              child: MeasurementsCardFrame(
                child: ListView.builder(
                  controller: controller,
                  itemCount: 30,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 60, child: Text('$i')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(at(300)); // card shown
      await tester.pump();
      expect(find.byType(MeasurementsCard), findsOneWidget);
      controller.jumpTo(240);
      await tester.pump();
      await tester.pumpWidget(at(270)); // below 286: card gone
      await tester.pump();
      expect(find.byType(MeasurementsCard), findsNothing);
      expect(controller.offset, 240);
      await tester.pumpWidget(at(300)); // card back
      await tester.pump();
      expect(find.byType(MeasurementsCard), findsOneWidget);
      expect(controller.offset, 240);
    });
  });
}

class _Flag extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}
