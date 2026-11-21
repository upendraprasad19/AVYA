// Stats CONTINUE vs the target-weight rules (founder call 2026-11-01).
// Writer: StatsScreen._onCalibrate -> validateTargetWeight -> dialog | go(details).
// Reader: the Details route receives `extra['target_weight_kg']` + `seeded_for_goal`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/features/onboarding/screens/stats_screen.dart';

void main() {
  Map<String, dynamic>? detailsExtra;
  Map<String, dynamic>? goalExtra;

  Widget build(String goal, Map<String, dynamic> initial) {
    detailsExtra = null;
    goalExtra = null;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => StatsScreen(goal: goal, initial: initial),
      ),
      GoRoute(
        path: '/onboarding/details',
        builder: (_, state) {
          detailsExtra = Map<String, dynamic>.from((state.extra as Map?) ?? const {});
          return const Scaffold(body: Text('DETAILS'));
        },
      ),
      GoRoute(
        path: '/onboarding/goal',
        builder: (_, state) {
          goalExtra = Map<String, dynamic>.from((state.extra as Map?) ?? const {});
          return const Scaffold(body: Text('GOAL'));
        },
      ),
    ]);
    return MaterialApp.router(routerConfig: router);
  }

  Finder targetField() => find.byType(TextField).at(1);

  Future<void> tallScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> tapContinue(WidgetTester tester) async {
    final f = find.textContaining('CONTINUE');
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('Cut with a HIGHER target shows the popup and does not navigate',
      (tester) async {
    await tallScreen(tester);
    await tester.pumpWidget(build('lose_fat', {
      'weight_kg': 75.0,
      'target_weight_kg': 80.0,
      'seeded_for_goal': 'lose_fat',
    }));
    await tapContinue(tester);
    expect(find.byKey(const ValueKey('target_weight_dialog')), findsOneWidget);
    expect(find.textContaining('lower than your current weight'),
        findsOneWidget);
    expect(detailsExtra, isNull, reason: 'must not navigate on an invalid target');
  });

  testWidgets('closing the popup returns to the screen with focus on TARGET',
      (tester) async {
    await tallScreen(tester);
    await tester.pumpWidget(build('lose_fat', {
      'weight_kg': 75.0,
      'target_weight_kg': 80.0,
      'seeded_for_goal': 'lose_fat',
    }));
    await tapContinue(tester);
    await tester.tap(find.byKey(const ValueKey('target_weight_dialog_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('target_weight_dialog')), findsNothing);
    expect(detailsExtra, isNull);
    final tf = tester.widget<TextField>(targetField());
    expect(tf.focusNode?.hasFocus, isTrue,
        reason: 'focus must return to the TARGET field');
  });

  testWidgets('tapping outside dismisses the popup too', (tester) async {
    await tallScreen(tester);
    await tester.pumpWidget(build('build_muscle', {
      'weight_kg': 75.0,
      'target_weight_kg': 70.0,
      'seeded_for_goal': 'build_muscle',
    }));
    await tapContinue(tester);
    expect(find.textContaining('higher than your current weight'),
        findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('target_weight_dialog')), findsNothing);
  });

  testWidgets('Maintain outside +-3 kg shows the popup; inside continues',
      (tester) async {
    await tallScreen(tester);
    await tester.pumpWidget(build('general_fitness', {
      'weight_kg': 75.0,
      'target_weight_kg': 79.0,
      'seeded_for_goal': 'general_fitness',
    }));
    await tapContinue(tester);
    expect(find.byKey(const ValueKey('target_weight_dialog')), findsOneWidget);
    expect(detailsExtra, isNull);

    await tester.pumpWidget(build('general_fitness', {
      'weight_kg': 75.0,
      'target_weight_kg': 78.0,
      'seeded_for_goal': 'general_fitness',
    }));
    await tapContinue(tester);
    expect(find.byKey(const ValueKey('target_weight_dialog')), findsNothing);
    expect(detailsExtra?['target_weight_kg'], 78.0);
    expect(detailsExtra?['seeded_for_goal'], 'general_fitness');
  });

  testWidgets('a valid Cut target continues and carries seeded_for_goal',
      (tester) async {
    await tallScreen(tester);
    await tester.pumpWidget(build('lose_fat', {'weight_kg': 75.0}));
    // Untouched: seed is current - 5 = 70.0, which satisfies the Cut rule.
    await tapContinue(tester);
    expect(find.byKey(const ValueKey('target_weight_dialog')), findsNothing);
    expect(detailsExtra?['target_weight_kg'], 70.0);
    expect(detailsExtra?['seeded_for_goal'], 'lose_fat');
  });

  testWidgets('a blank target is rejected for a Cut', (tester) async {
    await tallScreen(tester);
    await tester.pumpWidget(build('lose_fat', {'weight_kg': 75.0}));
    await tester.enterText(targetField(), '');
    await tapContinue(tester);
    expect(find.text('Enter your target weight to continue.'), findsOneWidget);
    expect(detailsExtra, isNull);
  });

  testWidgets('goal changed after BACK reseeds the target (Cut -> Build)',
      (tester) async {
    await tallScreen(tester);
    // Extras as Stats BACK would have written them for a Cut: target 70.
    await tester.pumpWidget(build('build_muscle', {
      'weight_kg': 75.0,
      'target_weight_kg': 70.0,
      'seeded_for_goal': 'lose_fat',
    }));
    await tapContinue(tester);
    expect(find.byKey(const ValueKey('target_weight_dialog')), findsNothing,
        reason: 'untouched CONTINUE must not fail the Build rule');
    expect(detailsExtra?['target_weight_kg'], 78.0);
  });

  testWidgets('BACK writes seeded_for_goal and the typed target', (tester) async {
    await tallScreen(tester);
    await tester.pumpWidget(build('lose_fat', {'weight_kg': 75.0}));
    await tester.enterText(targetField(), '68.5');
    final back = find.text('BACK');
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(goalExtra?['seeded_for_goal'], 'lose_fat');
    expect(goalExtra?['target_weight_kg'], 68.5);
  });

  testWidgets('BACK with a blank target, same goal, reseeds from the delta',
      (tester) async {
    await tallScreen(tester);
    await tester.pumpWidget(build('lose_fat', {'weight_kg': 75.0}));
    await tester.enterText(targetField(), '');
    final back = find.text('BACK');
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(goalExtra?['target_weight_kg'], isNull,
        reason: 'a blank target is forwarded as null, not left to a stale spread');
    // Re-open Stats with those extras: it must reseed (-5), not resurrect a stale value.
    await tester.pumpWidget(build('lose_fat', {...?goalExtra}));
    await tester.pump();
    final tf = tester.widget<TextField>(targetField());
    expect(tf.controller?.text, '70.0');
  });

  testWidgets('blank BACK does not resurrect a stale target from the incoming extras',
      (tester) async {
    await tallScreen(tester);
    await tester.pumpWidget(build('lose_fat', {
      'weight_kg': 75.0,
      'target_weight_kg': 66.0,
      'seeded_for_goal': 'lose_fat',
    }));
    await tester.enterText(targetField(), '');
    final back = find.text('BACK');
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(goalExtra?['target_weight_kg'], isNull);
    await tester.pumpWidget(build('lose_fat', {...?goalExtra}));
    await tester.pump();
    expect(tester.widget<TextField>(targetField()).controller?.text, '70.0');
  });

  testWidgets('blank BACK writes explicit nulls for weight, height and body fat',
      (tester) async {
    await tallScreen(tester);
    await tester.pumpWidget(build('lose_fat', {
      'weight_kg': 75.0,
      'height_cm': 178.0,
      'body_fat_pct': 18.0,
    }));
    for (var i = 0; i < 4; i++) {
      if (i == 1) continue; // TARGET stays
      await tester.enterText(find.byType(TextField).at(i), '');
    }
    final back = find.text('BACK');
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();
    for (final k in const ['weight_kg', 'height_cm', 'body_fat_pct']) {
      expect(goalExtra!.containsKey(k), isTrue, reason: '$k key must be present');
      expect(goalExtra![k], isNull, reason: '$k must not be resurrected');
    }
  });
}
