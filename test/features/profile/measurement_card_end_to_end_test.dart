// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md section 4.9): the FIRST test
// is a typography warmup before any path_provider mock; Hive is set up per
// group. Every real Hive write happens inside tester.runAsync (a put started in
// the fake-async zone never completes), and SyncService.pausedForSimulation is
// ON in every row (a real save reaches SyncService.instance through
// syncMeasurementsNow() and pushSnapshot() and would hang a testWidgets).
@Timeout(Duration(minutes: 4))
library;

// L2b Landing C (E3): the Progress comparison card from the writer to the
// screen, with nothing stubbed between them: HealthWriteService.logMeasurements
// -> the healthBox -> HealthReadService.measurementHistory ->
// bodyMeasurementsProvider -> measurementCardRows -> the tiles. THIS FILE IS
// THE `behavioral_test_path` of the registry concept `measurement_card_rows`.
//
// CLOCKS: pinned to 2031-06-15 20:00 UTC = 2031-06-16 01:30 IST (the IST and UTC
// days differ). Records are dated 2031; the save in the middle is dated by that
// clock, 16 Jun. A card that read the device clock would print the year on
// every date and fail the literals. No row turns red on the day the real clock
// reaches 2031; from then on such a card is simply not detectable by them.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_prompt_provider.dart';
import 'package:icanbefitter/features/profile/services/measurement_prompt_rules.dart';
import 'package:icanbefitter/features/profile/widgets/body_measurements_sheet.dart';
import 'package:icanbefitter/features/profile/widgets/measurements_card.dart';

