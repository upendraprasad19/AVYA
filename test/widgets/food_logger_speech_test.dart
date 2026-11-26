/// The nutrition Log sheet's mic (plan `docs/plans/voice-input-unified.md`, D5, §4 test 4): tap to start,
/// tap to stop, the words form live in the field, SEND replaces ANALYSE & LOG
/// while the mic is on.
///
/// `pump(Duration)`, never `pumpAndSettle`, while listening: the 1 s `elapsed`
/// ticker never settles.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/speech_input_lifecycle.dart';
import 'package:icanbefitter/core/services/speech_input_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/widgets/food_logger_section.dart';

import '../helpers/fake_speech_engine.dart';

class _RecordingBreakdown extends AiBreakdownNotifier {
  final List<String> calls = <String>[];
  @override
  Future<void> analyse(String text) async {
    calls.add(text);
    state = const AiBreakdownData(mealName: 'Meal', totalKcal: 100, items: []);
  }
}

class _Rig {
  final FakeSpeechEngine engine = FakeSpeechEngine();
  final _RecordingBreakdown breakdown = _RecordingBreakdown();
  late SpeechInputService service;
  late ProviderContainer container;

  Widget app({bool tickersEnabled = true}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        // NO Scaffold, like the real Log sheet (a modal bottom sheet has none):
        // a SnackBar would be drawn on the page behind it and never seen, so
        // every message must be found inline.
        home: Material(
          child: TickerMode(
            enabled: tickersEnabled,
            child: const SingleChildScrollView(child: FoodLoggerSection()),
          ),
        ),
      ),
    );
  }

  Future<void> pump(WidgetTester tester, {bool web = false}) async {
    engine.emitListeningInsideListen = !web;
    service = SpeechInputService(
      engine: engine,
      isWeb: web,
      platform: TargetPlatform.android,
    );
    container = ProviderContainer(
      overrides: [
        speechInputServiceProvider.overrideWithValue(service),
        aiBreakdownProvider.overrideWith(() => breakdown),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(app());
    await tester.pump();
  }
}

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

String _text(WidgetTester tester) => _field(tester).controller!.text;

double _buttonOpacity(WidgetTester tester, String label) {
  final opacity = find.ancestor(
    of: find.text(label),
    matching: find.byType(AnimatedOpacity),
  );
  return tester.widget<AnimatedOpacity>(opacity.first).opacity;
}

Future<void> _startListening(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.mic));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

// -- OI-348 Landing 3e helpers (plan `docs/plans/oi348-landing3e.md` §4) ------

RenderEditable _editable(WidgetTester tester) => tester
    .state<EditableTextState>(find.byType(EditableText))
    .renderEditable;

ScrollController _scroll(WidgetTester tester) =>
    _field(tester).scrollController!;

String _words(int n) => List<String>.generate(n, (i) => 'word$i').join(' ');

