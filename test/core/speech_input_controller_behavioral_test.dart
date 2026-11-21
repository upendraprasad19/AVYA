/// Behavioural pins for the shared speech session (plan `docs/plans/voice-input-unified.md`, D1/D2, §4 test 1).
///
/// The fake engine copies the plugin's shape (one result slot, one pair of
/// listeners, silent cancel on an idle engine) and the test drives each
/// platform's event ORDER. Every test runs under `fakeAsync`, and the rig
/// disposes the controllers, which cancels every timer.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/speech_input_controller.dart';
import 'package:icanbefitter/core/services/speech_input_service.dart';

import '../helpers/fake_speech_engine.dart';

class _Host {
  _Host(this.service) {
    controller = SpeechInputController(
      service: service,
      onEnd: ends.add,
      onBusyChanged: busy.add,
    );
  }

  final SpeechInputService service;
  late final SpeechInputController controller;
  final List<SpeechSessionEnd> ends = <SpeechSessionEnd>[];
  final List<bool> busy = <bool>[];

  SpeechSessionEnd get last => ends.last;
}

class _Rig {
  _Rig(FakeAsync async, {this.web = false}) : engine = FakeSpeechEngine() {
    // Web: `listening` arrives after the permission prompt, so the test emits
    // it; native: Android emits it inside `listen` (plan G5).
    engine.emitListeningInsideListen = !web;
    service = SpeechInputService(
      engine: engine,
      isWeb: web,
      platform: TargetPlatform.android,
      // The settle measures elapsed time: use the fake clock, not the wall.
      monotonic: () => async.elapsed,
    );
    host = _Host(service);
  }

  final bool web;
  final FakeSpeechEngine engine;
  late final SpeechInputService service;
  late final _Host host;
  final List<_Host> extraHosts = <_Host>[];

  SpeechInputController get c => host.controller;
  List<SpeechSessionEnd> get ends => host.ends;

  _Host addHost() {
    final h = _Host(service);
    extraHosts.add(h);
    return h;
  }

  void dispose() {
    host.controller.dispose();
    for (final h in extraHosts) {
      h.controller.dispose();
    }
  }
}

/// Starts a session on [c] and lets the async chain run.
void _tap(FakeAsync async, SpeechInputController c) {
  unawaited(c.toggle());
  async.flushMicrotasks();
}

/// Runs [body] in a fresh `fakeAsync` zone with a rig, then disposes it.
void _rigTest(
  String name,
  void Function(FakeAsync async, _Rig rig) body, {
  bool web = false,
}) {
  test(name, () {
    fakeAsync((async) {
      final rig = _Rig(async, web: web);
      try {
        body(async, rig);
      } finally {
        rig.dispose();
        async.flushMicrotasks();
      }
    });
  });
}

