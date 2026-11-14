// Diet plan Unit 3a (2026-11-14, docs/plans/diet-strategy.md §4 tests 7, 9,
// 9b): the Diet Plan screen's strategy block (DietStrategySection, the flag
// forced on through the seam) and Edit Profile's Save step
// (confirmEditProfileDietStrategy), on real Hive.
//
//   - free user: Low carb / Keto carry a PRO badge; a tap opens the paywall
//     for 'Diet Strategy'; nothing is written.
//   - PRO user: a tap opens the confirm dialog whose numbers equal the
//     helper before/after; Cancel writes nothing; Switch writes the field,
//     says so, selects the chip and shows the 3a meals note.
//   - equal shown targets: no dialog, the field is written, the snackbar
//     says the targets are already low in carbs.
//   - paused: a free user holding keto sees Balanced selected plus the hint;
//     a tap on that Balanced chip writes nothing (keto survives).
//   - Edit Profile: Cancel = null (nothing saved), unchanged shown targets =
//     write without a dialog, PRO lapsed at Save = false, calories moving =
//     the "also change" line with calorie and protein rows.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_actions.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_flags.dart';
import 'package:icanbefitter/features/nutrition/widgets/diet_strategy_section.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

import '../helpers/hive_test_setup.dart';

// Energy-consistent: 4 x 150 + 4 x 270 + 9 x 80 = 2400 kcal.
const _pack = <String, dynamic>{
  'full_name': 'T',
  'daily_calories': 2400,
  'protein_grams': 150,
  'carb_grams': 270,
  'carbs_grams': 270,
  'fat_grams': 80,
};

final _keto = BmrCalculator.macroSplit(
    dailyCalories: 2400,
    proteinGrams: 150,
    balancedCarbs: 270,
    strategy: DietStrategy.keto);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A tap whose handler WRITES Hive runs in the real zone: a box write started
/// inside the fake-async zone never completes there, and the tear-down's
/// HiveUserSession.closeAll() then waits on it forever.
Future<void> _tapReal(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await _settle(tester);
}

String? _stored() =>
    UserRepository.instance.getProfile()?['diet_strategy'] as String?;

