/// Pure pins for the speech input (plan `docs/plans/voice-input-unified.md`, §4 test 2): the
/// listen/init option builders, the timing relations and the error table.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/speech_input_service.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() {
  group('speechListenOptions', () {
    test('native equals the coach\'s historic call', () {
      final o = speechListenOptions(web: false);
      expect(o.localeId, 'en_IN');
      expect(o.listenMode, ListenMode.dictation);
      expect(o.partialResults, isTrue);
      expect(o.listenFor, const Duration(seconds: 60));
      expect(o.pauseFor, const Duration(seconds: 5));
      expect(o.cancelOnError, isFalse);
    });

    test(
      'web: hyphenated locale and NO Dart pause timer (applied on listening)',
      () {
        final o = speechListenOptions(web: true);
        expect(o.localeId, 'en-IN');
        expect(o.pauseFor, isNull);
        expect(o.listenFor, const Duration(seconds: 60));
        expect(o.listenMode, ListenMode.dictation);
        expect(o.partialResults, isTrue);
        expect(o.cancelOnError, isFalse);
      },
    );
  });

  group('speechInitOptions', () {
    test('only web on android turns result aggregation off', () {
      expect(
        speechInitOptions(web: true, platform: TargetPlatform.android),
        hasLength(1),
      );
      expect(
        speechInitOptions(
          web: true,
          platform: TargetPlatform.android,
        ).single.name,
        SpeechToText.webDoNotAggregate.name,
      );
      expect(
        speechInitOptions(web: true, platform: TargetPlatform.iOS),
        isEmpty,
      );
      expect(
        speechInitOptions(web: true, platform: TargetPlatform.windows),
        isEmpty,
      );
      expect(
        speechInitOptions(web: false, platform: TargetPlatform.android),
        isEmpty,
      );
    });
  });

  group('SpeechInputTiming relations', () {
    test(
      'the grace after a recognizer-initiated end exceeds the plugin\'s final timeout',
      () {
        expect(
          SpeechInputTiming.endGrace,
          greaterThan(SpeechInputTiming.finalTimeout),
        );
      },
    );

    test(
      'the web start timeout covers a permission prompt; native is shorter',
      () {
        expect(
          SpeechInputTiming.startTimeoutWeb,
          greaterThan(SpeechInputTiming.startTimeoutNative),
        );
        expect(
          SpeechInputTiming.startTimeoutNative,
          lessThan(SpeechInputTiming.engineCallTimeout),
        );
      },
    );

    test(
      'the quiesce outlasts the settle, and the toggle guard outlasts the settle',
      () {
        expect(
          SpeechInputTiming.quiesce,
          greaterThan(SpeechInputTiming.settle),
        );
        expect(
          SpeechInputTiming.toggleGuard,
          greaterThan(SpeechInputTiming.settle),
        );
      },
    );

    test('the listen limits are today\'s values', () {
      expect(SpeechInputTiming.listenFor, const Duration(seconds: 60));
      expect(SpeechInputTiming.pauseFor, const Duration(seconds: 5));
      expect(SpeechInputTiming.settle, const Duration(milliseconds: 150));
      expect(SpeechInputTiming.retryWindow, const Duration(milliseconds: 1500));
    });
  });

  group('classifySpeechError', () {
    const android = <String, SpeechErrorKind>{
      'error_no_match': SpeechErrorKind.benign,
      'error_speech_timeout': SpeechErrorKind.benign,
      'error_client': SpeechErrorKind.benign,
      'error_busy': SpeechErrorKind.benign,
      'error_permission': SpeechErrorKind.permission,
      'error_network': SpeechErrorKind.engine,
      'error_network_timeout': SpeechErrorKind.engine,
      'error_server': SpeechErrorKind.engine,
      'error_audio_error': SpeechErrorKind.engine,
      'error_language_unavailable': SpeechErrorKind.engine,
      'error_unknown (5)': SpeechErrorKind.engine,
      'recognizerNotAvailable': SpeechErrorKind.unsupported,
      'speech_not_supported': SpeechErrorKind.unsupported,
      'not supported': SpeechErrorKind.unsupported,
    };
    const web = <String, SpeechErrorKind>{
      'no-speech': SpeechErrorKind.benign,
      'aborted': SpeechErrorKind.benign,
      'not-allowed': SpeechErrorKind.permission,
      'service-not-allowed': SpeechErrorKind.permission,
      'network': SpeechErrorKind.engine,
      'audio-capture': SpeechErrorKind.engine,
      'not supported': SpeechErrorKind.unsupported,
      'speech_not_supported': SpeechErrorKind.unsupported,
    };

    test('every Android code', () {
      android.forEach((code, kind) {
        expect(classifySpeechError(code, web: false), kind, reason: code);
      });
    });

    test('every web code', () {
      web.forEach((code, kind) {
        expect(classifySpeechError(code, web: true), kind, reason: code);
      });
    });

    test('a web code does not mean its Android twin and vice versa', () {
      expect(
        classifySpeechError('no-speech', web: false),
        SpeechErrorKind.engine,
      );
      expect(
        classifySpeechError('error_no_match', web: true),
        SpeechErrorKind.engine,
      );
    });

    test('only busy and client are retryable start errors', () {
      expect(isRetryableStartError('error_busy'), isTrue);
      expect(isRetryableStartError('error_client'), isTrue);
      expect(isRetryableStartError('error_no_match'), isFalse);
      expect(isRetryableStartError('no-speech'), isFalse);
    });
  });
}
