/// One dictation session on behalf of one host (plan `docs/plans/voice-input-unified.md`, D2).
///
/// Local widget state like a `TextEditingController`: no `ref` inside. The host
/// creates it, listens to it, and disposes it. It owns NO plugin state: every
/// engine call goes through [SpeechInputService], which forwards the plugin's
/// events to the ONE bound session.
///
/// The design in one paragraph (plan §0, D2): three states (idle, starting,
/// listening), and ONE end path ([_finish]). Stop, Send and Cancel act at once
/// on the words that are on screen; the plugin's final is never awaited on a
/// user action (on a user stop Android emits `notListening` and `done` BEFORE
/// the final, errors arrive after `done`, and the web engine never sends a
/// final at all, plan G4/G5). Every end runs one idempotent engine cancel, which
/// is what clears the plugin's own timers. A session ignores every engine event
/// until its OWN `listening` status, so the late events of the previous listen
/// (the plugin has one result listener and no session ids, plan G1) can never
/// end or feed it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/speech_input_service.dart';

enum SpeechInputState { idle, starting, listening }

/// Why a session ended. `disposed` is the only reason that reaches no host.
enum SpeechEndReason {
  userStop,
  userSend,
  cancelled,
  auto,
  preempted,
  hidden,
  error,
  disposed,
}

enum SpeechFailure { permissionDenied, unsupported, engine }

/// What a host receives, exactly once per session that left `idle`.
class SpeechSessionEnd {
  const SpeechSessionEnd({
    required this.transcript,
    required this.reason,
    this.failure,
    this.empty = false,
  });

  /// The words on screen at that moment (the platform's final words when it
  /// just delivered a final, else the live text). Never null, may be empty.
  final String transcript;
  final SpeechEndReason reason;

  /// Set for `error` ends; the host shows the matching message once.
  final SpeechFailure? failure;

  /// An automatic end with no words: the host says it did not catch anything.
  final bool empty;
}

enum SpeechEndAction { commit, send, tooShort, discard, none }

/// What a host does with an end (pure). The coach passes `minChars: 1` (typing
/// "ok" sends today), nutrition 3 (`_analyse`'s own floor).
///
/// - Stop, an automatic end, a preemption, a hidden tab, an error that kept
///   words: `commit` (the words go into the field, never sent).
/// - Send: `send`, or `tooShort` under [minChars] (a message, no unit spent).
/// - Cancel: `discard`. Dispose: `none`.
SpeechEndAction decideSpeechEnd(SpeechSessionEnd end, {required int minChars}) {
  final words = end.transcript.trim();
  switch (end.reason) {
    case SpeechEndReason.disposed:
      return SpeechEndAction.none;
    case SpeechEndReason.cancelled:
      return SpeechEndAction.discard;
    case SpeechEndReason.userSend:
      return words.length >= minChars
          ? SpeechEndAction.send
          : SpeechEndAction.tooShort;
    case SpeechEndReason.userStop:
    case SpeechEndReason.auto:
    case SpeechEndReason.preempted:
    case SpeechEndReason.hidden:
    case SpeechEndReason.error:
      return words.isEmpty ? SpeechEndAction.discard : SpeechEndAction.commit;
  }
}

/// Whether a host should put the keyboard focus on its field after a COMMIT.
/// Stop, an automatic end and an error that kept words happen on a screen the
/// user is looking at; a hidden tab or a preemption do not, and a focus
/// request there would raise the keyboard over another tab (B-pass
/// 2026-11-14: offstage children can still take focus).
bool speechEndWantsFocus(SpeechSessionEnd end) =>
    end.reason != SpeechEndReason.hidden &&
    end.reason != SpeechEndReason.preempted;

