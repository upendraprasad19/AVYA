/// Pins for the host lifecycle (plan `docs/plans/voice-input-unified.md`, D3, G17): a hidden tab or an
/// app in the background ends the session and commits the words; the Android
/// permission dialog (`inactive`) must not.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/speech_input_controller.dart';
import 'package:icanbefitter/core/services/speech_input_lifecycle.dart';
import 'package:icanbefitter/core/services/speech_input_service.dart';

import '../helpers/fake_speech_engine.dart';

class _Harness {
  _Harness() {
    service = SpeechInputService(
      engine: engine,
      isWeb: false,
      platform: TargetPlatform.android,
    );
    controller = SpeechInputController(service: service, onEnd: ends.add);
  }

  final FakeSpeechEngine engine = FakeSpeechEngine();
  late final SpeechInputService service;
  late final SpeechInputController controller;
  final List<SpeechSessionEnd> ends = <SpeechSessionEnd>[];

  Widget app({required bool tickersEnabled}) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: TickerMode(
        enabled: tickersEnabled,
        child: SpeechInputLifecycle(
          controller: controller,
          child: const SizedBox(width: 10, height: 10),
        ),
      ),
    );
  }

  Future<void> startListening(WidgetTester tester, String words) async {
    unawaited(controller.toggle());
    await tester.pump();
    engine.emitResult(words);
    expect(controller.state, SpeechInputState.listening);
  }
}

void main() {
  testWidgets(
    'a tab that goes out of sight ends the session and keeps the words',
    (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.app(tickersEnabled: true));
      await h.startListening(tester, 'two rotis');
      await tester.pumpWidget(h.app(tickersEnabled: false));
      await tester.pump();
      await tester.pump();
      expect(h.controller.state, SpeechInputState.idle);
      expect(h.ends, hasLength(1));
      expect(h.ends.single.reason, SpeechEndReason.hidden);
      expect(h.ends.single.transcript, 'two rotis');
      expect(h.engine.cancelCalls, 1);
      h.controller.dispose();
    },
  );

  testWidgets('the end is deferred past the build that flipped TickerMode', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app(tickersEnabled: true));
    await h.startListening(tester, 'curd');
    // No exception from notifying listeners during build: the end runs after
    // the frame. (A synchronous end inside didChangeDependencies would throw
    // "setState() or markNeedsBuild() called during build" in a host.)
    final listenerDuringBuild = <bool>[];
    h.controller.addListener(() {
      listenerDuringBuild.add(
        tester.binding.schedulerPhase == SchedulerPhase.persistentCallbacks,
      );
    });
    await tester.pumpWidget(h.app(tickersEnabled: false));
    await tester.pump();
    expect(h.ends, hasLength(1));
    expect(listenerDuringBuild, isNotEmpty);
    expect(listenerDuringBuild.any((inBuild) => inBuild), isFalse);
    h.controller.dispose();
  });

  testWidgets(
    'inactive (the Android permission dialog) does NOT end the session',
    (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.app(tickersEnabled: true));
      await h.startListening(tester, 'rice');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(h.controller.state, SpeechInputState.listening);
      expect(h.ends, isEmpty);
      h.controller.dispose();
    },
  );

  for (final state in <AppLifecycleState>[
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    testWidgets('$state ends the session and commits the words', (
      tester,
    ) async {
      final h = _Harness();
      await tester.pumpWidget(h.app(tickersEnabled: true));
      await h.startListening(tester, 'paneer');
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      expect(h.ends, hasLength(1));
      expect(h.ends.single.reason, SpeechEndReason.hidden);
      expect(h.ends.single.transcript, 'paneer');
      h.controller.dispose();
    });
  }

  testWidgets('an idle controller ignores every lifecycle change', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app(tickersEnabled: true));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpWidget(h.app(tickersEnabled: false));
    await tester.pump();
    expect(h.ends, isEmpty);
    expect(h.engine.cancelCalls, 0);
    h.controller.dispose();
  });

  testWidgets('the observer is removed with the widget', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.app(tickersEnabled: true));
    await h.startListening(tester, 'oats');
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    // The widget is gone: it must not end the session on a stale observer.
    expect(h.ends, isEmpty);
    h.controller.dispose();
  });
}
