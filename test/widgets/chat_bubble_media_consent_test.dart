import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/widgets/chat_bubble.dart';

/// Unit 8 (coach-media-consent, OI-25) — the "Save this photo?" consent
/// chip on a user photo bubble.
///
/// Gate: isUser && hasMediaUrl && !showFailedSlot && mediaAnalysisComplete
/// && mediaSaveState == null && onSaveMedia != null. Founder's design note
/// (migration 070): "After AI analysis returns, app prompts" — the chip
/// must never appear before mediaAnalysisComplete flips true.
void main() {
  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: Center(child: child)));
  }

  const testUrl = 'https://dedsavbjuwgarrhphgnl.supabase.co/storage/v1/object/sign/chat-media/u/1.jpg';

  group('Unit 8 — ChatBubble media-consent chip', () {
    testWidgets(
        'shows SAVE PHOTO / NO THANKS once analysis completes and no decision made',
        (tester) async {
      await tester.pumpWidget(wrap(
        ChatBubble(
          text: 'Analyse this photo',
          isUser: true,
          mediaUrl: testUrl,
          mediaType: 'image',
          mediaAnalysisComplete: true,
          onSaveMedia: () {},
          onDeclineMedia: () {},
        ),
      ));

      expect(find.text('SAVE PHOTO'), findsOneWidget);
      expect(find.text('NO THANKS'), findsOneWidget);
    });

    testWidgets('tapping SAVE PHOTO fires onSaveMedia', (tester) async {
      var saveTaps = 0;
      await tester.pumpWidget(wrap(
        ChatBubble(
          text: 'Analyse this photo',
          isUser: true,
          mediaUrl: testUrl,
          mediaType: 'image',
          mediaAnalysisComplete: true,
          onSaveMedia: () => saveTaps++,
          onDeclineMedia: () {},
        ),
      ));

      await tester.tap(find.text('SAVE PHOTO'));
      await tester.pump();

      expect(saveTaps, 1);
    });

    testWidgets('tapping NO THANKS fires onDeclineMedia', (tester) async {
      var declineTaps = 0;
      await tester.pumpWidget(wrap(
        ChatBubble(
          text: 'Analyse this photo',
          isUser: true,
          mediaUrl: testUrl,
          mediaType: 'image',
          mediaAnalysisComplete: true,
          onSaveMedia: () {},
          onDeclineMedia: () => declineTaps++,
        ),
      ));

      await tester.tap(find.text('NO THANKS'));
      await tester.pump();

      expect(declineTaps, 1);
    });

    testWidgets('chip absent before analysis completes', (tester) async {
      await tester.pumpWidget(wrap(
        ChatBubble(
          text: 'Analyse this photo',
          isUser: true,
          mediaUrl: testUrl,
          mediaType: 'image',
          mediaAnalysisComplete: false, // still pending
          onSaveMedia: () {},
          onDeclineMedia: () {},
        ),
      ));

      expect(find.text('SAVE PHOTO'), findsNothing,
          reason: 'must never prompt before AI analysis returns, per the '
              'founder\'s migration-070 design note');
      expect(find.text('SAVED FOR LATER'), findsNothing);
    });

    testWidgets('chip absent, badge shown, once mediaSaveState is saved',
        (tester) async {
      await tester.pumpWidget(wrap(
        ChatBubble(
          text: 'Analyse this photo',
          isUser: true,
          mediaUrl: testUrl,
          mediaType: 'image',
          mediaAnalysisComplete: true,
          mediaSaveState: 'saved',
          onSaveMedia: () {},
          onDeclineMedia: () {},
        ),
      ));

      expect(find.text('SAVE PHOTO'), findsNothing,
          reason: 'must not re-offer the chip once a decision is recorded');
      expect(find.text('SAVED FOR LATER'), findsOneWidget);
    });

    testWidgets('neither chip nor badge shown once mediaSaveState is declined',
        (tester) async {
      await tester.pumpWidget(wrap(
        ChatBubble(
          text: 'Analyse this photo',
          isUser: true,
          mediaUrl: testUrl,
          mediaType: 'image',
          mediaAnalysisComplete: true,
          mediaSaveState: 'declined',
          onSaveMedia: () {},
          onDeclineMedia: () {},
        ),
      ));

      expect(find.text('SAVE PHOTO'), findsNothing);
      expect(find.text('SAVED FOR LATER'), findsNothing);
    });

    testWidgets('chip absent when onSaveMedia is null (no save path wired)',
        (tester) async {
      await tester.pumpWidget(wrap(
        const ChatBubble(
          text: 'Analyse this photo',
          isUser: true,
          mediaUrl: testUrl,
          mediaType: 'image',
          mediaAnalysisComplete: true,
          onSaveMedia: null,
        ),
      ));

      expect(find.text('SAVE PHOTO'), findsNothing);
    });

    testWidgets('chip never shows on an AI bubble, even with matching flags',
        (tester) async {
      await tester.pumpWidget(wrap(
        ChatBubble(
          text: 'Here is my analysis',
          isUser: false,
          mediaUrl: testUrl,
          mediaType: 'image',
          mediaAnalysisComplete: true,
          onSaveMedia: () {},
          onDeclineMedia: () {},
        ),
      ));

      expect(find.text('SAVE PHOTO'), findsNothing,
          reason: 'save-consent is a USER-bubble-only affordance — the '
              'photo the AI is discussing was the user\'s own upload');
    });

    testWidgets('chip suppressed on a failed-photo bubble', (tester) async {
      await tester.pumpWidget(wrap(
        ChatBubble(
          text: 'Analyse this photo',
          isUser: true,
          mediaUrl: testUrl,
          mediaType: 'image',
          mediaFailed: true, // showFailedSlot renders instead
          mediaAnalysisComplete: true,
          onSaveMedia: () {},
          onDeclineMedia: () {},
        ),
      ));

      expect(find.text('PHOTO FAILED'), findsOneWidget);
      expect(find.text('SAVE PHOTO'), findsNothing,
          reason: 'must not offer to save a photo that failed to upload');
    });

    // Round-2 review (2026-07-30) — isSavingMedia in-flight visual state.
    // The repo's own documented pitfall: every save action needs a visible
    // confirmation signal, not just an eventual outcome
    // (lib/features/ai_coach/CLAUDE.md common-pitfalls table).
    group('isSavingMedia in-flight state', () {
      testWidgets('shows SAVING… with a spinner instead of SAVE PHOTO',
          (tester) async {
        await tester.pumpWidget(wrap(
          ChatBubble(
            text: 'Analyse this photo',
            isUser: true,
            mediaUrl: testUrl,
            mediaType: 'image',
            mediaAnalysisComplete: true,
            isSavingMedia: true,
            onSaveMedia: () {},
            onDeclineMedia: () {},
          ),
        ));

        expect(find.text('SAVING…'), findsOneWidget);
        expect(find.text('SAVE PHOTO'), findsNothing,
            reason: 'the idle label must not render while a save is in '
                'flight');
        // Not asserting on CircularProgressIndicator's TYPE/count here —
        // CachedNetworkImage's own loading placeholder also renders one
        // (the test's mediaUrl is unreachable in the test environment),
        // so a type-based finder would double-count. The icon-swap check
        // below is the unambiguous signal instead.
        expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing,
            reason: 'the bookmark icon must be replaced by the spinner, '
                'not shown alongside it');
      });

      testWidgets('NO THANKS is still rendered (dimmed) during a save',
          (tester) async {
        await tester.pumpWidget(wrap(
          ChatBubble(
            text: 'Analyse this photo',
            isUser: true,
            mediaUrl: testUrl,
            mediaType: 'image',
            mediaAnalysisComplete: true,
            isSavingMedia: true,
            onSaveMedia: () {},
            onDeclineMedia: () {},
          ),
        ));

        expect(find.text('NO THANKS'), findsOneWidget);
      });

      testWidgets(
          'tapping SAVING… does not fire onSaveMedia while a save is already in flight',
          (tester) async {
        var saveTaps = 0;
        await tester.pumpWidget(wrap(
          ChatBubble(
            text: 'Analyse this photo',
            isUser: true,
            mediaUrl: testUrl,
            mediaType: 'image',
            mediaAnalysisComplete: true,
            isSavingMedia: true,
            onSaveMedia: () => saveTaps++,
            onDeclineMedia: () {},
          ),
        ));

        await tester.tap(find.text('SAVING…'));
        await tester.pump();

        expect(saveTaps, 0,
            reason: 'the tap target must be disabled (onTap: null) while '
                'isSavingMedia is true — this is the double-tap / '
                'concurrent-copy guard at the UI layer');
      });

      testWidgets(
          'tapping NO THANKS does not fire onDeclineMedia while a save is in flight',
          (tester) async {
        var declineTaps = 0;
        await tester.pumpWidget(wrap(
          ChatBubble(
            text: 'Analyse this photo',
            isUser: true,
            mediaUrl: testUrl,
            mediaType: 'image',
            mediaAnalysisComplete: true,
            isSavingMedia: true,
            onSaveMedia: () {},
            onDeclineMedia: () => declineTaps++,
          ),
        ));

        await tester.tap(find.text('NO THANKS'));
        await tester.pump();

        expect(declineTaps, 0,
            reason: 'round-2 review — closes the reverse race at the UI '
                'layer: a decline tap must be physically unreachable while '
                'a save for the same photo is in flight');
      });

      testWidgets('idle (isSavingMedia: false, the default) still shows the '
          'normal SAVE PHOTO label and a working tap target', (tester) async {
        var saveTaps = 0;
        await tester.pumpWidget(wrap(
          ChatBubble(
            text: 'Analyse this photo',
            isUser: true,
            mediaUrl: testUrl,
            mediaType: 'image',
            mediaAnalysisComplete: true,
            onSaveMedia: () => saveTaps++,
            onDeclineMedia: () {},
          ),
        ));

        expect(find.text('SAVE PHOTO'), findsOneWidget);
        expect(find.text('SAVING…'), findsNothing);
        expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
        await tester.tap(find.text('SAVE PHOTO'));
        await tester.pump();
        expect(saveTaps, 1);
      });
    });
  });
}