void main() {
  testWidgets('typography warmup — GoogleFonts caches before any Hive mock',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('a', style: AppTypography.h3),
          Text('b', style: AppTypography.bodySm),
          Text('c', style: AppTypography.monoXs),
          Text('d', style: AppTypography.body),
          Text('e', style: AppTypography.mono),
          // Fraunces (the paywall letterhead) and every DM Sans weight the
          // chips, dialog and snackbars use: GoogleFonts caches per family
          // AND weight, and the Hive group mocks path_provider.
          Text('f', style: AppTypography.h1),
          Text('g', style: AppTypography.body.copyWith(fontWeight: FontWeight.w700)),
          Text('h', style: AppTypography.body.copyWith(fontWeight: FontWeight.w400)),
          Text('i', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w700)),
          const WardButton(label: 'x', onPressed: null),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  test('preview: the OLD side uses the current PRO state, the NEW side '
      'assumes PRO (the gate just passed; a user mid-verification still sees '
      'the real change)', () {
    const base = (calories: 2400.0, protein: 150.0, carbs: 270.0, fat: 80.0);
    final p = previewDietStrategyChange(
      beforeBase: base,
      afterBase: base,
      storedStrategy: 'keto',
      next: DietStrategy.lowCarb,
      currentPro: false,
    )!;
    expect(p.before.strategy, DietStrategy.balanced);
    expect(p.before.carbs, 270);
    expect(p.after.strategy, DietStrategy.lowCarb);
    expect(p.after.carbs, 120);
    expect(p.sameShown, isFalse);
    expect(p.caloriesOrProteinMove, isFalse);
  });

  test('result copy: "updated" only when a shown number moved', () {
    const base = (calories: 2400.0, protein: 150.0, carbs: 270.0, fat: 80.0);
    final moved = previewDietStrategyChange(
        beforeBase: base,
        afterBase: base,
        storedStrategy: null,
        next: DietStrategy.keto,
        currentPro: true)!;
    expect(dietStrategyResultMessage(DietStrategy.keto, moved),
        'Targets updated for Keto');
    const low = (calories: 1500.0, protein: 150.0, carbs: 60.0, fat: 73.0);
    final same = previewDietStrategyChange(
        beforeBase: low,
        afterBase: low,
        storedStrategy: 'low_carb',
        next: DietStrategy.balanced,
        currentPro: true)!;
    expect(same.sameShown, isTrue);
    expect(dietStrategyResultMessage(DietStrategy.balanced, same),
        'Balanced is set. Your targets stay the same.');
    expect(dietStrategyResultMessage(DietStrategy.keto, null),
        'Diet strategy set to Keto.');
  });

  test('Edit Profile saved copy names a strategy dropped for lapsed PRO '
      '(B-pass seat B finding 2)', () {
    expect(editProfileSavedMessage(rescheduled: false), 'Profile saved');
    expect(editProfileSavedMessage(rescheduled: true),
        'Profile saved & workouts rescheduled');
    expect(
        editProfileSavedMessage(
            rescheduled: false, strategyNotSaved: DietStrategy.keto),
        'Profile saved. Keto needs PRO, so your diet strategy did not change.');
  });

  group('with Hive', () {
    late Directory dir;
    var pushes = 0;

    setUp(() async {
      dir = await setUpHiveForTests();
      pushes = 0;
      DietStrategyFlags.debugEnabledOverride = true;
      ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {};
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required reason, extra}) {};
      UserProfileNotifier.debugFoodTypeEffects = FoodTypeWriteEffects(
        currentUserId: () => 'user-a',
        pushSnapshot: () => pushes++,
        lockFields: (_) async {},
      );
    });

    tearDown(() async {
      DietStrategyFlags.debugEnabledOverride = null;
      ErrorTelemetry.debugOnLogEventForTests = null;
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
      UserProfileNotifier.debugFoodTypeEffects = null;
      await tearDownHiveForTests(dir);
    });

    Future<void> seed(WidgetTester tester,
        {required bool pro, Map<String, dynamic> extra = const {}}) async {
      await tester.runAsync(() async {
        await UserRepository.instance.updateProfileFields({..._pack, ...extra});
        await MigratedKey.write('isPro', pro);
        await MigratedKey.write('expiresAt',
            DateTime.now().add(const Duration(days: 30)).toIso8601String());
      });
    }

    Future<void> pumpSection(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: DietStrategySection())),
        ),
      ));
      await tester.pump();
    }

    Finder chip(DietStrategy s) =>
        find.byKey(ValueKey('diet_strategy_chip_${s.storageKey}'));

    testWidgets('free: PRO badges; a Keto tap opens the Diet Strategy paywall '
        'and writes nothing', (tester) async {
      await seed(tester, pro: false);
      await pumpSection(tester);
      expect(find.byKey(const ValueKey('diet_strategy_pro_badge_keto')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('diet_strategy_pro_badge_low_carb')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('diet_strategy_pro_badge_balanced')),
          findsNothing);
      await tester.tap(chip(DietStrategy.keto));
      await tester.pumpAndSettle();
      expect(find.text('Diet Strategy is a PRO feature'), findsOneWidget);
      expect(find.text('Low carb and keto targets, set for your goal.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('diet_strategy_confirm_dialog')),
          findsNothing);
      expect(_stored(), isNull);
      // Close the sheet so no route animation outlives the test.
      Navigator.of(tester.element(find.text('Diet Strategy is a PRO feature')))
          .pop();
      await tester.pumpAndSettle();
    });

    testWidgets('PRO: the dialog shows the helper before/after; Cancel '
        'writes nothing; Switch writes, says so and shows the meals note',
        (tester) async {
      await seed(tester, pro: true);
      await pumpSection(tester);
      expect(find.byKey(const ValueKey('diet_strategy_pro_badge_keto')),
          findsNothing);

      // The PRO gate (isPro, the DECISION path) may write Hive.
      await _tapReal(tester, chip(DietStrategy.keto));
      expect(find.text('Switch to Keto?'), findsOneWidget);
      expect(find.text('Carbs 270 g \u2192 ${_keto.carbGrams} g'),
          findsOneWidget);
      expect(find.text('Fat 80 g \u2192 ${_keto.fatGrams} g'), findsOneWidget);
      expect(find.text('Calories and protein stay the same.'), findsOneWidget);
      expect(find.textContaining('Calories 2400'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('diet_strategy_confirm_cancel')));
      await _settle(tester);
      expect(_stored(), isNull, reason: 'Cancel writes nothing');
      expect(pushes, 0);

      // The PRO gate (isPro, the DECISION path) may write Hive.
      await _tapReal(tester, chip(DietStrategy.keto));
      await _tapReal(
          tester, find.byKey(const ValueKey('diet_strategy_confirm_switch')));
      expect(_stored(), 'keto');
      expect(find.text('Targets updated for Keto'), findsOneWidget);
      expect(
          find.text('Meals for Keto come in the next update. '
              'This plan uses balanced meals.'),
          findsOneWidget);
      expect(tester.getSemantics(chip(DietStrategy.keto)).flagsCollection
          .isSelected, Tristate.isTrue);
    });

    testWidgets('equal shown targets: no dialog, written, "already low"',
        (tester) async {
      // Heavy-protein, low-calorie: Balanced carbs 60 g sit below Low carb's
      // 75 g floor, so Low carb equals Balanced for this user.
      await seed(tester, pro: true, extra: const {
        'daily_calories': 1500,
        'protein_grams': 150,
        'carb_grams': 60,
        'carbs_grams': 60,
        // Energy-consistent, as calculateTargets writes it:
        // 4 x 150 + 4 x 60 + 9 x 73 = 1497 kcal.
        'fat_grams': 73,
      });
      await pumpSection(tester);
      await _tapReal(tester, chip(DietStrategy.lowCarb));
      expect(find.byKey(const ValueKey('diet_strategy_confirm_dialog')),
          findsNothing);
      expect(_stored(), 'low_carb');
      expect(
          find.text('Low carb is set. Your targets stay the same: your carbs '
              'are already this low.'),
          findsOneWidget);
    });

    testWidgets('no targets and no inputs to compute them (hard-coded '
        'defaults, never strategy-shaped): no dialog, the field is written',
        (tester) async {
      await tester.runAsync(() async {
        await UserRepository.instance.updateProfileFields({'full_name': 'T'});
        await MigratedKey.write('isPro', true);
        await MigratedKey.write('expiresAt',
            DateTime.now().add(const Duration(days: 30)).toIso8601String());
      });
      await pumpSection(tester);
      await _tapReal(tester, chip(DietStrategy.keto));
      expect(find.byKey(const ValueKey('diet_strategy_confirm_dialog')),
          findsNothing);
      expect(_stored(), 'keto');
      // B-pass seat B finding 3: no shown number moved, so no "updated".
      expect(find.text('Diet strategy set to Keto.'), findsOneWidget);
      expect(find.text('Targets updated for Keto'), findsNothing);
    });

    testWidgets('a write that throws says so and stores nothing (B-pass seat '
        'B finding 1)', (tester) async {
      await seed(tester, pro: true);
      var reads = 0;
      UserProfileNotifier.debugFoodTypeEffects = FoodTypeWriteEffects(
        currentUserId: () {
          // The call's capture succeeds; the queued link's read throws, as a
          // failed Hive read or write would.
          if (++reads > 1) throw StateError('hive down');
          return 'user-a';
        },
        pushSnapshot: () => pushes++,
        lockFields: (_) async {},
      );
      await pumpSection(tester);
      await _tapReal(tester, chip(DietStrategy.keto));
      await _tapReal(
          tester, find.byKey(const ValueKey('diet_strategy_confirm_switch')));
      expect(find.text(kDietStrategyChangeFailedMessage), findsOneWidget);
      expect(_stored(), isNull);
      expect(pushes, 0);
    });

    testWidgets('paused: a free user holding keto sees Balanced selected and '
        'the hint; tapping Balanced keeps keto', (tester) async {
      await seed(tester, pro: false, extra: const {'diet_strategy': 'keto'});
      await pumpSection(tester);
      expect(tester.getSemantics(chip(DietStrategy.balanced)).flagsCollection
          .isSelected, Tristate.isTrue);
      expect(find.text('Keto is paused. It comes back with PRO.'),
          findsOneWidget);
      await _tapReal(tester, chip(DietStrategy.balanced));
      expect(_stored(), 'keto');
      expect(pushes, 0);
    });

    group('Edit Profile Save step', () {
      Future<bool?> run(
        WidgetTester tester, {
        required Map<String, dynamic> profile,
        Map<String, dynamic>? edited,
        Map<String, dynamic>? recompute,
        required DietStrategy next,
        required bool pro,
        Future<void> Function()? whileOpen,
      }) async {
        bool? result;
        var done = false;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await confirmEditProfileDietStrategy(context,
                      profile: profile,
                      edited: edited ?? profile,
                      recomputeAfter: recompute,
                      next: next,
                      pro: pro);
                  done = true;
                },
                child: const Text('save'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('save'));
        await tester.pumpAndSettle();
        if (whileOpen != null) await whileOpen();
        expect(done, isTrue);
        return result;
      }

      testWidgets('a changed strategy asks first; Cancel = null', (tester) async {
        final r = await run(tester,
            profile: _pack,
            next: DietStrategy.keto,
            pro: true, whileOpen: () async {
          expect(find.text('Switch to Keto?'), findsOneWidget);
          await tester
              .tap(find.byKey(const ValueKey('diet_strategy_confirm_cancel')));
          await tester.pumpAndSettle();
        });
        expect(r, isNull);
      });

      testWidgets('Switch = true', (tester) async {
        final r = await run(tester,
            profile: _pack,
            next: DietStrategy.keto,
            pro: true, whileOpen: () async {
          await tester
              .tap(find.byKey(const ValueKey('diet_strategy_confirm_switch')));
          await tester.pumpAndSettle();
        });
        expect(r, isTrue);
      });

      testWidgets('PRO lapsed between tap and Save: false, no dialog',
          (tester) async {
        final r = await run(tester,
            profile: _pack, next: DietStrategy.keto, pro: false);
        expect(r, isFalse);
        expect(find.byKey(const ValueKey('diet_strategy_confirm_dialog')),
            findsNothing);
      });

      testWidgets('back to Balanced while lapsed: true, no dialog (the shown '
          'targets are already Balanced)', (tester) async {
        final r = await run(tester,
            profile: {..._pack, 'diet_strategy': 'keto'},
            next: DietStrategy.balanced,
            pro: false);
        expect(r, isTrue);
      });

      testWidgets('other edits move calories: all four rows and the '
          '"also change" line', (tester) async {
        await run(tester,
            profile: _pack,
            recompute: const {
              'daily_calories': 2200,
              'protein_grams': 140,
              'carb_grams': 250,
              'carbs_grams': 250,
              'fat_grams': 73,
            },
            next: DietStrategy.keto,
            pro: true, whileOpen: () async {
          expect(find.text('Calories 2400 kcal \u2192 2200 kcal'),
              findsOneWidget);
          expect(find.text('Protein 150 g \u2192 140 g'), findsOneWidget);
          expect(
              find.text('Calories and protein also change because you edited '
                  'other fields.'),
              findsOneWidget);
          await tester
              .tap(find.byKey(const ValueKey('diet_strategy_confirm_cancel')));
          await tester.pumpAndSettle();
        });
      });
    });

    test('PRESENCE: Edit Profile saves the field only with the flag on, only '
        'for a changed chip, and seeds from the EFFECTIVE strategy', () {
      final src = File('lib/features/profile/screens/edit_profile_screen.dart')
          .readAsStringSync();
      expect(
          RegExp(r'_dietStrategy = DietStrategyFlags\.enabled\s*\?\s*dietStrategyOfTargets\(ref\.read\(macroTargetsProvider\)\)\s*:\s*kDefaultDietStrategy;')
              .hasMatch(src),
          isTrue,
          reason: 'seeded from the EFFECTIVE strategy, and no provider read '
              'with the flag off (B-pass seat A finding 2)');
      expect(src,
          contains('if (DietStrategyFlags.enabled && _dietStrategy != _originalDietStrategy) {'));
      expect(src, contains("updates['diet_strategy'] = _dietStrategy.storageKey;"));
      expect(src, contains('strategyNotSaved = _dietStrategy;'));
      expect(src, contains('strategyNotSaved: strategyNotSaved,'));
      expect("'diet_strategy'".allMatches(src).length, 1,
          reason: 'one write site, inside the gated block');
      expect(src, contains('if (DietStrategyFlags.enabled) ...['));
    });

    test('PRESENCE: the Diet Plan screen mounts the section only with the flag '
        'on and stamps a saved plan only with the flag on', () {
      final src = File('lib/features/nutrition/screens/diet_plan_screen.dart')
          .readAsStringSync();
      expect(
          RegExp(r'if \(DietStrategyFlags\.enabled\) \.\.\.\[\s*const SizedBox\(height: AppSpacing\.sectionGap\),\s*const DietStrategySection\(\),')
              .hasMatch(src),
          isTrue);
      expect(
          RegExp(r"if \(DietStrategyFlags\.enabled\)\s*'diet_strategy':")
              .hasMatch(src),
          isTrue);
      expect("'diet_strategy'".allMatches(src).length, 1);
    });
  });
}
