// Goal screen offers exactly Build / Cut / Maintain (founder call 2026-11-01) and
// a legacy goal key arriving in the route extras (`recomp`, `strength`) falls back
// to the pre-selected default instead of leaving no card selected while CONTINUE
// forwards a hidden goal.
//
// Writer: GoalScreen CONTINUE -> `context.go('/onboarding/stats', extra: {goal})`.
// Reader: the Stats route builder (app_router.dart ~:284) reads `extra['goal']`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/features/onboarding/screens/goal_screen.dart';

void main() {
  Map<String, dynamic>? statsExtra;

  Widget build({String? initialGoal}) {
    statsExtra = null;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => GoalScreen(
          initialGoal: initialGoal,
          identity: const {'full_name': 'Test'},
        ),
      ),
      GoRoute(
        path: '/onboarding/stats',
        builder: (_, state) {
          statsExtra = Map<String, dynamic>.from((state.extra as Map?) ?? const {});
          return const Scaffold();
        },
      ),
    ]);
    return MaterialApp.router(routerConfig: router);
  }

  Future<void> continueTap(WidgetTester tester) async {
    await tester.tap(find.textContaining('CONTINUE'));
    await tester.pumpAndSettle();
  }

  testWidgets('offers exactly Build, Cut, Maintain', (tester) async {
    await tester.pumpWidget(build());
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Maintain'), findsOneWidget);
    expect(find.text('Recompose'), findsNothing);
    expect(find.text('Perform'), findsNothing);
  });

  testWidgets('default selection forwards build_muscle', (tester) async {
    await tester.pumpWidget(build());
    await continueTap(tester);
    expect(statsExtra?['goal'], 'build_muscle');
    expect(statsExtra?['full_name'], 'Test');
  });

  for (final legacy in const ['recomp', 'strength', 'nonsense']) {
    testWidgets('legacy initialGoal "$legacy" falls back to build_muscle',
        (tester) async {
      await tester.pumpWidget(build(initialGoal: legacy));
      await continueTap(tester);
      expect(statsExtra?['goal'], 'build_muscle');
    });
  }

  testWidgets('a valid initialGoal is preserved (Cut)', (tester) async {
    await tester.pumpWidget(build(initialGoal: 'lose_fat'));
    await continueTap(tester);
    expect(statsExtra?['goal'], 'lose_fat');
  });

  testWidgets('tapping Maintain then CONTINUE forwards general_fitness',
      (tester) async {
    await tester.pumpWidget(build());
    await tester.tap(find.text('Maintain'));
    await tester.pump();
    await continueTap(tester);
    expect(statsExtra?['goal'], 'general_fitness');
  });
}
