// Regression contract for bug e8a2c1 (2026-06-13) AND its successor e2b8a4
// (2026-09-19). e8a2c1: on the ~698px web mobile-frame the stock Material
// time/date picker's OK/Cancel action row fell BELOW the fold — fixed by
// scroll-wrapping the dialog in an unbounded SingleChildScrollView.
//
// e2b8a4 found that fix was itself the cause of a WORSE regression:
// SingleChildScrollView gives its child UNBOUNDED height along the scroll
// axis by design, regardless of what constrains the scroll view itself —
// so the fix let the time picker's dial claim more space than the actual
// viewport, breaking its internal GestureDetector's hit-region (taps on
// Cancel/OK/keyboard-toggle instead rotated the clock hand), and at the
// default viewport the dial + action row didn't render AT ALL (not
// scrolled off — genuinely absent). Also: the DOB YearPicker/
// CalendarDatePicker grid wrapped 4-digit years / 2-digit days onto two
// lines, because the app's global textTheme (Fraunces, larger than
// Material's defaults) leaked into the picker's fixed-size grid cells.
//
// The e2b8a4 fix (first pass): (1) reset textTheme to stock Material
// defaults inside the picker only, and (2) replace the unbounded
// SingleChildScrollView with a genuinely bounded ConstrainedBox
// (maxHeight/maxWidth derived from the real viewport) wrapping the dialog
// DIRECTLY — giving Flutter's own TimePickerDialog/CalendarDatePicker real
// constraints to adapt to, instead of infinite height that broke their
// internal assumptions.
//
// e2b8a4 SECOND PASS (same day, live re-verify): the first-pass fix was
// validated only against a SYNTHETIC oversized-TextTheme fixture (below) —
// it passed, but the day-grid wrap was STILL LIVE-REPRODUCIBLE in a real
// browser afterward. Root cause: `CalendarDatePicker`/`YearPicker` day and
// year cells read `datePickerTheme.dayStyle/yearStyle ??
// textTheme.bodyLarge` (Flutter's own `_DatePickerDefaultsM3`), and resetting
// the WHOLE textTheme did not stop the app's DM-Sans-family `bodyLarge`
// from still reaching those cells — `flutter test` never fetches the real
// DM Sans web font and silently falls back to a placeholder, which is
// exactly why the synthetic-fixture test below could not see this: it
// proves fontSIZE resets, not that the FAMILY is gone. The corrected fix
// sets `datePickerTheme.dayStyle/weekdayStyle/yearStyle` EXPLICITLY (no
// custom font family at all), which takes absolute precedence over the
// textTheme-derived fallback regardless of what the ambient textTheme is.
// See `responsive_picker_builder.dart`'s class doc for the full account.
//
// e2b8a4 THIRD PASS (same day, live re-verify of showTimePicker itself):
// after the datePickerTheme fix landed, the DOB date-picker was confirmed
// fixed live, but showTimePicker + responsivePickerBuilder was ALSO
// live-reproduced still showing the dial + OK/Cancel as genuinely absent
// (confirmed via direct canvas-pixel sampling, not just a screenshot read)
// — the SAME root cause, one theme extension over: TimePickerDialog's
// hour/minute display resolves via `textTheme.displayMedium`, which the
// app maps to Fraunces (a serif VARIABLE font), not DM Sans. Fixed
// identically: `timePickerTheme`'s text styles (hourMinuteTextStyle,
// dayPeriodTextStyle, helpTextStyle, dialTextStyle,
// timeSelectorSeparatorTextStyle) are now set EXPLICITLY with no custom
// font family. NOTE: no PRODUCT call site currently reaches this path
// (Edit Profile's showTimePicker calls use no builder at all; muster's
// was retired — see the companion diagnose) — this test exists so the
// shared builder stays correct for whenever a future call site reaches
// for it, since its own doc comment advertises it for both pickers.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/theme/app_theme.dart';
import 'package:icanbefitter/shared/widgets/responsive_picker_builder.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  testWidgets(
      'e2b8a4 — responsivePickerBuilder bounds the dialog to a genuine '
      'fraction of the viewport (no unbounded SingleChildScrollView)',
      (tester) async {
    const viewportSize = Size(800, 600);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: viewportSize),
        child: Builder(
          builder: (context) => responsivePickerBuilder(
            context,
            // A child taller AND wider than the test viewport — the bound
            // must clip it via real BoxConstraints, not an unbounded scroll.
            const SizedBox(height: 2000, width: 2000, child: Text('picker')),
          ),
        ),
      ),
    ));

    // The old mechanism must be gone — SingleChildScrollView gives its
    // child unbounded extent along the scroll axis regardless of what
    // constrains the scroll view itself, which is exactly what broke the
    // dial's internal gesture-region sizing (e2b8a4).
    expect(find.byType(SingleChildScrollView), findsNothing,
        reason:
            'e2b8a4: SingleChildScrollView must not wrap the picker — it '
            'gives the child UNBOUNDED height regardless of its own '
            'constraints, which is the root cause this diagnose fixed.');

    // Scoped by the EXPECTED constraint values rather than assuming exactly
    // one ConstrainedBox exists anywhere in the tree — the SDK's own View/
    // MediaQuery plumbing inserts an unrelated root-level ConstrainedBox
    // with BoxConstraints.biggest, which a bare byType(ConstrainedBox) also
    // matches (found live: 2 matches, not 1, when this was first run).
    final constrainedBoxFinder = find.byWidgetPredicate(
      (w) =>
          w is ConstrainedBox &&
          w.constraints.maxHeight < double.infinity &&
          (w.constraints.maxHeight - viewportSize.height * 0.9).abs() < 0.5 &&
          (w.constraints.maxWidth - viewportSize.width * 0.95).abs() < 0.5,
    );
    expect(constrainedBoxFinder, findsOneWidget,
        reason:
            'the picker must be wrapped in a genuinely bounded ConstrainedBox '
            '(maxHeight/maxWidth derived from the real viewport) so Flutter\'s '
            'own TimePickerDialog/CalendarDatePicker can adapt their internal '
            'layout to the space actually available');

    // The bound must actually be ENFORCED on the rendered tree, not just
    // declared — a 2000x2000 child must render clipped to the bound.
    final renderedSize = tester.getSize(find.text('picker'));
    expect(renderedSize.height, lessThanOrEqualTo(viewportSize.height * 0.9),
        reason: 'rendered content must not exceed the declared height bound');
    expect(renderedSize.width, lessThanOrEqualTo(viewportSize.width * 0.95),
        reason: 'rendered content must not exceed the declared width bound');
    expect(tester.takeException(), isNull,
        reason: 'a genuinely bounded ConstrainedBox must not overflow');
  });

  testWidgets('e2b8a4 — textTheme inside the picker is reset, not inherited',
      (tester) async {
    // A deliberately oversized custom textTheme, mimicking the app's real
    // global theme (Fraunces headlines well above Material's defaults) —
    // this is the exact condition that made 4-digit years / 2-digit days
    // wrap onto two lines inside the date-picker's fixed-size grid cells.
    final oversizedTheme = ThemeData(
      brightness: Brightness.dark,
      textTheme: const TextTheme(bodyLarge: TextStyle(fontSize: 40)),
    );
    late BuildContext pickerContext;

    await tester.pumpWidget(MaterialApp(
      theme: oversizedTheme,
      home: Builder(
        builder: (context) => responsivePickerBuilder(
          context,
          Builder(builder: (innerContext) {
            pickerContext = innerContext;
            return const SizedBox(width: 100, height: 100);
          }),
        ),
      ),
    ));

    final effectiveBodyLarge = Theme.of(pickerContext).textTheme.bodyLarge;
    expect(effectiveBodyLarge?.fontSize, isNot(40),
        reason:
            'e2b8a4: the picker must NOT inherit the ambient (app-global) '
            'textTheme verbatim — that is exactly what let an oversized '
            'font leak into the fixed-size YearPicker/CalendarDatePicker '
            'grid cells and wrap 4-digit years onto two lines');
    expect(effectiveBodyLarge?.fontFamily, isNot(contains('DMSans')),
        reason: 'the picker\'s textTheme must not carry the app\'s custom '
            'DM Sans family either — resetting only the size and leaving '
            'the family would still leave a real-browser-only web-font-'
            'metrics risk (see the 2nd-pass test below, which is the '
            'concrete regression proof for this).');
    // NOTE: an earlier version of this test also compared
    // effectiveBodyLarge.fontSize against a freshly-recomputed
    // `ThemeData(brightness: Brightness.dark).textTheme.bodyLarge?.fontSize`
    // ("stockDefault") for exact equality. That comparison was REMOVED
    // (2026-09-19) after it was observed to return DIFFERENT values (null
    // vs 16.0) across two otherwise-identical runs of this same file —
    // genuinely non-deterministic, not just platform-dependent. A flaky
    // comparison proves nothing; the family/size checks above plus the
    // real-AppTheme, real-showDatePicker test below are the actual,
    // stable regression coverage for this bug.
  });

  testWidgets(
      'e2b8a4 (2nd pass) — real showDatePicker day cell never resolves to '
      'the app\'s DM Sans family, and never wraps, against the REAL '
      'AppTheme.dark (not a synthetic fixture)', (tester) async {
    // The first-pass fix's test above used a hand-built oversized TextTheme
    // fixture and missed that the app's REAL bodyLarge (DM Sans, no
    // explicit fontSize — AppTypography.dmSansFamily's "seed" pattern) still
    // reached the day cells via datePickerTheme's fallback chain. Testing
    // against the real AppTheme.dark is the point of this test — a fixture
    // that doesn't reproduce the real theme proves nothing about it.
    tester.view.physicalSize = const Size(782, 741);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                await showDatePicker(
                  context: context,
                  initialDate: DateTime(2001, 1, 15),
                  firstDate: DateTime(1950),
                  lastDate: DateTime.now(),
                  helpText: 'DATE OF BIRTH',
                  builder: responsivePickerBuilder,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Day "15" is a 2-digit day cell — the exact shape that wrapped live.
    final dayFinder = find.text('15');
    expect(dayFinder, findsWidgets,
        reason: 'day 15 should be visible in the January 2001 grid');

    final style = tester.renderObject<RenderParagraph>(dayFinder.first).text.style;
    expect(style?.fontFamily, isNot(contains('DMSans')),
        reason: 'e2b8a4 2nd pass: the day cell must NOT resolve to the '
            'app\'s DM Sans family — that family\'s real web-font metrics '
            '(only present in a real browser, never in flutter test) are '
            'what actually caused the live wrap, not just an oversized '
            'fontSize');
    expect(style?.fontFamilyFallback, isNot(contains('DMSans')),
        reason: 'DM Sans must not be reachable via a fallback list either');

    final dayParagraph = tester.renderObject<RenderParagraph>(dayFinder.first);
    expect(dayParagraph.didExceedMaxLines, isFalse,
        reason: 'e2b8a4 2nd pass: the day cell must render on exactly one '
            'line against the REAL app theme — this is the actual '
            'regression proof; the synthetic-fixture test above could not '
            'catch this because it never used AppTheme.dark');

    // Structural pin: datePickerTheme must carry explicit, non-null styles
    // so a future edit can't silently drop the override and fall back to
    // the textTheme-derived chain again.
    final pickerTheme = Theme.of(tester.element(dayFinder.first)).datePickerTheme;
    expect(pickerTheme.dayStyle, isNotNull,
        reason: 'datePickerTheme.dayStyle must be set explicitly — this is '
            'what takes precedence over the textTheme fallback chain');
    expect(pickerTheme.dayStyle?.fontFamily, isNot(contains('DMSans')));
    expect(pickerTheme.yearStyle?.fontFamily, isNot(contains('DMSans')));
    expect(pickerTheme.weekdayStyle?.fontFamily, isNot(contains('DMSans')));
  });

  testWidgets(
      'e2b8a4 (3rd pass) — showTimePicker dial + OK/Cancel render (not '
      'genuinely absent) via responsivePickerBuilder, against the REAL '
      'AppTheme.dark', (tester) async {
    // Live-reproduced: with only the datePickerTheme fix in place, the
    // dial + action row rendered as genuinely absent (confirmed via direct
    // canvas-pixel sampling in the live browser — flat background color,
    // not a color/visibility issue). Root cause: hourMinuteTextStyle
    // resolves via textTheme.displayMedium, which the app maps to Fraunces
    // (a variable serif font) — the same class of bug as the day-grid one,
    // one theme extension over.
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                await showTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 6, minute: 30),
                  builder: responsivePickerBuilder,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'no overflow expected with a correctly bounded dialog');

    final okFinder = find.text('OK');
    expect(okFinder, findsOneWidget,
        reason: 'OK must be present and reachable, not genuinely absent');
    final okSize = tester.getSize(okFinder);
    expect(okSize.width, greaterThan(0));
    expect(okSize.height, greaterThan(0));

    final dialFinder =
        find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Dial');
    expect(dialFinder, findsOneWidget,
        reason: 'e2b8a4 3rd pass: the dial must actually render — this is '
            'the concrete regression proof for the live-reproduced '
            '"genuinely absent" symptom');
    final dialSize = tester.getSize(dialFinder);
    expect(dialSize.width, greaterThan(50),
        reason: 'the dial must have a real, usable size, not be collapsed '
            'to near-zero by a starved layout');
    expect(dialSize.height, greaterThan(50));

    // The dial and OK button must not overlap — proof the layout has
    // genuinely separated them, not just that both technically exist.
    final dialBottom = tester.getBottomLeft(dialFinder).dy;
    final okTop = tester.getTopLeft(okFinder).dy;
    expect(okTop, greaterThanOrEqualTo(dialBottom - 1),
        reason: 'OK must sit at or below the dial, not overlapping it');

    // Structural pin, mirroring the datePickerTheme one above.
    final pickerTheme = Theme.of(tester.element(okFinder)).timePickerTheme;
    expect(pickerTheme.hourMinuteTextStyle, isNotNull,
        reason: 'timePickerTheme.hourMinuteTextStyle must be set explicitly '
            '— this is what takes precedence over textTheme.displayMedium '
            '(Fraunces) reaching the hour/minute display');
    expect(
        pickerTheme.hourMinuteTextStyle?.fontFamily, isNot(contains('Fraunces')));
    expect(pickerTheme.dialTextStyle?.fontFamily, isNot(contains('DMSans')));
    expect(
        pickerTheme.dayPeriodTextStyle?.fontFamily, isNot(contains('DMSans')));
    expect(pickerTheme.helpTextStyle?.fontFamily, isNot(contains('DMSans')));
  });

  test('e2b8a4 — identity DOB picker still uses the responsive host', () {
    final identity = _strip(File(
            'lib/features/onboarding/screens/identity_screen.dart')
        .readAsStringSync());
    expect(identity.contains('builder: responsivePickerBuilder'), isTrue,
        reason: 'identity DOB picker must use the responsive host');
  });

  test(
      'e2b8a4 — muster no longer has a time picker at all (wake/workout-time '
      'question retired, not just re-wired)', () {
    // diagnose e2b8a4 (2026-09-19): muster's wake/workout-time question was
    // retired entirely (Edit Profile already has full UI for it) — its
    // showTimePicker call site is GONE, not merely still-present. Asserting
    // absence here (rather than deleting this test's muster coverage
    // outright) makes the retirement itself a pinned, checkable fact: a
    // future re-add of a muster time picker should have to consciously
    // remove this assertion, not silently slip past an untouched file.
    final muster = _strip(
        File('lib/features/ai_coach/screens/muster_screen.dart')
            .readAsStringSync());
    expect(muster.contains('showTimePicker'), isFalse,
        reason:
            'muster_screen.dart must not call showTimePicker — the '
            'wake/workout-time question is retired (diagnose e2b8a4)');
    expect(muster.contains('responsivePickerBuilder'), isFalse,
        reason:
            'muster_screen.dart has no picker call left to need the '
            'responsive host');
  });
}
