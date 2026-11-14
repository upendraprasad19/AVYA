/// The ONE owner of the `speech_to_text` plugin (plan `docs/plans/voice-input-unified.md`, D1).
///
/// Why one owner: `SpeechToText()` is a process-wide singleton. `initialize()`
/// returns early once it worked, so a second caller's `onStatus`/`onError` are
/// never installed; the plugin keeps ONE `_resultListener` that every `listen()`
/// overwrites, and results carry no session id, so a late result of session A
/// reaches whatever session B installed (plan G1). Every host (the AI Coach
/// composer, the nutrition Log sheet) therefore talks to this service, which
/// forwards each engine event to the single BOUND session and drops the rest.
///
/// The service never decides what a session means; it only (a) initialises the
/// plugin once, (b) serialises the engine calls, (c) binds exactly one session
/// to the event stream, and (d) makes sure a new listen never starts while the
/// previous one is still shutting down (quiesce + settle).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/serial_slot.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Every timing constant of the speech input, in ONE place (plan D1). A test
/// pins the relations between them.
class SpeechInputTiming {
  const SpeechInputTiming._();

  /// Passed to the plugin's `initialize`: after a plugin-initiated stop (the
  /// `pauseFor` / `listenFor` timers) the plugin fabricates a final from the
  /// last partial this long afterwards.
  static const Duration finalTimeout = Duration(seconds: 1);

  /// Native only: how long a recognizer-initiated end (`notListening` without
  /// a final) waits for a final, `done` or an error before the session ends
  /// with the words on screen. Must exceed [finalTimeout].
  static const Duration endGrace = Duration(milliseconds: 1500);

  /// Native only: a `done` with no words waits this long for a trailing error
  /// (Android delivers errors through `handler.post`, AFTER `done`).
  static const Duration errorGrace = Duration(milliseconds: 400);

  /// The longest a new listen waits for the previous run of the engine to go
  /// inactive.
  static const Duration quiesce = Duration(seconds: 1);

  /// After a cancel of the engine completed, the next listen waits until this
  /// long has passed (Android SDK 29 destroys the recognizer 50 ms after a
  /// cancel, plan G5).
  static const Duration settle = Duration(milliseconds: 150);

  /// A session that has produced no words and is younger than this may be
  /// restarted ONCE after a busy/client error or a web start exception.
  static const Duration retryWindow = Duration(milliseconds: 1500);

  /// A tap within this long after a session ended is ignored (a double tap on
  /// the mic must not land on the Stop/Send buttons that replace it).
  static const Duration toggleGuard = Duration(milliseconds: 300);

  /// Bounds every engine call that holds the serial slot.
  static const Duration engineCallTimeout = Duration(seconds: 5);

  /// `starting` -> `listening` must happen within this long (native).
  static const Duration startTimeoutNative = Duration(seconds: 4);

  /// Same, on web: the browser's permission prompt can take a while.
  static const Duration startTimeoutWeb = Duration(seconds: 15);

  /// Today's values (the "mic stops after 2-3 seconds" fix): do not change.
  static const Duration listenFor = Duration(seconds: 60);
  static const Duration pauseFor = Duration(seconds: 5);
}

/// What the listen call carries. A function, because `SpeechListenOptions` has
/// a non-const constructor and no `==` (plan G3).
///
/// Native values equal the coach's historic call (en_IN, dictation, partial
/// results, 60 s, 5 s). On web the locale is `en-IN` (the Web Speech API wants
/// a hyphen; Android converts) and there is NO Dart pause timer: it would start
/// before the user answers the browser's permission prompt (plan G4). The
/// service applies the pause on the session's own `listening` status instead.
SpeechListenOptions speechListenOptions({required bool web}) {
  return SpeechListenOptions(
    localeId: web ? 'en-IN' : 'en_IN',
    listenMode: ListenMode.dictation,
    partialResults: true,
    listenFor: SpeechInputTiming.listenFor,
    pauseFor: web ? null : SpeechInputTiming.pauseFor,
    cancelOnError: false,
  );
}

/// The `initialize(options:)` list. Chrome on Android duplicates results when
/// phrases are aggregated, so aggregation is switched off there. Flutter web
/// reports the browser's OS in `defaultTargetPlatform`; an unknown OS also
/// resolves to android, which is harmless.
List<SpeechConfigOption> speechInitOptions({
  required bool web,
  required TargetPlatform platform,
}) {
  return <SpeechConfigOption>[
    if (web && platform == TargetPlatform.android)
      SpeechToText.webDoNotAggregate,
  ];
}

/// How a plugin error code is treated (plan D2). Table-driven and pure.
enum SpeechErrorKind {
  /// Silence, no match, an aborted run: the session just ends.
  benign,

