// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md section 4.9): the first test
// is a typography warmup before any path_provider mock; Hive is set up per
// group. History is a FAKE notifier. The screen is the REAL one: with no
// Supabase initialised `StatSnapshotService.listAll` catches and returns an
// empty list, which is exactly the empty state this file needs (plan G2).
@Timeout(Duration(minutes: 4))
library;

// L2b Landing C (E3 host + C2b): Profile -> Progress comparison.
// Plan: docs/plans/coach-measurement-surfaces.md (C2, C2b, section 4).
//
// CLOCKS: pinned to 2031-06-15 20:00 UTC (2031-06-16 01:30 IST); entries dated
// 2031. The first date a literal here turns red is the day the real clock
// reaches 2031.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';
import 'package:icanbefitter/features/profile/screens/progress_comparison_screen.dart';
import 'package:icanbefitter/features/profile/widgets/measurements_card.dart';

import '../../helpers/dart_source_slice.dart';
import '../../helpers/flutter_error_capture.dart';
import '../../helpers/hive_test_setup.dart';

class _FakeHistory extends BodyMeasurementsNotifier {
  @override
  BodyMeasurementsState build() {
    final entries = [
      MeasurementEntry(date: '2031-06-10', sites: {'waist': 79.5}),
      MeasurementEntry(date: '2031-05-20', sites: {'waist': 81.0}),
    ];
    return BodyMeasurementsState(
      loaded: true,
      latest: HealthReadService.latestBySiteOf(entries),
      lastEntryDate: '2031-06-10',
      entries: entries,
    );
  }
}

class _FakeWrite extends MeasurementWriteNotifier {
  @override
  bool? lastUnitInches() => false;
}

const _emptyKey = ValueKey('progress_empty_scroll');

// The two strings of the empty state, as literals (the test does not read them
// back from the screen it checks).
const _emptyTitle = 'No snapshots yet';
const _emptyBody =
    'Your starting baseline is captured at onboarding. '
    'Promotion snapshots fire automatically as you climb the rank ladder. '
    'You can also tap "Take Snapshot" above to capture a manual checkpoint.';

