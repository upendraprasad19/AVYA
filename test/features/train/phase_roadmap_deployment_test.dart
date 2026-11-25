// OI-447 — the Roadmap screen printed `DEPLOYMENT 01` for everybody, clamped to
// 12 weeks, and had no "you are here" on the rank ladder.
//
// Writer: `user_progress.current_phase` (commitPhaseAdvance), read by
// `PhaseRoadmapScreen.build` (UserRepository.getProgress) and handed to
// `RoadmapBody`. The pure helpers and the body are tested here; the screen
// shell only resolves singletons.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/train/screens/phase_roadmap_screen.dart';

Future<void> _pump(
  WidgetTester tester, {
  required int phase,
  required int weekInPhase,
  int? holdOrdinal,
}) async {
  tester.view.physicalSize = const Size(800, 9000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final programWeek = ((phase - 1) % 3) * 4 + weekInPhase;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RoadmapBody(
          phase: phase,
          weekInPhase: weekInPhase,
          programWeek: programWeek,
          phaseName: const [
            'Foundation',
            'Strength',
            'Hypertrophy',
          ][(phase - 1) % 3],
          holdOrdinal: holdOrdinal,
          isPro: true,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('pure position helpers', () {
    test('deployment number follows the phase, 3 phases each', () {
      expect([1, 2, 3, 4, 5, 6, 7, 12].map(roadmapDeploymentNumber).toList(), [
        1,
        1,
        1,
        2,
        2,
        2,
        3,
        4,
      ]);
      expect(roadmapDeploymentNumber(0), 1);
      expect(roadmapDeploymentNumber(-3), 1);
    });

    test('eyebrow is two-digit and upper-case', () {
      expect(
        roadmapDeploymentEyebrow(5, 'Strength'),
        'DEPLOYMENT 02 · STRENGTH',
      );
      expect(
        roadmapDeploymentEyebrow(1, 'Foundation'),
        'DEPLOYMENT 01 · FOUNDATION',
      );
    });

    test('absolute week spans deployments', () {
      expect(roadmapAbsoluteWeek(1, 1), 1);
      expect(roadmapAbsoluteWeek(4, 1), 13);
      expect(roadmapAbsoluteWeek(5, 3), 19);
      expect(roadmapAbsoluteWeek(12, 4), 48);
    });

    test('marker sits before the first ladder row past the week', () {
      expect(roadmapLadderMarkerIndex(12), isNull);
      expect(roadmapLadderMarkerIndex(13), 0); // before CPO (26)
      expect(roadmapLadderMarkerIndex(26), 1); // CPO reached, before MCPO
      expect(roadmapLadderMarkerIndex(48), 1);
      expect(roadmapLadderMarkerIndex(300), 7); // after the last row
    });

    test('hold caption never claims a new week', () {
      expect(
        roadmapYouAreHereLabel(absoluteWeek: 4),
        'YOU ARE HERE · PROGRAM WEEK 4',
      );
      expect(
        roadmapYouAreHereLabel(absoluteWeek: 4, holdOrdinal: 2),
        'YOU ARE HERE · HOLDING AFTER WEEK 4',
      );
    });
  });

  group('RoadmapBody', () {
    testWidgets('phase 1: Deployment 01, nothing complete, no ladder marker', (
      tester,
    ) async {
      await _pump(tester, phase: 1, weekInPhase: 2);
      expect(find.text('DEPLOYMENT 01 · FOUNDATION'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('roadmap_deployment_complete_1')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('roadmap_you_are_here')), findsNothing);
      expect(find.textContaining('WK 2 / 12'), findsOneWidget);
    });

    testWidgets('phase 4: Deployment 02, 01 complete, marker before CPO', (
      tester,
    ) async {
      await _pump(tester, phase: 4, weekInPhase: 1);
      expect(find.text('DEPLOYMENT 02 · FOUNDATION'), findsOneWidget);
      expect(find.text('DEPLOYMENT 01 · COMPLETE'), findsOneWidget);
      expect(find.text('YOU ARE HERE · PROGRAM WEEK 13'), findsOneWidget);
      expect(find.textContaining('WK 1 / 12'), findsOneWidget);
    });

    testWidgets('phase 5: the founder case — Deployment 02, WK n of THIS '
        'deployment, marker at absolute week', (tester) async {
      await _pump(tester, phase: 5, weekInPhase: 3);
      expect(find.text('DEPLOYMENT 02 · STRENGTH'), findsOneWidget);
      expect(find.text('DEPLOYMENT 01 · COMPLETE'), findsOneWidget);
      expect(find.text('YOU ARE HERE · PROGRAM WEEK 19'), findsOneWidget);
      // WK 7/12 of Deployment 02, 58% — not 'DEPLOYMENT 01' and not week 19.
      expect(find.textContaining('WK 7 / 12'), findsOneWidget);
      expect(find.text('DEPLOYMENT 01 · STRENGTH'), findsNothing);
    });

    testWidgets('phase 12: Deployment 04, three earlier ones complete', (
      tester,
    ) async {
      await _pump(tester, phase: 12, weekInPhase: 4);
      expect(find.text('DEPLOYMENT 04 · HYPERTROPHY'), findsOneWidget);
      for (final n in [1, 2, 3]) {
        expect(
          find.byKey(ValueKey('roadmap_deployment_complete_$n')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const ValueKey('roadmap_deployment_complete_4')),
        findsNothing,
      );
      expect(find.text('YOU ARE HERE · PROGRAM WEEK 48'), findsOneWidget);
    });

    testWidgets('hold arm: counter suppressed, caption says HOLDING', (
      tester,
    ) async {
      await _pump(tester, phase: 4, weekInPhase: 4, holdOrdinal: 1);
      expect(find.textContaining('HOLDING · '), findsWidgets);
      expect(find.textContaining('WK 4 / 12'), findsNothing);
      expect(find.text('YOU ARE HERE · HOLDING AFTER WEEK 16'), findsOneWidget);
    });
  });
}
