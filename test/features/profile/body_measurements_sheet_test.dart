// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md section 4.9 "A widget test
// that mocks path_provider makes GoogleFonts fail LOUDLY"): the FIRST test below
// is a typography warmup that runs BEFORE any path_provider mock is installed
// (the mock is scoped to the groups below, each with its own setUp / tearDown).
// GoogleFonts caches per family + weight, so the warmup renders every style the
// sheet uses. Reference: test/widgets/day_swap_allowance_line_test.dart.
//
// Real Hive I/O inside a testWidgets body is escaped with tester.runAsync (a
// put started in the fake-async zone never completes). Everything except the
// one end-to-end test uses FAKE history and write notifiers, so no Hive write
// happens in the fake zone at all.
@Timeout(Duration(minutes: 4))
library;

// L2b Landing B (B4) - the body-measurements sheet. Plan:
// docs/plans/coach-measurement-sheet-ui.md (B4, section 4).

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/body_measurement_specs.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/widgets/body_measurements_sheet.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../../helpers/hive_test_setup.dart';

class _FakeHistory extends BodyMeasurementsNotifier {
  _FakeHistory(this.script, this.builds);

  /// One state per build; the last one repeats.
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
  final List<({Map<String, double> sites, bool inches, WriteSource source})>
  calls = [];
  Completer<WriteResult>? gate;
  WriteResult result = WriteResult.ok('measurement_2026-10-12');
  void Function()? afterWrite;

  @override
  Future<WriteResult> save({
    required Map<String, double> sites,
    required WriteSource source,
    required bool inchesUsed,
  }) async {
    calls.add((sites: Map.of(sites), inches: inchesUsed, source: source));
    if (gate != null) await gate!.future;
    afterWrite?.call();
    return result;
  }

  @override
  bool? lastUnitInches() => unit;
}

class _ThrowingUnitWrite extends _FakeWrite {
  @override
  bool? lastUnitInches() => throw StateError('corrupt unit');
}

BodyMeasurementsState known(
  Map<String, double> cmBySite, {
  String date = '2026-09-12',
}) {
  return BodyMeasurementsState(
    loaded: true,
    latest: {
      for (final e in cmBySite.entries) e.key: (cm: e.value, date: date),
    },
    lastEntryDate: cmBySite.isEmpty ? null : date,
  );
}