Future<void> _phoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(360, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Speaks more and more words until the field's CONTENT (its height plus what
/// it scrolled away) is at least [lines] lines of [lineHeight].
Future<String> _speakLines(
  WidgetTester tester,
  _Rig rig,
  double lineHeight,
  int lines,
) async {
  for (var n = 1; n < 600; n += 2) {
    final words = _words(n);
    rig.engine.emitResult(words);
    await tester.pump(); // the write, and the post-frame jump
    await tester.pump();
    final content = _editable(tester).size.height +
        _scroll(tester).position.maxScrollExtent;
    if (content >= lineHeight * (lines - 0.5)) return words;
  }
  fail('the field never reached $lines lines');
}

Map<String, dynamic> _lastClientConfig(WidgetTester tester) {
  final call = tester.testTextInput.log.lastWhere(
    (c) => c.method == 'TextInput.setClient',
  );
  return ((call.arguments as List)[1] as Map).cast<String, dynamic>();
}

void main() {
  group('the mic tile', () {
    testWidgets('shows on native and starts a session on tap', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      expect(find.byIcon(Icons.mic), findsOneWidget);
      await _startListening(tester);
      expect(find.byIcon(Icons.stop), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsNothing);
      expect(rig.engine.listenCalls, 1);
    });

    testWidgets(
      'from starting on the field is read-only and the button reads SEND',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester);
        expect(_field(tester).readOnly, isFalse);
        expect(find.text('ANALYSE & LOG'), findsOneWidget);
        await _startListening(tester);
        expect(_field(tester).readOnly, isTrue);
        expect(find.text('SEND'), findsOneWidget);
        expect(find.text('ANALYSE & LOG'), findsNothing);
        expect(find.textContaining('LISTENING'), findsOneWidget);
      },
    );

    testWidgets('the words form live in the field', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await _startListening(tester);
      rig.engine.emitResult('two rotis');
      await tester.pump();
      expect(_text(tester), 'two rotis');
      rig.engine.emitResult('two rotis with dal');
      await tester.pump();
      expect(_text(tester), 'two rotis with dal');
    });

    testWidgets('SEND is dimmed until the words reach the analyse floor', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);
      await _startListening(tester);
      expect(_buttonOpacity(tester, 'SEND'), lessThan(1.0));
      rig.engine.emitResult('ab');
      await tester.pump(const Duration(milliseconds: 250));
      expect(_buttonOpacity(tester, 'SEND'), lessThan(1.0));
      rig.engine.emitResult('abc');
      await tester.pump(const Duration(milliseconds: 250));
      expect(_buttonOpacity(tester, 'SEND'), 1.0);
    });

    testWidgets(
      'Stop keeps the words, sends nothing and leaves the field editable',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester);
        await _startListening(tester);
        rig.engine.emitResult('three idlis');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.stop));
        await tester.pump(const Duration(milliseconds: 10));
        expect(_text(tester), 'three idlis');
        expect(rig.breakdown.calls, isEmpty);
        expect(_field(tester).readOnly, isFalse);
        expect(find.byIcon(Icons.mic), findsOneWidget);
        expect(find.text('ANALYSE & LOG'), findsOneWidget);
        expect(rig.engine.cancelCalls, 1);
      },
    );

    testWidgets('a natural end puts the platform\'s FINAL words in the field', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);
      await _startListening(tester);
      rig.engine.emitResult('paneer');
      await tester.pump();
      expect(_text(tester), 'paneer');
      // Android's natural end: the final (which differs from the last partial)
      // comes before `notListening`.
      rig.engine.emitNativeNaturalEnd('paneer tikka masala');
      await tester.pump(const Duration(milliseconds: 10));
      expect(_text(tester), 'paneer tikka masala');
      expect(
        rig.breakdown.calls,
        isEmpty,
        reason: 'an automatic end never sends',
      );
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets(
      'a typed prefix is kept, and Cancel puts the field back as it was',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester);
        await tester.enterText(find.byType(TextField), 'dal');
        await tester.pump();
        await _startListening(tester);
        rig.engine.emitResult('and rice');
        await tester.pump();
        expect(_text(tester), 'dal and rice');
        await tester.tap(find.text('CANCEL'));
        await tester.pump(const Duration(milliseconds: 10));
        expect(_text(tester), 'dal');
        expect(rig.breakdown.calls, isEmpty);
      },
    );

    testWidgets('onSubmitted during a session is a no-op', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await _startListening(tester);
      rig.engine.emitResult('paneer tikka');
      await tester.pump();
      // The read-only field has no text-input client: call the callback.
      _field(tester).onSubmitted!('paneer tikka');
      await tester.pump(const Duration(milliseconds: 10));
      expect(rig.breakdown.calls, isEmpty);
      expect(find.byIcon(Icons.stop), findsOneWidget);
    });

    testWidgets('closing the sheet mid-session releases the engine', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);
      await _startListening(tester);
      rig.engine.emitResult('half a');
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      expect(rig.engine.cancelCalls, greaterThanOrEqualTo(1));
      expect(rig.engine.running, isFalse);
    });

    testWidgets('the mic is inert while an analysis is running', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);
      rig.container.read(aiAnalysingProvider.notifier).set(true);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump(const Duration(milliseconds: 10));
      expect(rig.engine.initializeCalls, 0);
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('an engine failure shows a message and puts the field back', (
      tester,
    ) async {
      final rig = _Rig();
      rig.engine.initializeResult = false; // the microphone was refused
      await rig.pump(tester);
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.textContaining('Microphone access is off'), findsOneWidget);
      expect(find.byKey(const ValueKey('speech_notice')), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(_field(tester).readOnly, isFalse);
    });

    testWidgets('the notice goes away when the user taps the mic again', (
      tester,
    ) async {
      final rig = _Rig();
      rig.engine.initializeResult = false;
      await rig.pump(tester);
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.byKey(const ValueKey('speech_notice')), findsOneWidget);
      rig.engine.initializeResult = true; // allowed in settings meanwhile
      await tester.pump(const Duration(milliseconds: 400)); // past the toggle guard
      await _startListening(tester);
      // The previous (failed) session's cancel is still inside the 150 ms
      // settle on the real clock: let the service's wait elapse.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('speech_notice')), findsNothing);
      expect(find.byIcon(Icons.stop), findsOneWidget);
    });

    testWidgets('the notice goes away when the user types', (tester) async {
      final rig = _Rig();
      rig.engine.initializeResult = false;
      await rig.pump(tester);
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.byKey(const ValueKey('speech_notice')), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'dal');
      await tester.pump();
      expect(find.byKey(const ValueKey('speech_notice')), findsNothing);
    });

    testWidgets('Stop keeps the words and puts the cursor back in the field', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);
      await _startListening(tester);
      rig.engine.emitResult('two rotis');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      expect(_text(tester), 'two rotis');
      expect(rig.breakdown.calls, isEmpty);
      expect(_field(tester).focusNode!.hasFocus, isTrue);
    });
  });

  group('OI-348 Landing 3e: the field grows to six lines', () {
    testWidgets('T6: past six lines, each live write keeps the NEWEST in view', (
      tester,
    ) async {
      await _phoneSurface(tester);
      final rig = _Rig();
      await rig.pump(tester);
      final line = _editable(tester).size.height;
      await _startListening(tester);
      await _speakLines(tester, rig, line, 10);
      final scroll = _scroll(tester);
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 0.5),
          reason: 'the unfocused field was jumped to its end');
      expect(_editable(tester).size.height,
          closeTo(kDictationFieldMaxLines * line, 1.0));
    });

    testWidgets('T7: two lines show whole, nothing scrolled', (tester) async {
      await _phoneSurface(tester);
      final rig = _Rig();
      await rig.pump(tester);
      final line = _editable(tester).size.height;
      await _startListening(tester);
      await _speakLines(tester, rig, line, 2);
      expect(_scroll(tester).offset, 0);
      final height = _editable(tester).size.height;
      expect(height, greaterThan(line * 1.5));
      expect(height, lessThan(line * kDictationFieldMaxLines));
    });

    testWidgets('T8: after Stop, three lines; done keeps; Enter analyses once', (
      tester,
    ) async {
      await _phoneSurface(tester);
      final rig = _Rig();
      await rig.pump(tester);
      final field = _field(tester);
      expect(field.minLines, 1);
      expect(field.maxLines, kDictationFieldMaxLines);
      final line = _editable(tester).size.height;
      await _startListening(tester);
      final words = await _speakLines(tester, rig, line, 3);
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      expect(_text(tester), words);
      expect(_editable(tester).size.height, closeTo(3 * line, 1.0));
      expect(_field(tester).focusNode!.hasFocus, isTrue);
      final config = _lastClientConfig(tester);
      expect(
        (config['inputType'] as Map)['name'],
        'TextInputType.text',
        reason: 'multiline would turn the action key into a newline',
      );
      expect(config['inputAction'], 'TextInputAction.done');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 10));
      expect(rig.breakdown.calls, <String>[words]);
    });

    testWidgets('T8b: after Stop, ten lines show six with the caret end in view', (
      tester,
    ) async {
      await _phoneSurface(tester);
      final rig = _Rig();
      await rig.pump(tester);
      final line = _editable(tester).size.height;
      await _startListening(tester);
      final words = await _speakLines(tester, rig, line, 10);
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_text(tester), words);
      final editable = _editable(tester);
      expect(editable.size.height, closeTo(kDictationFieldMaxLines * line, 1.0));
      // `getLocalRectForCaret` is in TEXT coordinates: subtract the scroll.
      final caret = editable
          .getLocalRectForCaret(TextPosition(offset: words.length))
          .shift(Offset(0, -_scroll(tester).offset));
      final box = Offset.zero & editable.size;
      expect(caret.top, greaterThanOrEqualTo(box.top - 1.0));
      expect(caret.bottom, lessThanOrEqualTo(box.bottom + 1.0),
          reason: 'the end of the text is in view');
    });

    testWidgets('T8c: the strut, not the font, sets the field\'s line height', (
      tester,
    ) async {
      await _phoneSurface(tester);
      final rig = _Rig();
      await rig.pump(tester);
      final fieldLine = _editable(tester).size.height;
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: Text(
                'x',
                key: const ValueKey('strut_probe'),
                style: AppTypography.body,
                strutStyle: kDictationStrut,
              ),
            ),
          ),
        ),
      );
      final probe =
          tester.getSize(find.byKey(const ValueKey('strut_probe'))).height;
      expect(fieldLine, closeTo(probe, 0.01));
    });
  });

  group('lifecycle and gate', () {
    testWidgets(
      'a hidden tab ends the session and keeps the words in the field',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester);
        await _startListening(tester);
        rig.engine.emitResult('two chapatis');
        await tester.pump();
        // The Log sheet's tab goes out of sight (TickerMode turns off).
        await tester.pumpWidget(rig.app(tickersEnabled: false));
        await tester.pump();
        await tester.pump();
        expect(_text(tester), 'two chapatis');
        expect(
          rig.breakdown.calls,
          isEmpty,
          reason: 'hidden commits, never sends',
        );
        expect(rig.engine.cancelCalls, greaterThanOrEqualTo(1));
        // A hidden tab must not raise the keyboard over another tab (offstage
        // children can still take focus).
        expect(_field(tester).focusNode!.hasFocus, isFalse);
      },
    );

    test(
      'presence pin: the mic runs the same usage gate as ANALYSE before it listens',
      () {
        // The cap itself cannot be driven headless (the counter lives in Hive),
        // so this pins the ORDER in `_onMicTap`: gate first, listen after. A free
        // user at the cap must see the paywall BEFORE speaking a whole meal.
        final src = File(
          'lib/features/nutrition/widgets/food_logger_section.dart',
        ).readAsStringSync();
        final start = src.indexOf('Future<void> _onMicTap() async {');
        expect(start, greaterThan(0));
        final end = src.indexOf('\n  }\n', start);
        final body = src.substring(start, end);
        final gate = body.indexOf('_passesUsageGate(');
        final toggle = body.lastIndexOf('_speech.toggle()');
        expect(gate, greaterThan(0));
        expect(
          toggle,
          greaterThan(gate),
          reason: 'the gate must run before the session starts',
        );
      },
    );
  });

  group('web support', () {
    testWidgets('a browser without a recognizer shows no mic', (tester) async {
      final rig = _Rig();
      rig.engine.initializeResult = false;
      await rig.pump(tester, web: true);
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.byIcon(Icons.mic), findsNothing);
      expect(rig.engine.initializeCalls, 1, reason: 'one probe, no prompt');
      expect(rig.engine.listenCalls, 0);
    });

    testWidgets('a browser with a recognizer shows the mic after the probe', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester, web: true);
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });
  });

  group('analyseOutcome (pure)', () {
    test('a success clears the field and counts one unit', () {
      final out = analyseOutcome(
        const AiBreakdownData(mealName: 'm', totalKcal: 10, items: []),
      );
      expect(out.clearField, isTrue);
      expect(out.count, isTrue);
    });

    test('a failed call keeps the text and does NOT count', () {
      final out = analyseOutcome(
        const AiBreakdownData(
          mealName: 'm',
          totalKcal: 0,
          items: [],
          error: 'The AI is offline',
        ),
      );
      expect(out.clearField, isFalse);
      expect(out.count, isFalse);
    });

    test('no state at all is a failure', () {
      final out = analyseOutcome(null);
      expect(out.clearField, isFalse);
      expect(out.count, isFalse);
    });
  });
}
