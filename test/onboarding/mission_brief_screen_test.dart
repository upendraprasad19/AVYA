import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/features/onboarding/screens/mission_brief_screen.dart';

void main() {
  // Backlog #3 (post-Test-#15) — un-skipped 2026-05-10. The original
  // skip note said AssetImage('assets/founder/upendra.jpg') fails to
  // load in widget tests. Verified that mission_brief_screen.dart:75
  // wraps Image.asset with an errorBuilder that falls back to a person
  // icon, so asset-load failure does NOT crash the widget tree. The
  // founder-photo Image widget is still findable by ValueKey regardless
  // of whether its underlying provider succeeded.
  //
  // The renders-founder-photo-as-AssetImage test still asserts the
  // image's provider type to lock the production AssetImage choice.
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

    testWidgets('does NOT render an Instagram CTA (removed Unit 5 2026-06-14)',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      // The Instagram handle lived in a RichText span — find.text can't see
      // inside RichText, so walk every RichText's plain text and pin the
      // handle's absence SEMANTICALLY. (A structural find.byType(GestureDetector)
      // check would be brittle + coincidental — the CONTINUE ElevatedButton
      // legitimately owns its own gesture layer.)
      final hasInstagram = tester
          .widgetList<RichText>(find.byType(RichText))
          .any((rt) =>
              rt.text.toPlainText().toLowerCase().contains('icanbefitter'));
      expect(hasInstagram, isFalse,
          reason: 'Instagram CTA must stay removed from the Mission Brief');
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
      // Production wraps AssetImage in ResizeImage via cacheWidth /
      // cacheHeight (mission_brief_screen.dart:73-74) — the provider is a
      // ResizeImage whose inner imageProvider is the AssetImage. Pin
      // both: the wrapper type AND the underlying asset name.
      expect(image.image, isA<ResizeImage>(),
          reason:
              'Image.asset with cacheWidth/cacheHeight produces a '
              'ResizeImage wrapping AssetImage. If the wrapper is '
              'absent, cacheWidth/cacheHeight were dropped — re-add '
              'them to keep the founder photo memory-bounded.');
      final inner = (image.image as ResizeImage).imageProvider;
      expect(inner, isA<AssetImage>());
      expect((inner as AssetImage).assetName, 'assets/founder/upendra.jpg');
    });
  });
}
