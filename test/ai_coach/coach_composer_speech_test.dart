/// The coach composer's mic (plan `docs/plans/voice-input-unified.md`, D4, §4 test 3): tap to start, tap
/// Stop to keep the words, tap Send to send them, tap X to discard.
///
/// `CoachComposer` is pumped ALONE with explicit inputs (nothing can pump the
/// whole screen). `pump(Duration)`, never `pumpAndSettle`: the 1 s `elapsed`
/// ticker runs while a session is open.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/speech_input_service.dart';
import 'package:icanbefitter/features/ai_coach/screens/ai_coach/screen.dart';

import '../helpers/fake_speech_engine.dart';

/// Logs every focus REQUEST into the rig's shared order list, next to the
/// screen's `onListeningChanged` calls: the order between the two is what keeps
/// the measurement chip from flashing for a frame after Stop.
class _SpyFocusNode extends FocusNode {
  _SpyFocusNode(this.order);

  final List<String> order;

  @override
  void requestFocus([FocusNode? node]) {
    order.add('focus');
    super.requestFocus(node);
  }
}

class _Rig {
  final FakeSpeechEngine engine = FakeSpeechEngine();
  final TextEditingController controller = TextEditingController();
  final List<String> order = <String>[];
  late final FocusNode focusNode = _SpyFocusNode(order);
  final List<String> sent = <String>[];
  final List<bool> listening = <bool>[];
  late SpeechInputService service;

  bool isSending = false;
  int messageCount = 0;
  bool isPro = true;
  bool tickersEnabled = true;

