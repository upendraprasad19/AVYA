// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md section 4.9): the FIRST test
// is a typography warmup that runs before any path_provider mock is installed.
// Reference: test/widgets/day_swap_allowance_line_test.dart.
@Timeout(Duration(minutes: 3))
library;

// L2b Landing B (B6) - the Home banner (due and baseline variants) and the slot
// that owns its flag and prompt checks. Plan:
// docs/plans/coach-measurement-sheet-ui.md (B6, section 4).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/measurement_copy.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/widgets/measurement_due_banner.dart';
import 'package:icanbefitter/features/home/widgets/measurement_due_slot.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_prompt_provider.dart';
import 'package:icanbefitter/features/profile/services/measurement_prompt_rules.dart';
import 'package:icanbefitter/features/profile/widgets/body_measurements_sheet.dart';

import '../helpers/hive_test_setup.dart';

class _FakePrompt extends MeasurementPromptNotifier {
  _FakePrompt(this.value, this.log);
  final MeasurementPrompt value;
  final List<String> log;

  @override
  MeasurementPrompt build() {
    log.add('build');
    return value;
  }

  @override
  Future<void> dismiss() async => log.add('dismiss');

  @override
  Future<void> skipBaseline() async => log.add('skipBaseline');
}

class _FakeHistory extends BodyMeasurementsNotifier {
  @override
  BodyMeasurementsState build() => const BodyMeasurementsState(loaded: true);
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