class SpeechInputController extends ChangeNotifier
    implements SpeechSessionSink {
  SpeechInputController({
    required SpeechInputService service,
    required void Function(SpeechSessionEnd end) onEnd,
    void Function(bool busy)? onBusyChanged,
  }) : _service = service,
       _onEnd = onEnd,
       _onBusyChanged = onBusyChanged;

  final SpeechInputService _service;
  final void Function(SpeechSessionEnd end) _onEnd;
  final void Function(bool busy)? _onBusyChanged;

  SpeechInputState _state = SpeechInputState.idle;
  String _liveText = '';
  bool _disposed = false;

  /// Bumps on EVERY `_finish`: a continuation that resumes after an await
  /// compares it to the value it started with.
  int _epoch = 0;

  bool _retried = false;
  bool _inRetryWindow = false;
  bool _listenIssued = false;

  Timer? _startTimeout;
  Timer? _endGrace;
  Timer? _errorGrace;
  Timer? _retryWindow;
  Timer? _ticker;
  Timer? _toggleGuard;
  bool _guardActive = false;

  final ValueNotifier<Duration> _elapsed = ValueNotifier<Duration>(
    Duration.zero,
  );

  // -- read side ------------------------------------------------------------

  SpeechInputState get state => _state;
  String get liveText => _liveText;

  /// `starting` or `listening`: the host swaps its field for the bar.
  bool get isBusy => _state != SpeechInputState.idle;

  /// Web: true only after the probe found a recognizer. Native: true until the
  /// device reports it has none.
  bool get supported => _service.isSupported;

  /// The session counter, for a deferred check that nothing changed.
  int get sessionEpoch => _epoch;

  /// Whole seconds since `listening`, ticked once a second, so the tick
  /// rebuilds only the timer text.
  ValueListenable<Duration> get elapsed => _elapsed;

  /// Web: asks the browser whether a recognizer exists (no permission prompt).
  Future<void> probeSupport() async {
    await _service.probeSupport();
    if (!_disposed) notifyListeners();
  }

  // -- user actions ---------------------------------------------------------

  /// The mic tap: idle starts, listening stops (words kept, nothing sent), a
  /// tap while `starting` is ignored. A tap within [SpeechInputTiming.toggleGuard]
  /// of any end is ignored (a double tap on the mic must not land on the Stop
  /// and Send buttons that replace it).
  Future<void> toggle() async {
    if (_disposed || _guardActive) return;
    switch (_state) {
      case SpeechInputState.idle:
        await _start();
      case SpeechInputState.starting:
        return;
      case SpeechInputState.listening:
        stop();
    }
  }

  /// Keeps the words, sends nothing. Inert unless listening.
  void stop() {
    if (_state != SpeechInputState.listening) return;
    _finish(SpeechEndReason.userStop, _liveText);
  }

  /// Stops and asks the host to send the words. Inert unless listening.
  void send() {
    if (_state != SpeechInputState.listening) return;
    _finish(SpeechEndReason.userSend, _liveText);
  }

  /// Discards the session. Live in `starting` and `listening`; on an idle
  /// controller the end path's latch makes it a no-op (it never touches another
  /// host's session: the engine release is part of the end, which an idle host
  /// never reaches).
  void cancel() => _finish(SpeechEndReason.cancelled, '');

  /// The host went out of sight (hidden tab or sheet, app in the background).
  void endForHidden() => _finish(SpeechEndReason.hidden, _wordsNow());

  @override
  void endForPreempt() => _finish(SpeechEndReason.preempted, _wordsNow());

  String _wordsNow() => _state == SpeechInputState.listening ? _liveText : '';

  // -- start ----------------------------------------------------------------

  Future<void> _start() async {
    if (_service.knownUnsupported) {
      // The service already knows: say so, start nothing.
      _emitWithoutSession(
        const SpeechSessionEnd(
          transcript: '',
          reason: SpeechEndReason.error,
          failure: SpeechFailure.unsupported,
        ),
      );
      return;
    }
    _state = SpeechInputState.starting;
    _liveText = '';
    _elapsed.value = Duration.zero;
    _retried = false;
    _listenIssued = false;
    _inRetryWindow = false;
    _retryWindow?.cancel();
    _retryWindow = null;
    _armStartTimeout(_prelistenBudget());
    _notifyBusy(true);
    notifyListeners();
    await _runBegin(_epoch);
  }

  /// How long the session may wait BEFORE the listen is issued. On a device that
  /// has never been initialised the first `initialize` is where Android shows
  /// the microphone dialog, so the budget is long; once the permission is
  /// settled it is the short listen budget (B-pass 2026-11-14).
  Duration _prelistenBudget() {
    if (_service.isWeb) return SpeechInputTiming.startTimeoutWeb;
    return _service.isInitialized
        ? SpeechInputTiming.startTimeoutNative
        : SpeechInputTiming.startTimeoutFirstUse;
  }

  Duration _listenBudget() => _service.isWeb
      ? SpeechInputTiming.startTimeoutWeb
      : SpeechInputTiming.startTimeoutNative;

  void _armStartTimeout(Duration budget) {
    _startTimeout?.cancel();
    _startTimeout = Timer(budget, () {
      if (_state != SpeechInputState.starting) return;
      _finish(
        SpeechEndReason.error,
        '',
        failure: SpeechFailure.engine,
        code: 'start_timeout',
      );
    });
  }

  /// Called by the service synchronously BEFORE it issues `engine.listen`:
  /// Android emits `listening` before `listen()` returns, web after, so the
  /// listen budget and the one-restart window must be live by then and not a
  /// moment earlier (the permission dialog and the quiesce are not part of
  /// either).
  void _onListenIssuing() {
    _armStartTimeout(_listenBudget());
    if (!_retried) {
      _inRetryWindow = true;
      _retryWindow?.cancel();
      _retryWindow = Timer(SpeechInputTiming.retryWindow, () {
        _inRetryWindow = false;
      });
    }
  }

  /// The host's busy callback must never break the session: a throw here would
  /// skip `notifyListeners` or leave a session in `starting` (B-pass
  /// 2026-11-14). Report the TYPE only.
  void _notifyBusy(bool busy) {
    try {
      _onBusyChanged?.call(busy);
    } catch (e, s) {
      unawaited(
        ErrorTelemetry.recordNonFatal(
          e.runtimeType.toString(),
          s,
          reason: 'speech_input_on_busy',
        ),
      );
    }
  }

  Future<void> _runBegin(int epoch) async {
    final result = await _service.begin(
      this,
      stillWanted: () => !_disposed && _epoch == epoch,
      onListenIssuing: _onListenIssuing,
    );
    // Re-checked after EVERY await: the session may have ended (Cancel, hidden,
    // dispose, timeout) while the service was waiting, and a continuation must
    // never open a mic or touch a later session.
    if (_disposed || _epoch != epoch) return;
    switch (result.status) {
      case SpeechBeginStatus.started:
        _listenIssued = true;
      case SpeechBeginStatus.abandoned:
        return;
      case SpeechBeginStatus.unsupported:
        _finish(
          SpeechEndReason.error,
          '',
          failure: SpeechFailure.unsupported,
          code: 'unsupported',
        );
      case SpeechBeginStatus.permissionDenied:
        _finish(
          SpeechEndReason.error,
          '',
          failure: SpeechFailure.permissionDenied,
          code: 'permission',
        );
      case SpeechBeginStatus.engineFailure:
        // A web `start()` can throw while the previous `abort()` is still
        // ending (plan G4): one restart inside the retry window.
        if (_service.isWeb && _canRetry(requireRetryableCode: null)) {
          _retry(epoch);
        } else {
          _finish(
            SpeechEndReason.error,
            '',
            failure: SpeechFailure.engine,
            code: result.code ?? 'listen_failed',
          );
        }
    }
  }

  bool _canRetry({required String? requireRetryableCode}) {
    if (_retried || !_inRetryWindow) return false;
    if (_liveText.trim().isNotEmpty) return false;
    if (requireRetryableCode != null &&
        !isRetryableStartError(requireRetryableCode)) {
      return false;
    }
    return true;
  }

  /// ONE restart: release the engine (unbind + idempotent cancel), go back to
  /// `starting`, and begin again; the service waits for the engine to go
  /// inactive and for the settle before it listens.
  void _retry(int epoch) {
    _retried = true;
    _listenIssued = false;
    // Null them too: `engineNotListening` / `engineDone` arm with `??=`, and a
    // cancelled Timer is still non-null, so the retried session would never
    // arm its own grace and a native end with no final would hang (B-pass
    // 2026-11-14).
    _endGrace?.cancel();
    _endGrace = null;
    _errorGrace?.cancel();
    _errorGrace = null;
    _stopTicker();
    _state = SpeechInputState.starting;
    _armStartTimeout(_prelistenBudget());
    _service.release(this);
    notifyListeners();
    unawaited(_runBegin(epoch));
  }

  // -- engine events (SpeechSessionSink) -------------------------------------

  @override
  void engineListening() {
    // A `listening` while already listening is the web firing it twice; one
    // while idle cannot reach us (unbound).
    if (_state != SpeechInputState.starting) return;
    _startTimeout?.cancel();
    _state = SpeechInputState.listening;
    _startTicker();
    notifyListeners();
  }

  @override
  void engineResult(SpeechEngineResult result) {
    if (_state != SpeechInputState.listening) return;
    if (result.isFinal) {
      if (result.words.trim().isNotEmpty) {
        // The platform's natural end: the final comes BEFORE `notListening`.
        _finish(SpeechEndReason.auto, result.words);
      }
      return;
    }
    if (result.words == _liveText) return;
    _liveText = result.words;
    notifyListeners();
  }

  @override
  void engineNotListening() {
    if (_state != SpeechInputState.listening) return;
    if (_service.isWeb) {
      // Results precede `onend` on web: the words on screen are final.
      _finish(SpeechEndReason.auto, _liveText);
      return;
    }
    // Native: a recognizer-initiated end. A final, `done` or an error inside
    // the grace ends the session; else it ends with the words on screen.
    _endGrace ??= Timer(SpeechInputTiming.endGrace, () {
      if (_state != SpeechInputState.listening) return;
      _finish(SpeechEndReason.auto, _liveText);
    });
  }

  @override
  void engineDone() {
    if (_state != SpeechInputState.listening) return;
    // Web: results precede `onend`, so `engineNotListening` already ended it.
    if (_service.isWeb) return;
    if (_liveText.trim().isNotEmpty) {
      _finish(SpeechEndReason.auto, _liveText);
      return;
    }
    // Android delivers errors through `handler.post`, AFTER `done`.
    _errorGrace ??= Timer(SpeechInputTiming.errorGrace, () {
      if (_state != SpeechInputState.listening) return;
      _finish(SpeechEndReason.auto, '');
    });
  }

  @override
  void engineError(SpeechErrorKind kind, String code) {
    if (_state == SpeechInputState.idle) return;
    final listening = _state == SpeechInputState.listening;
    final words = listening ? _liveText : '';
    switch (kind) {
      case SpeechErrorKind.permission:
        _finish(
          SpeechEndReason.error,
          words,
          failure: SpeechFailure.permissionDenied,
          code: code,
        );
      case SpeechErrorKind.unsupported:
        _finish(
          SpeechEndReason.error,
          words,
          failure: SpeechFailure.unsupported,
          code: code,
        );
      case SpeechErrorKind.engine:
        _finish(
          SpeechEndReason.error,
          words,
          failure: SpeechFailure.engine,
          code: code,
        );
      case SpeechErrorKind.benign:
        // Android emits `listening` BEFORE the recognizer's own start, so
        // busy/client arrive after it: restart once while nothing was heard.
        if (_listenIssued || listening) {
          if (_canRetry(requireRetryableCode: code)) {
            _retry(_epoch);
            return;
          }
          if (_retried && isRetryableStartError(code) && words.trim().isEmpty) {
            // The second failure: say so, with the engine message.
            _finish(
              SpeechEndReason.error,
              words,
              failure: SpeechFailure.engine,
              code: code,
            );
            return;
          }
        }
        if (!listening) return; // a late benign error of the PREVIOUS session
        _finish(SpeechEndReason.auto, words);
    }
  }

  // -- the one end path -------------------------------------------------------

  void _finish(
    SpeechEndReason reason,
    String words, {
    SpeechFailure? failure,
    String? code,
  }) {
    if (_state == SpeechInputState.idle) return; // latch
    _state = SpeechInputState.idle;
    _epoch++;
    _cancelTimers();
    _stopTicker();
    _guardActive = true;
    _toggleGuard = Timer(SpeechInputTiming.toggleGuard, () {
      _guardActive = false;
    });
    // Unbind synchronously (nothing more reaches this session) and enqueue the
    // idempotent cancel: EVERY end releases the engine, because the plugin's
    // timers are cleared only by it (plan G1).
    _service.release(this);

    if (reason == SpeechEndReason.disposed) return;

    if (failure == SpeechFailure.engine && code != null) {
      // The CODE only, never the transcript (plan G18).
      unawaited(
        ErrorTelemetry.recordNonFatal(
          'speech_input_error:$code',
          StackTrace.current,
          reason: 'speech_input_session_error',
        ),
      );
    }

    final end = SpeechSessionEnd(
      transcript: words,
      reason: reason,
      failure: failure,
      empty: reason == SpeechEndReason.auto && words.trim().isEmpty,
    );
    _deliver(end);
    _notifyBusy(false);
    if (!_disposed) notifyListeners();
  }

  /// A tap that started nothing (the platform has no recognizer) still tells
  /// the host once.
  void _emitWithoutSession(SpeechSessionEnd end) {
    _deliver(end);
    if (!_disposed) notifyListeners();
  }

  void _deliver(SpeechSessionEnd end) {
    try {
      _onEnd(end);
    } catch (e, s) {
      // A throw here would propagate into the plugin's result chain and skip
      // its own final status notification (plan D2): report the TYPE only.
      unawaited(
        ErrorTelemetry.recordNonFatal(
          e.runtimeType.toString(),
          s,
          reason: 'speech_input_on_end',
        ),
      );
    }
  }

  // -- timers -----------------------------------------------------------------

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed.value += const Duration(seconds: 1);
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _cancelTimers() {
    _startTimeout?.cancel();
    _endGrace?.cancel();
    _errorGrace?.cancel();
    _retryWindow?.cancel();
    _startTimeout = null;
    _endGrace = null;
    _errorGrace = null;
    _retryWindow = null;
    _inRetryWindow = false;
  }

  @override
  void dispose() {
    if (_disposed) return;
    // Ends a session this controller owns; an idle host cannot touch another
    // host's mic. No host callback and no notification for `disposed`.
    if (_state != SpeechInputState.idle) {
      _finish(SpeechEndReason.disposed, _wordsNow());
    }
    _disposed = true;
    _toggleGuard?.cancel();
    _toggleGuard = null;
    _cancelTimers();
    _stopTicker();
    _elapsed.dispose();
    super.dispose();
  }
}