  Widget app() {
    return ProviderScope(
      overrides: [speechInputServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        home: Scaffold(
          body: TickerMode(
            enabled: tickersEnabled,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: CoachComposer(
                controller: controller,
                focusNode: focusNode,
                isSending: isSending,
                messageCount: messageCount,
                isPro: isPro,
                onSend: sent.add,
                onAttach: () {},
                onListeningChanged: (busy) {
                  listening.add(busy);
                  order.add('busy:$busy');
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    bool web = false,
    bool holdStarting = false,
  }) async {
    engine.emitListeningInsideListen = !web && !holdStarting;
    service = SpeechInputService(
      engine: engine,
      isWeb: web,
      platform: TargetPlatform.android,
    );
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(app());
    await tester.pump();
  }

  /// Re-pump with the rig's current inputs (same tree shape, State kept).
  Future<void> rebuild(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
  }

  Future<void> tapMic(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.mic).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// The mic <-> send morph is a 200 ms AnimatedSwitcher: one frame starts it, 200
/// ms run it, one more frame drops the outgoing child.
Future<void> _settleMorph(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

double _opacityOf(WidgetTester tester, IconData icon) => tester
    .widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byIcon(icon),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

bool get _noTextField => find.byType(TextField).evaluate().isEmpty;

void main() {
  testWidgets('warm-up: the idle composer and the listening bar render', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);
    await rig.tapMic(tester);
    expect(find.byIcon(Icons.close), findsOneWidget);
    rig.engine.emitResult('warm up');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 10));
  });

  group('the bar', () {
    testWidgets('tap the mic: the field is replaced by Cancel, Stop and Send', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);
      expect(find.byType(TextField), findsOneWidget);
      await rig.tapMic(tester);
      expect(_noTextField, isTrue);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.stop), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(
        _opacityOf(tester, Icons.stop),
        1.0,
        reason: 'Stop is live while listening',
      );
      expect(
        find.byIcon(Icons.explore_outlined),
        findsNothing,
        reason: 'compass and attach are hidden while recording',
      );
      expect(find.byIcon(Icons.attach_file), findsNothing);
      expect(rig.listening, <bool>[true]);
    });

    testWidgets('the words show live and the newest stay visible', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.tapMic(tester);
      rig.engine.emitResult(
        'I had two rotis with dal and a bowl of curd and a plate of salad '
        'and some rice and chicken curry for lunch today',
      );
      await tester.pump();
      final words = find.textContaining('lunch today');
      expect(words, findsOneWidget);
      // Longer than the bar: the line is scrolled to its END, so the right
      // edge of the text sits at the right edge of the viewport (the newest
      // words visible), not the left edge (the oldest).
      final text = tester.getRect(words);
      final viewport = tester.getRect(
        find
            .ancestor(of: words, matching: find.byType(SingleChildScrollView))
            .first,
      );
      expect(text.width, greaterThan(viewport.width), reason: 'it overflows');
      expect(text.right, closeTo(viewport.right, 1.0));
    });

    testWidgets('the timer ticks while listening', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.tapMic(tester);
      expect(find.text('0:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('0:03'), findsOneWidget);
    });

    testWidgets(
      'in starting only Cancel responds; a double tap on the mic never ends the session',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester, holdStarting: true);
        final micAt = tester.getCenter(find.byIcon(Icons.mic).last);
        await tester.tapAt(micAt);
        await tester.pump(const Duration(milliseconds: 10));
        // The second tap lands on whatever replaced the mic (Send).
        await tester.tapAt(micAt);
        await tester.pump(const Duration(milliseconds: 10));
        expect(_noTextField, isTrue, reason: 'still in the bar');
        expect(rig.sent, isEmpty);
        // Stop and Send look inert while starting (they sit where the mic was).
        expect(_opacityOf(tester, Icons.stop), lessThan(1.0));
        expect(_opacityOf(tester, Icons.arrow_upward), lessThan(1.0));
        await tester.tap(find.byIcon(Icons.stop));
        await tester.pump(const Duration(milliseconds: 10));
        expect(_noTextField, isTrue, reason: 'Stop is inert while starting');
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump(const Duration(milliseconds: 10));
        expect(find.byType(TextField), findsOneWidget, reason: 'Cancel works');
      },
    );
  });

  group('Stop, Send, Cancel', () {
    testWidgets(
      'Stop puts the words in the field and onSend is called ZERO times',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester);
        await rig.tapMic(tester);
        rig.engine.emitResult('log my lunch');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.stop));
        await tester.pump(const Duration(milliseconds: 10));
        expect(rig.controller.text, 'log my lunch');
        expect(rig.sent, isEmpty);
        expect(find.byType(TextField), findsOneWidget);
        expect(rig.listening, <bool>[true, false]);
        await tester.pump(const Duration(milliseconds: 10));
        expect(rig.focusNode.hasFocus, isTrue, reason: 'focus returns to edit');
      },
    );

    testWidgets(
      'Send calls onSend ONCE with the words, written to the field first',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester);
        await rig.tapMic(tester);
        rig.engine.emitResult('how many calories in a banana');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward));
        await tester.pump(const Duration(milliseconds: 10));
        expect(rig.sent, <String>['how many calories in a banana']);
        expect(
          rig.controller.text,
          'how many calories in a banana',
          reason:
              'the words are in the controller exactly as typing (the '
              'screen\'s send path clears it)',
        );
      },
    );

    testWidgets(
      'Send keeps the typed text: typed "dal", dictated "and rice", Send sends both',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester);
        await tester.enterText(find.byType(TextField), 'dal');
        await _settleMorph(tester);
        await rig.tapMic(tester); // the small mic beside the send arrow
        rig.engine.emitResult('and rice');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward));
        await tester.pump(const Duration(milliseconds: 10));
        expect(rig.sent, <String>['dal and rice']);
        expect(rig.controller.text, 'dal and rice');
      },
    );

    testWidgets(
      'a Stop commit asks for the keyboard BEFORE the screen is told the mic is off',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester);
        await rig.tapMic(tester);
        rig.engine.emitResult('two idlis');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.stop));
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 10));
        expect(
          rig.order,
          <String>['busy:true', 'focus', 'busy:false'],
          reason: 'busy:false first would show the chip for one frame',
        );
        expect(rig.focusNode.hasFocus, isTrue);
      },
    );

    testWidgets('at the daily cap the field is inert for the mic', (tester) async {
      final rig = _Rig()
        ..isPro = false
        ..messageCount = AppConstants.freeAiMessagesPerDay;
      await rig.pump(tester);
      expect(find.text('Daily limit reached — Go PRO'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.mic).last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 10));
      expect(rig.listening, isEmpty, reason: 'no session at the cap');
      expect(rig.engine.listenCalls, 0);
    });

    testWidgets('Send is dimmed and inert before any words', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.tapMic(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pump(const Duration(milliseconds: 10));
      expect(rig.sent, isEmpty);
      expect(_noTextField, isTrue, reason: 'the session is still running');
    });

    testWidgets('Cancel leaves the field exactly as it was', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await tester.enterText(find.byType(TextField), 'my draft');
      await _settleMorph(tester);
      await rig.tapMic(tester);
      rig.engine.emitResult('something I changed my mind about');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump(const Duration(milliseconds: 10));
      expect(rig.controller.text, 'my draft');
      expect(rig.sent, isEmpty);
    });

    testWidgets(
      'with text in the field: a small mic beside the send arrow, dictating appends',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester);
        await tester.enterText(find.byType(TextField), 'dal');
        await _settleMorph(tester);
        expect(find.byIcon(Icons.mic), findsOneWidget, reason: 'the small mic');
        expect(find.byIcon(Icons.arrow_upward), findsOneWidget, reason: 'send');
        await rig.tapMic(tester);
        rig.engine.emitResult('and rice');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.stop));
        await tester.pump(const Duration(milliseconds: 10));
        expect(rig.controller.text, 'dal and rice');
      },
    );

    testWidgets(
      'the typed text is read at COMMIT: a send that cleared it meanwhile is not resurrected',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester);
        await tester.enterText(find.byType(TextField), 'already sent');
        await _settleMorph(tester);
        await rig.tapMic(tester);
        rig.controller
            .clear(); // `_doSend` cleared it while the field was unmounted
        rig.engine.emitResult('new words');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.stop));
        await tester.pump(const Duration(milliseconds: 10));
        expect(rig.controller.text, 'new words');
      },
    );
  });

  group('guards', () {
    testWidgets('the mic is inert at the daily limit', (tester) async {
      final rig = _Rig()
        ..isPro = false
        ..messageCount = AppConstants.freeAiMessagesPerDay;
      await rig.pump(tester);
      await tester.tap(find.byIcon(Icons.mic).last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 10));
      expect(rig.engine.initializeCalls, 0);
      expect(rig.listening, isEmpty);
    });

    testWidgets('the mic is inert while a reply is sending', (tester) async {
      final rig = _Rig()..isSending = true;
      await rig.pump(tester);
      await tester.tap(find.byIcon(Icons.mic).last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 10));
      expect(rig.engine.initializeCalls, 0);
    });

    testWidgets(
      'a turn that starts while the mic is on keeps the words and leaves the bar',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester);
        await rig.tapMic(tester);
        rig.engine.emitResult('half a question');
        await tester.pump();
        rig.isSending = true; // e.g. a quick prompt was tapped
        await rig.rebuild(tester);
        await tester.pump();
        expect(find.byType(TextField), findsOneWidget);
        expect(rig.controller.text, 'half a question');
        expect(rig.sent, isEmpty);
        expect(rig.listening, <bool>[true, false]);
      },
    );

    testWidgets('a hidden tab ends the session and commits the words', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.tapMic(tester);
      rig.engine.emitResult('stay with me');
      await tester.pump();
      rig.tickersEnabled = false;
      await rig.rebuild(tester);
      await tester.pump();
      await tester.pump();
      expect(rig.controller.text, 'stay with me');
      expect(rig.sent, isEmpty);
      expect(rig.listening, <bool>[true, false]);
      // A hidden tab must not raise the keyboard over another tab (offstage
      // children can still take focus).
      expect(rig.order, isNot(contains('focus')));
      expect(rig.focusNode.hasFocus, isFalse);
    });

    testWidgets(
      'a composer removed while listening releases the engine and tells the screen',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester);
        await rig.tapMic(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.pump();
        expect(rig.engine.cancelCalls, greaterThanOrEqualTo(1));
        expect(rig.listening, <bool>[
          true,
          false,
        ], reason: 'the screen\'s chip must not stay hidden');
      },
    );

    testWidgets(
      'a refused microphone shows the message and returns to the field',
      (tester) async {
        final rig = _Rig();
        rig.engine.initializeResult = false;
        await rig.pump(tester);
        await rig.tapMic(tester);
        expect(find.textContaining('Microphone access is off'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
      },
    );

    testWidgets(
      'a browser with a recognizer shows the mic once the probe answered',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester, web: true);
        await tester.pump(const Duration(milliseconds: 10));
        expect(find.byIcon(Icons.mic), findsOneWidget);
        expect(rig.engine.initializeCalls, 1, reason: 'one probe, no prompt');
        expect(rig.engine.listenCalls, 0);
      },
    );

    testWidgets(
      'a browser without a recognizer shows no mic (the send arrow stays, dimmed)',
      (tester) async {
        final rig = _Rig();
        rig.engine.initializeResult = false;
        await rig.pump(tester, web: true);
        await tester.pump(const Duration(milliseconds: 10));
        expect(find.byIcon(Icons.mic), findsNothing);
        expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
        expect(rig.engine.listenCalls, 0);
      },
    );
  });
}
