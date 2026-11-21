import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/screens/promotion_celebration_screen.dart';

/// Plan F F-15 — promotion celebration overlay smoke tests.
void main() {
  testWidgets('PromotionCelebrationScreen renders header + insignia + ceremonial line + share button', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PromotionCelebrationScreen(newRankCode: 'SD1'),
      ),
    );
    await tester.pump();

    expect(find.text('PROMOTION DAY'), findsOneWidget);
    expect(find.text('Seaman 1st Class'), findsOneWidget);
    expect(find.textContaining('By order of the Captain'), findsOneWidget);
    expect(find.text('Share this moment'), findsOneWidget);
    expect(find.text('Tap anywhere to dismiss'), findsOneWidget);
  });

  testWidgets('Tap on background dismisses the screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                builder: (_) => const PromotionCelebrationScreen(newRankCode: 'LS'),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('PROMOTION DAY'), findsOneWidget);

    // Tap "Tap anywhere to dismiss" hint area (in the GestureDetector)
    await tester.tap(find.text('Tap anywhere to dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('PROMOTION DAY'), findsNothing);
  });

  testWidgets('Renders for unknown rank code without crashing (falls back to first rank)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PromotionCelebrationScreen(newRankCode: 'INVALID_CODE'),
      ),
    );
    await tester.pump();
    // Falls back to first ladder entry (SD2)
    expect(find.text('PROMOTION DAY'), findsOneWidget);
  });
}
