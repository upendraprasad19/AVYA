import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/widgets/wardroom/rank_chip.dart';

void main() {
  testWidgets('RankChip shows rank name + countdown', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RankChip(
            rankCode: 'SD2',
            displayName: 'SEAMAN 2ND CLASS',
            countdownText: 'NEXT IN 12 DAYS',
          ),
        ),
      ),
    );

    expect(find.text('SEAMAN 2ND CLASS'), findsOneWidget);
    expect(find.text('NEXT IN 12 DAYS'), findsOneWidget);
  });

  testWidgets('RankChip shows MAX RANK when terminal', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RankChip(
            rankCode: 'Capt',
            displayName: 'CAPTAIN',
            countdownText: null,
            isTerminal: true,
          ),
        ),
      ),
    );

    // RankInsignia text fallback also renders 'CAPTAIN' (shortName ==
    // displayName for Captain), so >=1 match is the right contract.
    expect(find.text('CAPTAIN'), findsAtLeastNWidgets(1));
    expect(find.text('MAX RANK ACHIEVED'), findsOneWidget);
    expect(find.text('NEXT IN 12 DAYS'), findsNothing);
  });
}
