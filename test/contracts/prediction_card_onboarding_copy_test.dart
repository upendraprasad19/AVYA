// Regression test for audit-2026-05-16 reader-side / R7 —
// PredictionCard's empty-state copy must NOT say "Complete onboarding"
// for users who ARE onboarded but whose prediction simply hasn't been
// generated yet.
//
// Pre-fix `prediction_card.dart:93-94` rendered:
//   "Complete onboarding to get your personalised fitness prediction."
// whenever `predictionText` was null/empty — regardless of actual
// onboarding state. Live symptom on 2026-05-16: founder (fully
// onboarded) saw the message because `prediction_text` Hive field
// wasn't restored from cloud on fresh install.
//
// Fix: caller passes `onboardingCompleted` (read from
// `userProfileProvider['onboarding_completed_at']`); card branches
// placeholder copy AND surfaces an UPDATE CTA for onboarded users so
// they can actually trigger generation.
//
// closes-diagnose: 2026-05-16-prediction-card-onboarding-copy

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/widgets/prediction_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  group('PredictionCard empty-state copy', () {
    testWidgets(
        'non-onboarded user sees "Complete onboarding" copy (unchanged)',
        (tester) async {
      await tester.pumpWidget(wrap(PredictionCard(
        predictionText: null,
        generatedAt: null,
        isPro: false,
        canRefresh: false,
        isStale: false,
        onboardingCompleted: false,
        onRefreshTap: () {},
      )));

      expect(
          find.text(
              'Complete onboarding to get your personalised fitness prediction.'),
          findsOneWidget);
      expect(find.text('UPDATE'), findsNothing,
          reason:
              'Non-onboarded users do not get an empty-state UPDATE CTA — '
              'the path forward is to complete onboarding first.');
    });

    testWidgets(
        'onboarded user with no prediction sees "queued / tap UPDATE" copy',
        (tester) async {
      await tester.pumpWidget(wrap(PredictionCard(
        predictionText: null,
        generatedAt: null,
        isPro: false,
        canRefresh: false,
        isStale: false,
        onboardingCompleted: true,
        onRefreshTap: () {},
      )));

      expect(
          find.text(
              'Complete onboarding to get your personalised fitness prediction.'),
          findsNothing,
          reason:
              'Onboarded users must NOT see the "complete onboarding" copy '
              '— that misleads them. Pre-fix bug: empty predictionText '
              'triggered this copy regardless of onboarding state.');
      expect(
          find.text(
              'Your forecast is queued. Tap UPDATE to generate it now.'),
          findsOneWidget);
    });

    testWidgets('onboarded user with no prediction sees UPDATE CTA',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(PredictionCard(
        predictionText: null,
        generatedAt: null,
        isPro: false, // even free tier sees the CTA — first prediction is free
        canRefresh: false,
        isStale: false,
        onboardingCompleted: true,
        onRefreshTap: () => tapped = true,
      )));

      expect(find.text('UPDATE'), findsOneWidget,
          reason:
              'Empty-state CTA must be visible for onboarded users so they '
              'can trigger first-time generation (free per docs/architecture/business-rules.md).');

      await tester.tap(find.text('UPDATE'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('user with existing prediction sees full action row (no empty-state CTA)',
        (tester) async {
      await tester.pumpWidget(wrap(PredictionCard(
        predictionText: 'You will reach 80kg by August.',
        generatedAt: DateTime(2026, 5, 16),
        isPro: false,
        canRefresh: false,
        isStale: false,
        onboardingCompleted: true,
        onRefreshTap: () {},
      )));

      expect(find.text('DISPATCH'), findsOneWidget,
          reason: 'Share button visible when prediction exists');
      // PRO label shown (free user), no empty-state CTA. The two
      // "UPDATE" branches must be mutually exclusive — never both.
      expect(find.text('PRO'), findsOneWidget);
    });
  });
}
