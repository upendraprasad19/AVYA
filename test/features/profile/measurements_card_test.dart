// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md section 4.9): the FIRST test
// is a typography warmup that runs before any path_provider mock is installed;
// the mock lives in the groups below (setUpHiveForTests). Real Hive I/O inside a
// testWidgets body is escaped with tester.runAsync. Except for the two rows that
// need the REAL reader (the mount refresh), history is a FAKE notifier, so no
// Hive write happens in the fake-async zone.
@Timeout(Duration(minutes: 4))
library;

// L2b Landing C (E3): the "Body measurements" card on Progress comparison.
// Plan: docs/plans/coach-measurement-surfaces.md (C2, section 4).
//
// CLOCKS: every row pins the clock to 2031-06-15 20:00 UTC = 2031-06-16 01:30
// IST (the IST and UTC days differ) and dates its entries in 2031. A card that
// asked the device clock for "this year" would print the year on every tile
// today (the real clock is in 2026) and fail the literals below. No row turns
// red on the day the real clock reaches 2031: from then on a card that asked the
// device clock simply cannot be told apart by these literals, which is why the
// New Year row pins a clock whose IST year differs from its UTC year.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_prompt_provider.dart';
import 'package:icanbefitter/features/profile/widgets/body_measurements_sheet.dart';
import 'package:icanbefitter/features/profile/widgets/measurements_card.dart';

import '../../helpers/flutter_error_capture.dart';
import '../../helpers/hive_test_setup.dart';

class _FakeHistory extends BodyMeasurementsNotifier {
  _FakeHistory(this.script, this.builds);

  /// One state per build; the last one repeats. NOTE the mount refresh: the
  /// card invalidates the provider once after its first frame, so a mounted
  /// card consumes TWO builds before a test does anything (see [twice]).
  final List<BodyMeasurementsState> script;
  final List<int> builds;

  @override
  BodyMeasurementsState build() {
    final i = builds.length;
    builds.add(i);
    return script[i < script.length ? i : script.length - 1];
  }

  void set(BodyMeasurementsState s) => state = s;
}

class _FakeWrite extends MeasurementWriteNotifier {
  _FakeWrite({this.unit});

  final bool? unit;

  @override
  bool? lastUnitInches() => unit;
}

/// Counts the unit reads the tiles make.
class _CountingWrite extends MeasurementWriteNotifier {
  int reads = 0;

  @override
  bool preferredInches() {
    reads++;
    return false;
  }
}

/// The first state of a script built for a mounted card: the mount's own build
/// and the post-frame refresh both see it.
List<BodyMeasurementsState> twice(List<BodyMeasurementsState> script) => [
  script.first,
  ...script,
];

MeasurementEntry e(String date, Map<String, double> sites) =>
    MeasurementEntry(date: date, sites: sites);

/// State built the way the real reader builds it: `entries` and `latest`
/// filled together, so a card that read the wrong one could not pass by luck.
BodyMeasurementsState hist(List<MeasurementEntry> entries) =>
    BodyMeasurementsState(
      loaded: true,
      latest: HealthReadService.latestBySiteOf(entries),
      lastEntryDate: entries.isEmpty ? null : entries.first.date,
      entries: entries,
    );

const _unreadable = BodyMeasurementsState();

// Waist 81.0 -> 79.5 (down), chest 96.0 only once (no change line).
final _twoDays = hist([
  e('2031-06-10', {'waist': 79.5, 'chest': 96.0}),
  e('2031-05-20', {'waist': 81.0}),
]);

// One site per sign: up, down, equal, held once.
final _allSigns = hist([
  e('2031-06-10', {'chest': 97.5, 'waist': 79.5, 'hips': 100.0, 'arms': 33.0}),
  e('2031-05-20', {'chest': 96.0, 'waist': 81.0, 'hips': 100.0}),
]);

final class _Created extends ProviderObserver {
  final List<ProviderBase<Object?>> providers = [];

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    providers.add(context.provider);
  }

  bool saw(ProviderBase<Object?> p) => providers.contains(p);
}

