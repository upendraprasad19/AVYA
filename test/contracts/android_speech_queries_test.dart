/// The Android manifest lets the speech recognizer see the device's recognition
/// service (plan `docs/plans/voice-input-unified.md`, D7, G11).
///
/// On Android 11+ an app only sees the services it declares in `<queries>`;
/// without the `android.speech.RecognitionService` intent, a device that HAS a
/// recognizer can still report none, and the mic would show "not available".
/// Presence-only (the manifest is not run here): the real check is the T8
/// device walk, which also reads the merged release manifest.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String manifest;

  setUpAll(() {
    manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync().replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  });

  test('the <queries> block declares the RecognitionService intent', () {
    final queries = RegExp(
      r'<queries>(.*?)</queries>',
      dotAll: true,
    ).firstMatch(manifest);
    expect(queries, isNotNull, reason: 'the manifest must keep its <queries>');
    final block = queries!.group(1)!;
    expect(
      RegExp(
        r'<intent>\s*<action\s+android:name="android\.speech\.RecognitionService"\s*/>\s*</intent>',
      ).hasMatch(block),
      isTrue,
      reason: 'a RecognitionService <intent> must sit INSIDE <queries>',
    );
  });

  test('the entry is inside <queries>, not just somewhere in the file', () {
    final at = manifest.indexOf('android.speech.RecognitionService');
    final open = manifest.indexOf('<queries>');
    final close = manifest.indexOf('</queries>');
    expect(at, greaterThan(open));
    expect(at, lessThan(close));
  });

  test('the microphone permission is still declared', () {
    expect(manifest.contains('android.permission.RECORD_AUDIO'), isTrue);
  });

  test(
    'the other <queries> entries are untouched (PROCESS_TEXT, Health Connect)',
    () {
      expect(manifest.contains('android.intent.action.PROCESS_TEXT'), isTrue);
      expect(manifest.contains('com.google.android.apps.healthdata'), isTrue);
    },
  );
}
