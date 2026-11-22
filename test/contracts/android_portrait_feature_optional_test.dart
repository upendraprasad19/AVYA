/// The image-crop activity (`com.yalantis.ucrop.UCropActivity`) is locked to
/// portrait, and Android turns ANY activity's portrait lock into a REQUIRED
/// `android.hardware.screen.portrait` feature for the whole app. Play Console
/// warned that this hides the app from devices that cannot show a portrait
/// screen (release 1.0.0+50). `MainActivity` is not locked. The manifest marks
/// the feature optional so the crop lock can stay while availability widens.
///
/// Presence-only (the manifest is not run here): the real check is the Play
/// Console "Required hardware feature declarations" warning, which must be gone
/// for the first build that carries this change.
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

  test('the portrait feature is declared optional', () {
    final feature = RegExp(
      r'<uses-feature\b[^>]*android:name="android\.hardware\.screen\.portrait"[^>]*/>',
    ).firstMatch(manifest);
    expect(
      feature,
      isNotNull,
      reason:
          'without this, the portrait lock makes the feature required and Play '
          'hides the app from devices without a portrait screen',
    );
    expect(
      RegExp(r'android:required="false"').hasMatch(feature!.group(0)!),
      isTrue,
      reason: 'the declaration must say required="false"',
    );
  });

  test(
    'the declaration is a direct child of <manifest>, not inside <application>',
    () {
      final application = RegExp(
        r'<application\b.*?</application>',
        dotAll: true,
      ).firstMatch(manifest);
      expect(application, isNotNull);
      expect(
        application!.group(0)!.contains('android.hardware.screen.portrait'),
        isFalse,
        reason: '<uses-feature> inside <application> is ignored by the build',
      );
    },
  );

  test('the crop activity keeps its portrait lock', () {
    expect(
      RegExp(
        r'<activity\b[^>]*android:name="com\.yalantis\.ucrop\.UCropActivity"'
        r'[^>]*android:screenOrientation="portrait"',
      ).hasMatch(manifest),
      isTrue,
      reason:
          'this change widens availability, it does not unlock the crop '
          'screen (the lock is what implies the feature in the first place)',
    );
  });
}