  /// The user (or the browser) refused the microphone.
  permission,

  /// No recognizer on this device or browser.
  unsupported,

  /// Anything else: shown to the user and reported (code only).
  engine,
}

SpeechErrorKind classifySpeechError(String code, {required bool web}) {
  final c = code.trim().toLowerCase();
  if (c == 'not supported' ||
      c.contains('speech_not_supported') ||
      c.contains('recognizernotavailable')) {
    return SpeechErrorKind.unsupported;
  }
  if (web) {
    switch (c) {
      case 'no-speech':
      case 'aborted':
        return SpeechErrorKind.benign;
      case 'not-allowed':
      case 'service-not-allowed':
        return SpeechErrorKind.permission;
      default:
        return SpeechErrorKind.engine;
    }
  }
  switch (c) {
    case 'error_no_match':
    case 'error_speech_timeout':
    case 'error_client':
    case 'error_busy':
      return SpeechErrorKind.benign;
    case 'error_permission':
      return SpeechErrorKind.permission;
    default:
      return SpeechErrorKind.engine;
  }
}

/// `error_busy` / `error_client` can mean "the recognizer was not free yet":
/// the session may be restarted once inside the retry window.
bool isRetryableStartError(String code) {
  final c = code.trim().toLowerCase();
  return c == 'error_busy' || c == 'error_client';
}

// ---------------------------------------------------------------------------
// The engine seam
// ---------------------------------------------------------------------------

class SpeechEngineResult {
  const SpeechEngineResult(this.words, {this.isFinal = false});
  final String words;
  final bool isFinal;
}

class SpeechEngineError {
  const SpeechEngineError(this.code, {this.permanent = false});
  final String code;
  final bool permanent;
}

/// What the service needs from the plugin. The real one wraps the plugin; tests
/// use `FakeSpeechEngine`, which mimics the plugin's single result slot.
abstract class SpeechEngine {
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(SpeechEngineError error) onError,
    required Duration finalTimeout,
    required List<SpeechConfigOption> options,
  });

  Future<void> listen({
    required void Function(SpeechEngineResult result) onResult,
    required SpeechListenOptions options,
  });

  Future<void> cancel();

  Future<void> changePauseFor(Duration pauseFor);
}

class PluginSpeechEngine implements SpeechEngine {
  PluginSpeechEngine({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(SpeechEngineError error) onError,
    required Duration finalTimeout,
    required List<SpeechConfigOption> options,
  }) {
    void onPluginError(SpeechRecognitionError e) =>
        onError(SpeechEngineError(e.errorMsg, permanent: e.permanent));
    // The plugin is a singleton and `initialize` returns early once it worked,
    // so a second attach would never install its callbacks. The listeners are
    // public fields: re-assign them on every attach (plan G1).
    _speech.errorListener = onPluginError;
    _speech.statusListener = onStatus;
    return _speech.initialize(
      onError: onPluginError,
      onStatus: onStatus,
      finalTimeout: finalTimeout,
      options: options,
    );
  }

  @override
  Future<void> listen({
    required void Function(SpeechEngineResult result) onResult,
    required SpeechListenOptions options,
  }) async {
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) => onResult(
        SpeechEngineResult(r.recognizedWords, isFinal: r.finalResult),
      ),
      listenOptions: options,
    );
  }

  @override
  Future<void> cancel() => _speech.cancel();

  @override
  Future<void> changePauseFor(Duration pauseFor) async {
    _speech.changePauseFor(pauseFor);
  }
}

// ---------------------------------------------------------------------------
// The session seam
// ---------------------------------------------------------------------------

/// Receives the engine events of the ONE bound session. Implemented privately
/// by `SpeechInputController`.
abstract class SpeechSessionSink {
  void engineListening();
  void engineResult(SpeechEngineResult result);
  void engineNotListening();
  void engineDone();
  void engineError(SpeechErrorKind kind, String code);

  /// A new session wants the microphone: end this one normally.
  void endForPreempt();
}

enum SpeechBeginStatus {
  /// `engine.listen` was issued; the session waits for its `listening` status.
  started,

  /// The session ended while `begin` was waiting: nothing was started.
  abandoned,

  /// No recognizer here (web without the API, `recognizerNotAvailable`).
  unsupported,

  /// `initialize` returned false on a device: the microphone was refused.
  permissionDenied,

  /// The listen call threw or timed out.
  engineFailure,
}

class SpeechBeginResult {
  const SpeechBeginResult(this.status, {this.code});
  final SpeechBeginStatus status;

  /// The exception type, for telemetry. Never a transcript.
  final String? code;
}

// ---------------------------------------------------------------------------
// The service
// ---------------------------------------------------------------------------