void main() {
  final recorded = <({Object error, String reason})>[];

  setUp(() {
    recorded.clear();
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (error, stack, {required reason, extra}) {
          recorded.add((error: error, reason: reason));
        };
  });

  tearDown(() {
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
  });

  group('start, stop, send, cancel (native)', () {
    _rigTest('a tap goes starting -> listening and issues one listen', (
      async,
      rig,
    ) {
      _tap(async, rig.c);
      expect(rig.c.state, SpeechInputState.listening);
      expect(rig.host.busy, <bool>[true]);
      expect(rig.engine.initializeCalls, 1);
      expect(rig.engine.listenCalls, 1);
      expect(rig.engine.lastListenOptions!.localeId, 'en_IN');
    });

    _rigTest('state is starting until the engine says listening', (async, rig) {
      rig.engine.emitListeningInsideListen = false;
      _tap(async, rig.c);
      expect(rig.c.state, SpeechInputState.starting);
      expect(rig.c.isBusy, isTrue);
      rig.engine.emitStatus('listening');
      expect(rig.c.state, SpeechInputState.listening);
    });

    _rigTest('Stop keeps the words on screen and reports userStop once', (
      async,
      rig,
    ) {
      _tap(async, rig.c);
      rig.engine.emitResult('two rotis');
      rig.engine.emitResult('two rotis and five eggs');
      expect(rig.c.liveText, 'two rotis and five eggs');
      rig.c.stop();
      async.flushMicrotasks();
      expect(rig.c.state, SpeechInputState.idle);
      expect(rig.ends, hasLength(1));
      expect(rig.host.last.reason, SpeechEndReason.userStop);
      expect(rig.host.last.transcript, 'two rotis and five eggs');
      expect(rig.host.busy, <bool>[true, false]);
    });

    _rigTest('Send reports userSend with the words on screen', (async, rig) {
      _tap(async, rig.c);
      rig.engine.emitResult('one banana');
      rig.c.send();
      expect(rig.ends, hasLength(1));
      expect(rig.host.last.reason, SpeechEndReason.userSend);
      expect(rig.host.last.transcript, 'one banana');
    });

    _rigTest('the plugin final is never awaited on Stop (user-stop order)', (
      async,
      rig,
    ) {
      _tap(async, rig.c);
      rig.engine.emitResult('curd rice');
      rig.c.stop();
      async.flushMicrotasks();
      // Android: notListening, done, THEN the final, all after the end.
      rig.engine.emitNativeStopOrder('curd rice and pickle');
      async.elapse(const Duration(seconds: 3));
      expect(rig.ends, hasLength(1));
      expect(rig.host.last.transcript, 'curd rice');
    });

    _rigTest('Cancel in listening discards the words', (async, rig) {
      _tap(async, rig.c);
      rig.engine.emitResult('something');
      rig.c.cancel();
      expect(rig.host.last.reason, SpeechEndReason.cancelled);
      expect(rig.host.last.transcript, '');
    });

    _rigTest('Stop and Send are inert while starting; Cancel is live', (
      async,
      rig,
    ) {
      rig.engine.emitListeningInsideListen = false;
      _tap(async, rig.c);
      expect(rig.c.state, SpeechInputState.starting);
      rig.c.stop();
      rig.c.send();
      expect(rig.c.state, SpeechInputState.starting);
      expect(rig.ends, isEmpty);
      rig.c.cancel();
      expect(rig.host.last.reason, SpeechEndReason.cancelled);
    });

    _rigTest('a second tap while starting is ignored', (async, rig) {
      rig.engine.emitListeningInsideListen = false;
      _tap(async, rig.c);
      _tap(async, rig.c);
      expect(rig.c.state, SpeechInputState.starting);
      expect(rig.engine.listenCalls, 1);
      expect(rig.ends, isEmpty);
    });

    _rigTest('a tap on the mic while listening is a Stop', (async, rig) {
      _tap(async, rig.c);
      rig.engine.emitResult('hello there');
      _tap(async, rig.c);
      expect(rig.host.last.reason, SpeechEndReason.userStop);
    });

    _rigTest('a tap within the toggle guard of an end is ignored', (
      async,
      rig,
    ) {
      _tap(async, rig.c);
      rig.c.stop();
      _tap(async, rig.c);
      expect(rig.c.state, SpeechInputState.idle);
      expect(rig.engine.listenCalls, 1);
      async.elapse(SpeechInputTiming.toggleGuard);
      _tap(async, rig.c);
      async.elapse(SpeechInputTiming.settle);
      expect(rig.c.state, SpeechInputState.listening);
      expect(rig.engine.listenCalls, 2);
    });
  });

  group('every end releases the engine and reports once', () {
    for (final reason in <SpeechEndReason>[
      SpeechEndReason.userStop,
      SpeechEndReason.userSend,
      SpeechEndReason.cancelled,
      SpeechEndReason.hidden,
      SpeechEndReason.auto,
      SpeechEndReason.error,
    ]) {
      _rigTest('$reason: one onEnd, one engine cancel', (async, rig) {
        _tap(async, rig.c);
        rig.engine.emitResult('some words');
        switch (reason) {
          case SpeechEndReason.userStop:
            rig.c.stop();
          case SpeechEndReason.userSend:
            rig.c.send();
          case SpeechEndReason.cancelled:
            rig.c.cancel();
          case SpeechEndReason.hidden:
            rig.c.endForHidden();
          case SpeechEndReason.auto:
            rig.engine.emitResult('some words', isFinal: true);
          case SpeechEndReason.error:
            rig.engine.emitError('error_network');
          default:
            fail('unreachable');
        }
        async.flushMicrotasks();
        // A second end of the same session is a no-op.
        rig.c.stop();
        rig.c.cancel();
        rig.c.endForHidden();
        async.flushMicrotasks();
        expect(rig.ends, hasLength(1));
        expect(rig.host.last.reason, reason);
        expect(rig.engine.cancelCalls, 1);
      });
    }

    _rigTest('hidden commits the words (does not discard)', (async, rig) {
      _tap(async, rig.c);
      rig.engine.emitResult('half a meal');
      rig.c.endForHidden();
      expect(rig.host.last.reason, SpeechEndReason.hidden);
      expect(rig.host.last.transcript, 'half a meal');
    });

    _rigTest('an ownerless engine is cancelled once the session is gone', (
      async,
      rig,
    ) {
      rig.engine.emitListeningInsideListen = false;
      _tap(async, rig.c);
      rig.c.cancel();
      async.flushMicrotasks();
      final before = rig.engine.cancelCalls;
      // The permission prompt was answered after the session gave up.
      rig.engine.emitStatus('listening');
      async.flushMicrotasks();
      expect(rig.engine.cancelCalls, before + 1);
      expect(rig.c.state, SpeechInputState.idle);
    });
  });

  group('natural ends (native)', () {
    _rigTest('a final inside listening ends with the final words, once', (
      async,
      rig,
    ) {
      _tap(async, rig.c);
      rig.engine.emitResult('a roti');
      rig.engine.emitNativeNaturalEnd('a roti with dal');
      async.elapse(const Duration(seconds: 3));
      expect(rig.ends, hasLength(1));
      expect(rig.host.last.reason, SpeechEndReason.auto);
      expect(rig.host.last.transcript, 'a roti with dal');
      expect(rig.host.last.empty, isFalse);
    });

    _rigTest(
      'the plugin swallows done while the result is partial: only the final ends the session',
      (async, rig) {
        _tap(async, rig.c);
        rig.engine.emitResult('three idlis');
        rig.engine.emitStatus('done'); // swallowed: only a PARTIAL was sent
        expect(rig.c.state, SpeechInputState.listening);
        expect(rig.ends, isEmpty);
        rig.engine.emitResult('three idlis and sambar', isFinal: true);
        expect(rig.ends, hasLength(1));
        expect(rig.host.last.reason, SpeechEndReason.auto);
        expect(rig.host.last.transcript, 'three idlis and sambar');
      },
    );

    // DEFENSIVE: speech_to_text 7.4.0 never delivers a `done` after only
    // PARTIAL results (the fake's `emitRawStatus` bypasses that rule), but a
    // platform interface that forwarded it must still end the session cleanly.
    _rigTest('a raw done with words ends at once', (async, rig) {
      _tap(async, rig.c);
      rig.engine.emitResult('three idlis');
      rig.engine.emitRawStatus('done');
      expect(rig.host.last.reason, SpeechEndReason.auto);
      expect(rig.host.last.transcript, 'three idlis');
    });

    // The REAL silent-session path: Android sends `doneNoResult` when no result
    // was sent, the plugin rewrites it to `done` and delivers it.
    _rigTest(
      'a silent session: done with no words waits errorGrace, then ends empty',
      (async, rig) {
        _tap(async, rig.c);
        rig.engine.emitStatus('done'); // delivered: no result was ever sent
        expect(rig.c.state, SpeechInputState.listening);
        async.elapse(SpeechInputTiming.errorGrace);
        expect(rig.ends, hasLength(1));
        expect(rig.host.last.reason, SpeechEndReason.auto);
        expect(rig.host.last.empty, isTrue);
      },
    );

    _rigTest(
      'a recognizer end with no words and no done ends empty after endGrace',
      (async, rig) {
        _tap(async, rig.c);
        rig.engine.emitStatus('notListening');
        expect(rig.c.state, SpeechInputState.listening);
        async.elapse(SpeechInputTiming.endGrace);
        expect(rig.ends, hasLength(1));
        expect(rig.host.last.reason, SpeechEndReason.auto);
        expect(rig.host.last.empty, isTrue);
      },
    );

    _rigTest('a trailing no-match error after done ends empty (benign)', (
      async,
      rig,
    ) {
      _tap(async, rig.c);
      rig.engine.emitStatus('notListening');
      rig.engine.emitStatus('done');
      rig.engine.emitError('error_no_match');
      expect(rig.ends, hasLength(1));
      expect(rig.host.last.reason, SpeechEndReason.auto);
      expect(rig.host.last.empty, isTrue);
      expect(rig.host.last.failure, isNull);
    });

    _rigTest(
      'notListening alone arms endGrace, then ends with the live words',
      (async, rig) {
        _tap(async, rig.c);
        rig.engine.emitResult('paneer tikka');
        rig.engine.emitStatus('notListening');
        expect(rig.c.state, SpeechInputState.listening);
        async.elapse(SpeechInputTiming.endGrace);
        expect(rig.host.last.reason, SpeechEndReason.auto);
        expect(rig.host.last.transcript, 'paneer tikka');
      },
    );

    _rigTest('a final inside endGrace wins over the grace', (async, rig) {
      _tap(async, rig.c);
      rig.engine.emitResult('paneer tik');
      rig.engine.emitStatus('notListening');
      async.elapse(const Duration(milliseconds: 400));
      rig.engine.emitResult('paneer tikka masala', isFinal: true);
      expect(rig.host.last.transcript, 'paneer tikka masala');
      async.elapse(const Duration(seconds: 3));
      expect(rig.ends, hasLength(1));
    });
  });

  group('web ordering', () {
    _rigTest('notListening ends at once with the words on screen', (
      async,
      rig,
    ) {
      _tap(async, rig.c);
      expect(rig.c.state, SpeechInputState.starting);
      rig.engine.emitStatus('listening');
      rig.engine.emitResult('rajma chawal');
      rig.engine.emitStatus('notListening');
      expect(rig.host.last.reason, SpeechEndReason.auto);
      expect(rig.host.last.transcript, 'rajma chawal');
    }, web: true);

    _rigTest('done is ignored; a second listening is ignored', (async, rig) {
      _tap(async, rig.c);
      rig.engine.emitStatus('listening');
      rig.engine.emitStatus('listening');
      rig.engine.emitResult('chole');
      rig.engine.emitRawStatus('done'); // the web branch ignores a raw done
      expect(rig.c.state, SpeechInputState.listening);
      expect(rig.ends, isEmpty);
    }, web: true);

    _rigTest(
      'the web pause is applied on the session\'s own listening status',
      (async, rig) {
        _tap(async, rig.c);
        expect(rig.engine.lastListenOptions!.pauseFor, isNull);
        expect(rig.engine.lastListenOptions!.localeId, 'en-IN');
        expect(rig.engine.lastChangedPauseFor, isNull);
        rig.engine.emitStatus('listening');
        async.flushMicrotasks();
        expect(rig.engine.lastChangedPauseFor, SpeechInputTiming.pauseFor);
      },
      web: true,
    );

    _rigTest('native never calls changePauseFor', (async, rig) {
      _tap(async, rig.c);
      async.flushMicrotasks();
      expect(rig.engine.calls, isNot(contains('changePauseFor')));
      expect(
        rig.engine.lastListenOptions!.pauseFor,
        SpeechInputTiming.pauseFor,
      );
    });

    _rigTest('a probe on web asks the engine once and caches the answer', (
      async,
      rig,
    ) {
      unawaited(rig.c.probeSupport());
      async.flushMicrotasks();
      expect(rig.c.supported, isTrue);
      unawaited(rig.c.probeSupport());
      async.flushMicrotasks();
      expect(rig.engine.initializeCalls, 1);
    }, web: true);

    _rigTest('a browser without the API: not supported, a tap starts nothing', (
      async,
      rig,
    ) {
      rig.engine.initializeResult = false;
      unawaited(rig.c.probeSupport());
      async.flushMicrotasks();
      expect(rig.c.supported, isFalse);
      _tap(async, rig.c);
      expect(rig.engine.listenCalls, 0);
      expect(rig.engine.initializeCalls, 1);
      expect(rig.host.last.failure, SpeechFailure.unsupported);
    }, web: true);

    _rigTest('web is not supported until the probe answered', (async, rig) {
      expect(rig.c.supported, isFalse);
    }, web: true);
  });

  group('errors', () {
    _rigTest('permission refused at initialize: failure, no listen', (
      async,
      rig,
    ) {
      rig.engine.initializeResult = false;
      _tap(async, rig.c);
      expect(rig.engine.listenCalls, 0);
      expect(rig.host.last.reason, SpeechEndReason.error);
      expect(rig.host.last.failure, SpeechFailure.permissionDenied);
      expect(rig.host.last.transcript, '');
    });

    _rigTest('a refusal is not cached on native: a later tap asks again', (
      async,
      rig,
    ) {
      rig.engine.initializeResult = false;
      _tap(async, rig.c);
      expect(rig.engine.initializeCalls, 1);
      rig.engine.initializeResult = true;
      async.elapse(SpeechInputTiming.toggleGuard);
      _tap(async, rig.c);
      expect(rig.engine.initializeCalls, 2);
      expect(rig.c.state, SpeechInputState.listening);
    });

    _rigTest(
      'recognizerNotAvailable at initialize: unsupported, and remembered',
      (async, rig) {
        rig.engine.initializeThrows = PlatformException(
          code: 'recognizerNotAvailable',
        );
        _tap(async, rig.c);
        expect(rig.host.last.failure, SpeechFailure.unsupported);
        expect(rig.c.supported, isFalse);
        async.elapse(SpeechInputTiming.toggleGuard);
        _tap(async, rig.c);
        expect(rig.engine.initializeCalls, 1);
        expect(rig.ends, hasLength(2));
        expect(rig.host.last.failure, SpeechFailure.unsupported);
      },
    );

    _rigTest(
      'error_permission while listening ends with the permission failure',
      (async, rig) {
        _tap(async, rig.c);
        rig.engine.emitError('error_permission');
        expect(rig.host.last.failure, SpeechFailure.permissionDenied);
      },
    );

    _rigTest('error_permission while starting is fatal too', (async, rig) {
      rig.engine.emitListeningInsideListen = false;
      _tap(async, rig.c);
      rig.engine.emitError('error_permission');
      expect(rig.host.last.failure, SpeechFailure.permissionDenied);
      expect(rig.host.last.transcript, '');
    });

    _rigTest('an engine error reports the CODE to telemetry, never the words', (
      async,
      rig,
    ) {
      _tap(async, rig.c);
      rig.engine.emitResult('my secret lunch order');
      rig.engine.emitError('error_network');
      expect(rig.host.last.failure, SpeechFailure.engine);
      expect(rig.host.last.transcript, 'my secret lunch order');
      expect(recorded, hasLength(1));
      expect(recorded.single.error.toString(), contains('error_network'));
      expect(recorded.single.error.toString(), isNot(contains('secret')));
      expect(recorded.single.reason, 'speech_input_session_error');
    });

    _rigTest('a benign no-match while listening ends empty without a failure', (
      async,
      rig,
    ) {
      _tap(async, rig.c);
      rig.engine.emitError('error_no_match');
      expect(rig.host.last.reason, SpeechEndReason.auto);
      expect(rig.host.last.empty, isTrue);
      expect(rig.host.last.failure, isNull);
      expect(recorded, isEmpty);
    });

    _rigTest(
      'a benign error is dropped while starting (a late error of the previous session)',
      (async, rig) {
        _tap(async, rig.c);
        expect(rig.c.state, SpeechInputState.starting);
        rig.engine.emitError('aborted');
        rig.engine.emitError('no-speech');
        expect(rig.c.state, SpeechInputState.starting);
        expect(rig.ends, isEmpty);
        rig.engine.emitStatus('listening');
        expect(rig.c.state, SpeechInputState.listening);
      },
      web: true,
    );

    _rigTest(
      'a late done / notListening / final of the previous listen never reaches the new session',
      (async, rig) {
        _tap(async, rig.c);
        rig.engine.emitResult('old words');
        rig.c.stop();
        async.elapse(SpeechInputTiming.toggleGuard);
        rig.engine.emitListeningInsideListen = false;
        _tap(async, rig.c);
        async.elapse(SpeechInputTiming.settle);
        expect(rig.c.state, SpeechInputState.starting);
        // The single result slot now points at the new listen: the late events
        // of the previous one land on it.
        rig.engine.emitResult('old words and more', isFinal: true);
        rig.engine.emitStatus('notListening');
        rig.engine.emitStatus('done');
        expect(rig.c.state, SpeechInputState.starting);
        expect(rig.ends, hasLength(1));
        rig.engine.emitStatus('listening');
        expect(rig.c.state, SpeechInputState.listening);
        expect(rig.c.liveText, '');
      },
    );

    _rigTest(
      'the start timeout (armed before listen) ends the session and cancels',
      (async, rig) {
        rig.engine.emitListeningInsideListen = false;
        rig.engine.listenGate = Completer<void>();
        _tap(async, rig.c);
        expect(rig.c.state, SpeechInputState.starting);
        async.elapse(SpeechInputTiming.startTimeoutNative);
        expect(rig.host.last.reason, SpeechEndReason.error);
        expect(rig.host.last.failure, SpeechFailure.engine);
        // The end enqueues its cancel behind the hung listen; that call's own
        // timeout frees the slot, then the cancel runs.
        expect(rig.engine.cancelCalls, 0);
        async.elapse(SpeechInputTiming.engineCallTimeout);
        expect(rig.engine.cancelCalls, 1);
      },
    );

    _rigTest('the web start timeout is the long one (permission prompt)', (
      async,
      rig,
    ) {
      _tap(async, rig.c);
      async.elapse(
        SpeechInputTiming.startTimeoutNative + const Duration(seconds: 1),
      );
      expect(rig.c.state, SpeechInputState.starting);
      async.elapse(SpeechInputTiming.startTimeoutWeb);
      expect(rig.host.last.failure, SpeechFailure.engine);
    }, web: true);

    _rigTest('an onEnd that throws is reported by type and never rethrown', (
      async,
      rig,
    ) {
      final throwing = SpeechInputController(
        service: rig.service,
        onEnd: (_) => throw StateError('host bug'),
      );
      _tap(async, throwing);
      rig.engine.emitResult('words');
      throwing.stop();
      expect(throwing.state, SpeechInputState.idle);
      expect(recorded.map((r) => r.reason), contains('speech_input_on_end'));
      expect(recorded.map((r) => r.error.toString()), contains('StateError'));
      throwing.dispose();
    });
  });


  group('first use: the permission dialog is not part of the listen budget', () {
    _rigTest(
      'a slow Allow (longer than the listen budget) still reaches listening',
      (async, rig) {
        rig.engine.initializeGate = Completer<bool>();
        _tap(async, rig.c);
        expect(rig.c.state, SpeechInputState.starting);
        async.elapse(SpeechInputTiming.startTimeoutNative * 3);
        expect(rig.c.state, SpeechInputState.starting);
        expect(rig.ends, isEmpty);
        rig.engine.initializeGate!.complete(true);
        async.flushMicrotasks();
        expect(rig.c.state, SpeechInputState.listening);
        expect(rig.engine.listenCalls, 1);
        expect(rig.service.isInitialized, isTrue);
        expect(rig.ends, isEmpty);
      },
    );

    _rigTest(
      'a dialog left unanswered ends at the first-use budget, and a late Allow opens no mic',
      (async, rig) {
        rig.engine.initializeGate = Completer<bool>();
        _tap(async, rig.c);
        async.elapse(
          SpeechInputTiming.startTimeoutFirstUse - const Duration(seconds: 1),
        );
        expect(rig.c.state, SpeechInputState.starting);
        async.elapse(const Duration(seconds: 2));
        expect(rig.ends, hasLength(1));
        expect(rig.host.last.failure, SpeechFailure.engine);
        rig.engine.initializeGate!.complete(true);
        async.elapse(const Duration(seconds: 1));
        expect(rig.engine.listenCalls, 0);
        expect(rig.service.isInitialized, isTrue);
        expect(rig.ends, hasLength(1));
      },
    );

    _rigTest('the listen budget counts from the listen, not from the tap', (
      async,
      rig,
    ) {
      rig.engine.initializeGate = Completer<bool>();
      rig.engine.emitListeningInsideListen = false;
      _tap(async, rig.c);
      async.elapse(const Duration(seconds: 3));
      rig.engine.initializeGate!.complete(true);
      async.flushMicrotasks();
      expect(rig.engine.listenCalls, 1);
      // 3 s of dialog + 3.9 s after the listen is far past the 4 s a timer
      // armed at the tap would allow.
      async.elapse(
        SpeechInputTiming.startTimeoutNative - const Duration(milliseconds: 100),
      );
      expect(rig.c.state, SpeechInputState.starting);
      async.elapse(const Duration(milliseconds: 200));
      expect(rig.ends, hasLength(1));
      expect(rig.host.last.failure, SpeechFailure.engine);
    });

    _rigTest('an initialised engine keeps the SHORT pre-listen budget', (
      async,
      rig,
    ) {
      _tap(async, rig.c); // first session: initialises the engine
      expect(rig.service.isInitialized, isTrue);
      rig.engine.cancelGate = Completer<void>(); // the next cancel hangs
      rig.c.stop();
      async.elapse(SpeechInputTiming.toggleGuard);
      // The hung cancel holds the slot, so the second begin waits behind it.
      _tap(async, rig.c);
      expect(rig.c.state, SpeechInputState.starting);
      async.elapse(SpeechInputTiming.startTimeoutNative);
      expect(rig.ends, hasLength(2));
      expect(rig.host.last.failure, SpeechFailure.engine);
      rig.engine.cancelGate!.complete();
    });

    _rigTest(
      'the one-restart window opens at the listen too: a busy after a slow Allow is retried',
      (async, rig) {
        rig.engine.initializeGate = Completer<bool>();
        _tap(async, rig.c);
        async.elapse(SpeechInputTiming.retryWindow * 2);
        rig.engine.initializeGate!.complete(true);
        async.flushMicrotasks();
        expect(rig.c.state, SpeechInputState.listening);
        rig.engine.emitError('error_busy');
        async.elapse(SpeechInputTiming.settle * 2);
        expect(rig.engine.listenCalls, 2);
        expect(rig.ends, isEmpty);
      },
    );

    _rigTest(
      'an initialize that never answers frees the slot at its own bound',
      (async, rig) {
        rig.engine.initializeGate = Completer<bool>();
        _tap(async, rig.c);
        async.elapse(SpeechInputTiming.startTimeoutFirstUse);
        expect(rig.ends, hasLength(1));
        // The end queued its cancel behind the begin that still holds the slot.
        expect(rig.engine.cancelCalls, 0);
        async.elapse(
          SpeechInputTiming.initializeTimeout -
              SpeechInputTiming.startTimeoutFirstUse +
              const Duration(seconds: 1),
        );
        expect(rig.engine.cancelCalls, 1);
      },
    );

    _rigTest(
      'an older begin of the SAME controller finishing does not clear the newer one\'s in-flight marker',
      (async, rig) {
        rig.engine.initializeGate = Completer<bool>(); // the dialog is never answered
        final other = rig.addHost();
        _tap(async, rig.c);
        async.elapse(SpeechInputTiming.startTimeoutFirstUse + const Duration(seconds: 1));
        expect(rig.ends, hasLength(1), reason: 'the first-use budget ended session 1');
        // Session 2 of the SAME controller queues behind the first begin, which
        // still holds the slot (its own bound is 60 s).
        async.elapse(SpeechInputTiming.toggleGuard);
        _tap(async, rig.c);
        expect(rig.c.state, SpeechInputState.starting);
        // The first begin times out and runs its `finally`; session 2 now holds
        // the slot, still waiting on the same memo.
        async.elapse(
          SpeechInputTiming.initializeTimeout -
              SpeechInputTiming.startTimeoutFirstUse +
              const Duration(seconds: 2),
        );
        expect(rig.c.state, SpeechInputState.starting);
        // A second host taps: it must still see session 2 as in flight.
        _tap(async, other.controller);
        expect(rig.ends, hasLength(2));
        expect(rig.host.last.reason, SpeechEndReason.preempted);
      },
    );

    _rigTest(
      'a second host that taps while the first waits for the dialog preempts it: ONE listen',
      (async, rig) {
        rig.engine.initializeGate = Completer<bool>();
        final other = rig.addHost();
        unawaited(rig.c.toggle());
        unawaited(other.controller.toggle());
        async.flushMicrotasks();
        expect(rig.ends, hasLength(1));
        expect(rig.host.last.reason, SpeechEndReason.preempted);
        rig.engine.initializeGate!.complete(true);
        async.elapse(const Duration(seconds: 1));
        expect(rig.engine.listenCalls, 1);
        expect(other.controller.state, SpeechInputState.listening);
        expect(rig.c.state, SpeechInputState.idle);
      },
    );
  });

  group('retry (time based, once)', () {
    _rigTest(
      'error_busy right after listening restarts once, then ends with the engine message',
      (async, rig) {
        _tap(async, rig.c);
        rig.engine.emitError('error_busy');
        async.elapse(SpeechInputTiming.settle * 2);
        expect(rig.engine.listenCalls, 2);
        expect(rig.ends, isEmpty);
        expect(rig.c.state, SpeechInputState.listening);
        rig.engine.emitError('error_client');
        expect(rig.ends, hasLength(1));
        expect(rig.host.last.failure, SpeechFailure.engine);
      },
    );

    _rigTest(
      'after a retry the native end still arms its own grace (Android order: notListening, done, error)',
      (async, rig) {
        _tap(async, rig.c);
        rig.engine.emitStatus('notListening'); // arms endGrace in session 1
        rig.engine.emitStatus('done'); // delivered (no result): arms errorGrace
        rig.engine.emitError('error_busy'); // the retry cancels both graces
        async.elapse(SpeechInputTiming.settle * 2);
        expect(rig.engine.listenCalls, 2);
        expect(rig.c.state, SpeechInputState.listening);
        // Session 2 ends natively with no final: its OWN grace must run.
        rig.engine.emitStatus('notListening');
        expect(rig.c.state, SpeechInputState.listening);
        async.elapse(SpeechInputTiming.endGrace);
        expect(rig.ends, hasLength(1));
        expect(rig.host.last.reason, SpeechEndReason.auto);
        expect(rig.host.last.empty, isTrue);
      },
    );

    _rigTest('after a retry a done with no words arms errorGrace again', (
      async,
      rig,
    ) {
      _tap(async, rig.c);
      rig.engine.emitStatus('done'); // arms errorGrace in session 1
      rig.engine.emitError('error_client');
      async.elapse(SpeechInputTiming.settle * 2);
      expect(rig.engine.listenCalls, 2);
      rig.engine.emitStatus('done');
      expect(rig.c.state, SpeechInputState.listening);
      async.elapse(SpeechInputTiming.errorGrace);
      expect(rig.ends, hasLength(1));
      expect(rig.host.last.empty, isTrue);
    });

    _rigTest('busy after the retry window is not retried', (async, rig) {
      _tap(async, rig.c);
      async.elapse(
        SpeechInputTiming.retryWindow + const Duration(milliseconds: 1),
      );
      rig.engine.emitError('error_busy');
      async.elapse(const Duration(seconds: 1));
      expect(rig.engine.listenCalls, 1);
      expect(rig.host.last.reason, SpeechEndReason.auto);
    });

    _rigTest('busy after words were heard is not retried', (async, rig) {
      _tap(async, rig.c);
      rig.engine.emitResult('already speaking');
      rig.engine.emitError('error_client');
      expect(rig.engine.listenCalls, 1);
      expect(rig.host.last.transcript, 'already speaking');
    });

    _rigTest(
      'a web start exception restarts once and the session then listens',
      (async, rig) {
        rig.engine.listenThrows = StateError('InvalidStateError');
        _tap(async, rig.c);
        rig.engine.listenThrows = null;
        async.elapse(SpeechInputTiming.settle * 2);
        expect(rig.engine.listenCalls, 2);
        rig.engine.emitStatus('listening');
        expect(rig.c.state, SpeechInputState.listening);
        expect(rig.ends, isEmpty);
      },
      web: true,
    );

    _rigTest('a second web start exception ends with the engine failure', (
      async,
      rig,
    ) {
      rig.engine.listenThrows = StateError('InvalidStateError');
      _tap(async, rig.c);
      async.elapse(const Duration(seconds: 1));
      expect(rig.engine.listenCalls, 2);
      expect(rig.host.last.failure, SpeechFailure.engine);
      expect(rig.ends, hasLength(1));
    }, web: true);
  });

  group('serialisation, quiesce and settle', () {
    _rigTest('two concurrent first taps share ONE initialize', (async, rig) {
      rig.engine.initializeGate = Completer<bool>();
      final other = rig.addHost();
      unawaited(rig.c.toggle());
      unawaited(other.controller.toggle());
      async.flushMicrotasks();
      expect(rig.engine.initializeCalls, 1);
      rig.engine.initializeGate!.complete(true);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      expect(rig.engine.initializeCalls, 1);
    });

    _rigTest('a controller disposed while starting never opens a mic', (
      async,
      rig,
    ) {
      rig.engine.initializeGate = Completer<bool>();
      _tap(async, rig.c);
      rig.c.dispose();
      rig.engine.initializeGate!.complete(true);
      async.elapse(const Duration(seconds: 1));
      expect(rig.engine.listenCalls, 0);
      expect(rig.ends, isEmpty, reason: 'no host callback on disposed');
    });

    _rigTest('a Cancel during a slow initialize never lets a listen through', (
      async,
      rig,
    ) {
      rig.engine.initializeGate = Completer<bool>();
      _tap(async, rig.c);
      rig.c.cancel();
      rig.engine.initializeGate!.complete(true);
      async.elapse(const Duration(seconds: 1));
      expect(rig.engine.listenCalls, 0);
      expect(rig.ends, hasLength(1));
    });

    _rigTest(
      'the next listen waits for the engine to go inactive, capped at the quiesce',
      (async, rig) {
        rig.engine.cancelEmitsStatuses =
            false; // a recognizer slow to shut down
        final other = rig.addHost();
        _tap(async, rig.c);
        rig.c.stop();
        async.flushMicrotasks();
        _tap(async, other.controller);
        async.elapse(const Duration(milliseconds: 500));
        expect(
          rig.engine.listenCalls,
          1,
          reason: 'still waiting for notListening',
        );
        rig.engine.emitStatus('notListening');
        async.elapse(SpeechInputTiming.settle);
        expect(rig.engine.listenCalls, 2);
      },
    );

    _rigTest(
      'the quiesce is capped: a silent engine does not block the next listen forever',
      (async, rig) {
        rig.engine.cancelEmitsStatuses = false;
        final other = rig.addHost();
        _tap(async, rig.c);
        rig.c.stop();
        async.flushMicrotasks();
        _tap(async, other.controller);
        async.elapse(SpeechInputTiming.quiesce + SpeechInputTiming.settle * 2);
        expect(rig.engine.listenCalls, 2);
      },
    );

    _rigTest(
      'Cancel then a tap inside the web prompt still waits (keyed on engine activity, not on listening)',
      (async, rig) {
        // Web: `listening` has NOT arrived yet when Cancel is tapped.
        rig.engine.cancelEmitsStatuses = false;
        final other = rig.addHost();
        _tap(async, rig.c);
        expect(rig.c.state, SpeechInputState.starting);
        rig.c.cancel();
        async.flushMicrotasks();
        _tap(async, other.controller);
        async.elapse(const Duration(milliseconds: 500));
        expect(rig.engine.listenCalls, 1);
        rig.engine.emitStatus('notListening');
        async.elapse(SpeechInputTiming.settle);
        expect(rig.engine.listenCalls, 2);
      },
      web: true,
    );

    _rigTest('the next listen waits the settle after a completed cancel', (
      async,
      rig,
    ) {
      final other = rig.addHost();
      _tap(async, rig.c);
      rig.engine.emitResult('x');
      rig.c.stop();
      _tap(async, other.controller);
      expect(rig.engine.listenCalls, 1);
      async.elapse(SpeechInputTiming.settle - const Duration(milliseconds: 1));
      expect(rig.engine.listenCalls, 1);
      async.elapse(const Duration(milliseconds: 1));
      expect(rig.engine.listenCalls, 2);
    });

    _rigTest('a settle that already passed costs nothing', (async, rig) {
      _tap(async, rig.c);
      rig.c.stop();
      async.elapse(const Duration(seconds: 2));
      _tap(async, rig.c);
      expect(rig.engine.listenCalls, 2);
    });

    _rigTest(
      'a hung engine cancel does not wedge the slot: the next start times out, a later one works',
      (async, rig) {
        rig.engine.cancelGate = Completer<void>();
        final other = rig.addHost();
        _tap(async, rig.c);
        rig.c.stop();
        async.flushMicrotasks();
        _tap(async, other.controller);
        // The start timeout (4 s) covers the wait for the slot too, so the next
        // start gives up before the hung cancel's own timeout (5 s).
        async.elapse(SpeechInputTiming.startTimeoutNative);
        expect(other.last.failure, SpeechFailure.engine);
        expect(rig.engine.listenCalls, 1);
        // The engine answers again; the hung call's timeout frees the slot.
        rig.engine.cancelGate = null;
        async.elapse(SpeechInputTiming.engineCallTimeout);
        async.elapse(SpeechInputTiming.toggleGuard);
        _tap(async, other.controller);
        async.elapse(SpeechInputTiming.settle * 2);
        expect(rig.engine.listenCalls, 2);
        expect(other.controller.state, SpeechInputState.listening);
      },
    );
  });

  group('stale results of an ended session', () {
    _rigTest(
      'a stale begin result never ends the NEXT session of the same controller (epoch)',
      (async, rig) {
        // Web: a long start timeout, so only the stale result could end B.
        rig.engine.listenGate = Completer<void>();
        _tap(async, rig.c); // A: its listen call hangs
        expect(rig.c.state, SpeechInputState.starting);
        rig.c.cancel();
        expect(rig.ends, hasLength(1));
        async.elapse(SpeechInputTiming.toggleGuard);
        rig.engine.listenGate = null;
        _tap(async, rig.c); // B queues behind A's hung call
        expect(rig.c.state, SpeechInputState.starting);
        // A's listen call times out and A's begin returns an engine failure...
        async.elapse(
          SpeechInputTiming.engineCallTimeout + SpeechInputTiming.settle * 2,
        );
        // ...which must not end B.
        expect(rig.ends, hasLength(1), reason: 'only A ended');
        expect(rig.c.state, SpeechInputState.starting);
        rig.engine.emitStatus('listening');
        expect(rig.c.state, SpeechInputState.listening);
      },
      web: true,
    );

    _rigTest(
      'an ownerless listening (a prompt answered late) never starts a session that is still waiting',
      (async, rig) {
        rig.engine.cancelEmitsStatuses =
            false; // A's recognizer is slow to stop
        final other = rig.addHost();
        _tap(
          async,
          rig.c,
        ); // A: listen issued, no `listening` yet (prompt open)
        rig.c.cancel();
        async.flushMicrotasks();
        _tap(async, other.controller); // B waits for the engine to go inactive
        expect(other.controller.state, SpeechInputState.starting);
        final cancelsBefore = rig.engine.cancelCalls;
        // The user answers A's prompt: `listening` arrives with no owner.
        rig.engine.emitStatus('listening');
        async.flushMicrotasks();
        expect(
          other.controller.state,
          SpeechInputState.starting,
          reason: 'B has not issued its own listen yet',
        );
        expect(
          rig.engine.cancelCalls,
          cancelsBefore + 1,
          reason: 'an ownerless hot mic is cancelled',
        );
        // B then gets its turn and its own listening status.
        rig.engine.emitStatus('notListening');
        async.elapse(SpeechInputTiming.settle * 2);
        expect(rig.engine.listenCalls, 2);
        rig.engine.emitStatus('listening');
        expect(other.controller.state, SpeechInputState.listening);
      },
      web: true,
    );
  });

  group('two hosts, one engine', () {
    _rigTest('a foreign active session is ended as preempted, words kept', (
      async,
      rig,
    ) {
      final other = rig.addHost();
      _tap(async, rig.c);
      rig.engine.emitResult('first host words');
      _tap(async, other.controller);
      expect(rig.host.last.reason, SpeechEndReason.preempted);
      expect(rig.host.last.transcript, 'first host words');
      async.elapse(SpeechInputTiming.settle * 2);
      expect(other.controller.state, SpeechInputState.listening);
    });

    _rigTest(
      'cancel / endForHidden / dispose of an idle host never touch another host\'s mic',
      (async, rig) {
        final other = rig.addHost();
        _tap(async, rig.c);
        rig.engine.emitResult('keep going');
        final cancelsBefore = rig.engine.cancelCalls;
        other.controller.cancel();
        other.controller.endForHidden();
        other.controller.stop();
        other.controller.send();
        other.controller.dispose();
        async.flushMicrotasks();
        expect(rig.c.state, SpeechInputState.listening);
        expect(rig.engine.cancelCalls, cancelsBefore);
        expect(rig.ends, isEmpty);
      },
    );

    _rigTest('results reach only the bound session', (async, rig) {
      final other = rig.addHost();
      _tap(async, rig.c);
      rig.engine.emitResult('for the first');
      expect(other.controller.liveText, '');
      expect(rig.c.liveText, 'for the first');
    });
  });

  group('host callbacks', () {
    _rigTest(
      'dispose while listening: no onEnd, no busy(false), engine released',
      (async, rig) {
        _tap(async, rig.c);
        rig.engine.emitResult('half a sentence');
        rig.c.dispose();
        async.flushMicrotasks();
        expect(rig.ends, isEmpty);
        expect(rig.host.busy, <bool>[true]);
        expect(rig.engine.cancelCalls, 1);
      },
    );

    _rigTest(
      'a busy callback that throws is reported by type and never breaks the session',
      (async, rig) {
        final throwing = SpeechInputController(
          service: rig.service,
          onEnd: rig.host.ends.add,
          onBusyChanged: (_) => throw StateError('host bug'),
        );
        _tap(async, throwing);
        expect(throwing.state, SpeechInputState.listening);
        rig.engine.emitResult('two rotis');
        throwing.stop();
        expect(throwing.state, SpeechInputState.idle);
        expect(rig.host.ends, hasLength(1));
        expect(rig.host.last.transcript, 'two rotis');
        expect(recorded.map((r) => r.reason), contains('speech_input_on_busy'));
        expect(
          recorded.map((r) => r.error.toString()),
          contains('StateError'),
        );
        throwing.dispose();
      },
    );

    _rigTest(
      'a host disposed inside its own onEnd does not crash the controller',
      (async, rig) {
        late SpeechInputController self;
        self = SpeechInputController(
          service: rig.service,
          onEnd: (_) => self.dispose(),
        );
        _tap(async, self);
        rig.engine.emitResult('words');
        self.stop();
        async.flushMicrotasks();
        expect(self.state, SpeechInputState.idle);
      },
    );

    _rigTest(
      'elapsed ticks once a second while listening and stops at the end',
      (async, rig) {
        _tap(async, rig.c);
        async.elapse(const Duration(seconds: 3));
        expect(rig.c.elapsed.value, const Duration(seconds: 3));
        rig.c.stop();
        async.elapse(const Duration(seconds: 3));
        expect(rig.c.elapsed.value, const Duration(seconds: 3));
      },
    );
  });

  group('speechEndWantsFocus (pure)', () {
    SpeechSessionEnd end(SpeechEndReason r) =>
        SpeechSessionEnd(transcript: 'x', reason: r);

    test('only a hidden tab or a preemption must NOT take the keyboard', () {
      for (final r in SpeechEndReason.values) {
        final expected =
            r != SpeechEndReason.hidden && r != SpeechEndReason.preempted;
        expect(speechEndWantsFocus(end(r)), expected, reason: '$r');
      }
    });
  });

  group('decideSpeechEnd', () {
    SpeechSessionEnd end(SpeechEndReason r, String words) =>
        SpeechSessionEnd(transcript: words, reason: r);

    test('Stop, auto, hidden, preempted commit the words; nothing is sent', () {
      for (final r in <SpeechEndReason>[
        SpeechEndReason.userStop,
        SpeechEndReason.auto,
        SpeechEndReason.hidden,
        SpeechEndReason.preempted,
        SpeechEndReason.error,
      ]) {
        expect(
          decideSpeechEnd(end(r, 'two rotis'), minChars: 3),
          SpeechEndAction.commit,
          reason: '$r',
        );
      }
    });

    test('Send sends at or above minChars, tooShort under it', () {
      expect(
        decideSpeechEnd(end(SpeechEndReason.userSend, 'ok'), minChars: 1),
        SpeechEndAction.send,
      );
      expect(
        decideSpeechEnd(end(SpeechEndReason.userSend, 'ok'), minChars: 3),
        SpeechEndAction.tooShort,
      );
      expect(
        decideSpeechEnd(end(SpeechEndReason.userSend, '  '), minChars: 1),
        SpeechEndAction.tooShort,
      );
      expect(
        decideSpeechEnd(end(SpeechEndReason.userSend, 'egg'), minChars: 3),
        SpeechEndAction.send,
      );
    });

    test('Cancel discards, dispose is none, an end with no words discards', () {
      expect(
        decideSpeechEnd(end(SpeechEndReason.cancelled, 'words'), minChars: 1),
        SpeechEndAction.discard,
      );
      expect(
        decideSpeechEnd(end(SpeechEndReason.disposed, 'words'), minChars: 1),
        SpeechEndAction.none,
      );
      expect(
        decideSpeechEnd(end(SpeechEndReason.userStop, ' '), minChars: 1),
        SpeechEndAction.discard,
      );
      expect(
        decideSpeechEnd(end(SpeechEndReason.auto, ''), minChars: 1),
        SpeechEndAction.discard,
      );
    });
  });
}
