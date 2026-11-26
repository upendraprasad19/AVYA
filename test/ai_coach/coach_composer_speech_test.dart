/// The coach composer's mic (plan `docs/plans/voice-input-unified.md`, D4, §4 test 3): tap to start, tap
/// Stop to keep the words, tap Send to send them, tap X to discard.
///
/// `CoachComposer` is pumped ALONE with explicit inputs (nothing can pump the
/// whole screen). `pump(Duration)`, never `pumpAndSettle`: the 1 s `elapsed`
/// ticker runs while a session is open.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/speech_input_lifecycle.dart';
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
  double textScale = 1.0;

  /// Every `onHeightGrew` call (OI-348 Landing 3e, C4).
  final List<double> grew = <double>[];

  Widget app() {
    return ProviderScope(
      overrides: [speechInputServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        home: Scaffold(
          body: TickerMode(
            enabled: tickersEnabled,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(textScale),
                  ),
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
                    onHeightGrew: grew.add,
                  ),
                ),
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

// -- OI-348 Landing 3e helpers (plan `docs/plans/oi348-landing3e.md` §4) ------

Finder get _bubble => find.byKey(const ValueKey('coach_composer_bubble'));
Finder get _live => find.byKey(const ValueKey('coach_live_words'));
Finder get _viewport => find.byKey(const ValueKey('coach_live_words_viewport'));

double _bubbleHeight(WidgetTester tester) => tester.getSize(_bubble).height;

RenderEditable _editable(WidgetTester tester) => tester
    .state<EditableTextState>(find.byType(EditableText))
    .renderEditable;

String _words(int n) => List<String>.generate(n, (i) => 'word$i').join(' ');

/// A 360 x 800 dp surface, so line counts do not depend on the test window.
Future<void> _phoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(360, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Speaks more and more words until the live text is at least [lines] lines of
/// [lineHeight] tall (measured, never counted by eye). Returns the words.
Future<String> _speakLines(
  WidgetTester tester,
  _Rig rig,
  double lineHeight,
  int lines,
) async {
  for (var n = 1; n < 600; n += 2) {
    final words = _words(n);
    rig.engine.emitResult(words);
    await tester.pump();
    if (tester.getSize(_live).height >= lineHeight * (lines - 0.5)) {
      return words;
    }
  }
  fail('the live words never reached $lines lines');
}

/// Types more and more words into the idle field until it shows at least
/// [lines] lines of [lineHeight]; past six the field scrolls, so the content
/// height is read from the render editable's text height.
Future<String> _typeLines(
  WidgetTester tester,
  _Rig rig,
  double lineHeight,
  int lines,
) async {
  for (var n = 1; n < 600; n += 2) {
    final words = _words(n);
    rig.controller.text = words;
    await tester.pump();
    final contentHeight = _editable(tester).size.height +
        _fieldScroll(tester).position.maxScrollExtent;
    if (contentHeight >= lineHeight * (lines - 0.5)) return words;
  }
  fail('the field never reached $lines lines');
}

ScrollableState _fieldScroll(WidgetTester tester) => tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(EditableText),
        matching: find.byType(Scrollable),
      ),
    );

Map<String, dynamic> _lastClientConfig(WidgetTester tester) {
  final call = tester.testTextInput.log.lastWhere(
    (c) => c.method == 'TextInput.setClient',
  );
  return ((call.arguments as List)[1] as Map).cast<String, dynamic>();
}

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

    // OI-348 Landing 3e rewrote this test (it asserted one horizontal line):
    // the live words now WRAP, up to six lines, then show the newest lines.
    testWidgets('T1: three lines of live words all show, the bubble grows', (
      tester,
    ) async {
      await _phoneSurface(tester);
      final rig = _Rig();
      await rig.pump(tester);
      await rig.tapMic(tester);
      rig.engine.emitResult('hi');
      await tester.pump();
      final line = tester.getSize(_live).height;
      await _speakLines(tester, rig, line, 3);
      final text = tester.getRect(_live);
      final viewport = tester.getRect(_viewport);
      expect(text.height, closeTo(3 * line, 1.0));
      expect(text.top, greaterThanOrEqualTo(viewport.top - 1.0));
      expect(text.bottom, lessThanOrEqualTo(viewport.bottom + 1.0));
      expect(_bubbleHeight(tester), greaterThan(48.5));
    });

    for (final scale in <double>[1.0, 1.5]) {
      testWidgets(
        'T2: past six lines the box stays at six and shows the NEWEST (scale $scale)',
        (tester) async {
          await _phoneSurface(tester);
          final rig = _Rig()..textScale = scale;
          await rig.pump(tester);
          await rig.tapMic(tester);
          rig.engine.emitResult('hi');
          await tester.pump();
          final line = tester.getSize(_live).height;
          await _speakLines(tester, rig, line, 10);
          final text = tester.getRect(_live);
          final viewport = tester.getRect(_viewport);
          expect(viewport.height, closeTo(kDictationFieldMaxLines * line, 1.0));
          expect(text.bottom, closeTo(viewport.bottom, 1.0),
              reason: 'the newest line sits at the bottom of the box');
          expect(text.top, lessThan(viewport.top), reason: 'oldest scrolled off');
          expect(text.height, greaterThan(viewport.height));
        },
      );
    }

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

    // A presence pin: THREE guards keep the mic dead at the cap (`_onMicTap`,
    // `canMic`, the morph button), so no single-token regression reddens it.
    testWidgets('at the daily cap no listen starts', (tester) async {
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

  group('OI-348 Landing 3e: the field grows to six lines', () {
    testWidgets('T3: after Stop, three lines show; the keyboard keeps done', (
      tester,
    ) async {
      await _phoneSurface(tester);
      final rig = _Rig();
      await rig.pump(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.minLines, 1);
      expect(field.maxLines, kDictationFieldMaxLines);
      await rig.tapMic(tester);
      rig.engine.emitResult('hi');
      await tester.pump();
      final line = tester.getSize(_live).height;
      final words = await _speakLines(tester, rig, line, 3);
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      expect(rig.controller.text, words);
      expect(_editable(tester).size.height, closeTo(3 * line, 1.0));
      expect(_bubbleHeight(tester), greaterThan(48.5));
      expect(rig.focusNode.hasFocus, isTrue);
      final config = _lastClientConfig(tester);
      expect(
        (config['inputType'] as Map)['name'],
        'TextInputType.text',
        reason: 'multiline would turn the action key into a newline',
      );
      expect(config['inputAction'], 'TextInputAction.done');
    });

    testWidgets('T3b: after Stop, a ten-line text shows six with the caret end in view', (
      tester,
    ) async {
      await _phoneSurface(tester);
      final rig = _Rig();
      await rig.pump(tester);
      await rig.tapMic(tester);
      rig.engine.emitResult('hi');
      await tester.pump();
      final line = tester.getSize(_live).height;
      final words = await _speakLines(tester, rig, line, 10);
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      // The caret reveal starts in a post-frame callback after the focus lands,
      // then animates for 100 ms: run the frame that starts it, then the clock.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(rig.controller.text, words);
      final editable = _editable(tester);
      expect(editable.size.height, closeTo(kDictationFieldMaxLines * line, 1.0));
      // `getLocalRectForCaret` is in TEXT coordinates: subtract the scroll.
      final caret = editable
          .getLocalRectForCaret(TextPosition(offset: words.length))
          .shift(Offset(0, -_fieldScroll(tester).position.pixels));
      final box = Offset.zero & editable.size;
      expect(caret.top, greaterThanOrEqualTo(box.top - 1.0));
      expect(caret.bottom, lessThanOrEqualTo(box.bottom + 1.0),
          reason: 'the end of the text is in view');
    });

    testWidgets('T3c: the live cap and the field\'s six lines are one height', (
      tester,
    ) async {
      await _phoneSurface(tester);
      final rig = _Rig();
      await rig.pump(tester);
      await rig.tapMic(tester);
      rig.engine.emitResult('hi');
      await tester.pump();
      final line = tester.getSize(_live).height;
      await _speakLines(tester, rig, line, 10);
      final listening = _bubbleHeight(tester);
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      expect(_bubbleHeight(tester), closeTo(listening, 1.0));
    });

    testWidgets('T4: one line is 48 dp: idle empty, idle one line, listening, limit', (
      tester,
    ) async {
      await _phoneSurface(tester);
      final rig = _Rig();
      await rig.pump(tester);
      expect(_bubbleHeight(tester), closeTo(48, 0.01), reason: 'idle empty');
      rig.controller.text = 'hi';
      await _settleMorph(tester);
      expect(_bubbleHeight(tester), closeTo(48, 0.01), reason: 'idle one line');
      rig.controller.clear();
      await _settleMorph(tester);
      await rig.tapMic(tester);
      rig.engine.emitResult('hi');
      await tester.pump();
      expect(_bubbleHeight(tester), closeTo(48, 0.01), reason: 'listening');

      final limited = _Rig()
        ..isPro = false
        ..messageCount = AppConstants.freeAiMessagesPerDay;
      await limited.pump(tester);
      expect(_bubbleHeight(tester), closeTo(48, 0.01), reason: 'limit hint');
    });

    testWidgets('T4b: one line stays centred against the buttons', (
      tester,
    ) async {
      await _phoneSurface(tester);
      final rig = _Rig();
      await rig.pump(tester);
      rig.controller.text = 'hi';
      await _settleMorph(tester);
      final compass = tester.getCenter(find.byIcon(Icons.explore_outlined)).dy;
      expect(
        tester.getCenter(find.byType(EditableText)).dy,
        closeTo(compass, 1.0),
        reason: 'idle field vs compass',
      );
      rig.controller.clear();
      await _settleMorph(tester);
      await rig.tapMic(tester);
      rig.engine.emitResult('hi');
      await tester.pump();
      final x = tester.getCenter(find.byIcon(Icons.close)).dy;
      expect(tester.getCenter(_live).dy, closeTo(x, 1.0), reason: 'live words');
      expect(
        tester.getCenter(find.byKey(const ValueKey('coach_listening_dot'))).dy,
        closeTo(x, 1.0),
        reason: 'red dot',
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('coach_listening_clock'))).dy,
        closeTo(x, 1.0),
        reason: 'clock',
      );
    });

    testWidgets('T5: the done action sends the whole text once', (
      tester,
    ) async {
      await _phoneSurface(tester);
      final rig = _Rig();
      await rig.pump(tester);
      final text = _words(40);
      await tester.enterText(find.byType(TextField), text);
      await _settleMorph(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(rig.sent, <String>[text]);
    });

    for (final pro in <bool>[true, false]) {
      testWidgets('T9: a growing composer reports each step it grew (isPro $pro)', (
        tester,
      ) async {
        await _phoneSurface(tester);
        final rig = _Rig()..isPro = pro;
        await rig.pump(tester);
        final line = _editable(tester).size.height;
        double composer() => tester.getSize(find.byType(CoachComposer)).height;

        final h0 = composer();
        await _typeLines(tester, rig, line, 3);
        await tester.pump();
        final h3 = composer();
        expect(h3, greaterThan(h0));
        expect(rig.grew, isNotEmpty);
        expect(rig.grew.every((d) => d > 0), isTrue);
        expect(
          rig.grew.fold<double>(0, (a, b) => a + b),
          closeTo(h3 - h0, 0.01),
          reason: 'the deltas add up to the WHOLE composer\'s growth',
        );

        rig.grew.clear();
        rig.controller.clear();
        await _settleMorph(tester);
        expect(rig.grew, isEmpty, reason: 'a shrink reports nothing');

        // Grow, shrink, regrow: each report is exactly that step's growth.
        final h1 = composer();
        await _typeLines(tester, rig, line, 2);
        await tester.pump();
        final h2 = composer();
        expect(rig.grew.fold<double>(0, (a, b) => a + b), closeTo(h2 - h1, 0.01));
        rig.grew.clear();
        rig.controller.text = 'hi';
        await tester.pump();
        await tester.pump();
        expect(rig.grew, isEmpty, reason: 'shrink');
        final hBack = composer();
        await _typeLines(tester, rig, line, 3);
        await tester.pump();
        expect(
          rig.grew.fold<double>(0, (a, b) => a + b),
          closeTo(composer() - hBack, 0.01),
          reason: 'the regrow reports from the SHRUNK height',
        );
      });
    }

    testWidgets('T9c: a composer mounted with text already in it reports nothing', (
      tester,
    ) async {
      await _phoneSurface(tester);
      final rig = _Rig();
      rig.controller.text = _words(40);
      await rig.pump(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_bubbleHeight(tester), greaterThan(48.5), reason: 'it is tall');
      expect(rig.grew, isEmpty, reason: 'the first layout only records');
    });

    test('T9c pin: the screen follows a taller composer with the chip rule', () {
      final src = File(
        'lib/features/ai_coach/screens/ai_coach/screen.dart',
      ).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
      expect(
        src,
        contains(
          'onHeightGrew:(delta)=>keepBottomAfterChip(_scrollController,delta)',
        ),
      );
    });
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
