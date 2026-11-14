/// The in-app privacy copy tells the truth about voice input (plan
/// `docs/plans/voice-input-unified.md`, D9, T8/T9 and the website policy row 3.6
/// of `docs/operations/GO_LIVE_CHECKLIST.md`).
///
/// The recognizer is the phone's or the browser's own speech service. On
/// Android that is usually Google's, and Chrome sends the audio to its provider.
/// So no user-facing string may promise the audio stays on the device, and the
/// privacy dialog must carry a `Microphone:` line that says the audio may be
/// sent. Presence-only: the copy is a const string, there is no behaviour to run.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test(
    'the privacy dialog lists the microphone and says the audio may be sent',
    () {
      final src = _read(
        'lib/features/profile/screens/profile/privacy_dialog.dart',
      );
      expect(
        src,
        contains('Microphone:'),
        reason:
            'voice input needs RECORD_AUDIO; the permission list must say so',
      );
      final line = RegExp(r'Microphone:[^\n]*').firstMatch(src)!.group(0)!;
      expect(
        line.toLowerCase(),
        contains('may send the audio'),
        reason: 'the recognizer is the device or browser service, not ours',
      );
    },
  );

  test('no user-facing speech string promises on-device processing', () {
    const files = [
      'lib/core/copy/speech_input_copy.dart',
      'lib/features/profile/screens/profile/privacy_dialog.dart',
      'lib/shared/widgets/paywall_sheet.dart',
    ];
    final banned = RegExp(
      r'on[- ]device|stays on your (phone|device)|never leaves|offline (speech|recogni)',
      caseSensitive: false,
    );
    for (final f in files) {
      final hits = banned.allMatches(_read(f)).map((m) => m.group(0)).toList();
      expect(hits, isEmpty, reason: '$f must not promise on-device speech');
    }
  });

  test('the documented behaviour says the audio may reach the provider', () {
    for (final f in const [
      'docs/architecture/business-rules.md',
      'docs/architecture/functionality-flow.md',
    ]) {
      expect(
        RegExp(
          r'may send the audio|may leave the device',
          caseSensitive: false,
        ).hasMatch(_read(f)),
        isTrue,
        reason: '$f must keep the provider-transfer wording for voice input',
      );
    }
  });
}