class SpeechInputService {
  SpeechInputService({
    required SpeechEngine engine,
    bool? isWeb,
    TargetPlatform? platform,
    Duration Function()? monotonic,
  }) : _engine = engine,
       isWeb = isWeb ?? kIsWeb,
       platform = platform ?? defaultTargetPlatform,
       _monotonic = monotonic ?? _stopwatchClock();

  final SpeechEngine _engine;

  /// A monotonic clock for the settle (a real [Stopwatch] by default). A timer
  /// armed at every cancel would outlive a widget test and trip its pending-
  /// timer check; an elapsed-time check creates a timer only when a listen
  /// actually follows a cancel within [SpeechInputTiming.settle].
  final Duration Function() _monotonic;

  static Duration Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  /// Injected so tests can cover the web branch (`kIsWeb` is a compile-time
  /// constant, false on the VM).
  final bool isWeb;
  final TargetPlatform platform;

  final SerialSlot _slot = SerialSlot();
  SpeechSessionSink? _bound;

  /// True from the moment `engine.listen` is ISSUED until `notListening` /
  /// `done`. The quiesce keys on this, not on `listening`: on web `listening`
  /// arrives only after the permission prompt (plan D1).
  bool _engineActive = false;
  Completer<void>? _inactiveWaiter;

  /// When the last cancel completed ([_monotonic] time); the next `begin`
  /// waits out the rest of [SpeechInputTiming.settle].
  Duration? _lastCancelDoneAt;

  Future<bool>? _ready;

  /// Web: null until the probe answered. Native: stays null.
  bool? _webSupported;

  /// True once the platform said there is no recognizer (native
  /// `recognizerNotAvailable`, a web browser without the API). Cached.
  bool _unsupported = false;

  /// Web: true only once the probe found a recognizer (no flicker of a mic that
  /// then disappears on Firefox). Native: true until `initialize` reports that
  /// the device has no recognizer; the permission is asked on the first tap,
  /// never at mount.
  bool get isSupported => isWeb ? _webSupported == true : !_unsupported;

  /// True only once the platform definitely said there is no recognizer. A tap
  /// on web before the probe answered is NOT unsupported (the mic is hidden
  /// until then, so this is only reachable through a race).
  bool get knownUnsupported => _unsupported;

  /// True while the engine may still be running (observability for tests).
  bool get isEngineActive => _engineActive;

  /// Web only: takes the support probe (no permission prompt, plan G4).
  Future<bool> probeSupport() async {
    if (!isWeb) return true;
    await _ensureReady();
    return isSupported;
  }

  Future<bool> _ensureReady() {
    final existing = _ready;
    if (existing != null) return existing;
    final future = _initializeEngine();
    _ready = future;
    return future;
  }

  Future<bool> _initializeEngine() async {
    var ok = false;
    try {
      ok = await _engine.initialize(
        onStatus: _onStatus,
        onError: _onError,
        finalTimeout: SpeechInputTiming.finalTimeout,
        options: speechInitOptions(web: isWeb, platform: platform),
      );
    } catch (e, s) {
      // `recognizerNotAvailable` is a PlatformException from initialize; the
      // web initialize can throw out of its try/finally (plan G4). Both mean
      // "no recognizer".
      _unsupported = true;
      unawaited(
        ErrorTelemetry.recordNonFatal(e, s, reason: 'speech_input_initialize'),
      );
    }
    if (isWeb) {
      _webSupported = ok;
      if (!ok) _unsupported = true;
    } else if (!ok && !_unsupported) {
      // Native: a refusal may be granted later, so a false is not cached.
      _ready = null;
    }
    return ok;
  }

