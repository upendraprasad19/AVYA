import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/auth/widgets/auth_header.dart';

void main() {
  group('AuthHeader', () {
    testWidgets('renders eyebrow + title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthHeader(eyebrow: 'RECRUIT REGISTRY', title: 'Sign in'),
          ),
        ),
      );
      expect(find.text('RECRUIT REGISTRY'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('back button when onBack provided', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuthHeader(
              eyebrow: 'RECRUIT REGISTRY',
              title: 'Sign in',
              onBack: () => pressed = true,
            ),
          ),
        ),
      );
      final backBtn = find.byKey(const ValueKey('auth-header-back'));
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      expect(pressed, true);
    });

    testWidgets('no back button when onBack null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthHeader(eyebrow: 'RECRUIT REGISTRY', title: 'Sign in'),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('auth-header-back')), findsNothing);
    });

    testWidgets('renders mini AVYA seal', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthHeader(eyebrow: 'RECRUIT REGISTRY', title: 'Sign in'),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('auth-header-seal')), findsOneWidget);
    });
  });
}
