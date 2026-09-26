import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/widgets/chat_bubble.dart';

/// Bug 913261 (2026-05-16) — chat bubble must render an explicit
/// "PHOTO FAILED — Tap to retry" tile in any of three scenarios:
///
///   1. `mediaFailed=true` (provider marked it after Storage failure).
///   2. The bubble carries a `mediaType` (photo message) but no
///      `mediaUrl` (upload never completed — bubble exists because of
///      the local-first pattern but the URL is empty).
///   3. The `CachedNetworkImage.errorWidget` fires at runtime (CDN
///      propagation race, ACL drift) — this case is harder to test in
///      pure widget tests because it depends on a network failure, so
///      we cover the failure-tile path via (1) and (2).
///
/// Pre-fix the only failure surface was a generic `broken_image_outlined`
/// icon with no caption — users had no signal whether to retry, restart,
/// or contact support.
///
/// closes-diagnose: 2026-05-16-photo-analysis-500-913261
void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('Bug 913261 — ChatBubble photo failure tile', () {
    testWidgets('mediaFailed=true renders PHOTO FAILED tile', (tester) async {
      await tester.pumpWidget(wrap(
        const ChatBubble(
          text: 'Analyse this photo',
          isUser: true,
          mediaUrl: 'https://example.com/some-url-that-doesnt-matter.jpg',
          mediaType: 'image',
          mediaFailed: true,
        ),
      ));

      expect(find.text('PHOTO FAILED'), findsOneWidget,
          reason: 'When mediaFailed=true the bubble must show the explicit '
              '"PHOTO FAILED" caption instead of rendering the image.');
      expect(find.text('Tap to retry'), findsOneWidget,
          reason: 'Subline must indicate the tap target intent.');
      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget,
          reason: 'Failure glyph must be the unsupported-image icon, not the '
              'broken-image placeholder (which gave zero actionable signal).');
    });

    testWidgets(
        'photo message with mediaType but no mediaUrl renders failure tile',
        (tester) async {
      // The local-first pattern means a user bubble exists in the chat
      // history even if the upload failed before mediaUrl was set. The
      // bubble must NOT show a broken-image icon; it must show the
      // failure tile.
      await tester.pumpWidget(wrap(
        const ChatBubble(
          text: 'Analyse this photo',
          isUser: true,
          mediaUrl: null,
          mediaType: 'image',
        ),
      ));

      expect(find.text('PHOTO FAILED'), findsOneWidget);
      expect(find.text('Tap to retry'), findsOneWidget);
    });

    testWidgets('empty-string mediaUrl on a photo bubble renders failure tile',
        (tester) async {
      // Defensive — some legacy persisted rows may have an empty string
      // rather than null. Same failure surface.
      await tester.pumpWidget(wrap(
        const ChatBubble(
          text: 'Analyse this photo',
          isUser: true,
          mediaUrl: '',
          mediaType: 'image',
        ),
      ));

      expect(find.text('PHOTO FAILED'), findsOneWidget);
    });

    testWidgets('onMediaRetry callback fires when failed tile is tapped',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(wrap(
        ChatBubble(
          text: 'Analyse this photo',
          isUser: true,
          mediaUrl: null,
          mediaType: 'image',
          mediaFailed: true,
          onMediaRetry: () => tapped++,
        ),
      ));

      await tester.tap(find.text('PHOTO FAILED'));
      await tester.pump();

      expect(tapped, 1,
          reason:
              'Tapping the failure tile must fire onMediaRetry so the user '
              'can re-pick the photo without retyping the caption.');
    });

    testWidgets(
        'failure tile renders non-tappable when onMediaRetry is null',
        (tester) async {
      // When the retry handler is null (e.g. picker has been disposed),
      // the tile must still render — just without firing anything on tap.
      // The "Tap to retry" subline stays visible but inactive; no crash.
      await tester.pumpWidget(wrap(
        const ChatBubble(
          text: 'Analyse this photo',
          isUser: true,
          mediaUrl: null,
          mediaType: 'image',
          mediaFailed: true,
          onMediaRetry: null,
        ),
      ));

      expect(find.text('PHOTO FAILED'), findsOneWidget);
      // Tapping must not throw even with no handler.
      await tester.tap(find.text('PHOTO FAILED'));
      await tester.pump();
    });

    testWidgets(
        'normal photo bubble with valid mediaUrl does NOT show failure tile',
        (tester) async {
      // Sanity check — the happy path must NOT trigger the failure tile.
      // The CachedNetworkImage placeholder spinner is what renders here;
      // we just check that the failure caption is absent.
      await tester.pumpWidget(wrap(
        const ChatBubble(
          text: 'Analyse this photo',
          isUser: true,
          mediaUrl:
              'https://dedsavbjuwgarrhphgnl.supabase.co/storage/v1/object/public/chat-media/u/1.jpg',
          mediaType: 'image',
          // mediaFailed defaults to false.
        ),
      ));

      expect(find.text('PHOTO FAILED'), findsNothing,
          reason: 'Happy path must not surface the failure tile.');
    });

    testWidgets('text-only bubble with no mediaType renders without failure tile',
        (tester) async {
      // Regression guard — text messages must never accidentally trigger
      // the photo-failure surface. The `isPhotoMessage` heuristic
      // (`mediaType != null && mediaType.isNotEmpty`) must return false
      // when both mediaUrl AND mediaType are null.
      await tester.pumpWidget(wrap(
        const ChatBubble(
          text: 'Hello, can you help me with my workout?',
          isUser: true,
        ),
      ));

      expect(find.text('PHOTO FAILED'), findsNothing);
      // _buildRichText returns a RichText when no inline-markup patterns
      // match — `find.text` can't traverse RichText spans, so we assert
      // via descendant search on the RichText itself.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('Hello, can you help me'),
        ),
        findsOneWidget,
      );
    });
  });
}
