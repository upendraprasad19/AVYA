/// A scriptable stand-in for the `speech_to_text` plugin (plan `docs/plans/voice-input-unified.md`, D1).
///
/// It copies the plugin's SHAPE, which is what the session logic must survive:
///
/// - ONE result slot. Every `listen()` overwrites it, results carry no session
///   id, so [emitResult] reaches whichever session listened LAST (plan G1).
/// - ONE pair of status/error listeners, installed by the first `initialize`
///   and replaced on every attach (the real engine re-assigns the plugin's
///   public `statusListener` / `errorListener` fields).
/// - A cancel on an idle engine emits nothing; a cancel on a running one emits
///   `notListening` then `done` (a user stop's order on Android, plan G5).
/// - The engine never emits anything by itself: the test drives every event, in
///   the order it wants to prove (native: final before `notListening`; user
///   stop: `notListening`, `done`, error; web: `listening` after the permission
///   prompt, never a final).
/// - `done` follows the plugin's own rule (speech_to_text 7.4.0): Android sends
///   `done` when a result was sent and `doneNoResult` when none was, and Dart
///   rewrites `doneNoResult` to `done` and DELIVERS it; a `done` after only
///   PARTIAL results is swallowed until the FINAL result releases it.
///   So a silent session delivers `notListening`, `done`, then the posted error.
///   [emitRawStatus] bypasses the rule for the controller's defensive branches
///   (a partial result followed by a delivered `done`, which 7.4.0 never sends)
///   (B-pass 2026-11-14).
library;

import 'dart:async';

import 'package:icanbefitter/core/services/speech_input_service.dart';
import 'package:speech_to_text/speech_to_text.dart';

class FakeSpeechEngine implements SpeechEngine {
  // -- scripting --------------------------------------------------------------

  /// What `initialize` answers. A gate holds it open.
  bool initializeResult = true;
  Object? initializeThrows;
  Completer<bool>? initializeGate;

  /// `listen` throws this (a web `start()` InvalidStateError, a plugin
  /// `ListenFailedException`).
  Object? listenThrows;

  /// Holds `listen` open (an engine call that hangs).
  Completer<void>? listenGate;

  /// Native: emit `listening` synchronously inside `listen` (Android calls
  /// `notifyListening(true)` before the recognizer's own start, plan G5). Web:
  /// leave false and call [emitStatus] after the permission prompt.
  bool emitListeningInsideListen = true;

  /// A cancel of a running engine emits `notListening` then `done` (true), or
  /// stays silent (false: a recognizer that is slow to shut down, so the
  /// service's quiesce has something to wait for).
  bool cancelEmitsStatuses = true;

  /// `cancel` throws / hangs.
  Object? cancelThrows;
  Completer<void>? cancelGate;

  // -- observation -------------------------------------------------------------

  final List<String> calls = <String>[];
  int initializeCalls = 0;
  int listenCalls = 0;
  int cancelCalls = 0;
  List<SpeechConfigOption>? lastInitOptions;
  Duration? lastFinalTimeout;
  SpeechListenOptions? lastListenOptions;
  Duration? lastChangedPauseFor;

  /// True from a `listen` until a `cancel` (or a test-driven `notListening`).
  bool running = false;

  // The plugin's `done` rule state, reset by every `listen`.
  bool _resultSent = false;
  bool _latestResultFinal = false;
  bool _notifiedDone = false;

  void Function(String status)? _onStatus;
  void Function(SpeechEngineError error)? _onError;
  void Function(SpeechEngineResult result)? _resultListener;

  // -- the SpeechEngine contract ------------------------------------------------

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(SpeechEngineError error) onError,
    required Duration finalTimeout,
    required List<SpeechConfigOption> options,
  }) async {
    calls.add('initialize');
    initializeCalls++;
    // The real engine re-assigns the listeners on every attach.
    _onStatus = onStatus;
    _onError = onError;
    lastFinalTimeout = finalTimeout;
    lastInitOptions = options;
    final gate = initializeGate;
    if (gate != null) return gate.future;
    final thrown = initializeThrows;
    if (thrown != null) throw thrown;
    return initializeResult;
  }

  @override
  Future<void> listen({
    required void Function(SpeechEngineResult result) onResult,
    required SpeechListenOptions options,
  }) async {
    calls.add('listen');
    listenCalls++;
    lastListenOptions = options;
    // The single result slot: the LAST listen wins, whoever it was for.
    _resultListener = onResult;
    _resultSent = false;
    _latestResultFinal = false;
    _notifiedDone = false;
    final thrown = listenThrows;
    if (thrown != null) throw thrown;
    running = true;
    if (emitListeningInsideListen) emitStatus('listening');
    final gate = listenGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    cancelCalls++;
    final gate = cancelGate;
    if (gate != null) await gate.future;
    final thrown = cancelThrows;
    if (thrown != null) throw thrown;
    if (running && cancelEmitsStatuses) {
      running = false;
      emitStatus('notListening');
      emitStatus('done');
    }
  }

  @override
  Future<void> changePauseFor(Duration pauseFor) async {
    calls.add('changePauseFor');
    lastChangedPauseFor = pauseFor;
  }

  // -- driving events -------------------------------------------------------------

  /// A status the plugin would deliver. `done` follows the plugin's rule: with
  /// NO result sent it is Android's `doneNoResult` (rewritten to `done`,
  /// delivered); after only partial results it is swallowed until the final.
  void emitStatus(String status) {
    if (status == 'notListening' || status == 'done') running = false;
    if (status == 'done') {
      _notifiedDone = true;
      if (_resultSent && !_latestResultFinal) return;
    }
    _onStatus?.call(status);
  }

  /// A status delivered as-is, past the plugin's `done` rule: for the
  /// controller's DEFENSIVE branches (`done` delivered after only partial
  /// results, which 7.4.0 never produces).
  void emitRawStatus(String status) {
    if (status == 'notListening' || status == 'done') running = false;
    _onStatus?.call(status);
  }

  /// Delivered to the result listener of the LAST `listen`, like the plugin.
  /// A FINAL result after a swallowed `done` releases it (plugin: the final
  /// status check right after the result).
  void emitResult(String words, {bool isFinal = false}) {
    _resultSent = true;
    _resultListener?.call(SpeechEngineResult(words, isFinal: isFinal));
    if (isFinal) {
      _latestResultFinal = true;
      if (_notifiedDone) _onStatus?.call('done');
    }
  }

  void emitError(String code, {bool permanent = false}) {
    _onError?.call(SpeechEngineError(code, permanent: permanent));
  }

  /// The platform's natural end on Android: the final comes BEFORE
  /// `notListening` (plan G5).
  void emitNativeNaturalEnd(String words) {
    emitResult(words, isFinal: true);
    emitStatus('notListening');
    emitStatus('done');
  }

  /// A user stop's order on Android: `notListening`, `done`, THEN the final.
  void emitNativeStopOrder(String words) {
    emitStatus('notListening');
    emitStatus('done');
    emitResult(words, isFinal: true);
  }
}
