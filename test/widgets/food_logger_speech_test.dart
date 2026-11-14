/// The nutrition Log sheet's mic (plan `docs/plans/voice-input-unified.md`, D5, §4 test 4): tap to start,
/// tap to stop, the words form live in the field, SEND replaces ANALYSE & LOG
/// while the mic is on.
///
/// `pump(Duration)`, never `pumpAndSettle`, while listening: the 1 s `elapsed`
/// ticker never settles.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/speech_input_service.dart';
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
        home: Scaffold(
          body: TickerMode(
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
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(_field(tester).readOnly, isFalse);
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