import '../../helpers/hive_test_setup.dart';

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

  group('the card, from the writer to the screen', () {
    late Directory dir;

    setUp(() async {
      dir = await setUpHiveForTests();
      setTestClockTo(DateTime.utc(2031, 6, 15, 20)); // 2031-06-16 01:30 IST
      SyncService.pausedForSimulation = true;
    });

    tearDown(() async {
      SyncService.pausedForSimulation = false;
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    Future<void> log(
      WidgetTester tester,
      DateTime day,
      Map<String, double> sites, {
      WriteSource source = WriteSource.manual,
    }) async {
      late WriteResult r;
      await tester.runAsync(() async {
        r = await HealthWriteService.instance.logMeasurements(
          date: day,
          sites: sites,
          source: source,
        );
      });
      expect(r.success, isTrue, reason: 'precondition: the write landed');
    }

    /// Three days, one site absent from the oldest and one only in the middle.
    Future<void> writeThreeDays(WidgetTester tester) async {
      // 06:00 UTC = 11:30 IST on the same day, so the key is the date written.
      await log(tester, DateTime.utc(2031, 5, 20, 6), {
        'waist': 81.0,
        'hips': 100.0,
      });
      await log(tester, DateTime.utc(2031, 6, 1, 6), {
        'waist': 80.0,
        'chest': 96.0,
        'arms': 33.0,
      });
      await log(tester, DateTime.utc(2031, 6, 10, 6), {
        'waist': 79.5,
        'chest': 97.0,
      });
    }

    Widget host() => ProviderScope(
      overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
      child: const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 360,
              height: 400,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: SingleChildScrollView(child: MeasurementsCard()),
              ),
            ),
          ),
        ),
      ),
    );

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(MeasurementsCard)),
        );

    testWidgets('three written days show the right latest value, day and '
        'change since the FIRST holder of each site', (tester) async {
      await writeThreeDays(tester);
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      // waist: held on all three days; first 81.0 (20 May), latest 79.5.
      expect(find.text('WAIST · 10 Jun'), findsOneWidget);
      expect(find.text('79.5 cm'), findsOneWidget);
      expect(find.text('-1.5 cm since 20 May'), findsOneWidget);
      // chest: ABSENT from the oldest day; first holder 1 Jun (96.0).
      expect(find.text('CHEST · 10 Jun'), findsOneWidget);
      expect(find.text('97.0 cm'), findsOneWidget);
      expect(find.text('+1.0 cm since 1 Jun'), findsOneWidget);
      // hips and arms were measured on one day only: a value, no change line.
      expect(find.text('HIPS · 20 May'), findsOneWidget);
      expect(find.text('100.0 cm'), findsOneWidget);
      expect(find.text('ARMS · 1 Jun'), findsOneWidget);
      expect(find.text('33.0 cm'), findsOneWidget);
      expect(find.textContaining('since'), findsNWidgets(2));
    });

    testWidgets('a real save() in inches updates the tile and the unit, with no '
        'rebuild of the parent', (tester) async {
      await writeThreeDays(tester);
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      expect(find.text('79.5 cm'), findsOneWidget);

      late WriteResult r;
      await tester.runAsync(() async {
        r = await containerOf(tester)
            .read(measurementWriteProvider.notifier)
            .save(
              sites: {'waist': 80.0}, // 31.5 in typed, stored as 80.0 cm
              source: WriteSource.manual,
              inchesUsed: true,
            );
      });
      // The save invalidates the history provider from inside runAsync, so
      // Riverpod schedules the refresh on the REAL zone's queue; one real tick
      // lets it run before the fake-async pump (in the app there is one zone).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(r.success, isTrue);
      // The save is dated by the test clock: 16 Jun IST. 80.0 cm shows 31.5 in
      // and the first waist 81.0 cm shows 31.9 in: the change of the displays.
      expect(find.text('WAIST · 16 Jun'), findsOneWidget);
      expect(find.text('31.5 in'), findsOneWidget);
      expect(find.text('-0.4 in since 20 May'), findsOneWidget);
      // The other tiles follow the remembered unit too: chest 97.0 / 96.0 cm.
      expect(find.text('38.2 in'), findsOneWidget);
      expect(find.text('+0.4 in since 1 Jun'), findsOneWidget);
      expect(find.textContaining(' cm'), findsNothing);
    });

    testWidgets('a write made elsewhere (the chat path) shows after '
        'noteWritten()', (tester) async {
      await writeThreeDays(tester);
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      expect(find.text('HIPS · 20 May'), findsOneWidget);

      await log(tester, DateTime.utc(2031, 6, 15, 20), {
        'hips': 101.5,
      }, source: WriteSource.aiCoach);
      containerOf(tester).read(measurementWriteProvider.notifier).noteWritten();
      await tester.pumpAndSettle();
      expect(find.text('HIPS · 16 Jun'), findsOneWidget);
      expect(find.text('101.5 cm'), findsOneWidget);
      expect(find.text('+1.5 cm since 20 May'), findsOneWidget);
    });

    // D4: the card ignores the prompt and its dismissal. The provider route is
    // pinned elsewhere (the card never creates the prompt provider); this is the
    // STORED route: a card that read the dismissal key itself and hid with it
    // would pass that test and fail here. The prompt is `due` first (the control
    // that the entry is old enough), then dismissed, and the tiles stay.
    testWidgets('a stored dismissal silences the prompt but not the card', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await HiveService.instance.configBox.put(
          'enable_body_measurements',
          true,
        );
        await HiveService.instance.userBox.put('profile', <String, dynamic>{
          'full_name': 'Test',
          'onboarding_completed_at': '2031-01-01T00:00:00Z',
        });
      });
      await log(tester, DateTime.utc(2031, 4, 1, 6), {'waist': 81.0});
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      final container = containerOf(tester);
      expect(
        container.read(measurementPromptProvider),
        MeasurementPrompt.due,
        reason: 'precondition: a 76-day-old entry is due',
      );
      expect(find.text('WAIST · 1 Apr'), findsOneWidget);
      await tester.runAsync(() async {
        await container.read(measurementPromptProvider.notifier).dismiss();
      });
      await tester.pump();
      expect(
        container.read(measurementPromptProvider),
        MeasurementPrompt.none,
        reason: 'precondition: the dismissal is in force',
      );
      expect(find.text('WAIST · 1 Apr'), findsOneWidget);
      expect(find.text('81.0 cm'), findsOneWidget);
      expect(find.text('Add measurements'), findsOneWidget);
      // A card that read the stored stamp itself would only notice on its next
      // build, and nothing rebuilds this one: mount it again, with the stamp in
      // the box, and ask the prompt and the card.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      expect(
        containerOf(tester).read(measurementPromptProvider),
        MeasurementPrompt.none,
        reason: 'precondition: the stored dismissal is read on a fresh mount',
      );
      expect(find.text('WAIST · 1 Apr'), findsOneWidget);
      expect(find.text('81.0 cm'), findsOneWidget);
    });

    testWidgets('a skipped baseline silences the prompt but not the card\'s '
        'door', (tester) async {
      await tester.runAsync(() async {
        await HiveService.instance.configBox.put(
          'enable_body_measurements',
          true,
        );
        await HiveService.instance.userBox.put('profile', <String, dynamic>{
          'full_name': 'Test',
          'onboarding_completed_at': '2031-01-01T00:00:00Z',
        });
      });
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      final container = containerOf(tester);
      expect(
        container.read(measurementPromptProvider),
        MeasurementPrompt.baseline,
        reason: 'precondition: never measured, long enough since onboarding',
      );
      await tester.runAsync(() async {
        await container.read(measurementPromptProvider.notifier).skipBaseline();
      });
      await tester.pump();
      expect(
        container.read(measurementPromptProvider),
        MeasurementPrompt.none,
        reason: 'precondition: the skip is in force',
      );
      expect(find.text('Add measurements'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      expect(
        containerOf(tester).read(measurementPromptProvider),
        MeasurementPrompt.none,
        reason: 'precondition: the stored skip is read on a fresh mount',
      );
      expect(find.text('Add measurements'), findsOneWidget);
    });

    // The card and the sheet ask the same question (`preferredInches`), so for
    // any stored state they must answer the same way.
    for (final row
        in <
          ({String name, String? remembered, bool deviceMetric, bool inches})
        >[
          (
            name: 'remembered in, metric device',
            remembered: 'in',
            deviceMetric: true,
            inches: true,
          ),
          (
            name: 'remembered cm, imperial device',
            remembered: 'cm',
            deviceMetric: false,
            inches: false,
          ),
          (
            name: 'nothing remembered, metric device',
            remembered: null,
            deviceMetric: true,
            inches: false,
          ),
          (
            name: 'nothing remembered, imperial device',
            remembered: null,
            deviceMetric: false,
            inches: true,
          ),
        ]) {
      testWidgets('card and sheet agree: ${row.name}', (tester) async {
        await writeThreeDays(tester);
        await tester.runAsync(() async {
          await HiveService.instance.configBox.put(
            'units_metric',
            row.deviceMetric,
          );
          if (row.remembered != null) {
            await HiveService.instance.userBox.put(
              'body_measurement_sheet_unit',
              row.remembered,
            );
          }
        });
        await tester.pumpWidget(host());
        await tester.pump();
        await tester.pump();
        // The card prints the unit in the value text ...
        expect(find.textContaining(row.inches ? ' in' : ' cm'), findsWidgets);
        expect(find.textContaining(row.inches ? ' cm' : ' in'), findsNothing);
        // ... and the sheet opened from its header button shows the same unit
        // as its field suffix (one 'cm' or 'in' per row, four rows).
        await tester.tap(find.text('Add measurements'));
        await tester.pumpAndSettle();
        expect(find.byType(BodyMeasurementsSheet), findsOneWidget);
        final suffix = row.inches ? 'in' : 'cm';
        final other = row.inches ? 'cm' : 'in';
        expect(find.text(suffix), findsNWidgets(4));
        expect(find.text(other), findsNothing);
      });
    }
  });
}