/// The frame's own composition around the card, with the cap as a parameter.
Widget capped(double cap, {double width = 360}) => Align(
  alignment: Alignment.topCenter,
  child: SizedBox(
    width: width,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: cap),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          kCardMarginTop,
          AppSpacing.screenPadding,
          kCardMarginBottom,
        ),
        child: SizedBox(width: double.infinity, child: MeasurementsCard()),
      ),
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

  group('MeasurementsCard', () {
    late Directory dir;
    late List<int> builds;
    late _FakeHistory history;

    setUp(() async {
      dir = await setUpHiveForTests();
      // 2031-06-15 20:00 UTC = 2031-06-16 01:30 IST (see the file header).
      setTestClockTo(DateTime.utc(2031, 6, 15, 20));
      builds = [];
    });

    tearDown(() async {
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    Widget host(
      List<BodyMeasurementsState> script, {
      double cap = 320,
      double width = 360,
      double textScale = 1.0,
      bool? unit,
      ProviderObserver? observer,
    }) {
      return ProviderScope(
        observers: [?observer],
        overrides: [
          authUserIdTokenProvider.overrideWithValue(kTestUserId),
          bodyMeasurementsProvider.overrideWith(() {
            history = _FakeHistory(script, builds);
            return history;
          }),
          measurementWriteProvider.overrideWith(() => _FakeWrite(unit: unit)),
        ],
        child: MaterialApp(
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(
              ctx,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(body: capped(cap, width: width)),
        ),
      );
    }

    Future<void> mount(
      WidgetTester tester,
      List<BodyMeasurementsState> script, {
      double cap = 320,
      double width = 360,
      double textScale = 1.0,
      bool? unit,
      ProviderObserver? observer,
    }) async {
      await tester.pumpWidget(
        host(
          twice(script),
          cap: cap,
          width: width,
          textScale: textScale,
          unit: unit,
          observer: observer,
        ),
      );
      await tester.pump();
    }

    testWidgets('tiles: title with the day, value, and the change since the '
        'FIRST entry', (tester) async {
      await mount(tester, [_twoDays]);
      expect(find.text('BODY MEASUREMENTS'), findsOneWidget);
      expect(find.text('Add measurements'), findsOneWidget);
      expect(find.text('WAIST · 10 Jun'), findsOneWidget);
      expect(find.text('79.5 cm'), findsOneWidget);
      expect(find.text('-1.5 cm since 20 May'), findsOneWidget);
      expect(find.text('CHEST · 10 Jun'), findsOneWidget);
      expect(find.text('96.0 cm'), findsOneWidget);
      // chest was measured on one day only: no change line for it, and no
      // tile at all for the sites never measured.
      expect(find.textContaining('since'), findsOneWidget);
      expect(find.textContaining('HIPS'), findsNothing);
      expect(find.textContaining('ARMS'), findsNothing);
    });

    testWidgets('the change line is textDim for an increase, a decrease and no '
        'change (never green or red)', (tester) async {
      await mount(tester, [_allSigns]);
      Color? colorOf(String text) =>
          tester.widget<Text>(find.text(text)).style?.color;
      expect(colorOf('+1.5 cm since 20 May'), AppColors.textDim); // chest up
      expect(colorOf('-1.5 cm since 20 May'), AppColors.textDim); // waist down
      expect(colorOf('no change since 20 May'), AppColors.textDim); // hips
      // The value is the primary text colour and the title the dim one; neither
      // is a sign colour either.
      expect(colorOf('97.5 cm'), AppColors.textPrimary);
      expect(colorOf('CHEST · 10 Jun'), AppColors.textDim);
    });

    testWidgets('two-up grid: the first two tiles share a row, the next two '
        'start the second, each reads title over value over change', (
      tester,
    ) async {
      await mount(tester, [_allSigns], cap: 400);
      Rect r(String text) => tester.getRect(find.text(text));
      final chest = r('CHEST · 10 Jun');
      final waist = r('WAIST · 10 Jun');
      final hips = r('HIPS · 10 Jun');
      final arms = r('ARMS · 10 Jun');
      expect(waist.top, chest.top, reason: 'chest and waist share a row');
      expect(
        waist.left,
        greaterThan(chest.right - 1),
        reason: 'chest left of waist, not overlapping',
      );
      expect(arms.top, hips.top, reason: 'hips and arms share a row');
      expect(arms.left, greaterThan(hips.right - 1));
      expect(
        hips.top,
        greaterThan(r('+1.5 cm since 20 May').bottom - 1),
        reason: 'the second row starts below the first row\'s last line',
      );
      expect(hips.left, chest.left, reason: 'columns line up');
      // Inside a tile: title, then value, then the change.
      expect(r('97.5 cm').top, greaterThanOrEqualTo(chest.bottom));
      expect(
        r('+1.5 cm since 20 May').top,
        greaterThanOrEqualTo(r('97.5 cm').bottom),
      );
      // The two columns split the card's inner width: neither is wider than half.
      final inner = tester.getRect(find.byType(MeasurementsCard));
      expect(waist.left - chest.left, greaterThan(0));
      expect(
        waist.left - inner.left,
        greaterThan((inner.width - 8) / 2 - 1),
        reason: 'the second column starts at the half',
      );
    });

    testWidgets('an odd last tile stays in the left column', (tester) async {
      await mount(tester, [
        hist([
          e('2031-06-10', {'chest': 97.5, 'waist': 79.5, 'hips': 100.5}),
          e('2031-05-20', {'chest': 96.0, 'waist': 81.0, 'hips': 100.0}),
        ]),
      ], cap: 400);
      final chest = tester.getRect(find.text('CHEST · 10 Jun'));
      final waist = tester.getRect(find.text('WAIST · 10 Jun'));
      final hips = tester.getRect(find.text('HIPS · 10 Jun'));
      expect(waist.left, greaterThan(chest.left), reason: 'precondition');
      expect(hips.top, greaterThan(chest.top), reason: 'second row');
      expect(hips.left, chest.left, reason: 'the lone tile is not pushed right');
    });

    testWidgets('the year rule uses the IST day: 01:30 IST on 1 January prints '
        'last year\'s dates with their year', (tester) async {
      // 2031-12-31 20:00 UTC is 2032-01-01 01:30 IST: the UTC year is 2031.
      setTestClockTo(DateTime.utc(2031, 12, 31, 20));
      await mount(tester, [
        hist([
          e('2031-12-20', {'waist': 79.5}),
          e('2031-11-01', {'waist': 81.0}),
        ]),
      ]);
      expect(find.text('WAIST · 20 Dec 2031'), findsOneWidget);
      expect(find.text('-1.5 cm since 1 Nov 2031'), findsOneWidget);
    });

    testWidgets('an unreadable history shows the caption and Retry, never the '
        'empty state', (tester) async {
      await mount(tester, [_unreadable]);
      expect(find.text("Couldn't load your last entries"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // The header (and its door) is there in the error state too.
      expect(find.text('Add measurements'), findsOneWidget);
      expect(find.textContaining('WAIST'), findsNothing);
    });

    testWidgets('a loaded EMPTY history is the header and nothing below it', (
      tester,
    ) async {
      await mount(tester, [hist(const [])]);
      expect(find.text('BODY MEASUREMENTS'), findsOneWidget);
      expect(find.text('Add measurements'), findsOneWidget);
      expect(find.text("Couldn't load your last entries"), findsNothing);
      expect(find.text('Retry'), findsNothing);
      final texts = tester.widgetList<Text>(find.byType(Text)).length;
      expect(texts, 2, reason: 'only the eyebrow and the button label');
    });

    testWidgets('Retry reads again and the second read shows the tiles', (
      tester,
    ) async {
      await mount(tester, [_unreadable, _twoDays]);
      expect(find.text("Couldn't load your last entries"), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.text("Couldn't load your last entries"), findsNothing);
      expect(find.text('79.5 cm'), findsOneWidget);
    });

    testWidgets('a read that fails AFTER a good one drops the tiles to the '
        'error state', (tester) async {
      await mount(tester, [_twoDays]);
      expect(find.text('79.5 cm'), findsOneWidget);
      history.set(_unreadable);
      await tester.pump();
      expect(find.text("Couldn't load your last entries"), findsOneWidget);
      expect(find.text('79.5 cm'), findsNothing);
    });

    testWidgets('the card ignores the prompt and the dismissal: it never even '
        'creates the prompt provider', (tester) async {
      final created = _Created();
      await mount(tester, [_twoDays], observer: created);
      expect(find.text('79.5 cm'), findsOneWidget);
      expect(created.saw(bodyMeasurementsProvider), isTrue); // positive control
      expect(created.saw(measurementPromptProvider), isFalse);
    });

    for (final state in <String, BodyMeasurementsState>{
      'tiles': _twoDays,
      'empty': hist(const []),
      'error': _unreadable,
    }.entries) {
      testWidgets('the header button opens the sheet (${state.key})', (
        tester,
      ) async {
        await mount(tester, [state.value]);
        expect(find.byType(BodyMeasurementsSheet), findsNothing);
        await tester.tap(find.text('Add measurements'));
        await tester.pumpAndSettle();
        expect(find.byType(BodyMeasurementsSheet), findsOneWidget);
      });
    }

    for (final row in <({String name, bool? unit, String value, String delta})>[
      (
        name: 'remembered inches shows inches',
        unit: true,
        // 79.5 cm = 31.3 in; 81.0 cm = 31.9 in; the change is of the displays.
        value: '31.3 in',
        delta: '-0.6 in since 20 May',
      ),
      (
        name: 'remembered centimetres shows centimetres',
        unit: false,
        value: '79.5 cm',
        delta: '-1.5 cm since 20 May',
      ),
      (
        name: 'nothing remembered follows the device (metric here)',
        unit: null,
        value: '79.5 cm',
        delta: '-1.5 cm since 20 May',
      ),
    ]) {
      testWidgets('units: ${row.name}', (tester) async {
        await mount(tester, [_twoDays], unit: row.unit);
        expect(find.text(row.value), findsOneWidget);
        expect(find.text(row.delta), findsOneWidget);
        final other = row.value.endsWith(' in') ? '79.5 cm' : '31.3 in';
        expect(find.text(other), findsNothing);
      });
    }

    testWidgets('an account swap rebuilds from the new user and the anonymous '
        'window shows nothing (no caption, no Retry)', (tester) async {
      final token = NotifierProvider<_Token, String>(_Token.new);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserIdTokenProvider.overrideWith((ref) => ref.watch(token)),
            bodyMeasurementsProvider.overrideWith(_ByUser.new),
            measurementWriteProvider.overrideWith(
              () => _FakeWrite(unit: false),
            ),
          ],
          child: MaterialApp(home: Scaffold(body: capped(320))),
        ),
      );
      await tester.pump();
      expect(find.text('79.5 cm'), findsOneWidget); // user A

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MeasurementsCard)),
      );
      container.read(token.notifier).set('<anon>');
      await tester.pump();
      expect(find.text("Couldn't load your last entries"), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Add measurements'), findsNothing);
      expect(find.text('79.5 cm'), findsNothing);

      container.read(token.notifier).set('user-b');
      await tester.pump();
      await tester.pump();
      expect(find.text('70.0 cm'), findsOneWidget); // user B's own history
      expect(find.text('79.5 cm'), findsNothing);
    });

    testWidgets('compact: a cap below 200 dp shows the header and no tiles', (
      tester,
    ) async {
      await mount(tester, [_twoDays], cap: 199);
      expect(find.text('Add measurements'), findsOneWidget);
      expect(find.text('79.5 cm'), findsNothing);
      expect(find.text('WAIST · 10 Jun'), findsNothing);
    });

    testWidgets('the tiles appear exactly at a cap of 200 dp', (tester) async {
      await mount(tester, [_twoDays], cap: 200);
      expect(find.text('79.5 cm'), findsOneWidget);
    });

    testWidgets(
      'sizes: the header button is at least 48 dp, Retry at least 44',
      (tester) async {
        await mount(tester, [_unreadable]);
        final button = find.ancestor(
          of: find.text('Add measurements'),
          matching: find.byType(InkWell),
        );
        expect(tester.getSize(button.first).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(button.first).width, greaterThanOrEqualTo(48));
        final retry = find.widgetWithText(TextButton, 'Retry');
        expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(retry).width, greaterThanOrEqualTo(44));
      },
    );

    testWidgets('semantics: a tile is ONE node with the spoken sentence, and '
        'its visible texts are not announced again', (tester) async {
      final handle = tester.ensureSemantics();
      await mount(tester, [_twoDays]);
      expect(
        find.bySemanticsLabel(
          'Waist, 79.5 centimetres, measured 10 June. '
          'Down 1.5 centimetres since 20 May.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Chest, 96.0 centimetres, measured 10 June.'),
        findsOneWidget,
      );
      // No node carries the visual title or the visual value.
      expect(find.bySemanticsLabel(RegExp('WAIST · ')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('79.5 cm')), findsNothing);
      handle.dispose();
    });

    testWidgets('semantics: the header button is a button with the full label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await mount(tester, [_twoDays]);
      final node = tester.getSemantics(
        find.bySemanticsLabel('Add measurements'),
      );
      expect(node.flagsCollection.isButton, isTrue);
      // The button excludes its descendants' semantics, so its own tap action
      // is the only way a screen reader's double tap reaches it; this throws if
      // the node declares none.
      expect(find.byType(BodyMeasurementsSheet), findsNothing);
      tester.semantics.tap(find.semantics.byLabel('Add measurements'));
      await tester.pumpAndSettle();
      expect(find.byType(BodyMeasurementsSheet), findsOneWidget);
      handle.dispose();
    });

    // ── the header at a real phone width ───────────────────────────────────
    //
    // JetBrains Mono (the header's face) has a 0.6 em advance and a 1.32 em
    // line height, measured from the font file. The test font (Ahem) has a
    // 1.0 em advance, so a text scale of 0.6 gives Ahem exactly the real
    // advance (letter spacing is not scaled): 17 x (6 + 2) for the eyebrow and
    // 16 x (6 + 2) + 8 for the button = 272 dp, in the 282 dp a 360 dp phone
    // leaves between the card's padding. Line height is NOT modelled here (the
    // frame test's header floor adds it).
    testWidgets('header at 360 dp with the real 0.6 em advance: ONE run, the '
        'button flush right, centred on the eyebrow, 8 dp or more apart', (
      tester,
    ) async {
      await mount(tester, [hist(const [])], width: 360, textScale: 0.6);
      final eyebrow = tester.getRect(find.text('BODY MEASUREMENTS'));
      final label = tester.getRect(find.text('Add measurements'));
      final button = tester.getRect(
        find.ancestor(
          of: find.text('Add measurements'),
          matching: find.byType(InkWell),
        ),
      );
      final card = tester.getRect(find.byType(MeasurementsCard));
      // The card is the phone's width less the frame's 22 dp each side (316),
      // with a 1 dp border and 16 dp padding inside.
      expect(card.width, 360 - 2 * AppSpacing.screenPadding);
      expect(eyebrow.left, closeTo(card.left + 17, 0.5));
      expect(
        button.right,
        closeTo(card.right - 17, 0.5),
        reason: 'spaceBetween puts the button at the right edge',
      );
      expect(
        label.center.dy,
        closeTo(eyebrow.center.dy, 1),
        reason: 'one run: the label and the eyebrow share a line',
      );
      expect(
        button.left - eyebrow.right,
        greaterThanOrEqualTo(8),
        reason: 'a gap, so a slightly wider real glyph still fits',
      );
      expect(
        tester.widget<Text>(find.text('BODY MEASUREMENTS')).overflow,
        TextOverflow.ellipsis,
        reason: 'the eyebrow gives way before the button does',
      );
    });

    testWidgets('control: at the test font\'s own 1.0 em advance the same '
        'header wraps to two runs, so the row above can tell the difference', (
      tester,
    ) async {
      await mount(tester, [hist(const [])], width: 360, textScale: 1.0);
      final eyebrow = tester.getRect(find.text('BODY MEASUREMENTS'));
      final button = tester.getRect(
        find.ancestor(
          of: find.text('Add measurements'),
          matching: find.byType(InkWell),
        ),
      );
      expect(
        button.top,
        greaterThanOrEqualTo(eyebrow.bottom),
        reason: 'the label dropped under the eyebrow',
      );
    });

    testWidgets('the tile scroll view does not take the primary scroll '
        'controller (the list below it owns that)', (tester) async {
      final primary = ScrollController();
      addTearDown(primary.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserIdTokenProvider.overrideWithValue(kTestUserId),
            bodyMeasurementsProvider.overrideWith(
              () => _FakeHistory(twice([_allSigns]), builds),
            ),
            measurementWriteProvider.overrideWith(
              () => _FakeWrite(unit: false),
            ),
          ],
          child: MaterialApp(
            home: PrimaryScrollController(
              controller: primary,
              child: Scaffold(body: capped(320)),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text('97.5 cm'),
        findsOneWidget,
        reason: 'precondition: the tile region is mounted',
      );
      expect(primary.hasClients, isFalse);
    });

    // "Only a card with tiles to show reads a unit": the empty and the error
    // states build no tiles, so they read none and add no space below the
    // header (a built-but-empty tile region would add its 8 dp top padding).
    for (final state in <String, BodyMeasurementsState>{
      'a loaded empty history': hist(const []),
      'an unreadable history': _unreadable,
    }.entries) {
      testWidgets('${state.key}: no unit is read, and nothing but the header '
          'and (for the error) its caption is built', (tester) async {
        final write = _CountingWrite();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authUserIdTokenProvider.overrideWithValue(kTestUserId),
              bodyMeasurementsProvider.overrideWith(
                () => _FakeHistory(twice([state.value]), builds),
              ),
              measurementWriteProvider.overrideWith(() => write),
            ],
            child: MaterialApp(home: Scaffold(body: capped(320))),
          ),
        );
        await tester.pump();
        expect(find.text('Add measurements'), findsOneWidget,
            reason: 'precondition: the card is mounted');
        expect(write.reads, 0);
        if (state.value.loaded) {
          final header = tester.getSize(
            find.descendant(
              of: find.byType(MeasurementsCard),
              matching: find.byType(Wrap),
            ),
          );
          // card = padding 12 + 12, border 1 + 1, and the header: nothing more.
          expect(
            tester.getSize(find.byType(MeasurementsCard)).height,
            header.height + 26,
          );
        }
      });
    }

    testWidgets('the unit is read once per history state, not once per layout '
        'pass', (tester) async {
      final write = _CountingWrite();
      final cap = ValueNotifier<double>(320);
      addTearDown(cap.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserIdTokenProvider.overrideWithValue(kTestUserId),
            bodyMeasurementsProvider.overrideWith(() {
              history = _FakeHistory(twice([_twoDays]), builds);
              return history;
            }),
            measurementWriteProvider.overrideWith(() => write),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<double>(
                valueListenable: cap,
                builder: (_, v, _) => capped(v),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('79.5 cm'), findsOneWidget);
      expect(write.reads, 1, reason: 'the first tiles read it');
      for (final h in [330.0, 340.0, 350.0]) {
        cap.value = h; // a new constraint: the card's LayoutBuilder re-runs
        await tester.pump();
      }
      expect(find.text('79.5 cm'), findsOneWidget);
      expect(write.reads, 1, reason: 'layout passes do not read it again');
      history.set(
        hist([
          e('2031-06-12', {'waist': 79.0}),
        ]),
      );
      await tester.pump();
      expect(find.text('79.0 cm'), findsOneWidget);
      expect(write.reads, 2, reason: 'a new history state reads it again');
    });

    testWidgets('the tile region scrolls and the header does not move', (
      tester,
    ) async {
      // Four sites with a change line each at 2x text in a short cap: the tiles
      // are taller than the window the cap leaves them.
      await mount(tester, [_allSigns], cap: 210, textScale: 2.0);
      final scrollable = find.descendant(
        of: find.byType(MeasurementsCard),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      final state = tester.state<ScrollableState>(scrollable);
      expect(
        state.position.maxScrollExtent,
        greaterThan(0),
        reason: 'precondition: there is something to scroll',
      );
      final header = find.text('BODY MEASUREMENTS');
      final before = tester.getRect(header);
      final firstTile = tester.getRect(find.textContaining('CHEST'));
      await tester.drag(scrollable, const Offset(0, -80));
      await tester.pump();
      expect(tester.getRect(header), before);
      expect(
        tester.getRect(find.textContaining('CHEST')).top,
        lessThan(firstTile.top),
        reason: 'the tiles moved',
      );
    });

    testWidgets('two-up tiles at 320 dp and 2x text do not overflow', (
      tester,
    ) async {
      final capture = FlutterErrorCapture()..start();
      addTearDown(capture.stop);
      await mount(tester, [_allSigns], cap: 400, width: 320, textScale: 2.0);
      capture.stop(); // before any expect that can fail
      expect(find.text('CHEST · 10 Jun'), findsOneWidget);
      expect(capture.overflowsIn('measurements_card.dart'), isEmpty);
      expect(capture.others, isEmpty);
    });
  });

  group('MeasurementsCard against the real reader', () {
    late Directory dir;

    setUp(() async {
      dir = await setUpHiveForTests();
      setTestClockTo(DateTime.utc(2031, 6, 15, 20)); // 2031-06-16 01:30 IST
    });

    tearDown(() async {
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    testWidgets('mount refresh: an entry written since the provider last built '
        'appears without a Retry tap (built exactly twice)', (tester) async {
      var builds = 0;
      final container = ProviderContainer(
        overrides: [
          authUserIdTokenProvider.overrideWithValue(kTestUserId),
          bodyMeasurementsProvider.overrideWith(
            () => _Counting(() => builds++),
          ),
          measurementWriteProvider.overrideWith(() => _FakeWrite(unit: false)),
        ],
      );
      addTearDown(container.dispose);
      // The provider is built FIRST, over an empty box ...
      expect(container.read(bodyMeasurementsProvider).entries, isEmpty);
      expect(builds, 1);
      // ... then a record lands WITHOUT any invalidation (the Telegram pull).
      await tester.runAsync(() async {
        await HiveService.instance.healthBox.put('measurement_2031-06-10', {
          'date': '2031-06-10',
          'waist': 79.5,
        });
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: capped(320))),
        ),
      );
      await tester.pump();
      expect(find.text('79.5 cm'), findsOneWidget);
      expect(builds, 2);
    });

    testWidgets('the mount refresh is guarded: a card unmounted before its '
        'post-frame callback runs raises nothing', (tester) async {
      final container = ProviderContainer(
        overrides: [
          authUserIdTokenProvider.overrideWithValue(kTestUserId),
          measurementWriteProvider.overrideWith(() => _FakeWrite(unit: false)),
        ],
      );
      addTearDown(container.dispose);
      final hideable = GlobalKey<_HideableState>();
      // Registered BEFORE the card's own callback (initState registers that one
      // during the pump), so it runs first: it removes the card from the tree
      // synchronously, the way a frame in which the screen was popped would.
      tester.binding.addPostFrameCallback((_) {
        hideable.currentState!.hide();
        tester.binding.buildOwner!
          ..buildScope(tester.binding.rootElement!)
          ..finalizeTree();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: _Hideable(key: hideable, child: capped(320)),
            ),
          ),
        ),
      );
      expect(
        find.byType(MeasurementsCard),
        findsNothing,
        reason: 'precondition: the card was gone before its callback ran',
      );
      expect(tester.takeException(), isNull);
    });
  });
}

class _Hideable extends StatefulWidget {
  const _Hideable({super.key, required this.child});

  final Widget child;

  @override
  State<_Hideable> createState() => _HideableState();
}

class _HideableState extends State<_Hideable> {
  bool _shown = true;

  void hide() => setState(() => _shown = false);

  @override
  Widget build(BuildContext context) =>
      _shown ? widget.child : const SizedBox.shrink();
}

class _Token extends Notifier<String> {
  @override
  String build() => kTestUserId;

  void set(String v) => state = v;
}

/// Reads the token like the real notifier does and answers per user.
class _ByUser extends BodyMeasurementsNotifier {
  @override
  BodyMeasurementsState build() {
    final t = ref.watch(authUserIdTokenProvider);
    if (t == kTestUserId) {
      return hist([
        e('2031-06-10', {'waist': 79.5}),
      ]);
    }
    if (t == 'user-b') {
      return hist([
        e('2031-06-11', {'waist': 70.0}),
      ]);
    }
    return const BodyMeasurementsState();
  }
}

class _Counting extends BodyMeasurementsNotifier {
  _Counting(this.onBuild);

  final void Function() onBuild;

  @override
  BodyMeasurementsState build() {
    onBuild();
    return super.build();
  }
}