/// The OLD empty state, verbatim (`Center > Padding > Column`), inside the
/// screen's own Scaffold and AppBar geometry: the oracle for "the same rects as
/// today" that does not compare the screen with itself.
class _OldEmptyScreen extends StatelessWidget {
  const _OldEmptyScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Progress comparison'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _emptyTitle,
                style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                _emptyBody,
                textAlign: TextAlign.center,
                style: AppTypography.bodyM.copyWith(color: AppColors.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// At 2x text and above the empty message is taller than the window it has:
/// precondition `maxScrollExtent > 0`, then a real drag moves it.
Future<void> _expectScrolls(WidgetTester tester, double scale) async {
  final scrollable = find.descendant(
    of: find.byKey(_emptyKey),
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsOneWidget);
  if (scale < 2.0) return;
  final position = tester.state<ScrollableState>(scrollable).position;
  expect(position.maxScrollExtent, greaterThan(0));
  final before = tester.getRect(find.text(_emptyTitle));
  await tester.drag(scrollable, const Offset(0, -80));
  await tester.pump();
  expect(
    tester.getRect(find.text(_emptyTitle)).top,
    lessThan(before.top),
    reason: 'the message moved with the drag',
  );
}

void main() {
  testWidgets('typography warmup - GoogleFonts caches before any Hive mock', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Text('a', style: AppTypography.h3),
              Text('b', style: AppTypography.bodyM),
              Text('c', style: AppTypography.bodyS),
              Text('d', style: AppTypography.titleS),
              Text('e', style: AppTypography.mono),
              Text('f', style: AppTypography.monoXs),
              Text('g', style: AppTypography.label),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('Progress comparison screen', () {
    late Directory dir;

    setUp(() async {
      dir = await setUpHiveForTests();
      setTestClockTo(DateTime.utc(2031, 6, 15, 20)); // 2031-06-16 01:30 IST
    });

    tearDown(() async {
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    void window(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    /// The app's own nesting: a shell Scaffold with an 80 dp bottom bar and a
    /// 24 dp status inset around the page.
    Widget app(Widget page, {bool flag = true, double textScale = 1.0}) {
      return ProviderScope(
        overrides: [
          authUserIdTokenProvider.overrideWithValue(kTestUserId),
          measurementsEnabledProvider.overrideWithValue(flag),
          bodyMeasurementsProvider.overrideWith(_FakeHistory.new),
          measurementWriteProvider.overrideWith(_FakeWrite.new),
        ],
        child: MaterialApp(
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(
              textScaler: TextScaler.linear(textScale),
              padding: const EdgeInsets.only(top: 24),
              viewPadding: const EdgeInsets.only(top: 24),
            ),
            child: child!,
          ),
          home: Scaffold(
            bottomNavigationBar: const SizedBox(height: 80),
            body: page,
          ),
        ),
      );
    }

    Future<void> openScreen(
      WidgetTester tester, {
      bool flag = true,
      double textScale = 1.0,
    }) async {
      window(tester);
      await tester.pumpWidget(
        app(const ProgressComparisonScreen(), flag: flag, textScale: textScale),
      );
      await tester.pump(); // the async load settles to the empty state
      await tester.pump();
    }

    testWidgets('ON: the card sits above the empty message', (tester) async {
      await openScreen(tester);
      expect(find.text(_emptyTitle), findsOneWidget);
      expect(find.byType(MeasurementsCard), findsOneWidget);
      expect(find.text('79.5 cm'), findsOneWidget);
      final card = tester.getRect(find.byType(MeasurementsCard));
      final message = tester.getRect(find.text(_emptyTitle));
      expect(card.bottom, lessThanOrEqualTo(message.top));
      expect(find.text('Take Snapshot'), findsOneWidget);
    });

    testWidgets('OFF: no card, and the empty message sits exactly where the '
        'OLD Center put it', (tester) async {
      await openScreen(tester, flag: false);
      expect(find.byType(MeasurementsCard), findsNothing);
      final newTitle = tester.getRect(find.text(_emptyTitle));
      final newBody = tester.getRect(find.text(_emptyBody));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(const _OldEmptyScreen()));
      await tester.pump();
      expect(tester.getRect(find.text(_emptyTitle)), newTitle);
      expect(tester.getRect(find.text(_emptyBody)), newBody);
    });

    // The screen's own AppBar (title column + the Take Snapshot action)
    // overflows to the right at 2x and 3x text in the wide test font, with the
    // flag OFF as well: PRE-EXISTING and not this landing's. So each row runs
    // the OFF screen first (the baseline), then the ON screen, and asserts that
    // ON adds no overflow message of its own, none from the card's file and
    // none on the bottom edge (a vertical overflow is the empty state's).
    for (final scale in [1.5, 2.0, 3.0]) {
      testWidgets('text x$scale: the empty state scrolls instead of '
          'overflowing, the card adds no overflow to the OFF baseline', (
        tester,
      ) async {
        final capture = FlutterErrorCapture()..start();
        addTearDown(capture.stop);
        // try / finally: addTearDown runs AFTER the binding's end-of-test check
        // of FlutterError.onError, so a failing expect while the capture is
        // installed leaves the next test hanging instead of failing cleanly.
        try {
          await openScreen(tester, flag: false, textScale: scale);
          final baseline = List<String>.of(capture.overflows);
          expect(capture.others, isEmpty, reason: capture.others.join('\n'));
          expect(
            baseline.where((m) => m.contains('bottom')),
            isEmpty,
            reason: 'the empty state must not overflow vertically (OFF)',
          );
          await _expectScrolls(tester, scale);

          capture.clear();
          await tester.pumpWidget(const SizedBox());
          await openScreen(tester, flag: true, textScale: scale);
          final onOverflows = List<String>.of(capture.overflows);
          final onOthers = List<String>.of(capture.others);
          final inCard = capture.overflowsIn('measurements_card');
          capture.stop(); // before any expect that can fail
          expect(onOthers, isEmpty, reason: onOthers.join('\n'));
          expect(inCard, isEmpty);
          expect(
            onOverflows.where((m) => m.contains('bottom')),
            isEmpty,
            reason: 'the empty state must not overflow vertically (ON)',
          );
          expect(
            onOverflows.every(baseline.contains),
            isTrue,
            reason:
                'ON added an overflow the OFF baseline does not have: '
                '${onOverflows.where((m) => !baseline.contains(m))}',
          );
          await _expectScrolls(tester, scale);
        } finally {
          capture.stop();
        }
      });
    }

    testWidgets('the OLD empty state overflowed at x3 text (the precondition '
        'C2b fixes)', (tester) async {
      final capture = FlutterErrorCapture()..start();
      addTearDown(capture.stop);
      window(tester);
      await tester.pumpWidget(
        app(const _OldEmptyScreen(), flag: false, textScale: 3.0),
      );
      await tester.pump();
      capture.stop(); // before any expect that can fail
      expect(capture.overflows, isNotEmpty);
    });
  });

  group('host line (presence only)', () {
    // Presence-only: the real screen is pumped above, but a mutant that keeps
    // the frame and drops it from the host cannot be told apart from the OFF
    // flag by behaviour alone, so the one host line is also pinned in source.
    // This file is the ONE home of this pin.
    test('exactly one MeasurementsCardFrame(child: _buildBody()) is the '
        "Scaffold's body", () {
      final src = stripDartComments(
        File(
          'lib/features/profile/screens/progress_comparison_screen.dart',
        ).readAsStringSync(),
      );
      expect(
        countOf(src, 'body: MeasurementsCardFrame(child: _buildBody())'),
        1,
      );
      expect(countOf(src, 'MeasurementsCardFrame('), 1);
      expect(countOf(src, 'body: _buildBody()'), 0);
    });
  });
}
