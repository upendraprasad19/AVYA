// Obs 5, internal-testing batch 2026-09-14. The Profile "Credits & Licences"
// row used to open Flutter's stock showLicensePage directly, which dumps
// every registered package (including dev/build tooling internals) with no
// curation. This screen replaces that direct tap target with a minimal
// attribution view + a single row that opens the full stock list on demand.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/screens/credits_licenses_screen.dart';

void main() {
  testWidgets('shows curated attribution, not the raw package dump',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CreditsLicensesScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('ICANBEFITTER'), findsOneWidget);
    expect(
      find.textContaining('workout-guide'),
      findsOneWidget,
      reason: 'artwork attribution required by CC BY-SA must stay visible',
    );
    expect(find.text('Powered by Flutter'), findsOneWidget);

    // The noisy stock dump (e.g. build-tooling package names) must NOT be
    // dumped inline on this curated screen — it lives one tap away instead.
    expect(find.text('_fe_analyzer_shared'), findsNothing);
    expect(find.textContaining('license'), findsNothing);

    // Single row to reach the full stock license list on demand.
    expect(find.text('View all open-source licences'), findsOneWidget);
  });

  testWidgets('tapping the row opens the stock license page', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CreditsLicensesScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View all open-source licences'));
    await tester.pumpAndSettle();

    // Flutter's stock LicensePage renders this title.
    expect(find.text('Licenses'), findsOneWidget);
  });
}
