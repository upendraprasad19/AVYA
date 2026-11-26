// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md section 4.9): the FIRST test
// is a typography warmup that runs before any path_provider mock is installed,
// and renders every style the Weight sheet and the measurements sheet use.
// Reference: test/widgets/day_swap_allowance_line_test.dart.
@Timeout(Duration(minutes: 4))
library;

// L2b Landing B (B6, E2) - the "Add body measurements" link on the Weight sheet.
// Plan: docs/plans/coach-measurement-sheet-ui.md (B6, section 4).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/measurement_copy.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/widgets/weight_log_sheet.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_prompt_provider.dart';
import 'package:icanbefitter/features/profile/services/measurement_prompt_rules.dart';
import 'package:icanbefitter/features/profile/widgets/body_measurements_sheet.dart';

import '../helpers/flutter_error_capture.dart';
import '../helpers/hive_test_setup.dart';

class _FakePrompt extends MeasurementPromptNotifier {
  _FakePrompt(this.initial, this.log, this.holder);
  final MeasurementPrompt initial;
  final List<String> log;
  final List<_FakePrompt> holder;

  @override
  MeasurementPrompt build() {
    log.add('build');
    holder.add(this);
    return initial;
  }

  void set(MeasurementPrompt p) => state = p;
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
              Text('e', style: AppTypography.monoXs),
              Text('f', style: AppTypography.display),
              Text('g', style: AppTypography.label),
              Text('h', style: AppTypography.numeric),
              Text('i', style: AppTypography.buttonLabel),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('WeightLogSheet measurements link', () {
    late Directory dir;
    late List<String> promptLog;
    late List<_FakePrompt> prompts;
    late FlutterErrorCapture errors;

    setUp(() async {
      dir = await setUpHiveForTests();
      promptLog = [];
      prompts = [];
      // The Weight sheet's fixed 160 dp weight row overflows by a few pixels
      // under the test font, with the flag OFF as well (see
      // FlutterErrorCapture). The tests below care what the LINK adds.
      errors = FlutterErrorCapture();
    });

    tearDown(() async {
      errors.stop();
      expect(
        errors.others,
        isEmpty,
        reason: 'only render overflows are expected',
      );
      await tearDownHiveForTests(dir);
    });

    List<Override> overrides({
      required bool flag,
      required MeasurementPrompt prompt,
    }) => [
      authUserIdTokenProvider.overrideWithValue(kTestUserId),
      measurementsEnabledProvider.overrideWithValue(flag),
      measurementPromptProvider.overrideWith(
        () => _FakePrompt(prompt, promptLog, prompts),
      ),
      bodyMeasurementsProvider.overrideWith(_FakeHistory.new),
    ];

    /// Launch shape A (Home quick action): a modal sheet from the page itself.
    Widget hostA(List<Override> o) => ProviderScope(
      key: UniqueKey(),
      overrides: o,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: ctx,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => const WeightLogSheet(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    /// Launch shape B (rest-day sheet): a first sheet pops itself and then
    /// opens the Weight sheet with its OWN (now popped) context.
    Widget hostB(List<Override> o) => ProviderScope(
      key: UniqueKey(),
      overrides: o,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: ctx,
                builder: (sheetCtx) => ElevatedButton(
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    showModalBottomSheet<void>(
                      context: sheetCtx,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => const WeightLogSheet(),
                    );
                  },
                  child: const Text('first'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    Future<void> openA(WidgetTester tester, List<Override> o) async {
      await tester.pumpWidget(hostA(o));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    final link = find.text(MeasurementCopy.weightSheetLink);

    /// The capture must be installed INSIDE the test body: the test binding
    /// replaces FlutterError.onError when the body starts, after setUp.
    void wtest(String description, Future<void> Function(WidgetTester) body) {
      testWidgets(description, (tester) async {
        errors.start();
        try {
          await body(tester);
        } finally {
          errors.stop();
        }
      });
    }

    wtest('flag ON and a due or baseline prompt: the link is offered', (
      tester,
    ) async {
      for (final p in [MeasurementPrompt.due, MeasurementPrompt.baseline]) {
        await openA(tester, overrides(flag: true, prompt: p));
        expect(link, findsOneWidget, reason: '$p');
        Navigator.of(tester.element(find.byType(WeightLogSheet))).pop();
        await tester.pumpAndSettle();
      }
    });

    wtest('prompt none: no link, and the Weight sheet is today\'s tree '
        '(no scroll view)', (tester) async {
      await openA(
        tester,
        overrides(flag: true, prompt: MeasurementPrompt.none),
      );
      expect(link, findsNothing);
      expect(
        find.descendant(
          of: find.byType(WeightLogSheet),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
    });

    wtest('flag OFF: no link, no scroll view, and the prompt provider is '
        'never built', (tester) async {
      await openA(
        tester,
        overrides(flag: false, prompt: MeasurementPrompt.due),
      );
      expect(link, findsNothing);
      expect(
        find.descendant(
          of: find.byType(WeightLogSheet),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
      expect(promptLog, isEmpty);
    });

    wtest('with the link the sheet scrolls', (tester) async {
      await openA(tester, overrides(flag: true, prompt: MeasurementPrompt.due));
      expect(
        find.descendant(
          of: find.byType(WeightLogSheet),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
    });

    wtest('the link is a tap target of at least 44 dp', (tester) async {
      await openA(tester, overrides(flag: true, prompt: MeasurementPrompt.due));
      final size = tester.getSize(
        find.ancestor(of: link, matching: find.byType(TextButton)).first,
      );
      expect(size.height, greaterThanOrEqualTo(44));
    });

    wtest('launch shape A: a tap pops the Weight sheet and opens the '
        'measurements sheet', (tester) async {
      await openA(tester, overrides(flag: true, prompt: MeasurementPrompt.due));
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.byType(WeightLogSheet), findsNothing);
      expect(find.byType(BodyMeasurementsSheet), findsOneWidget);
      expect(errors.others, isEmpty);
      expect(
        errors.overflowsIn('body_measurements_sheet.dart'),
        isEmpty,
        reason: 'the sheet this change adds reports no overflow of its own',
      );
    });

    wtest('launch shape B (opened from a popped sheet\'s own context): '
        'a tap still opens the measurements sheet', (tester) async {
      await tester.pumpWidget(
        hostB(overrides(flag: true, prompt: MeasurementPrompt.baseline)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('first'));
      await tester.pumpAndSettle();
      expect(find.byType(WeightLogSheet), findsOneWidget);
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.byType(WeightLogSheet), findsNothing);
      expect(find.byType(BodyMeasurementsSheet), findsOneWidget);
      expect(errors.others, isEmpty);
      expect(errors.overflowsIn('body_measurements_sheet.dart'), isEmpty);
    });

    wtest('a weight typed but not saved writes no weight log when the link is '
        'taken', (tester) async {
      await tester.runAsync(
        () => HiveService.instance.healthBox.put('weight_2026-01-01', {
          'type': 'weight_log',
          'weight_kg': 70.0,
        }),
      );
      List<String> weightKeys() => HiveService.instance.healthBox.keys
          .map((k) => '$k')
          .where((k) => k.startsWith('weight_'))
          .toList();
      expect(weightKeys(), [
        'weight_2026-01-01',
      ], reason: 'control: the prefix');

      await openA(tester, overrides(flag: true, prompt: MeasurementPrompt.due));
      await tester.enterText(find.byType(TextField).first, '72.5');
      await tester.pump();
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.byType(BodyMeasurementsSheet), findsOneWidget);
      expect(weightKeys(), [
        'weight_2026-01-01',
      ], reason: 'the typed 72.5 was never saved');
    });

    wtest('a prompt that flips to none while the sheet is open does not '
        'remove the link or move focus (the decision is latched)', (
      tester,
    ) async {
      await openA(tester, overrides(flag: true, prompt: MeasurementPrompt.due));
      final field = find.byType(TextField);
      final node = tester.widget<TextField>(field).focusNode;
      final element = tester.element(field);
      expect(link, findsOneWidget);
      prompts.last.set(MeasurementPrompt.none);
      await tester.pump();
      expect(link, findsOneWidget, reason: 'latched at open');
      expect(
        identical(tester.element(field), element),
        isTrue,
        reason: 'the weight field subtree was not re-created',
      );
      expect(tester.widget<TextField>(field).focusNode, node);
      // The autofocused field still holds the keyboard.
      expect(FocusManager.instance.primaryFocus?.hasPrimaryFocus, isTrue);
      expect(
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .widget
            .focusNode
            .hasFocus,
        isTrue,
      );
    });

    wtest('a prompt that flips to due while the sheet is open adds no '
        'link and leaves the field and its focus alone', (tester) async {
      await openA(
        tester,
        overrides(flag: true, prompt: MeasurementPrompt.none),
      );
      final field = find.byType(TextField);
      final element = tester.element(field);
      prompts.last.set(MeasurementPrompt.due);
      await tester.pump();
      expect(link, findsNothing);
      expect(identical(tester.element(field), element), isTrue);
      expect(
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .widget
            .focusNode
            .hasFocus,
        isTrue,
      );
    });

    // ── the overflow matrix: the link adds a row, so every shape must fit ─────
    //
    // Compared with the same geometry WITHOUT the link (prompt none): the link
    // may add no overflow report of its own (a vertical one is what a missing
    // scroll view would cause).

    Future<List<String>> openAndMeasure(
      WidgetTester tester, {
      required MeasurementPrompt prompt,
      required Size size,
      required double inset,
      required double scale,
      Size? box,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      addTearDown(tester.view.reset);
      errors.clear();
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: overrides(flag: true, prompt: prompt),
          child: MaterialApp(
            builder: (ctx, child) {
              var mq = MediaQuery.of(
                ctx,
              ).copyWith(textScaler: TextScaler.linear(scale));
              Widget content = child!;
              if (box != null) {
                // The shell hands a sheet a SMALLER box with no inset.
                mq = mq.copyWith(size: box, viewInsets: EdgeInsets.zero);
                content = Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox.fromSize(size: box, child: child),
                );
              }
              return MediaQuery(data: mq, child: content);
            },
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: ctx,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => const WeightLogSheet(),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      if (prompt != MeasurementPrompt.none) {
        await tester.ensureVisible(link);
        expect(link, findsOneWidget);
      }
      return List.of(errors.overflows);
    }

    wtest('control: an overflow report names the file of the widget that '
        'overflowed (so overflowsIn is not vacuous)', (tester) async {
      final reports = await openAndMeasure(
        tester,
        prompt: MeasurementPrompt.none,
        size: const Size(360, 640),
        inset: 0,
        scale: 1.0,
      );
      expect(
        reports,
        isNotEmpty,
        reason: 'the fixed weight row overflows under the test font',
      );
      expect(errors.overflowsIn('weight_log_sheet.dart'), isNotEmpty);
      expect(
        errors.overflowsIn('body_measurements_sheet.dart'),
        isEmpty,
        reason: 'a different file fragment does not match',
      );
    });

    for (final geometry in <(String, Size, double, Size?)>[
      ('360x640', const Size(360, 640), 0, null),
      ('320x480 with a 300 dp keyboard inset', const Size(320, 480), 300, null),
      (
        'a 360x260 shell box, no inset',
        const Size(360, 640),
        0,
        const Size(360, 260),
      ),
      (
        'a 320x100 shell box, no inset',
        const Size(320, 480),
        0,
        const Size(320, 100),
      ),
    ]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        wtest('${geometry.$1}, text scale $scale: the link adds no '
            'overflow of its own and stays reachable', (tester) async {
          final without = await openAndMeasure(
            tester,
            prompt: MeasurementPrompt.none,
            size: geometry.$2,
            inset: geometry.$3,
            scale: scale,
            box: geometry.$4,
          );
          final withLink = await openAndMeasure(
            tester,
            prompt: MeasurementPrompt.due,
            size: geometry.$2,
            inset: geometry.$3,
            scale: scale,
            box: geometry.$4,
          );
          for (final m in withLink) {
            expect(
              without,
              contains(m),
              reason: 'an overflow only the link version reports: $m',
            );
          }
        });
      }
    }
  });
}