  group('MeasurementDueBanner', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool baseline,
      required VoidCallback onOpen,
      required VoidCallback onDismiss,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeasurementDueBanner(
              baseline: baseline,
              onOpen: onOpen,
              onDismiss: onDismiss,
            ),
          ),
        ),
      );
    }

    testWidgets('the due and the baseline variants say different things', (
      tester,
    ) async {
      await pump(tester, baseline: false, onOpen: () {}, onDismiss: () {});
      expect(find.text(MeasurementCopy.bannerDue), findsOneWidget);
      expect(find.text(MeasurementCopy.bannerBaseline), findsNothing);
      await pump(tester, baseline: true, onOpen: () {}, onDismiss: () {});
      expect(find.text(MeasurementCopy.bannerBaseline), findsOneWidget);
      expect(find.text(MeasurementCopy.bannerDue), findsNothing);
      expect(MeasurementCopy.bannerDue, isNot(MeasurementCopy.bannerBaseline));
    });

    testWidgets('a tap on the card opens, a tap on the X dismisses and does '
        'not open', (tester) async {
      var opened = 0;
      var dismissed = 0;
      await pump(
        tester,
        baseline: false,
        onOpen: () => opened++,
        onDismiss: () => dismissed++,
      );
      await tester.tap(find.text(MeasurementCopy.bannerDue));
      expect((opened, dismissed), (1, 0));
      await tester.tap(find.byIcon(Icons.close));
      expect((opened, dismissed), (1, 1));
    });

    testWidgets('there is exactly one dismiss control, at least 44 dp, with a '
        'Semantics label', (tester) async {
      await pump(tester, baseline: true, onOpen: () {}, onDismiss: () {});
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.textContaining('Not now'), findsNothing);
      final x = find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(InkWell),
      );
      final size = tester.getSize(x.first);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(
        find.bySemanticsLabel(MeasurementCopy.bannerDismissLabel),
        findsOneWidget,
      );
    });

    testWidgets(
      'the banner, link and X words are the shipped ones (literals)',
      (tester) async {
        expect(
          MeasurementCopy.bannerDue,
          "It's been about a month. Log a fresh set of measurements?",
        );
        expect(
          MeasurementCopy.bannerBaseline,
          'Set your baseline: four tape measures, about a minute.',
        );
        expect(
          MeasurementCopy.bannerDismissLabel,
          'Dismiss measurements reminder',
        );
        expect(MeasurementCopy.weightSheetLink, 'Add body measurements');
      },
    );

    testWidgets('the X is announced as a button with its label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, baseline: false, onOpen: () {}, onDismiss: () {});
      final node = tester.getSemantics(
        find.bySemanticsLabel(MeasurementCopy.bannerDismissLabel),
      );
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('text scale $scale: both variants lay out without overflow '
          'and the X stays a 44 dp target that works', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        for (final baseline in [false, true]) {
          var dismissed = 0;
          await tester.pumpWidget(
            MaterialApp(
              builder: (ctx, child) => MediaQuery(
                data: MediaQuery.of(
                  ctx,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: MeasurementDueBanner(
                  baseline: baseline,
                  onOpen: () {},
                  onDismiss: () => dismissed++,
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull, reason: 'baseline $baseline');
          final x = find.ancestor(
            of: find.byIcon(Icons.close),
            matching: find.byType(InkWell),
          );
          expect(tester.getSize(x.first).height, greaterThanOrEqualTo(44));
          await tester.tap(find.byIcon(Icons.close));
          expect(dismissed, 1, reason: 'baseline $baseline');
        }
      });
    }

    test(
      'no em dash anywhere in the copy file or the site labels and guides',
      () {
        final emDash = String.fromCharCode(0x2014);
        for (final path in [
          'lib/core/copy/measurement_copy.dart',
          'lib/core/constants/body_measurement_specs.dart',
        ]) {
          final src = File(path).readAsStringSync();
          // Comments may talk about the rule; strings may not use the character.
          final code = src
              .split('\n')
              .where((l) => !l.trimLeft().startsWith('//'))
              .join('\n');
          expect(code.contains(emDash), isFalse, reason: path);
        }
      },
    );

    testWidgets('the copy has no good / bad wording, no guilt and no streak '
        'framing', (tester) async {
      for (final s in [
        MeasurementCopy.bannerDue,
        MeasurementCopy.bannerBaseline,
        MeasurementCopy.weightSheetLink,
      ]) {
        final low = s.toLowerCase();
        for (final w in [
          'streak',
          'lose',
          'lost',
          'miss',
          'behind',
          'should',
          'must',
          'overdue',
          'great',
          'good job',
          'bad',
          'pro ',
        ]) {
          expect(low.contains(w), isFalse, reason: "'$s' contains '$w'");
        }
        expect(s.contains('—'), isFalse, reason: 'no em dash in: $s');
      }
    });

    // L2b Landing C: the card and chip copy. The scan above is a lowercase
    // SUBSTRING test (`miss` matches inside "Dismiss"), so the new strings get
    // WORD-BOUNDARY patterns, scoped to the new constants and builder outputs.
    testWidgets('Landing C copy: no good / bad wording, no guilt, no streak '
        'framing, no "snapshot", no em dash (word-boundary scan over the '
        'builder output in both units)', (tester) async {
      final em = String.fromCharCode(0x2014);
      final strings = <String>[
        MeasurementCopy.cardAddButton,
        MeasurementCopy.chipLabel,
        MeasurementCopy.bannerDismissLabel,
        MeasurementCopy.cardTileTitle('Waist', '3 Oct'),
      ];
      for (final inches in [false, true]) {
        strings.add(MeasurementCopy.cardValue(79.5, inches: inches));
        for (final delta in [1.5, -1.5, 0.0, -0.0]) {
          strings.add(
            MeasurementCopy.cardDeltaLine(
              delta,
              inches: inches,
              shortFirstDate: '12 Sep',
            ),
          );
          strings.add(
            MeasurementCopy.cardTileSemantics(
              label: 'Waist',
              value: 79.5,
              inches: inches,
              longLatestDate: '3 October',
              delta: delta,
              longFirstDate: '12 September',
            ),
          );
        }
        strings.add(
          MeasurementCopy.cardTileSemantics(
            label: 'Waist',
            value: 79.5,
            inches: inches,
            longLatestDate: '3 October',
          ),
        );
      }
      expect(strings.length, greaterThan(15), reason: 'the scan saw them all');
      final banned = <RegExp>[
        for (final w in [
          'good',
          'bad',
          'lost?',
          'lose',
          'gained',
          'gain',
          'streak',
          'behind',
          'ahead',
          'miss(ed)?',
          'should',
          'must',
          'overdue',
          'great',
          'pro',
          'better',
          'worse',
          'progress',
          'fail(ed)?',
        ])
          RegExp('\\b$w\\b', caseSensitive: false),
        RegExp('snapshot', caseSensitive: false),
      ];
      for (final s in strings) {
        for (final re in banned) {
          expect(re.hasMatch(s), isFalse, reason: "'$s' matches ${re.pattern}");
        }
        expect(s.contains(em), isFalse, reason: 'no em dash in: $s');
      }
      // The scan is not vacuous: the word-boundary patterns do not trip on
      // "Dismiss" (which the old substring scan would), and they do trip on a
      // real banned word.
      expect(banned.any((re) => re.hasMatch('Dismiss measurements reminder')),
          isFalse);
      expect(banned.any((re) => re.hasMatch('you missed a week')), isTrue);
    });
  });

  group('MeasurementDueSlot', () {
    late Directory dir;
    late List<String> log;

    setUp(() async {
      dir = await setUpHiveForTests();
      log = [];
    });

    tearDown(() async {
      await tearDownHiveForTests(dir);
    });

    Widget host({required bool flag, required MeasurementPrompt prompt}) {
      return ProviderScope(
        key: UniqueKey(),
        overrides: [
          authUserIdTokenProvider.overrideWithValue(kTestUserId),
          measurementsEnabledProvider.overrideWithValue(flag),
          measurementPromptProvider.overrideWith(
            () => _FakePrompt(prompt, log),
          ),
          bodyMeasurementsProvider.overrideWith(_FakeHistory.new),
        ],
        child: const MaterialApp(home: Scaffold(body: MeasurementDueSlot())),
      );
    }

    testWidgets('flag OFF: nothing is shown and the prompt provider is never '
        'built', (tester) async {
      await tester.pumpWidget(host(flag: false, prompt: MeasurementPrompt.due));
      expect(find.byType(MeasurementDueBanner), findsNothing);
      expect(log, isEmpty);
    });

    testWidgets('flag ON, prompt none: nothing is shown', (tester) async {
      await tester.pumpWidget(host(flag: true, prompt: MeasurementPrompt.none));
      expect(find.byType(MeasurementDueBanner), findsNothing);
    });

    testWidgets('flag ON, due: the due banner; baseline: the baseline banner', (
      tester,
    ) async {
      await tester.pumpWidget(host(flag: true, prompt: MeasurementPrompt.due));
      expect(find.text(MeasurementCopy.bannerDue), findsOneWidget);
      await tester.pumpWidget(
        host(flag: true, prompt: MeasurementPrompt.baseline),
      );
      await tester.pump();
      expect(find.text(MeasurementCopy.bannerBaseline), findsOneWidget);
    });

    testWidgets('a tap on the banner opens the measurements sheet, for the '
        'due and the baseline variant', (tester) async {
      for (final p in [MeasurementPrompt.due, MeasurementPrompt.baseline]) {
        await tester.pumpWidget(host(flag: true, prompt: p));
        await tester.pump();
        await tester.tap(find.byType(MeasurementDueBanner));
        await tester.pumpAndSettle();
        expect(
          find.byType(BodyMeasurementsSheet),
          findsOneWidget,
          reason: '$p',
        );
        Navigator.of(tester.element(find.byType(BodyMeasurementsSheet))).pop();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('the X on a due banner calls dismiss and not skipBaseline', (
      tester,
    ) async {
      await tester.pumpWidget(host(flag: true, prompt: MeasurementPrompt.due));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(log.where((e) => e != 'build'), ['dismiss']);
    });

    testWidgets('the X on a baseline banner calls skipBaseline and not '
        'dismiss', (tester) async {
      await tester.pumpWidget(
        host(flag: true, prompt: MeasurementPrompt.baseline),
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(log.where((e) => e != 'build'), ['skipBaseline']);
    });
  });

  // The slot over the REAL notifiers (nothing overridden but the token): the
  // fakes above always return a constant, so they cannot tell a slot that
  // WATCHES its state from one that read it once.
  group('MeasurementDueSlot on the real graph', () {
    late Directory dir;

    setUp(() async {
      dir = await setUpHiveForTests();
      setTestClockTo(DateTime.utc(2026, 10, 12, 6));
    });

    tearDown(() async {
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    Future<void> plant(
      WidgetTester tester, {
      required bool? flag, // null: the key is never written (the default)
      String? lastEntry,
    }) async {
      await tester.runAsync(() async {
        if (flag != null) {
          await HiveService.instance.configBox.put(
            'enable_body_measurements',
            flag,
          );
        }
        await HiveService.instance.userBox.put('profile', <String, dynamic>{
          'full_name': 'Test',
          'onboarding_completed_at': '2026-08-01T00:00:00Z',
        });
        if (lastEntry != null) {
          await HiveService.instance.healthBox.put('measurement_$lastEntry', {
            'id': 'meas_$lastEntry',
            'date': lastEntry,
            'waist': 80.0,
            'created_at': '${lastEntry}T01:00:00.000Z',
            'updated_at_ms': 1,
          });
        }
      });
    }

    Future<void> mount(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
          child: const MaterialApp(home: Scaffold(body: MeasurementDueSlot())),
        ),
      );
      await tester.pump();
    }

    /// Fires the X's callback in the REAL zone: the notifier writes Hive, and a
    /// put started inside the fake-async zone never completes.
    Future<void> tapX(WidgetTester tester) async {
      final x = find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(InkWell),
      );
      await tester.runAsync(() async {
        tester.widget<InkWell>(x.first).onTap!();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
    }

    // The production default since the 2026-10-16 flip: the key was never
    // written, so the slot must show the banner with no flag put at all.
    testWidgets('the key never written (the default ON): a due banner shows, '
        'and a stored false hides it', (tester) async {
      await plant(tester, flag: null, lastEntry: '2026-09-01');
      await mount(tester);
      expect(find.text(MeasurementCopy.bannerDue), findsOneWidget);
      await tester.runAsync(
        () => HiveService.instance.configBox.put(
          'enable_body_measurements',
          false,
        ),
      );
      ProviderScope.containerOf(
        tester.element(find.byType(MeasurementDueSlot)),
      ).invalidate(measurementsEnabledProvider);
      await tester.pumpAndSettle();
      expect(find.byType(MeasurementDueBanner), findsNothing);
    });

    testWidgets('X on a due banner: the banner is gone afterwards, with no '
        'rebuild of the parent', (tester) async {
      await plant(tester, flag: true, lastEntry: '2026-09-01');
      await mount(tester);
      expect(find.text(MeasurementCopy.bannerDue), findsOneWidget);
      await tapX(tester);
      expect(find.byType(MeasurementDueBanner), findsNothing);
    });

    testWidgets('X on a baseline banner: the banner is gone afterwards', (
      tester,
    ) async {
      await plant(tester, flag: true);
      await mount(tester);
      expect(find.text(MeasurementCopy.bannerBaseline), findsOneWidget);
      await tapX(tester);
      expect(find.byType(MeasurementDueBanner), findsNothing);
    });

    testWidgets('switching the flag off under a mounted slot removes the '
        'banner (the slot watches the flag)', (tester) async {
      await plant(tester, flag: true, lastEntry: '2026-09-01');
      await mount(tester);
      expect(find.byType(MeasurementDueBanner), findsOneWidget);
      await tester.runAsync(
        () => HiveService.instance.configBox.put(
          'enable_body_measurements',
          false,
        ),
      );
      ProviderScope.containerOf(
        tester.element(find.byType(MeasurementDueSlot)),
      ).invalidate(measurementsEnabledProvider);
      await tester.pumpAndSettle();
      expect(find.byType(MeasurementDueBanner), findsNothing);
    });

    // The mirror of the test above, and the one that pins `watch` over `read`.
    // Flag ON -> OFF is also carried by the prompt provider (it watches the flag,
    // goes to `none`, and the slot rebuilds for THAT reason, so a `read` of the
    // flag still passes). Flag OFF -> ON is not: an OFF slot returns before it
    // watches the prompt provider, so the flag watch is its ONLY subscription.
    // (B-pass mutant MUT-22 survived without this row.)
    testWidgets('switching the flag ON under a mounted OFF slot shows the '
        'banner (the flag watch is the slot\'s only subscription while OFF)', (
      tester,
    ) async {
      await plant(tester, flag: false, lastEntry: '2026-09-01');
      await mount(tester);
      expect(find.byType(MeasurementDueBanner), findsNothing);
      await tester.runAsync(
        () => HiveService.instance.configBox.put(
          'enable_body_measurements',
          true,
        ),
      );
      ProviderScope.containerOf(
        tester.element(find.byType(MeasurementDueSlot)),
      ).invalidate(measurementsEnabledProvider);
      await tester.pumpAndSettle();
      expect(find.text(MeasurementCopy.bannerDue), findsOneWidget);
    });
  });
}
