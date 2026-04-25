import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/features/onboarding/screens/mission_brief_screen.dart';

void main() {
  group('MissionBriefScreen', () {
    Widget buildScreen() {
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const MissionBriefScreen()),
        GoRoute(path: '/onboarding/identity', builder: (_, __) => const Scaffold()),
      ]);
      return ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('renders eyebrow + title', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.textContaining('MISSION BRIEF'), findsOneWidget);
      expect(find.text('A note from your coach.'), findsOneWidget);
    });

    testWidgets('renders founder name + credentials', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.text('UPENDRA PRASAD'), findsOneWidget);
      expect(find.textContaining('EX-INDIAN NAVY'), findsOneWidget);
      expect(find.textContaining('14 YEARS'), findsOneWidget);
      expect(find.textContaining('CERTIFIED'), findsOneWidget);
    });

    testWidgets('renders locked copy with Jai Hind', (tester) async {
      await tester.pumpWidget(buildScreen());
      // RichText splits text — find by widget that contains all spans
      expect(find.byType(RichText), findsWidgets);
    });

    testWidgets('renders Instagram link', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.byType(GestureDetector), findsWidgets);
    });

    testWidgets('renders single CONTINUE CTA', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.textContaining('CONTINUE'), findsOneWidget);
    });

    testWidgets('renders founder photo as AssetImage', (tester) async {
      await tester.pumpWidget(buildScreen());
      final imageFinder = find.byKey(const ValueKey('founder-photo'));
      expect(imageFinder, findsOneWidget);
      final image = tester.widget<Image>(imageFinder);
      expect(image.image, isA<AssetImage>());
      expect((image.image as AssetImage).assetName, 'assets/founder/upendra.jpg');
    });
  });
}