/// WCAG relative luminance and contrast ratio, for the "functional text meets
/// AA" row.
double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final l1 = _luminance(a);
  final l2 = _luminance(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

const _empty = BodyMeasurementsState(loaded: true);
const _unreadable = BodyMeasurementsState();

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
              Text('e', style: AppTypography.label),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('BodyMeasurementsSheet', () {
    late Directory dir;
    late _FakeWrite write;
    late List<int> historyBuilds;

    setUp(() async {
      dir = await setUpHiveForTests();
      setTestClockTo(DateTime.utc(2026, 10, 12, 6)); // 11:30 IST on 2026-10-12
      write = _FakeWrite();
      historyBuilds = [];
    });

    tearDown(() async {
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    Widget host(
      List<BodyMeasurementsState> script, {
      _FakeWrite? w,
      double textScale = 1.0,
      Size? mediaSize,
    }) {
      if (w != null) write = w; // the test asserts on `write.calls`
      final fakeWrite = write;
      return ProviderScope(
        overrides: [
          authUserIdTokenProvider.overrideWithValue(kTestUserId),
          bodyMeasurementsProvider.overrideWith(
            () => _FakeHistory(script, historyBuilds),
          ),
          measurementWriteProvider.overrideWith(() => fakeWrite),
        ],
        child: MaterialApp(
          builder: (ctx, child) {
            var mq = MediaQuery.of(
              ctx,
            ).copyWith(textScaler: TextScaler.linear(textScale));
            Widget content = child!;
            if (mediaSize != null) {
              // The shell hands the sheet a SMALLER box (the body above the
              // keyboard and the bar) with no inset: lay the whole app out in
              // that box, so the modal route really gets those constraints.
              mq = mq.copyWith(size: mediaSize, viewInsets: EdgeInsets.zero);
              content = Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(size: mediaSize, child: child),
              );
            }
            return MediaQuery(data: mq, child: content);
          },
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => BodyMeasurementsSheet.show(ctx),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> open(WidgetTester tester, Widget app) async {
      await tester.pumpWidget(app);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Finder field(int i) =>
        find.byType(TextField).at(i); // chest waist hips arms

    Finder saveButton() => find.widgetWithText(ElevatedButton, 'SAVE');

    Future<void> tapSave(WidgetTester tester) async {
      await tester.ensureVisible(saveButton());
      await tester.tap(saveButton());
      await tester.pumpAndSettle();
    }

    Future<void> blur(WidgetTester tester, int i) async {
      // Move focus to another field: the blur listener marks the row touched.
      final other = i == 3 ? 0 : i + 1;
      await tester.ensureVisible(field(other));
      await tester.tap(field(other));
      await tester.pump();
    }

    Finder unitOption(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(InkWell));

    /// A hint sits under its field: scroll it into view first.
    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.pump();
      await tester.tap(find.text(text));
      await tester.pump();
    }

    /// The unit control scrolls with the sheet content, so bring it back into
    /// view before tapping (a lower field's ensureVisible scrolls it away).
    Future<void> tapUnit(WidgetTester tester, String label) async {
      await tester.ensureVisible(unitOption(label));
      await tester.pump();
      await tester.tap(unitOption(label));
      await tester.pump();
    }

    // ── the shape of the sheet ─────────────────────────────────────────────

    testWidgets('four rows in registry order with label and guide, the eyebrow '
        'and the first-entry intro; Save is disabled until a row has text', (
      tester,
    ) async {
      await open(tester, host([_empty]));
      expect(find.text('BODY MEASUREMENTS'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(4));
      for (final site in ['chest', 'waist', 'hips', 'arms']) {
        final spec = kBodyMeasurementSpecs[site]!;
        expect(find.text(spec.label), findsOneWidget, reason: site);
        expect(find.text(spec.guide), findsOneWidget, reason: site);
      }
      expect(
        find.textContaining('Four numbers give your coach a baseline'),
        findsOneWidget,
      );
      // The shipped words, as literals (the loop above compares the widget with
      // the spec, which would follow a changed string).
      for (final line in [
        'Around the fullest part of your chest, tape level under your arms.',
        'Around your natural waist, just above the navel, after a normal exhale.',
        'Around the widest part of your hips, feet together.',
        'Around the middle of your upper arm, relaxed, halfway from shoulder to elbow.',
      ]) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      expect(tester.widget<ElevatedButton>(saveButton()).onPressed, isNull);
      await tester.enterText(field(1), '80');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(saveButton()).onPressed, isNotNull);
      await tester.enterText(field(1), '');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(saveButton()).onPressed, isNull);
    });

    testWidgets('once an entry exists the intro changes and a field is never '
        'prefilled', (tester) async {
      await open(
        tester,
        host([
          known({'waist': 81.0}),
        ]),
      );
      expect(
        find.textContaining('Four numbers give your coach a baseline'),
        findsNothing,
      );
      expect(
        find.text('Fill in only what you measured today.'),
        findsOneWidget,
      );
      for (var i = 0; i < 4; i++) {
        expect(
          tester.widget<TextField>(field(i)).controller!.text,
          isEmpty,
          reason: 'field $i',
        );
      }
    });

    testWidgets('hints: the last value per site with its short date, in '
        'centimetres; none for a site without an entry', (tester) async {
      final s = BodyMeasurementsState(
        loaded: true,
        latest: {
          'waist': (cm: 81.0, date: '2026-09-12'),
          'arms': (cm: 33.5, date: '2025-12-30'),
        },
        lastEntryDate: '2026-09-12',
      );
      await open(tester, host([s], w: _FakeWrite(unit: false)));
      expect(find.text('Last: 81.0 cm · 12 Sep'), findsOneWidget);
      expect(
        find.text('Last: 33.5 cm · 30 Dec 2025'),
        findsOneWidget,
        reason: 'another year carries the year',
      );
      expect(find.textContaining('Last:'), findsNWidgets(2));
    });

    // The group's clock (2026-10-12) is also the REAL date on the day this file
    // was written, so a sheet that read `DateTime.now()` for "today" instead of
    // the clock seam passed every row above (B-pass mutant MUT-34). This row
    // moves the clock to a year the real clock is not in, so the in-year / year
    // suffix decision can only come from the seam.
    testWidgets('hints take "today" from the clock seam, not from the device '
        'clock: the year suffix follows the moved clock', (tester) async {
      setTestClockTo(DateTime.utc(2031, 5, 4, 6)); // 11:30 IST on 2031-05-04
      final s = BodyMeasurementsState(
        loaded: true,
        latest: {
          'waist': (cm: 81.0, date: '2031-02-03'),
          'arms': (cm: 33.5, date: '2026-09-12'),
        },
        lastEntryDate: '2031-02-03',
      );
      await open(tester, host([s], w: _FakeWrite(unit: false)));
      expect(find.text('Last: 81.0 cm · 3 Feb'), findsOneWidget);
      expect(find.text('Last: 33.5 cm · 12 Sep 2026'), findsOneWidget);
    });

    testWidgets('hints in inch mode add the inch value after the centimetre '
        'one', (tester) async {
      await open(
        tester,
        host([
          known({'waist': 81.0}),
        ], w: _FakeWrite(unit: true)),
      );
      expect(find.text('Last: 81.0 cm · 31.9 in · 12 Sep'), findsOneWidget);
    });

    // ── the unit story ──────────────────────────────────────────────────────

    testWidgets('75 in waist: valid in centimetres; switching to inches '
        'rereads it as 190.5 cm and never rewrites the digits', (tester) async {
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      await tester.enterText(field(1), '75');
      await tester.pump();
      await blur(tester, 1);
      expect(find.textContaining('Between'), findsNothing);
      expect(find.textContaining('= '), findsNothing, reason: 'cm mode');

      await tapUnit(tester, 'IN');
      await tester.pump();
      expect(tester.widget<TextField>(field(1)).controller!.text, '75');
      expect(find.text('= 190.5 cm'), findsOneWidget);
      expect(find.textContaining('Between'), findsNothing);

      await tapUnit(tester, 'CM');
      await tester.pump();
      expect(tester.widget<TextField>(field(1)).controller!.text, '75');
      expect(find.textContaining('= '), findsNothing);
    });

    testWidgets('arms 70: valid in centimetres, out of range in inches with a '
        'centimetres hint that switches back', (tester) async {
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      await tester.enterText(field(3), '70');
      await tester.pump();
      await blur(tester, 3);
      expect(find.textContaining('Between'), findsNothing);

      await tapUnit(tester, 'IN');
      await tester.pump();
      expect(find.text('Between 7.9 and 27.5 in'), findsOneWidget);
      expect(find.text('Looks like centimetres · switch?'), findsOneWidget);
      expect(
        find.textContaining('= '),
        findsNothing,
        reason: 'an invalid inch value has no stored-as line',
      );

      await tapText(tester, 'Looks like centimetres · switch?');
      expect(find.textContaining('Between'), findsNothing);
      expect(find.textContaining('switch?'), findsNothing);
      expect(tester.widget<TextField>(field(3)).controller!.text, '70');
    });

    testWidgets('34 in the waist field in centimetres: Save shows the range '
        'and an inches hint and writes nothing; the hint switches, the digits '
        'stay and the stored value is 86.4 cm', (tester) async {
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      await tester.enterText(field(1), '34');
      await tester.pump();
      expect(
        find.textContaining('Between'),
        findsNothing,
        reason: 'not before blur or Save',
      );
      expect(
        find.textContaining('switch?'),
        findsNothing,
        reason: 'the hint waits for the problem to be shown as well',
      );

      await tapSave(tester);
      expect(write.calls, isEmpty);
      expect(find.text('Between 50 and 200 cm'), findsOneWidget);
      expect(find.text('Looks like inches · switch?'), findsOneWidget);

      await tapText(tester, 'Looks like inches · switch?');
      expect(tester.widget<TextField>(field(1)).controller!.text, '34');
      expect(find.text('= 86.4 cm'), findsOneWidget);
      expect(find.textContaining('Between'), findsNothing);

      await tapSave(tester);
      expect(write.calls, hasLength(1));
      expect(write.calls.single.sites, {'waist': 86.4});
      expect(write.calls.single.inches, isTrue);
    });

    // L2b Landing C: the sheet's opening unit is `preferredInches()`, the one
    // expression the Progress comparison card also uses.
    testWidgets('nothing remembered and an imperial device: the sheet opens in '
        'inches', (tester) async {
      await tester.runAsync(
        () => HiveService.instance.configBox.put('units_metric', false),
      );
      await open(tester, host([_empty], w: _FakeWrite()));
      expect(find.text('in'), findsNWidgets(4));
      expect(find.text('cm'), findsNothing);
    });

    testWidgets('nothing remembered and a metric device: the sheet opens in '
        'centimetres', (tester) async {
      await open(tester, host([_empty], w: _FakeWrite()));
      expect(find.text('cm'), findsNWidgets(4));
      expect(find.text('in'), findsNothing);
    });

    testWidgets('a remembered unit beats the device setting', (tester) async {
      await tester.runAsync(
        () => HiveService.instance.configBox.put('units_metric', false),
      );
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      expect(find.text('cm'), findsNWidgets(4));
    });

    testWidgets(
      'a throwing unit read does not stop the sheet opening: it opens '
      'in centimetres, even on an imperial device',
      (tester) async {
        await tester.runAsync(
          () => HiveService.instance.configBox.put('units_metric', false),
        );
        await open(tester, host([_empty], w: _ThrowingUnitWrite()));
        expect(find.byType(BodyMeasurementsSheet), findsOneWidget);
        expect(find.text('cm'), findsNWidgets(4));
      },
    );

    testWidgets('80 in the waist field in inches is above 78.7: message and a '
        'centimetres hint; the hint switches to centimetres', (tester) async {
      await open(tester, host([_empty], w: _FakeWrite(unit: true)));
      await tester.enterText(field(1), '80');
      await tester.pump();
      await blur(tester, 1);
      expect(find.text('Between 19.7 and 78.7 in'), findsOneWidget);
      await tapText(tester, 'Looks like centimetres · switch?');
      expect(find.textContaining('Between'), findsNothing);
      expect(find.text('cm'), findsNWidgets(4), reason: 'suffix is now cm');
    });

    testWidgets('60 in the waist field is valid in both units: no hint in '
        'either', (tester) async {
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      await tester.enterText(field(1), '60');
      await tester.pump();
      await blur(tester, 1);
      expect(find.textContaining('switch?'), findsNothing);
      await tapUnit(tester, 'IN');
      await tester.pump();
      expect(find.textContaining('switch?'), findsNothing);
    });

    testWidgets('a lone "." and an over-range value are invalid with the range '
        'message; no hint when the other unit would not take it either', (
      tester,
    ) async {
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      await tester.enterText(field(1), '.');
      await tester.enterText(field(0), '999.9');
      await tester.pump();
      await tapSave(tester);
      expect(write.calls, isEmpty);
      expect(find.text('Between 50 and 200 cm'), findsOneWidget); // waist
      expect(find.text('Between 60 and 200 cm'), findsOneWidget); // chest
      expect(find.textContaining('switch?'), findsNothing);
    });

    testWidgets('typing is filtered to a leading digit prefix with at most one '
        'decimal: 1234.56 keeps 1234 (the range check rejects it), 82.37 keeps '
        '82.3 and letters never enter', (tester) async {
      await open(tester, host([_empty]));
      await tester.enterText(field(1), '1234.56');
      await tester.pump();
      expect(tester.widget<TextField>(field(1)).controller!.text, '1234');
      await tester.enterText(field(1), '82.37');
      await tester.pump();
      expect(tester.widget<TextField>(field(1)).controller!.text, '82.3');
      await tester.enterText(field(1), 'abc');
      await tester.pump();
      expect(tester.widget<TextField>(field(1)).controller!.text, '');
    });

    // ── Save ────────────────────────────────────────────────────────────────

    testWidgets('an invalid row blocks the whole Save, shows EVERY invalid '
        "row's message and focuses the first invalid one", (tester) async {
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      await tester.enterText(field(0), '100'); // valid
      await tester.enterText(field(1), '30'); // invalid
      // Arms is set on the controller, so that field is never focused and never
      // blurred: only the Save tap can make its message appear (typing into it
      // and moving focus would mark it touched by itself).
      tester.widget<TextField>(field(3)).controller!.text = '90'; // invalid
      await tester.pump();
      await tapSave(tester);
      expect(write.calls, isEmpty);
      expect(find.text('Between 50 and 200 cm'), findsOneWidget);
      expect(find.text('Between 20 and 70 cm'), findsOneWidget);
      expect(tester.widget<TextField>(field(1)).focusNode!.hasFocus, isTrue);
      expect(tester.widget<TextField>(field(3)).focusNode!.hasFocus, isFalse);
    });

    testWidgets('a save sends the centimetre values, manual source, the unit '
        'used, then pops and says "Baseline set" for one new site on a known '
        'empty history', (tester) async {
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      await tester.enterText(field(1), '79.5');
      await tester.pump();
      await tapSave(tester);
      expect(write.calls, hasLength(1));
      expect(write.calls.single.sites, {'waist': 79.5});
      expect(write.calls.single.inches, isFalse);
      expect(write.calls.single.source, WriteSource.manual);
      expect(find.byType(BodyMeasurementsSheet), findsNothing);
      expect(find.text('Baseline set ✓'), findsOneWidget);
    });

    testWidgets('four new sites say "Baseline set" too (the baseline prompt '
        'invites several at once)', (tester) async {
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      await tester.enterText(field(0), '100');
      await tester.enterText(field(1), '80');
      await tester.enterText(field(2), '95');
      await tester.enterText(field(3), '33');
      await tester.pump();
      await tapSave(tester);
      expect(write.calls.single.sites, {
        'chest': 100.0,
        'waist': 80.0,
        'hips': 95.0,
        'arms': 33.0,
      });
      expect(find.text('Baseline set ✓'), findsOneWidget);
    });

    testWidgets('one held site changed: the neutral delta in centimetres, '
        'taken from the value BEFORE the write', (tester) async {
      final w = _FakeWrite(unit: false);
      late _FakeHistory h;
      await open(
        tester,
        ProviderScope(
          overrides: [
            authUserIdTokenProvider.overrideWithValue(kTestUserId),
            bodyMeasurementsProvider.overrideWith(() {
              h = _FakeHistory([
                known({'waist': 81.0}),
              ], historyBuilds);
              return h;
            }),
            measurementWriteProvider.overrideWith(() => w),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => BodyMeasurementsSheet.show(ctx),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      // The write refreshes the history to the NEW value before returning, as
      // the real notifier does; a read after the await would print "79.5 -> 79.5".
      w.afterWrite = () => h.set(known({'waist': 79.5}, date: '2026-10-12'));
      await tester.enterText(field(1), '79.5');
      await tester.pump();
      await tapSave(tester);
      expect(find.text('Waist 81.0 → 79.5 cm'), findsOneWidget);
    });

    testWidgets('the delta is in centimetres even when the entry was typed in '
        'inches', (tester) async {
      await open(
        tester,
        host([
          known({'waist': 81.0}),
        ], w: _FakeWrite(unit: true)),
      );
      await tester.enterText(field(1), '31.5'); // 80.0 cm
      await tester.pump();
      await tapSave(tester);
      expect(write.calls.single.sites, {'waist': 80.0});
      expect(find.text('Waist 81.0 → 80.0 cm'), findsOneWidget);
    });

    testWidgets('a mixed edit (one held, one new site), several held sites, '
        'and an unreadable history all give the plain line', (tester) async {
      // mixed
      await open(
        tester,
        host([
          known({'waist': 81.0}),
        ], w: _FakeWrite(unit: false)),
      );
      await tester.enterText(field(1), '80');
      await tester.enterText(field(3), '33');
      await tester.pump();
      await tapSave(tester);
      expect(find.text('Measurements saved ✓'), findsOneWidget);
      expect(find.textContaining('→'), findsNothing);
      expect(find.textContaining('Baseline'), findsNothing);
    });

    testWidgets('several held sites give the plain line', (tester) async {
      await open(
        tester,
        host([
          known({'waist': 81.0, 'hips': 96.0}),
        ], w: _FakeWrite(unit: false)),
      );
      await tester.enterText(field(1), '80');
      await tester.enterText(field(2), '95');
      await tester.pump();
      await tapSave(tester);
      expect(find.text('Measurements saved ✓'), findsOneWidget);
    });

    testWidgets('an unreadable history gives the plain line, not "Baseline '
        'set", and shows the error caption with Retry', (tester) async {
      await open(tester, host([_unreadable], w: _FakeWrite(unit: false)));
      expect(find.text("Couldn't load your last entries"), findsOneWidget);
      expect(
        find.textContaining('Four numbers give your coach a baseline'),
        findsNothing,
        reason: 'an unreadable history is not "never measured"',
      );
      expect(
        find.text('Fill in only what you measured today.'),
        findsOneWidget,
      );
      await tester.enterText(field(1), '80');
      await tester.pump();
      await tapSave(tester);
      expect(find.text('Measurements saved ✓'), findsOneWidget);
      expect(find.textContaining('Baseline'), findsNothing);
    });

    testWidgets('the saved line is one line', (tester) async {
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      await tester.enterText(field(1), '80');
      await tester.pump();
      await tapSave(tester);
      final text = tester.widget<Text>(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
      );
      expect(text.data!.contains('\n'), isFalse);
    });

    testWidgets('a failed save keeps the sheet open with a message and the '
        'sheet is savable again (the guard is reset)', (tester) async {
      write = _FakeWrite(unit: false)..result = WriteResult.fail('boom');
      await open(tester, host([_empty]));
      await tester.enterText(field(1), '80');
      await tester.pump();
      await tapSave(tester);
      expect(find.byType(BodyMeasurementsSheet), findsOneWidget);
      expect(find.text("Couldn't save. Try again."), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tapSave(tester);
      expect(write.calls, hasLength(2), reason: 'the second tap reached save');
    });

    testWidgets('a second tap while the first save is in flight is ignored', (
      tester,
    ) async {
      write = _FakeWrite(unit: false)..gate = Completer<WriteResult>();
      await open(tester, host([_empty]));
      await tester.enterText(field(1), '80');
      await tester.pump();
      await tester.ensureVisible(saveButton());
      await tester.tap(saveButton());
      await tester.tap(saveButton()); // same frame: reaches the guard
      await tester.pump();
      expect(write.calls, hasLength(1));
      write.gate!.complete(WriteResult.ok('k'));
      await tester.pumpAndSettle();
      expect(write.calls, hasLength(1));
      expect(find.byType(BodyMeasurementsSheet), findsNothing);
    });

    testWidgets('the sheet swiped away while a save is pending: no pop, no '
        'SnackBar, no exception when the save completes', (tester) async {
      write = _FakeWrite(unit: false)..gate = Completer<WriteResult>();
      await open(tester, host([_empty]));
      await tester.enterText(field(1), '80');
      await tester.pump();
      await tester.ensureVisible(saveButton());
      await tester.tap(saveButton());
      await tester.pump();
      expect(write.calls, hasLength(1));
      // The user dismisses the modal.
      final ctx = tester.element(find.byType(BodyMeasurementsSheet));
      Navigator.of(ctx).pop();
      await tester.pumpAndSettle();
      expect(find.byType(BodyMeasurementsSheet), findsNothing);
      write.gate!.complete(WriteResult.ok('k'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsNothing);
    });

    // ── error state ─────────────────────────────────────────────────────────

    testWidgets('Retry rebuilds the history provider and a good read clears '
        'the caption', (tester) async {
      await open(
        tester,
        host([
          _unreadable,
          known({'waist': 81.0}),
        ]),
      );
      expect(find.text("Couldn't load your last entries"), findsOneWidget);
      expect(find.textContaining('Last:'), findsNothing);
      expect(historyBuilds, hasLength(1));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(historyBuilds, hasLength(2), reason: 'a second build');
      expect(find.text("Couldn't load your last entries"), findsNothing);
      expect(find.textContaining('Last:'), findsOneWidget);
    });

    // ── default unit ────────────────────────────────────────────────────────

    testWidgets('default unit: a remembered inches choice wins over a metric '
        'device setting', (tester) async {
      await tester.runAsync(() => UserRepository.instance.setUnitsMetric(true));
      await open(tester, host([_empty], w: _FakeWrite(unit: true)));
      expect(find.text('in'), findsNWidgets(4));
    });

    testWidgets('default unit: a remembered centimetres choice wins over an '
        'imperial device setting', (tester) async {
      await tester.runAsync(
        () => UserRepository.instance.setUnitsMetric(false),
      );
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      expect(find.text('cm'), findsNWidgets(4));
    });

    testWidgets('default unit: nothing remembered follows the device setting', (
      tester,
    ) async {
      await tester.runAsync(
        () => UserRepository.instance.setUnitsMetric(false),
      );
      await open(tester, host([_empty], w: _FakeWrite(unit: null)));
      expect(find.text('in'), findsNWidgets(4), reason: 'imperial device');
    });

    testWidgets('default unit: nothing remembered and a metric device is '
        'centimetres', (tester) async {
      await open(tester, host([_empty], w: _FakeWrite(unit: null)));
      expect(find.text('cm'), findsNWidgets(4));
    });

    // ── tap targets, keyboard actions ───────────────────────────────────────

    testWidgets('Save, the unit options and the Retry button are at least 44 '
        'dp; the "switch?" hint too', (tester) async {
      await open(tester, host([_unreadable], w: _FakeWrite(unit: false)));
      expect(tester.getSize(saveButton()).height, greaterThanOrEqualTo(44));
      for (final label in ['CM', 'IN']) {
        final size = tester.getSize(unitOption(label).first);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
      }
      final retry = tester.getSize(find.widgetWithText(TextButton, 'Retry'));
      expect(retry.height, greaterThanOrEqualTo(44));
      expect(retry.width, greaterThanOrEqualTo(44));

      await tester.enterText(field(1), '34');
      await tester.pump();
      await tapSave(tester);
      final hint = tester.getSize(
        find
            .ancestor(
              of: find.text('Looks like inches · switch?'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(hint.height, greaterThanOrEqualTo(44));
    });

    testWidgets('the first three fields offer Next and the last offers Done', (
      tester,
    ) async {
      await open(tester, host([_empty]));
      final actions = [
        for (var i = 0; i < 4; i++)
          tester.widget<TextField>(field(i)).textInputAction,
      ];
      expect(actions, [
        TextInputAction.next,
        TextInputAction.next,
        TextInputAction.next,
        TextInputAction.done,
      ]);
    });

    testWidgets('nothing in the sheet is behind a paywall or a PRO label', (
      tester,
    ) async {
      await open(tester, host([_empty]));
      expect(find.textContaining('PRO'), findsNothing);
      expect(find.textContaining('Upgrade'), findsNothing);
    });

    // ── properties no other row reads ────────────────────────────────────────

    testWidgets('the fields open the decimal keypad', (tester) async {
      await open(tester, host([_empty]));
      for (var i = 0; i < 4; i++) {
        expect(
          tester.widget<TextField>(field(i)).keyboardType,
          const TextInputType.numberWithOptions(decimal: true),
          reason: 'field $i',
        );
      }
    });

    testWidgets('Save is accent when enabled and input-coloured when '
        'disabled', (tester) async {
      await open(tester, host([_empty]));
      final style = tester.widget<ElevatedButton>(saveButton()).style!;
      expect(
        style.backgroundColor!.resolve({WidgetState.disabled}),
        AppColors.input,
      );
      expect(
        style.foregroundColor!.resolve({WidgetState.disabled}),
        AppColors.textDim,
      );
      expect(style.backgroundColor!.resolve(<WidgetState>{}), AppColors.accent);
    });

    testWidgets('the active unit is the highlighted one, and the highlight '
        'follows a switch', (tester) async {
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      Color? colorOf(String label) =>
          tester.widget<Text>(find.text(label)).style!.color;
      expect(colorOf('CM'), AppColors.accent);
      expect(colorOf('IN'), AppColors.textDim);
      await tapUnit(tester, 'IN');
      await tester.pump();
      expect(colorOf('IN'), AppColors.accent);
      expect(colorOf('CM'), AppColors.textDim);
    });

    testWidgets('a successful save fires ONE light impact and a failed one '
        'none', (tester) async {
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      write = _FakeWrite(unit: false)..result = WriteResult.fail('boom');
      await open(tester, host([_empty]));
      await tester.enterText(field(1), '80');
      await tester.pump();
      await tapSave(tester);
      expect(haptics, isEmpty, reason: 'a failed save is silent');

      write.result = WriteResult.ok('measurement_2026-10-12');
      await tapSave(tester);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('the "Last:" hint is functional text: it meets AA contrast on '
        'the card', (tester) async {
      await open(
        tester,
        host([
          known({'waist': 81.0}),
        ], w: _FakeWrite(unit: false)),
      );
      final color = tester
          .widget<Text>(find.text('Last: 81.0 cm · 12 Sep'))
          .style!
          .color!;
      expect(color, AppColors.textDim);
      expect(_contrast(color, AppColors.card), greaterThanOrEqualTo(4.5));
    });

    testWidgets('screen readers hear WHICH field is which, and which unit is '
        'active', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      for (var i = 0; i < 4; i++) {
        final node = tester.getSemantics(field(i));
        expect(
          node.label,
          contains(['Chest', 'Waist', 'Hips', 'Arms'][i]),
          reason: 'field $i must announce its site',
        );
      }
      final cm = tester.getSemantics(find.bySemanticsLabel('Centimetres'));
      final inch = tester.getSemantics(find.bySemanticsLabel('Inches'));
      expect(cm.getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
      expect(
        inch.getSemanticsData().flagsCollection.isSelected,
        Tristate.isFalse,
      );
      expect(cm.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(inch.getSemanticsData().flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('the "switch?" hint is a button and is skipped by the '
        'keyboard\'s Next action', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      await tester.enterText(field(1), '34');
      await tester.pump();
      await tapSave(tester); // shows the message and the hint
      final hint = find.ancestor(
        of: find.text('Looks like inches · switch?'),
        matching: find.byType(InkWell),
      );
      expect(
        tester.widget<InkWell>(hint.first).canRequestFocus,
        isFalse,
        reason: 'it sits between two fields in focus order',
      );
      final node = tester.getSemantics(hint.first);
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('a field that was touched and then cleared shows no message', (
      tester,
    ) async {
      await open(tester, host([_empty], w: _FakeWrite(unit: false)));
      await tester.enterText(field(1), '7');
      await tester.pump();
      await blur(tester, 1);
      expect(find.text('Between 50 and 200 cm'), findsOneWidget);
      await tester.enterText(field(1), '');
      await tester.pump();
      expect(
        find.textContaining('Between'),
        findsNothing,
        reason: 'an empty optional row is not a problem',
      );
    });

    // ── how the sheet is hosted ──────────────────────────────────────────────

    testWidgets('the sheet is full-height capable: it is taller than the '
        'default 9/16 cap of a non-scroll-controlled sheet', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await open(
        tester,
        host([
          known({'waist': 81.0}),
        ]),
      );
      final h = tester.getSize(find.byType(BodyMeasurementsSheet)).height;
      expect(h, greaterThan(640 * 9 / 16 + 1));
    });

    testWidgets('it opens on the NEAREST navigator (inside the shell body), '
        'not on the root one', (tester) async {
      final w = _FakeWrite(unit: false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserIdTokenProvider.overrideWithValue(kTestUserId),
            bodyMeasurementsProvider.overrideWith(
              () => _FakeHistory([_empty], historyBuilds),
            ),
            measurementWriteProvider.overrideWith(() => w),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => Builder(
                    builder: (ctx) => ElevatedButton(
                      onPressed: () => BodyMeasurementsSheet.show(ctx),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final navigators = find.ancestor(
        of: find.byType(BodyMeasurementsSheet),
        matching: find.byType(Navigator),
      );
      expect(
        navigators,
        findsNWidgets(2),
        reason: 'the nested navigator, inside the root one',
      );
    });

    testWidgets('below a status-bar inset the content starts under it, not '
        'behind it (useSafeArea)', (tester) async {
      tester.view.physicalSize = const Size(320, 300);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: 40);
      tester.view.viewPadding = const FakeViewPadding(top: 40);
      addTearDown(tester.view.reset);
      await open(tester, host([_empty], textScale: 2.0));
      expect(
        tester.getRect(find.text('BODY MEASUREMENTS')).top,
        greaterThanOrEqualTo(40),
      );
      expect(
        tester.getRect(find.byType(BodyMeasurementsSheet)).top,
        greaterThanOrEqualTo(40),
      );
    });

    // ── geometry: every field and Save are reachable, with no overflow ───────

    /// Reaches every field and Save and requires each to END UP inside the
    /// visible area ([visibleTop], [visibleBottom]). A tree-presence check
    /// would pass whatever the layout (a SingleChildScrollView builds every
    /// child), and `scrollUntilVisible` ends in a programmatic ensureVisible
    /// that ignores scroll physics, so the POSITIONS are the assertion.
    Future<void> reachAll(
      WidgetTester tester, {
      required double visibleBottom,
      double visibleTop = 0,
    }) async {
      for (var i = 0; i < 4; i++) {
        await tester.ensureVisible(field(i));
        await tester.pump();
        final r = tester.getRect(field(i));
        expect(
          r.top,
          greaterThanOrEqualTo(visibleTop - 0.5),
          reason: 'field $i',
        );
        expect(
          r.bottom,
          lessThanOrEqualTo(visibleBottom + 0.5),
          reason: 'field $i must end above the keyboard / the box bottom',
        );
      }
      await tester.ensureVisible(saveButton());
      await tester.pump();
      final save = tester.getRect(saveButton());
      expect(save.top, greaterThanOrEqualTo(visibleTop - 0.5), reason: 'Save');
      expect(
        save.bottom,
        lessThanOrEqualTo(visibleBottom + 0.5),
        reason: 'Save must end above the keyboard / the box bottom',
      );
    }

    /// Dragging the content moves it: a scroll view that cannot be dragged (no
    /// scroll view, NeverScrollableScrollPhysics) is not reachable by a user.
    Future<void> expectDraggable(WidgetTester tester) async {
      final before = tester.getTopLeft(find.text('BODY MEASUREMENTS')).dy;
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -60),
      );
      await tester.pump();
      final after = tester.getTopLeft(find.text('BODY MEASUREMENTS')).dy;
      expect(after, lessThan(before), reason: 'the content scrolled');
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets('surrogate geometry 360x640, no inset, text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await open(
          tester,
          host([
            known({'waist': 81.0}),
          ], textScale: scale),
        );
        await reachAll(tester, visibleBottom: 640);
        expect(tester.takeException(), isNull);
      });

      // The ROOT-navigator geometry (the dev panel's door): the live keyboard
      // inset reaches the sheet, so the sheet's own bottom padding is the only
      // thing that lifts Save above the keyboard.
      testWidgets('root-navigator geometry 320x480 with a 300 dp keyboard '
          'inset, text scale $scale', (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.reset);
        await open(
          tester,
          host([
            known({'waist': 81.0}),
          ], textScale: scale),
        );
        await reachAll(tester, visibleBottom: 480 - 300);
        await expectDraggable(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('production-like geometry (the shell hands the sheet a '
          '360x260 box, no inset), text scale $scale', (tester) async {
        await open(
          tester,
          host(
            [
              known({'waist': 81.0}),
            ],
            textScale: scale,
            mediaSize: const Size(360, 640 - 300 - 80),
          ),
        );
        await reachAll(tester, visibleBottom: 640 - 300 - 80);
        await expectDraggable(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'production-like geometry, a 320x100 box, text scale $scale',
        (tester) async {
          await open(
            tester,
            host(
              [
                known({'waist': 81.0}),
              ],
              textScale: scale,
              mediaSize: const Size(320, 480 - 300 - 80),
            ),
          );
          await reachAll(tester, visibleBottom: 480 - 300 - 80);
          await expectDraggable(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  // ── end to end with the real providers and real Hive ─────────────────────

  group('BodyMeasurementsSheet end to end', () {
    late Directory dir;

    setUp(() async {
      dir = await setUpHiveForTests();
      SyncService.pausedForSimulation = true;
      setTestClockTo(DateTime.utc(2026, 10, 12, 6));
    });

    tearDown(() async {
      SyncService.pausedForSimulation = false;
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    testWidgets('a real save lands in the box, says "Baseline set", and the '
        'next open shows the Last hint', (tester) async {
      Widget app() => ProviderScope(
        overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => BodyMeasurementsSheet.show(ctx),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '81.0');
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'SAVE'));
      // Start the save in the REAL zone: a Hive put started inside the fake
      // zone never completes.
      await tester.runAsync(() async {
        tester
            .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'SAVE'))
            .onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();
      expect(find.byType(BodyMeasurementsSheet), findsNothing);
      expect(find.text('Baseline set ✓'), findsOneWidget);
      final rec = await tester.runAsync(
        () async =>
            HiveService.instance.healthBox.get('measurement_2026-10-12'),
      );
      expect((rec as Map)['waist'], 81.0);

      await tester.pumpAndSettle(const Duration(seconds: 3));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Last: 81.0 cm · 12 Oct'), findsOneWidget);
    });
  });
}
