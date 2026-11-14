/// The founder's headline behaviour for nutrition (plan `docs/plans/voice-input-unified.md`, §4 test 5):
/// speak, tap SEND, the words go to the existing `food_text_analysis` call
/// ONCE, a failed call keeps the spoken text, and the global analysing flag
/// resets even when the sheet closed mid-call.
///
/// `_analyse` runs headless: with no Hive `HiveService.getBox` throws a
/// `StateError` that `MigratedKey.read` catches and defaults (`canUse` true,
/// `isPro()` false), the same reads the existing locked-slot test already makes.
///
/// The client COUNTER is deliberately not read back here. A Hive put started in
/// a widget test's fake zone never completes (it wedged `HiveUserSession.closeAll`
/// in teardown for every shape tried: settle loops, timed pumps), and a put
/// started in `runAsync` cannot be the one `_analyse` makes. The counter rule is
/// pinned instead by the pure `analyseOutcome` rows (food_logger_speech_test.dart)
/// and by the source pin below that the increment sits behind `outcome.count`
/// (presence only, SoT `presence_only: true` with this reason).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/speech_input_service.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/widgets/food_logger_section.dart';

import '../helpers/fake_speech_engine.dart';

class _Breakdown extends AiBreakdownNotifier {
  final List<String> calls = <String>[];
  AiBreakdownData result = const AiBreakdownData(
    mealName: 'Meal',
    totalKcal: 100,
    items: [],
  );
  Completer<void>? gate;

  @override
  Future<void> analyse(String text) async {
    calls.add(text);
    final g = gate;
    if (g != null) await g.future;
    state = result;
  }
}

class _Rig {
  final FakeSpeechEngine engine = FakeSpeechEngine();
  final _Breakdown breakdown = _Breakdown();
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    final service = SpeechInputService(
      engine: engine,
      isWeb: false,
      platform: TargetPlatform.android,
    );
    container = ProviderContainer(
      overrides: [
        speechInputServiceProvider.overrideWithValue(service),
        aiBreakdownProvider.overrideWith(() => breakdown),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: FoodLoggerSection()),
          ),
        ),
      ),
    );
    await tester.pump();
  }
}

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

Future<void> _speakAndSend(WidgetTester tester, _Rig rig, String words) async {
  await tester.tap(find.byIcon(Icons.mic));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  rig.engine.emitResult(words);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.tap(find.text('SEND'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  setUp(() {
    // A headless counter write ends in the (swallowed) missing-box branch and
    // reports through telemetry: keep that off the network.
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (error, stack, {required reason, extra}) {};
    ErrorTelemetry.debugOnLogEventForTests = (opType, {message}) {};
  });

  tearDown(() {
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    ErrorTelemetry.debugOnLogEventForTests = null;
  });

  testWidgets(
    'Send writes the final words to the field, THEN calls analyse ONCE',
    (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await _speakAndSend(tester, rig, 'three boiled eggs');
      await tester.pump(const Duration(milliseconds: 50));

      expect(rig.breakdown.calls, <String>['three boiled eggs']);
      // The session is over: the mic is back, the field editable.
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(_field(tester).readOnly, isFalse);
      expect(rig.engine.cancelCalls, 1);
    },
  );

  testWidgets(
    'a successful call clears the field and resets the analysing flag',
    (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await _speakAndSend(tester, rig, 'two rotis with dal');
      await tester.pump(const Duration(milliseconds: 50));

      expect(_field(tester).controller!.text, isEmpty);
      expect(rig.container.read(aiAnalysingProvider), isFalse);
    },
  );

  testWidgets('a FAILED call keeps the spoken text for a one-tap retry', (
    tester,
  ) async {
    final rig = _Rig();
    rig.breakdown.result = const AiBreakdownData(
      mealName: 'x',
      totalKcal: 0,
      items: [],
      error: 'The AI is offline (503). Please try again in a minute.',
    );
    await rig.pump(tester);
    await _speakAndSend(tester, rig, 'a bowl of poha');
    await tester.pump(const Duration(milliseconds: 50));

    expect(rig.breakdown.calls, <String>['a bowl of poha']);
    expect(_field(tester).controller!.text, 'a bowl of poha');
    expect(rig.container.read(aiAnalysingProvider), isFalse);
  });

  testWidgets(
    'closing the sheet while the call runs never leaves the analysing flag stuck',
    (tester) async {
      final rig = _Rig();
      rig.breakdown.gate = Completer<void>();
      await rig.pump(tester);
      await _speakAndSend(tester, rig, 'grilled chicken salad');
      expect(rig.container.read(aiAnalysingProvider), isTrue);

      await tester.pumpWidget(const SizedBox()); // the sheet closes mid-call
      rig.breakdown.gate!.complete();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        rig.container.read(aiAnalysingProvider),
        isFalse,
        reason: 'the global flag must reset even though the widget is gone',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('words under the floor never reach analyse (SEND is dimmed)', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);
    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    rig.engine.emitResult('ab');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('SEND'));
    await tester.pump(const Duration(milliseconds: 10));
    expect(rig.breakdown.calls, isEmpty);
    expect(
      find.byIcon(Icons.stop),
      findsOneWidget,
      reason: 'the session is still running: nothing ended it',
    );
  });

  test('presence pin: the client counter ticks only behind outcome.count', () {
    final src = File(
      'lib/features/nutrition/widgets/food_logger_section.dart',
    ).readAsStringSync();
    final start = src.indexOf('Future<void> _analyse() async {');
    expect(start, greaterThan(0));
    final body = src.substring(start);
    final gate = body.indexOf('if (outcome.count) {');
    final inc = body.indexOf('UsageCounterService.instance.increment');
    expect(gate, greaterThan(0), reason: 'the count gate must exist');
    expect(
      inc,
      greaterThan(gate),
      reason: 'the increment must sit AFTER (inside) the count gate',
    );
    expect(
      body.substring(gate, inc).contains('}'),
      isFalse,
      reason: 'the gate block must still be open when the increment is reached',
    );
  });
}
