// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md section 4.9): the FIRST test is a typography
// warmup that runs before any path_provider mock is installed. Harness copied from
// weight_sheet_measurements_link_test.dart.
@Timeout(Duration(minutes: 4))
library;

// goal-change-targets B2: the Weight sheet says, with the exact numbers, when the weigh-in moved the
// targets, and stays the plain "Weight logged" line when it did not. TargetImpactCopy.weighInSnackbar
// is pinned exactly in the pure group below.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/target_impact_copy.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/home/widgets/weight_log_sheet.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';
import 'package:icanbefitter/features/profile/services/weigh_in_target_refresh.dart';

import '../helpers/flutter_error_capture.dart';
import '../helpers/hive_test_setup.dart';

class _StubWeightLog extends WeightLogNotifier {
  _StubWeightLog(this.result);
  final WeightLogResult result;

  @override
  Future<WeightLogResult> logWeight(double weightKg) async => result;
}

void main() {
  testWidgets('typography warmup - GoogleFonts caches before any Hive mock', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('a', style: AppTypography.body),
          Text('b', style: AppTypography.bodyS),
          Text('c', style: AppTypography.titleS),
          Text('d', style: AppTypography.mono),
          Text('e', style: AppTypography.monoXs),
          Text('f', style: AppTypography.display),
          Text('g', style: AppTypography.label),
          Text('h', style: AppTypography.numeric),
          Text('i', style: AppTypography.buttonLabel),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('TargetImpactCopy.weighInSnackbar (pure)', () {
    test('exact text: comma formatting, new numbers first, old in brackets', () {
      expect(
        TargetImpactCopy.weighInSnackbar(
            caloriesFrom: 2111, caloriesTo: 1775, proteinFrom: 150, proteinTo: 1234),
        'Weight logged ✓  Targets updated: 1,775 kcal, 1,234 g protein (was 2,111 kcal, 150 g)',
      );
    });

    test('an unknown old number reads "not set"', () {
      final s = TargetImpactCopy.weighInSnackbar(
          caloriesFrom: null, caloriesTo: 1800, proteinFrom: null, proteinTo: 140);
      expect(s, contains('(was not set kcal, not set g)'));
    });

    test('the line pair for the dialogs', () {
      expect(TargetImpactCopy.caloriesLine(from: 2000, to: 1775),
          'Daily calories 2,000 → 1,775 kcal');
      expect(TargetImpactCopy.proteinLine(from: 144, to: 130), 'Protein 144 → 130 g');
    });
  });

  group('WeightLogSheet snackbar', () {
    late Directory dir;
    late FlutterErrorCapture errors;

    setUp(() async {
      dir = await setUpHiveForTests();
      errors = FlutterErrorCapture();
    });

    tearDown(() async {
      errors.stop();
      await tearDownHiveForTests(dir);
    });

    Future<void> saveWith(WidgetTester tester, WeightLogResult result) async {
      errors.start();
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          authUserIdTokenProvider.overrideWithValue(kTestUserId),
          measurementsEnabledProvider.overrideWithValue(false),
          weightLogNotifierProvider.overrideWith(() => _StubWeightLog(result)),
        ],
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
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SAVE'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('targets moved: the snackbar carries the exact numbers', (tester) async {
      await saveWith(
        tester,
        const WeightLogResult(
          wrote: true,
          targetsMoved: true,
          caloriesFrom: 2111,
          caloriesTo: 1775,
          proteinFrom: 150,
          proteinTo: 130,
        ),
      );
      expect(
        find.text(
            'Weight logged ✓  Targets updated: 1,775 kcal, 130 g protein (was 2,111 kcal, 150 g)'),
        findsOneWidget,
      );
    });

    testWidgets('targets did not move: the plain line', (tester) async {
      await saveWith(tester, const WeightLogResult(wrote: true));
      expect(find.text('Weight logged ✓'), findsOneWidget);
      expect(find.textContaining('Targets updated'), findsNothing);
    });
  });
}
