// The Razorpay Android SDK reaches us through floating versions:
// razorpay_flutter's own android/build.gradle asks for `checkout:1.6.+`, and
// checkout's POM asks for `standard-core:LATEST`. Each makes Gradle fetch a
// version listing on every build; an empty listing failed main CI on
// 2026-10-21, and a new Razorpay release silently changes the shipped SDK.
// android/build.gradle.kts pins both (diagnose a6c3e9). This test keeps the
// pin exact and forces a re-audit when the plugin itself changes.
//
// Presence-only by nature: Gradle does not run under `flutter test`. The
// behavioural proof (zero razorpay maven-metadata.xml fetches with
// --refresh-dependencies) is recorded in the diagnose doc.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every coordinate whose upstream selector floats, with the version every
/// built AAB (+46..+48) resolved.
const _expectedPins = {
  'com.razorpay:checkout': '1.6.41',
  'com.razorpay:standard-core': '1.7.19',
};

/// The razorpay_flutter version whose dependency tree was audited.
const _auditedPluginVersion = '1.4.5';

String _withoutComments(String src) => src
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split(RegExp(r'\r?\n'))
    .map((l) => l.trimLeft().startsWith('//') ? '' : l)
    .join('\n');

void main() {
  final gradle = _withoutComments(
      File('android/build.gradle.kts').readAsStringSync());

  test('each floating coordinate is pinned to an exact version', () {
    for (final MapEntry(key: coordinate, value: version) in _expectedPins.entries) {
      final pin = RegExp('"${RegExp.escape(coordinate)}"\\s+to\\s+"([^"]*)"')
          .firstMatch(gradle);
      expect(pin, isNotNull, reason: '$coordinate must be pinned');
      expect(pin!.group(1), matches(RegExp(r'^\d+\.\d+\.\d+$')),
          reason: '$coordinate must be an exact x.y.z, never + / latest / a range');
      expect(pin.group(1), version,
          reason: 'changing the pinned SDK is a deliberate bump: update this '
              'test and run a device payment test');
    }
  });

  test('the pin map is applied to every subproject before resolution', () {
    // Column 0: a block wrapped in `if (...)` or `gradle.projectsEvaluated`
    // is indented, so it cannot satisfy this.
    final subprojects = gradle.indexOf(RegExp(
        r'^subprojects\s*\{\s*configurations\.configureEach',
        multiLine: true));
    expect(subprojects, isNot(-1),
        reason: 'the rule must cover every subproject (the plugin is one)');
    final rule = gradle.substring(subprojects);
    expect(rule, contains('resolutionStrategy.eachDependency'));
    expect(rule, contains(r'pinnedAndroidDependencies["${requested.group}:${requested.name}"]'));
    expect(rule, contains('useVersion(it)'),
        reason: 'useVersion rewrites the selector, so no listing is fetched');
    expect(subprojects, lessThan(gradle.indexOf('evaluationDependsOn')),
        reason: 'declare the rule before projects are evaluated');
  });

  test('razorpay_flutter is still the audited version', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final entry = RegExp(r'\n  razorpay_flutter:\r?\n(?:    .*\r?\n)*?    version: "([^"]+)"')
        .firstMatch(lock);
    expect(entry, isNotNull, reason: 'razorpay_flutter must be in pubspec.lock');
    expect(entry!.group(1), _auditedPluginVersion,
        reason: 'razorpay_flutter changed, so re-audit its Android dependency '
            'tree before merging: (1) in the pub cache, read '
            'razorpay_flutter-<new>/android/build.gradle for "+", "latest" or '
            '"[..)" selectors; (2) fetch each com.razorpay POM it reaches from '
            'repo1.maven.org and look for the same; (3) pin every floating '
            'coordinate in android/build.gradle.kts and update _expectedPins '
            'and _auditedPluginVersion here.');
  });
}
