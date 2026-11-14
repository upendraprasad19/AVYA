// test/wardroom/ward_rank_pill_test.dart
//
// Smoke tests for WardRankPill — collapsed render, tap expands,
// builder invocation count, second tap collapses.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_pill.dart';

void main() {
  testWidgets('renders pill collapsed by default — builder NOT invoked',
      (tester) async {
    var builderCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WardRankPill(
          rankCode: 'LS',
          shortCapsName: 'LEADING SEAMAN',
          expandedContentBuilder: (ctx) {
            builderCalls++;
            return const Text('SERVICE-RECORD-CONTENT');
          },
        ),
      ),
    ));

    expect(find.text('LEADING SEAMAN'), findsOneWidget);
    expect(find.text('SERVICE-RECORD-CONTENT'), findsNothing);
    // Lazy-build proof: 0 invocations until expanded.
    expect(builderCalls, 0);
  });

  testWidgets('tap expands the pill and calls the builder', (tester) async {
    var builderCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WardRankPill(
          rankCode: 'LS',
          shortCapsName: 'LEADING SEAMAN',
          expandedContentBuilder: (ctx) {
            builderCalls++;
            return const Text('SERVICE-RECORD-CONTENT');
          },
        ),
      ),
    ));

    await tester.tap(find.text('LEADING SEAMAN'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.text('SERVICE-RECORD-CONTENT'), findsOneWidget);
    expect(builderCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('second tap collapses the pill', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WardRankPill(
          rankCode: 'LS',
          shortCapsName: 'LEADING SEAMAN',
          expandedContentBuilder: (ctx) =>
              const Text('SERVICE-RECORD-CONTENT'),
        ),
      ),
    ));

    await tester.tap(find.text('LEADING SEAMAN'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('SERVICE-RECORD-CONTENT'), findsOneWidget);

    await tester.tap(find.text('LEADING SEAMAN'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('SERVICE-RECORD-CONTENT'), findsNothing);
  });
}
