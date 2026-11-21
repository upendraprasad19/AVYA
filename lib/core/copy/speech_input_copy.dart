/// Copy for the speech input on the AI Coach composer and the nutrition Log
/// sheet (plan `docs/plans/voice-input-unified.md`, D9).
///
/// Const-only. No em dashes. Short, plain and calm, like the rest of the
/// product (Wardroom soul: the user is the one in command, the tool states the
/// fact and the next step, nothing more).
///
/// This is about the user's own dictation. It is NOT the coach persona's voice.
library;

import 'package:icanbefitter/core/services/speech_input_controller.dart';

class SpeechInputCopy {
  SpeechInputCopy._();

  // -- buttons and labels ----------------------------------------------------

  static const String tapToSpeak = 'Tap to speak';
  static const String listening = 'LISTENING';

  /// Shown in the coach bar before the first words arrive.
  static const String listeningHint = 'Listening...';
  static const String stop = 'Stop';
  static const String send = 'Send';
  static const String cancel = 'Cancel';

  // -- screen-reader labels -----------------------------------------------------

  static const String semanticsStart = 'Start speaking';
  static const String semanticsStop = 'Stop and keep the words';
  static const String semanticsSend = 'Stop and send';
  static const String semanticsCancel = 'Cancel and discard';

  // -- messages --------------------------------------------------------------

  /// An automatic end with no words.
  static const String didNotCatch =
      'Did not catch that. Tap the mic and try again.';

  /// The platform or the browser has no speech recognizer.
  static const String unsupported =
      'Speech input is not available here. You can type instead.';

  /// The microphone was refused.
  static const String permissionDenied =
      'Microphone access is off. Allow it in your settings, then tap the mic again.';

  /// Any other engine failure (network, audio, a recognizer that did not start).
  static const String engineFailure = 'Could not hear you. Please try again.';

  /// Send tapped with too few words to analyse (nutrition).
  static const String tooShort =
      'Say a little more about what you ate, then tap Send.';

  /// The message a host shows for a finished session, or null when there is
  /// nothing to say (a normal Stop, Send, Cancel, or an end that kept words).
  static String? messageFor(SpeechSessionEnd end) {
    switch (end.failure) {
      case SpeechFailure.permissionDenied:
        return permissionDenied;
      case SpeechFailure.unsupported:
        return unsupported;
      case SpeechFailure.engine:
        return engineFailure;
      case null:
        return end.empty ? didNotCatch : null;
    }
  }
}