  /// Starts one listen for [sink]. Order: end a foreign session, take the
  /// slot, initialise (memoised), wait for the previous run to go inactive and
  /// settle, bind, issue the listen. [stillWanted] lets the session say it was
  /// ended (Cancel, dispose, timeout) while this call was waiting.
  Future<SpeechBeginResult> begin(
    SpeechSessionSink sink, {
    required bool Function() stillWanted,
  }) async {
    // A foreign active session is ended through the normal end path BEFORE we
    // enter the slot, so its cancel is queued ahead of us (no screen shows two
    // live mics; this is a safety net).
    final other = _bound;
    if (other != null && !identical(other, sink)) other.endForPreempt();

    final ticket = _slot.enter();
    await ticket.turn;
    try {
      if (!stillWanted()) {
        return const SpeechBeginResult(SpeechBeginStatus.abandoned);
      }
      final ready = await _ensureReady();
      if (!stillWanted()) {
        return const SpeechBeginResult(SpeechBeginStatus.abandoned);
      }
      if (!ready) {
        return SpeechBeginResult(
          _unsupported
              ? SpeechBeginStatus.unsupported
              : SpeechBeginStatus.permissionDenied,
        );
      }

      if (_engineActive) await _waitInactive();
      final lastCancel = _lastCancelDoneAt;
      if (lastCancel != null) {
        final remaining =
            SpeechInputTiming.settle - (_monotonic() - lastCancel);
        if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      }
      if (!stillWanted()) {
        return const SpeechBeginResult(SpeechBeginStatus.abandoned);
      }

      _bound = sink;
      _engineActive = true;
      try {
        await _engine
            .listen(
              onResult: _onResult,
              options: speechListenOptions(web: isWeb),
            )
            .timeout(SpeechInputTiming.engineCallTimeout);
      } catch (e, s) {
        _engineActive = false;
        if (identical(_bound, sink)) _bound = null;
        unawaited(
          ErrorTelemetry.recordNonFatal(e, s, reason: 'speech_input_listen'),
        );
        return SpeechBeginResult(
          SpeechBeginStatus.engineFailure,
          code: e.runtimeType.toString(),
        );
      }
      return const SpeechBeginResult(SpeechBeginStatus.started);
    } finally {
      ticket.release();
    }
  }

  Future<void> _waitInactive() async {
    if (!_engineActive) return;
    final waiter = _inactiveWaiter ??= Completer<void>();
    await waiter.future.timeout(SpeechInputTiming.quiesce, onTimeout: () {});
  }

  void _markInactive() {
    _engineActive = false;
    final waiter = _inactiveWaiter;
    _inactiveWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  /// A session ended: unbind it (synchronously, so nothing more reaches it)
  /// and release the engine. EVERY end calls this; the cancel is idempotent
  /// (a cancel on an idle engine emits nothing, plan G5) and is what clears the
  /// plugin's own timers (plan G1).
  void release(SpeechSessionSink sink) {
    if (identical(_bound, sink)) _bound = null;
    unawaited(_cancelSerialized());
  }

  Future<void> _cancelSerialized() async {
    final ticket = _slot.enter();
    await ticket.turn;
    try {
      await _engine.cancel().timeout(SpeechInputTiming.engineCallTimeout);
    } catch (e, s) {
      unawaited(
        ErrorTelemetry.recordNonFatal(e, s, reason: 'speech_input_cancel'),
      );
    } finally {
      _lastCancelDoneAt = _monotonic();
      ticket.release();
    }
  }

  Future<void> _cancelOwnerless() async {
    try {
      await _engine.cancel().timeout(SpeechInputTiming.engineCallTimeout);
    } catch (e, s) {
      unawaited(
        ErrorTelemetry.recordNonFatal(e, s, reason: 'speech_input_cancel'),
      );
    } finally {
      _lastCancelDoneAt = _monotonic();
    }
  }

  // -- engine events --------------------------------------------------------

  void _onStatus(String status) {
    switch (status) {
      case 'listening':
        final bound = _bound;
        if (bound == null) {
          // The permission was answered after the session gave up, or a stop
          // arrived while starting: an ownerless hot mic is impossible. NOT
          // through the slot: a later session's `begin` may be waiting in it,
          // and a cancel queued behind that `begin` would run after ITS listen
          // and cancel the wrong one. A listen in flight always has a bound
          // sink (bound just before `engine.listen`), so an unowned `listening`
          // cannot belong to a live listen and this cancel is safe to run now.
          unawaited(_cancelOwnerless());
          return;
        }
        bound.engineListening();
        if (isWeb) unawaited(_applyWebPause());
      case 'notListening':
        _markInactive();
        _bound?.engineNotListening();
      case 'done':
      case 'doneNoResult':
        _markInactive();
        _bound?.engineDone();
    }
  }

  Future<void> _applyWebPause() async {
    try {
      await _engine
          .changePauseFor(SpeechInputTiming.pauseFor)
          .timeout(SpeechInputTiming.engineCallTimeout);
    } catch (e, s) {
      unawaited(
        ErrorTelemetry.recordNonFatal(
          e,
          s,
          reason: 'speech_input_change_pause',
        ),
      );
    }
  }

  void _onResult(SpeechEngineResult result) {
    _bound?.engineResult(result);
  }

  void _onError(SpeechEngineError error) {
    final bound = _bound;
    // No bound session: the web probe's own `not supported`, or an error of a
    // session that already ended. Nobody owns it.
    if (bound == null) return;
    bound.engineError(classifySpeechError(error.code, web: isWeb), error.code);
  }
}

/// The app-wide service. Tests override this with a fake engine.
final speechInputServiceProvider = Provider<SpeechInputService>(
  (ref) => SpeechInputService(engine: PluginSpeechEngine()),
);
