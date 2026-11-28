// test/wardroom/ward_rank_insignia_test.dart
//
// Smoke tests for all 11 Indian Navy rank insignia at 24dp (pill
// size) and 48dp (popup size). Goldens not yet wired in this repo,
// so we verify each painter renders without throwing + the SD2 text
// fallback shows the code label.
//
// Plan D-3 permits smoke tests if golden infra not yet set up.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_insignia.dart';

const _ranks = [
  'SD2',
  'SD1',
  'LS',
  'PO',
  'CPO',
  'MCPO',
  'SubLt',
  'Lt',
  'LtCdr',
  'Cdr',
  'Capt',
];

Widget _wrap(Widget child, double size) => MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF02070F),
        body: Center(
          child: SizedBox(width: size, height: size, child: child),
        ),
      ),
    );

void main() {
  for (final code in _ranks) {
    testWidgets('renders $code at 24dp', (tester) async {
      await tester.pumpWidget(
        _wrap(WardRankInsignia(rankCode: code, size: 24), 24),
      );
      expect(find.byType(WardRankInsignia), findsOneWidget);
      // Pump once more to flush any paint exceptions.
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: '$code painter must not throw at 24dp');
    });

    testWidgets('renders $code at 48dp', (tester) async {
      await tester.pumpWidget(
        _wrap(WardRankInsignia(rankCode: code, size: 48), 48),
      );
      expect(find.byType(WardRankInsignia), findsOneWidget);
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: '$code painter must not throw at 48dp');
    });
  }

  testWidgets('SD2 falls back to text label', (tester) async {
    await tester.pumpWidget(
      _wrap(const WardRankInsignia(rankCode: 'SD2', size: 24), 24),
    );
    expect(find.text('SD2'), findsOneWidget);
  });

  testWidgets('unknown code falls back to text label', (tester) async {
    await tester.pumpWidget(
      _wrap(const WardRankInsignia(rankCode: 'XYZ', size: 24), 24),
    );
    expect(find.text('XYZ'), findsOneWidget);
  });

  testWidgets('color override propagates to text fallback', (tester) async {
    const tealOverride = Color(0xFF00BFA6);
    await tester.pumpWidget(
      _wrap(
        const WardRankInsignia(
          rankCode: 'SD2',
          size: 24,
          color: tealOverride,
        ),
        24,
      ),
    );
    final txt = tester.widget<Text>(find.text('SD2'));
    expect(txt.style?.color, tealOverride);
  });
}
